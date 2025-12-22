// lib/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatMessage {
  final String id, fromAppId, toAppId, text;
  final DateTime ts;

  ChatMessage({
    required this.id,
    required this.fromAppId,
    required this.toAppId,
    required this.text,
    required this.ts,
  });

  bool isMine(String myAppId) => fromAppId == myAppId;

  factory ChatMessage.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final ts = (m['ts'] as Timestamp?)?.toDate() ?? DateTime.now();
    return ChatMessage(
      id: d.id,
      fromAppId: '${m['fromAppId'] ?? ''}',
      toAppId: '${m['toAppId'] ?? ''}',
      text: '${m['text'] ?? ''}',
      ts: ts,
    );
  }
}

class ChatThread {
  final String id;
  final List<String> participantsAppIds;
  final Map<String, dynamic> participants; // appId -> {name, avatar or avatars}
  final String lastText;
  final DateTime updatedAt;

  // optional (your UI reads these safely via dynamic)
  final String? lastSenderAppId;
  final Map<String, dynamic>? unread; // {appId: int}

  ChatThread({
    required this.id,
    required this.participantsAppIds,
    required this.participants,
    required this.lastText,
    required this.updatedAt,
    this.lastSenderAppId,
    this.unread,
  });

  String otherId(String me) =>
      participantsAppIds.firstWhere((x) => x != me, orElse: () => me);

  factory ChatThread.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};

    DateTime ts;
    final raw = m['updatedAt'];
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return ChatThread(
      id: d.id,
      participantsAppIds:
          (m['participantsAppIds'] as List? ?? const []).map((e) => '$e').toList(),
      participants: (m['participants'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      lastText: '${m['lastText'] ?? ''}',
      updatedAt: ts,
      lastSenderAppId: (m['lastSenderAppId'] is String) ? m['lastSenderAppId'] as String : null,
      unread: (m['unread'] is Map) ? Map<String, dynamic>.from(m['unread'] as Map) : null,
    );
  }
}

class ChatService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> _ensureCore() async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // ignore init race
      }
    }
  }

  static Future<String> myAppUserId() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('userId') ?? sp.getInt('userId')?.toString();
    return (s == null || s.isEmpty) ? 'guest' : s;
  }

  static Future<User> ensureFirebaseAuth({String? firebaseCustomToken}) async {
    await _ensureCore();

    final existing = _auth.currentUser;
    if (existing != null) return existing;

    if (firebaseCustomToken != null && firebaseCustomToken.isNotEmpty) {
      final cred = await _auth.signInWithCustomToken(firebaseCustomToken);
      return cred.user!;
    }

    final cred = await _auth.signInAnonymously();
    return cred.user!;
  }

  static Future<void> lockUidMapping(String appUserId) async {
    final uid = _auth.currentUser!.uid;
    final ref = _db.collection('profiles').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'appUserId': appUserId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  static String threadIdForApp(String a, String b) {
    final x = a.trim(), y = b.trim();
    return (x.compareTo(y) < 0) ? '${x}_$y' : '${y}_$x';
  }

  /// ✅ FIXED: no orderBy => NO composite index required
  /// We sort locally by updatedAt.
  static Stream<List<ChatThread>> threadsStream(String myAppId) {
    return _db
        .collection('threads')
        .where('participantsAppIds', arrayContains: myAppId)
        .snapshots()
        .map((qs) {
      final list = qs.docs.map((d) => ChatThread.fromSnap(d)).toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  static Future<void> ensureThread({
    required String myAppId,
    required String peerAppId,
    String? myName,
    String? myAvatar,
    dynamic myAvatars, // allow list too if you want
    String? peerName,
    String? peerAvatar,
    dynamic peerAvatars,
  }) async {
    final id = threadIdForApp(myAppId, peerAppId);
    final ref = _db.collection('threads').doc(id);

    await ref.set({
      'participantsAppIds': [myAppId, peerAppId],
      'participants': {
        myAppId: {
          'name': myName,
          if (myAvatars != null) 'avatars': myAvatars,
          if (myAvatars == null) 'avatar': myAvatar,
        },
        peerAppId: {
          'name': peerName,
          if (peerAvatars != null) 'avatars': peerAvatars,
          if (peerAvatars == null) 'avatar': peerAvatar,
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'lastText': FieldValue.delete(),
      'lastSenderAppId': FieldValue.delete(),
      'unread': {
        myAppId: 0,
        peerAppId: 0,
      },
    }, SetOptions(merge: true));
  }

  /// Messages stream (for MessagePage)
  static Stream<List<ChatMessage>> messagesStream(String threadId, {
    required String myAppId,
    required String peerAppId,
    int limit = 60,
  }) {
    final id = threadIdForApp(myAppId, peerAppId);

    return _db
        .collection('threads')
        .doc(id)
        .collection('messages')
        .orderBy('ts', descending: true)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map((d) => ChatMessage.fromSnap(d)).toList());
  }

  static Future<void> sendMessage({
    required String myAppId,
    required String peerAppId,
    required String text,
  }) async {
    final id = threadIdForApp(myAppId, peerAppId);
    final tRef = _db.collection('threads').doc(id);
    final mRef = tRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    await _db.runTransaction((tx) async {
      tx.set(mRef, {
        'fromAppId': myAppId,
        'toAppId': peerAppId,
        'text': text,
        'ts': now,
      });

      // ✅ keeps your UI "You:" prefix + unread badge working
      tx.set(
        tRef,
        {
          'updatedAt': now,
          'lastText': text,
          'lastSenderAppId': myAppId,
          'unread.$peerAppId': FieldValue.increment(1),
          'unread.$myAppId': 0,
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> markThreadRead({
    required String myAppId,
    required String peerAppId,
  }) async {
    final id = threadIdForApp(myAppId, peerAppId);
    await _db.collection('threads').doc(id).set(
      {'unread.$myAppId': 0},
      SetOptions(merge: true),
    );
  }
}
