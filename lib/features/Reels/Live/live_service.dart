import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';

/// A broadcast in `lives/{id}`.
class LiveStream {
  final String id;
  final String hostId;
  final String hostName;
  final String hostPhoto;
  final bool hostIsMerchant;
  final String title;
  final String status;
  final int viewerCount;
  final int likeCount;
  final DateTime startedAt;
  final DateTime? heartbeatAt;
  final String filter;
  final String effect;

  const LiveStream({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.hostPhoto,
    required this.hostIsMerchant,
    required this.title,
    required this.status,
    required this.viewerCount,
    required this.likeCount,
    required this.startedAt,
    required this.heartbeatAt,
    this.filter = 'normal',
    this.effect = 'none',
  });

  /// Live and the host's phone checked in recently (a crashed app stops beating).
  bool get isLive {
    if (status != 'live') return false;
    final beat = heartbeatAt ?? startedAt;
    return DateTime.now().difference(beat) < const Duration(seconds: 90);
  }

  factory LiveStream.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    int n(Object? v) => v is num ? v.toInt() : 0;
    DateTime? t(Object? v) => v is Timestamp ? v.toDate() : null;
    return LiveStream(
      id: doc.id,
      hostId: (d['hostId'] ?? '').toString(),
      hostName: (d['hostName'] ?? '').toString().trim().isEmpty
          ? 'Vero360 member'
          : (d['hostName'] ?? '').toString().trim(),
      hostPhoto: (d['hostPhoto'] ?? '').toString().trim(),
      hostIsMerchant: d['hostIsMerchant'] == true,
      title: (d['title'] ?? '').toString().trim(),
      status: (d['status'] ?? 'ended').toString(),
      viewerCount: n(d['viewerCount']),
      likeCount: n(d['likeCount']),
      startedAt: t(d['startedAt']) ?? DateTime.now(),
      heartbeatAt: t(d['heartbeatAt']),
      filter: (d['filter'] ?? 'normal').toString(),
      effect: (d['effect'] ?? 'none').toString(),
    );
  }
}

class LiveChatMessage {
  final String id;
  final String uid;
  final String name;
  final String photo;
  final String text;

  /// `chat` or `join`.
  final String type;

  const LiveChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.photo,
    required this.text,
    required this.type,
  });

  factory LiveChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return LiveChatMessage(
      id: doc.id,
      uid: (d['uid'] ?? '').toString(),
      name: (d['name'] ?? 'Vero360 member').toString(),
      photo: (d['photo'] ?? '').toString(),
      text: (d['text'] ?? '').toString(),
      type: (d['type'] ?? 'chat').toString(),
    );
  }
}

class LiveService {
  LiveService._();
  static final LiveService instance = LiveService._();

  /// The host uploads one stream per viewer, so keep rooms small.
  static const maxViewers = 20;

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get lives => _db.collection('lives');

  DocumentReference<Map<String, dynamic>> viewerDoc(String liveId, String uid) =>
      lives.doc(liveId).collection('viewers').doc(uid);

  String? get uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  /// Broadcasts happening now, busiest first.
  Stream<List<LiveStream>> watchLiveNow() {
    return lives.where('status', isEqualTo: 'live').limit(50).snapshots().map((snap) {
      final list = snap.docs.map(LiveStream.fromDoc).where((l) => l.isLive).toList()
        ..sort((a, b) => b.viewerCount.compareTo(a.viewerCount));
      return list;
    });
  }

  Stream<LiveStream?> watch(String liveId) => lives
      .doc(liveId)
      .snapshots()
      .map((d) => d.exists ? LiveStream.fromDoc(d) : null);

  Future<String> start({
    required String title,
    String filter = 'normal',
    String effect = 'none',
  }) async {
    final me = await ReelService.instance.myIdentity();
    if (me == null) throw Exception('Sign in to go live.');
    // A crashed earlier broadcast would otherwise linger as "live".
    try {
      final old = await lives
          .where('hostId', isEqualTo: me.uid)
          .where('status', isEqualTo: 'live')
          .get();
      for (final d in old.docs) {
        await d.reference.update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
    final ref = await lives.add({
      'hostId': me.uid,
      'hostName': me.name,
      'hostPhoto': me.photo,
      'hostIsMerchant': me.isMerchant,
      'title': title.trim(),
      'filter': filter,
      'effect': effect,
      'status': 'live',
      'viewerCount': 0,
      'peakViewers': 0,
      'likeCount': 0,
      'startedAt': FieldValue.serverTimestamp(),
      'heartbeatAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setLook(String liveId, {required String filter, required String effect}) async {
    try {
      await lives.doc(liveId).update({'filter': filter, 'effect': effect});
    } catch (_) {}
  }

  Future<void> heartbeat(String liveId) async {
    try {
      await lives.doc(liveId).update({'heartbeatAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  Future<void> setViewerCount(String liveId, int count, int peak) async {
    try {
      await lives.doc(liveId).update({'viewerCount': count, 'peakViewers': peak});
    } catch (_) {}
  }

  Future<void> end(String liveId) async {
    try {
      await lives.doc(liveId).update({
        'status': 'ended',
        'viewerCount': 0,
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> like(String liveId) async {
    try {
      await lives.doc(liveId).update({'likeCount': FieldValue.increment(1)});
    } catch (_) {}
  }

  Future<void> sendChat(String liveId, String text, {String type = 'chat'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final me = await ReelService.instance.myIdentity();
    if (me == null) throw Exception('Sign in to comment.');
    await lives.doc(liveId).collection('chat').add({
      'uid': me.uid,
      'name': me.name,
      'photo': me.photo,
      'text': clean.length > 200 ? clean.substring(0, 200) : clean,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Latest messages, oldest first.
  Stream<List<LiveChatMessage>> watchChat(String liveId) => lives
      .doc(liveId)
      .collection('chat')
      .orderBy('createdAt', descending: true)
      .limit(40)
      .snapshots()
      .map((s) => s.docs.map(LiveChatMessage.fromDoc).toList().reversed.toList());
}
