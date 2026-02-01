import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatMessage {
  final String id;
  final String fromAppId;
  final String toAppId;
  final String text;
  final DateTime ts;

  final bool isEdited;
  final bool isDeleted;

  ChatMessage({
    required this.id,
    required this.fromAppId,
    required this.toAppId,
    required this.text,
    required this.ts,
    this.isEdited = false,
    this.isDeleted = false,
  });

  bool isMine(String myAppId) => fromAppId == myAppId;

  factory ChatMessage.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final ts = (m['ts'] as Timestamp?)?.toDate() ?? DateTime.now();

    final deleted = (m['isDeleted'] == true) || (m['deleted'] == true);
    final edited = (m['isEdited'] == true) || (m['edited'] == true);

    return ChatMessage(
      id: d.id,
      fromAppId: '${m['fromAppId'] ?? ''}',
      toAppId: '${m['toAppId'] ?? ''}',
      text: '${m['text'] ?? ''}',
      ts: ts,
      isDeleted: deleted,
      isEdited: edited,
    );
  }
}

class ChatThread {
  final String id;

  final List<String> participantsAppIds; // [me, peer]
  final Map<String, dynamic> participants; // appId -> {name, avatar}

  final String lastText;
  final DateTime updatedAt;

  final String? lastSenderAppId;
  final String? lastMessageId;

  /// unread map: { "<appId>": int }
  final Map<String, dynamic> unread;

  ChatThread({
    required this.id,
    required this.participantsAppIds,
    required this.participants,
    required this.lastText,
    required this.updatedAt,
    this.lastSenderAppId,
    this.lastMessageId,
    this.unread = const {},
  });

  String otherId(String me) =>
      participantsAppIds.firstWhere((x) => x != me, orElse: () => me);

  factory ChatThread.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final ts = (m['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return ChatThread(
      id: d.id,
      participantsAppIds:
          (m['participantsAppIds'] as List? ?? const []).map((e) => '$e').toList(),
      participants: (m['participants'] as Map<String, dynamic>? ?? const {}),
      lastText: '${m['lastText'] ?? ''}',
      updatedAt: ts,
      lastSenderAppId: (m['lastSenderAppId'] == null) ? null : '${m['lastSenderAppId']}',
      lastMessageId: (m['lastMessageId'] == null) ? null : '${m['lastMessageId']}',
      unread: (m['unread'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

class ChatService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration _editWindow = Duration(minutes: 5);

  // ------------ Friendly errors (don’t show Firebase logs in UI) ------------
  static String friendlyError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unavailable':
          return 'You seem offline. Check your internet and try again.';
        case 'permission-denied':
          return 'You don’t have permission to do that.';
        case 'unauthenticated':
          return 'Please sign in again to continue.';
        case 'not-found':
          return 'Not found. Please try again.';
        case 'deadline-exceeded':
          return 'That took too long. Please try again.';
        case 'resource-exhausted':
          return 'Too many requests. Try again in a moment.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    final s = e.toString().toLowerCase();
    if (s.contains('network') || s.contains('offline') || s.contains('unavailable')) {
      return 'You seem offline. Check your internet and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  static Future<void> _ensureCore() async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // ignore race
      }
    }
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

  /// IMPORTANT:
  /// If this suddenly returns "guest", your threadId changes => messages look “gone”.
  /// So we try many keys + fallback to Firebase UID.
  static Future<String> myAppUserId() async {
    await _ensureCore();

    String? pick(SharedPreferences sp, String key) {
      final s = sp.getString(key);
      if (s != null && s.trim().isNotEmpty) return s.trim();
      final i = sp.getInt(key);
      if (i != null) return i.toString();
      return null;
    }

    final sp = await SharedPreferences.getInstance();

    final keys = <String>[
      'userId',
      'appUserId',
      'app_user_id',
      'user_id',
      'id',
      'uid',
      'sqlUserId',
    ];

    for (final k in keys) {
      final v = pick(sp, k);
      if (v != null && v.isNotEmpty) return v;
    }

    // fallback to firebase uid so it stays stable (and doesn’t break threads)
    final u = _auth.currentUser;
    if (u != null) return u.uid;

    // last resort
    return 'guest';
  }

  static Future<void> lockUidMapping(String appUserId) async {
    await _ensureCore();
    final u = _auth.currentUser ?? await ensureFirebaseAuth();
    final uid = u.uid;

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
    final x = a.trim();
    final y = b.trim();
    return (x.compareTo(y) < 0) ? '${x}_$y' : '${y}_$x';
  }

  // ------------ Streams ------------
  static Stream<List<ChatThread>> threadsStream(String myAppId) {
    // no orderBy => avoids index headaches; sort locally
    final q = _db.collection('threads').where('participantsAppIds', arrayContains: myAppId);

    return q.snapshots().map((qs) {
      final list = qs.docs.map((d) => ChatThread.fromSnap(d)).toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  static Stream<List<ChatMessage>> messagesStream(String threadId) {
    return _db
        .collection('threads')
        .doc(threadId)
        .collection('messages')
        .orderBy('ts', descending: false)
        .snapshots()
        .map((qs) => qs.docs.map((d) => ChatMessage.fromSnap(d)).toList());
  }

  // ------------ Thread helpers ------------
  static Future<void> ensureThread({
    required String myAppId,
    required String peerAppId,
    String? myName,
    String? myAvatar,
    String? peerName,
    String? peerAvatar,
  }) async {
    await _ensureCore();

    final id = threadIdForApp(myAppId, peerAppId);
    final ref = _db.collection('threads').doc(id);

    await ref.set({
      'participantsAppIds': [myAppId, peerAppId],
      'participants': {
        myAppId: {'name': myName ?? '', 'avatar': myAvatar ?? ''},
        peerAppId: {'name': peerName ?? '', 'avatar': peerAvatar ?? ''},
      },
      'unread': {myAppId: 0, peerAppId: 0},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> markThreadRead({
    required String myAppId,
    required String peerAppId,
  }) async {
    await _ensureCore();

    final id = threadIdForApp(myAppId, peerAppId);
    final ref = _db.collection('threads').doc(id);

    // Using update with dotted path; assumes appIds don’t contain '.'
    await ref.set({
      'unread': {myAppId: 0},
    }, SetOptions(merge: true));
  }

  static String _previewForThread(String text) {
    final t = text.trimLeft();
    if (t.startsWith('img::')) return '📷 Photo';
    if (t.startsWith('aud::')) return '🎤 Voice note';
    if (t.startsWith('call::')) return '📞 Call';
    return text;
  }

  // ------------ Send ------------
  static Future<void> sendMessage({
    required String myAppId,
    required String peerAppId,
    required String text,
  }) async {
    await _ensureCore();

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
        'isEdited': false,
        'isDeleted': false,
      });

      // keep thread alive + preview + lastMessageId
      tx.set(
        tRef,
        {
          'participantsAppIds': [myAppId, peerAppId],
          'updatedAt': now,
          'lastText': _previewForThread(text),
          'lastSenderAppId': myAppId,
          'lastMessageId': mRef.id,
        },
        SetOptions(merge: true),
      );

      // unread counts (assumes ids have no '.')
      tx.update(tRef, {
        'unread.$peerAppId': FieldValue.increment(1),
        'unread.$myAppId': 0,
      });
    });
  }

  // ------------ Edit / Delete (within 5 mins) ------------
  static Future<void> editMessage({
    required String threadId,
    required String messageId,
    required String myAppId,
    required String newText,
  }) async {
    await _ensureCore();

    final tRef = _db.collection('threads').doc(threadId);
    final mRef = tRef.collection('messages').doc(messageId);

    await _db.runTransaction((tx) async {
      final mSnap = await tx.get(mRef);
      if (!mSnap.exists) throw Exception('Message not found');

      final data = mSnap.data() as Map<String, dynamic>? ?? {};
      if ('${data['fromAppId'] ?? ''}' != myAppId) {
        throw Exception('You can only edit your own messages');
      }

      final ts = (data['ts'] as Timestamp?)?.toDate();
      if (ts == null) throw Exception('Missing timestamp');
      if (DateTime.now().difference(ts) > _editWindow) {
        throw Exception('Edit window expired (5 mins)');
      }

      final deleted = (data['isDeleted'] == true) || (data['deleted'] == true);
      if (deleted) throw Exception('Cannot edit a deleted message');

      tx.update(mRef, {
        'text': newText,
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });

      // update lastText only if this is the latest message
      final tSnap = await tx.get(tRef);
      final tData = tSnap.data() as Map<String, dynamic>? ?? {};
      final lastId = '${tData['lastMessageId'] ?? ''}';
      if (lastId == messageId) {
        tx.set(tRef, {'lastText': _previewForThread(newText)}, SetOptions(merge: true));
      }
    });
  }

  static Future<void> deleteMessage({
    required String threadId,
    required String messageId,
    required String myAppId,
  }) async {
    await _ensureCore();

    final tRef = _db.collection('threads').doc(threadId);
    final mRef = tRef.collection('messages').doc(messageId);

    await _db.runTransaction((tx) async {
      final mSnap = await tx.get(mRef);
      if (!mSnap.exists) return;

      final data = mSnap.data() as Map<String, dynamic>? ?? {};
      if ('${data['fromAppId'] ?? ''}' != myAppId) {
        throw Exception('You can only delete your own messages');
      }

      final ts = (data['ts'] as Timestamp?)?.toDate();
      if (ts == null) throw Exception('Missing timestamp');
      if (DateTime.now().difference(ts) > _editWindow) {
        throw Exception('Delete window expired (5 mins)');
      }

      tx.update(mRef, {
        'text': '',
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      });

      final tSnap = await tx.get(tRef);
      final tData = tSnap.data() as Map<String, dynamic>? ?? {};
      final lastId = '${tData['lastMessageId'] ?? ''}';
      if (lastId == messageId) {
        tx.set(tRef, {'lastText': 'Message deleted'}, SetOptions(merge: true));
      }
    });
  }
}
