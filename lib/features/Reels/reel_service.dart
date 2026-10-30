import 'dart:async';
import 'package:universal_io/io.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_video_cache.dart';
import 'package:vero360_app/utils/display_name_sync.dart';

class ReelIdentity {
  final String uid;
  final String name;
  final String photo;
  final bool isMerchant;

  const ReelIdentity({
    required this.uid,
    required this.name,
    required this.photo,
    required this.isMerchant,
  });
}

class ReelPage {
  final List<Reel> reels;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  /// Served from the on-device Firestore cache (offline or cache-only read).
  final bool fromCache;

  const ReelPage(this.reels, this.cursor, this.hasMore, {this.fromCache = false});
}

class ReelService {
  ReelService._();
  static final ReelService instance = ReelService._();

  static const maxVideoBytes = 40 * 1024 * 1024;
  static const maxDuration = Duration(seconds: 60);
  static const _pageSize = 15;
  /// Reels with this many reports are hidden until an admin reviews them.
  static const autoHideReports = 5;
  static const _hiddenPrefsKey = 'reels_hidden_by_me_v1';

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _reels =>
      _db.collection('reels');

  String? get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  bool get isSignedIn => _uid != null;

  final Set<String> _viewedThisSession = <String>{};
  final Map<String, bool> _likedCache = <String, bool>{};
  final Map<String, bool> _sharedCache = <String, bool>{};
  Set<String>? _followingCache;
  Set<String>? _hiddenByMe;

  // â”€â”€ Identity â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<ReelIdentity?> myIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    final prefs = await SharedPreferences.getInstance();
    final role = RoleHelper.normalizeAccountRole(
      prefs.getString('user_role') ?? prefs.getString('role'),
    );
    final isMerchant = role == RoleHelper.merchant;
    var name = '';
    try {
      name = await DisplayNameSync.resolveActingDisplayName(fallback: '');
    } catch (_) {}
    if (name.trim().isEmpty) {
      name = (user.displayName ?? '').trim();
    }
    if (name.isEmpty || name.contains('@')) {
      name = isMerchant ? 'My shop' : 'Vero360 member';
    }
    var photo = (prefs.getString('profilepicture') ?? '').trim();
    if (photo.isEmpty) photo = (user.photoURL ?? '').trim();
    return ReelIdentity(
      uid: user.uid,
      name: name.trim(),
      photo: photo,
      isMerchant: isMerchant,
    );
  }

  // â”€â”€ Feed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Set<String>> hiddenByMe() async {
    final cached = _hiddenByMe;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_hiddenPrefsKey) ?? const <String>[])
        .toSet();
    _hiddenByMe = set;
    return set;
  }

  Future<void> hideForMe(String reelId) async {
    final set = await hiddenByMe();
    set.add(reelId);
    final prefs = await SharedPreferences.getInstance();
    final list = set.toList();
    await prefs.setStringList(
      _hiddenPrefsKey,
      list.length > 500 ? list.sublist(list.length - 500) : list,
    );
  }

  bool _visible(Reel r, Set<String> hidden) =>
      !r.hidden &&
      r.videoUrl.isNotEmpty &&
      r.reportCount < autoHideReports &&
      !hidden.contains(r.id);

  /// Newest reels, re-ordered by engagement and whether you follow the poster.
  /// [cacheOnly] reads what's already on the device, for an instant first screen.
  Future<ReelPage> fetchForYou({
    DocumentSnapshot<Map<String, dynamic>>? after,
    bool cacheOnly = false,
  }) async {
    Query<Map<String, dynamic>> q =
        _reels.orderBy('createdAt', descending: true).limit(_pageSize);
    if (after != null) q = q.startAfterDocument(after);
    final results = await Future.wait<Object>([
      q.get(cacheOnly ? const GetOptions(source: Source.cache) : null),
      hiddenByMe(),
      cacheOnly ? Future.value(_followingCache ?? <String>{}) : followingIds(),
    ]);
    final snap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final hidden = results[1] as Set<String>;
    final following = results[2] as Set<String>;
    final reels =
        snap.docs.map(Reel.fromDoc).where((r) => _visible(r, hidden)).toList();
    final now = DateTime.now();
    double score(Reel r) {
      final hours = now.difference(r.createdAt).inMinutes / 60.0;
      final engagement = 1 +
          r.likeCount * 3 +
          r.commentCount * 4 +
          r.shareCount * 5 +
          r.viewCount * 0.2;
      var s = engagement / math.pow(hours.clamp(0, 24 * 60) + 2, 1.3);
      if (following.contains(r.ownerId)) s *= 1.6;
      if (_viewedThisSession.contains(r.id)) s *= 0.3;
      return s;
    }

    reels.sort((a, b) => score(b).compareTo(score(a)));
    return ReelPage(
      reels,
      snap.docs.isEmpty ? after : snap.docs.last,
      snap.docs.length == _pageSize,
      fromCache: snap.metadata.isFromCache,
    );
  }

  /// Reels from accounts you follow, newest first.
  Future<List<Reel>> fetchFollowing() async {
    final following = (await followingIds(refresh: true)).toList();
    if (following.isEmpty) return const [];
    final hidden = await hiddenByMe();
    final out = <Reel>[];
    for (var i = 0; i < following.length && i < 90; i += 30) {
      final chunk = following.sublist(i, math.min(i + 30, following.length));
      final snap =
          await _reels.where('ownerId', whereIn: chunk).limit(60).get();
      out.addAll(snap.docs.map(Reel.fromDoc).where((r) => _visible(r, hidden)));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<List<Reel>> fetchByOwner(String ownerId) async {
    final snap =
        await _reels.where('ownerId', isEqualTo: ownerId).limit(100).get();
    final mine = ownerId == _uid;
    final reels = snap.docs
        .map(Reel.fromDoc)
        .where((r) => r.videoUrl.isNotEmpty && (mine || !r.hidden))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reels;
  }

  List<ReelCreator>? _creators;
  DateTime? _creatorsAt;

  /// Shops and people who have posted recently, matched by name.
  /// Merchants come first, then the most-viewed.
  Future<List<ReelCreator>> searchCreators(String query) async {
    final fresh = _creatorsAt != null &&
        DateTime.now().difference(_creatorsAt!) < const Duration(minutes: 3);
    if (_creators == null || !fresh) {
      final snap = await _reels
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      final byOwner = <String, ReelCreator>{};
      for (final r in snap.docs.map(Reel.fromDoc)) {
        if (r.hidden || r.videoUrl.isEmpty || r.ownerId.isEmpty) continue;
        final c = byOwner.putIfAbsent(
          r.ownerId,
          () => ReelCreator(
            id: r.ownerId,
            name: r.ownerName,
            photo: r.ownerPhoto,
            isMerchant: r.ownerIsMerchant,
          ),
        );
        c.reelCount++;
        c.viewCount += r.viewCount;
        c.likeCount += r.likeCount;
      }
      _creators = byOwner.values.toList()
        ..sort((a, b) {
          if (a.isMerchant != b.isMerchant) return a.isMerchant ? -1 : 1;
          return b.viewCount.compareTo(a.viewCount);
        });
      _creatorsAt = DateTime.now();
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _creators!;
    return _creators!
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  /// Searches Spotify through the `spotifySearch` Cloud Function.
  Future<List<ReelMusic>> searchSpotify(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('spotifySearch')
          .call({'query': q});
      final data = res.data;
      final raw = data is Map ? data['tracks'] : null;
      if (raw is! List) return const [];
      return raw.map(ReelMusic.fromMap).whereType<ReelMusic>().toList();
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('[Reels] spotifySearch ${e.code}: ${e.message}');
      if (e.code == 'unauthenticated') throw Exception('Sign in to add music.');
      if (e.code == 'failed-precondition' || e.code == 'not-found') {
        throw Exception('Music is not set up yet. Try again later.');
      }
      throw Exception('Could not reach Spotify. Check your connection.');
    }
  }

  /// URL of the reel with the Vero360 watermark and the owner's end card.
  /// The first download of a reel is rendered on the server and can take ~30s.
  Future<String> brandedDownloadUrl(String reelId) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable(
            'prepareReelDownload',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call({'reelId': reelId});
      final data = res.data;
      final url = data is Map ? (data['url'] ?? '').toString() : '';
      if (url.isEmpty) throw Exception('Could not prepare the video. Try again.');
      return url;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('[Reels] prepareReelDownload ${e.code}: ${e.message}');
      if (e.code == 'unauthenticated') throw Exception('Sign in to download reels.');
      if (e.code == 'not-found' && (e.message ?? '').contains('reel')) {
        throw Exception('This reel is no longer available.');
      }
      if (e.code == 'deadline-exceeded') {
        throw Exception('This is taking too long. Try again.');
      }
      throw Exception('Could not prepare the video. Try again.');
    }
  }

  // â”€â”€ Posting â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _contentType(String ext) => switch (ext) {
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        '3gp' => 'video/3gpp',
        _ => 'video/mp4',
      };

  /// Uploads [filePath] and creates the reel; returns its id. [onProgress] gets 0.0â€“1.0.
  Future<String> postReel({
    required String filePath,
    required String caption,
    required Duration duration,
    ReelProduct? product,
    ReelMusic? music,
    void Function(double progress)? onProgress,
  }) async {
    final me = await myIdentity();
    if (me == null) throw Exception('Sign in to post a reel.');
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('That video is no longer on this phone.');
    }
    final size = await file.length();
    if (size <= 0) throw Exception('That video is empty.');
    if (size > maxVideoBytes) {
      throw Exception('That video is too large. Use one under 40 MB.');
    }

    final name = filePath.split(RegExp(r'[\\/]')).last.split('?').first;
    final dot = name.lastIndexOf('.');
    var ext = dot < 0 ? 'mp4' : name.substring(dot + 1).toLowerCase();
    if (!const ['mp4', 'mov', 'webm', '3gp'].contains(ext)) ext = 'mp4';
    // profile_photos/{uid}_* is writable by the owner under the deployed rules.
    final path =
        'profile_photos/${me.uid}_reel_${DateTime.now().microsecondsSinceEpoch}.$ext';
    final ref = _storage.ref().child(path);
    final task = ref.putFile(file, SettableMetadata(contentType: _contentType(ext)));
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    }, onError: (_) {});
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    final url = await ref.getDownloadURL();
    // The poster already has the file: seed the cache so it plays instantly.
    unawaited(ReelVideoCache.instance.adopt(url, file));

    final doc = await _reels.add({
      'ownerId': me.uid,
      'ownerName': me.name,
      'ownerPhoto': me.photo,
      'ownerIsMerchant': me.isMerchant,
      'videoUrl': url,
      'storagePath': path,
      'caption': caption.trim(),
      'durationMs': duration.inMilliseconds,
      if (product != null && me.isMerchant) 'product': product.toMap(),
      if (music != null) 'music': music.toMap(),
      'likeCount': 0,
      'commentCount': 0,
      'viewCount': 0,
      'shareCount': 0,
      'reportCount': 0,
      'hidden': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> deleteReel(Reel reel) async {
    if (reel.ownerId != _uid) throw Exception('You can only delete your own reels.');
    await _reels.doc(reel.id).delete();
    if (reel.storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(reel.storagePath).delete();
      } catch (_) {}
    }
  }

  /// Your marketplace products, for tagging a reel.
  List<ReelProduct>? _myProducts;
  String? _myProductsUid;
  DateTime? _myProductsAt;
  Future<List<ReelProduct>>? _myProductsInFlight;

  List<ReelProduct> _toProducts(QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
      .where((d) => d.data()['isActive'] != false)
      .map((d) {
        final data = d.data();
        return ReelProduct(
          id: d.id,
          name: (data['name'] ?? '').toString().trim(),
          image: (data['image'] ?? data['imageUrl'] ?? '').toString().trim(),
        );
      })
      .where((p) => p.name.isNotEmpty)
      .toList();

  Query<Map<String, dynamic>> _myProductsQuery(String uid) => _db
      .collection('marketplace_items')
      .where('merchantId', isEqualTo: uid)
      .limit(100);

  /// Products already loaded (memory or the phone's Firestore cache), or null.
  Future<List<ReelProduct>?> myProductsQuick() async {
    final uid = _uid;
    if (uid == null) return const [];
    if (_myProductsUid == uid && _myProducts != null) return _myProducts;
    try {
      final snap = await _myProductsQuery(uid).get(const GetOptions(source: Source.cache));
      if (snap.docs.isEmpty) return null;
      return _toProducts(snap);
    } catch (_) {
      return null;
    }
  }

  /// Fresh list from the server; reused for a few minutes and shared by
  /// concurrent callers (the post page warms it before the sheet opens).
  Future<List<ReelProduct>> myProducts({bool refresh = false}) {
    final uid = _uid;
    if (uid == null) return Future.value(const []);
    final fresh = _myProductsUid == uid &&
        _myProducts != null &&
        _myProductsAt != null &&
        DateTime.now().difference(_myProductsAt!) < const Duration(minutes: 5);
    if (fresh && !refresh) return Future.value(_myProducts!);
    return _myProductsInFlight ??= () async {
      try {
        final products = _toProducts(await _myProductsQuery(uid).get());
        _myProducts = products;
        _myProductsUid = uid;
        _myProductsAt = DateTime.now();
        return products;
      } finally {
        _myProductsInFlight = null;
      }
    }();
  }

  // â”€â”€ Engagement â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<bool> isLiked(String reelId) async {
    final uid = _uid;
    if (uid == null) return false;
    final cached = _likedCache[reelId];
    if (cached != null) return cached;
    try {
      final doc =
          await _reels.doc(reelId).collection('likes').doc(uid).get();
      _likedCache[reelId] = doc.exists;
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Returns the new liked state.
  Future<bool> toggleLike(String reelId) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to like reels.');
    final reelRef = _reels.doc(reelId);
    final likeRef = reelRef.collection('likes').doc(uid);
    final liked = await _db.runTransaction<bool>((tx) async {
      final like = await tx.get(likeRef);
      if (like.exists) {
        tx.delete(likeRef);
        tx.update(reelRef, {'likeCount': FieldValue.increment(-1)});
        return false;
      }
      tx.set(likeRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      tx.update(reelRef, {'likeCount': FieldValue.increment(1)});
      return true;
    });
    _likedCache[reelId] = liked;
    return liked;
  }

  /// Counts one view per reel per app session.
  void recordView(String reelId) {
    if (_uid == null || !_viewedThisSession.add(reelId)) return;
    unawaited(_reels
        .doc(reelId)
        .update({'viewCount': FieldValue.increment(1)})
        .catchError((Object e) {
      if (kDebugMode) debugPrint('[ReelService] view: $e');
    }));
  }

  /// Counts a share once per account. Returns true only the first time.
  Future<bool> recordShare(String reelId) async {
    final uid = _uid;
    if (uid == null) return false;
    if (_sharedCache[reelId] == true) return false;
    final reelRef = _reels.doc(reelId);
    final shareRef = reelRef.collection('shares').doc(uid);
    try {
      final counted = await _db.runTransaction<bool>((tx) async {
        final existing = await tx.get(shareRef);
        if (existing.exists) return false;
        tx.set(shareRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.update(reelRef, {'shareCount': FieldValue.increment(1)});
        return true;
      });
      _sharedCache[reelId] = true;
      return counted;
    } catch (e) {
      if (kDebugMode) debugPrint('[ReelService] share: $e');
      return false;
    }
  }

  Future<bool> hasShared(String reelId) async {
    final uid = _uid;
    if (uid == null) return false;
    final cached = _sharedCache[reelId];
    if (cached != null) return cached;
    try {
      final doc = await _reels.doc(reelId).collection('shares').doc(uid).get();
      _sharedCache[reelId] = doc.exists;
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> report(String reelId, String reason) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to report a reel.');
    final reportRef = _reels.doc(reelId).collection('reports').doc(uid);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(reportRef);
      tx.set(reportRef, {
        'uid': uid,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!existing.exists) {
        tx.update(_reels.doc(reelId), {'reportCount': FieldValue.increment(1)});
      }
    });
    await hideForMe(reelId);
  }

  // â”€â”€ Comments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Comments and replies together; the sheet groups replies under their parent.
  Stream<List<ReelComment>> watchComments(String reelId) => _reels
      .doc(reelId)
      .collection('comments')
      .orderBy('createdAt', descending: true)
      .limit(400)
      .snapshots()
      .map((s) => s.docs.map(ReelComment.fromDoc).toList());

  String? get myUid => _uid;

  /// Posts a comment, or a reply when [parentId] is set (replies stay one level deep).
  Future<void> addComment(
    String reelId,
    String text, {
    String? parentId,
    String? replyToName,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final me = await myIdentity();
    if (me == null) throw Exception('Sign in to comment.');
    final reelRef = _reels.doc(reelId);
    final comments = reelRef.collection('comments');
    final batch = _db.batch();
    batch.set(comments.doc(), {
      'uid': me.uid,
      'name': me.name,
      'photo': me.photo,
      'text': body.length > 500 ? body.substring(0, 500) : body,
      if (parentId != null) 'parentId': parentId,
      if (replyToName != null && replyToName.trim().isNotEmpty)
        'replyToName': replyToName.trim(),
      'likedBy': <String>[],
      'dislikedBy': <String>[],
      'replyCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (parentId != null) {
      batch.update(comments.doc(parentId), {'replyCount': FieldValue.increment(1)});
    }
    batch.update(reelRef, {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  /// [reaction] is 'like' or 'dislike'. Tapping the same one again removes it.
  Future<void> reactToComment(
    String reelId,
    ReelComment comment,
    String reaction,
  ) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to react.');
    final ref = _reels.doc(reelId).collection('comments').doc(comment.id);
    final isLike = reaction == 'like';
    final already =
        isLike ? comment.likedBy.contains(uid) : comment.dislikedBy.contains(uid);
    if (already) {
      await ref.update({
        isLike ? 'likedBy' : 'dislikedBy': FieldValue.arrayRemove([uid]),
      });
    } else {
      await ref.update({
        isLike ? 'likedBy' : 'dislikedBy': FieldValue.arrayUnion([uid]),
        isLike ? 'dislikedBy' : 'likedBy': FieldValue.arrayRemove([uid]),
      });
    }
  }

  /// A comment with replies is blanked instead of removed so the thread survives.
  Future<void> deleteComment(String reelId, ReelComment comment) async {
    final reelRef = _reels.doc(reelId);
    final ref = reelRef.collection('comments').doc(comment.id);
    final batch = _db.batch();
    if (!comment.isReply && comment.replyCount > 0) {
      batch.update(ref, {'deleted': true, 'text': ''});
    } else {
      batch.delete(ref);
      batch.update(reelRef, {'commentCount': FieldValue.increment(-1)});
      if (comment.parentId != null) {
        batch.update(reelRef.collection('comments').doc(comment.parentId),
            {'replyCount': FieldValue.increment(-1)});
      }
    }
    await batch.commit();
  }

  // â”€â”€ Following â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<Set<String>> followingIds({bool refresh = false}) async {
    final uid = _uid;
    if (uid == null) return <String>{};
    final cached = _followingCache;
    if (cached != null && !refresh) return cached;
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('followed_merchants')
          .limit(300)
          .get();
      _followingCache = snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      _followingCache ??= <String>{};
    }
    return _followingCache!;
  }

  /// Same documents the shop page Follow button uses.
  Future<void> follow(String ownerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('Sign in to follow.');
    }
    if (ownerId == user.uid) return;
    final me = await myIdentity();
    final batch = _db.batch();
    batch.set(
      _db
          .collection('merchant_followers')
          .doc(ownerId)
          .collection('followers')
          .doc(user.uid),
      {
        'uid': user.uid,
        'email': user.email,
        'displayName': me?.name ?? 'Vero360 member',
        'photoUrl': me?.photo ?? user.photoURL,
        'followedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      _db
          .collection('users')
          .doc(user.uid)
          .collection('followed_merchants')
          .doc(ownerId),
      {'merchantId': ownerId, 'followedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
    (_followingCache ??= <String>{}).add(ownerId);
  }

  Future<void> unfollow(String ownerId) async {
    final uid = _uid;
    if (uid == null) return;
    final batch = _db.batch();
    batch.delete(_db
        .collection('merchant_followers')
        .doc(ownerId)
        .collection('followers')
        .doc(uid));
    batch.delete(_db
        .collection('users')
        .doc(uid)
        .collection('followed_merchants')
        .doc(ownerId));
    await batch.commit();
    _followingCache?.remove(ownerId);
  }

  /// Bio, location and following count for a reels profile.
  Future<ReelProfile> fetchProfile(String ownerId) async {
    Future<Map<String, dynamic>> read(String col) async {
      try {
        final d = await _db.collection(col).doc(ownerId).get();
        return d.data() ?? const {};
      } catch (_) {
        return const {};
      }
    }

    Future<int> followingCount() async {
      try {
        final agg = await _db
            .collection('users')
            .doc(ownerId)
            .collection('followed_merchants')
            .count()
            .get();
        return agg.count ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final results = await Future.wait<Object>([
      read('marketplace_merchants'),
      read('users'),
      followingCount(),
      followerCount(ownerId),
    ]);
    final shop = results[0] as Map<String, dynamic>;
    final user = results[1] as Map<String, dynamic>;
    String pick(List<String> keys) {
      for (final m in [shop, user]) {
        for (final k in keys) {
          final v = (m[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    final role = (user['role'] ?? '').toString().toLowerCase();
    return ReelProfile(
      bio: pick(const ['businessDescription', 'description', 'about', 'bio']),
      location: pick(const ['businessAddress', 'address', 'location', 'city', 'district']),
      shopName: pick(const ['businessName', 'shopName', 'storeName']),
      isMerchant: shop.isNotEmpty || role.contains('merchant'),
      followingCount: results[2] as int,
      followerCount: results[3] as int,
    );
  }

  /// Active marketplace products a merchant sells (for the profile Shop tab).
  Future<List<ReelProduct>> productsOf(String ownerId) async {
    if (ownerId == _uid) return myProducts();
    final snap = await _myProductsQuery(ownerId).get();
    return _toProducts(snap);
  }

  Future<int> followerCount(String ownerId) async {
    try {
      final agg = await _db
          .collection('merchant_followers')
          .doc(ownerId)
          .collection('followers')
          .count()
          .get();
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
