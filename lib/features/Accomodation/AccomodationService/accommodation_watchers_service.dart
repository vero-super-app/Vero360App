import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live “X people watching this stay” via Firestore presence.
///
/// `accommodation_watchers/{listingId}` `{ activeCount }`
/// `…/viewers/{viewerId}` `{ lastSeen }`
class AccommodationWatchersService {
  AccommodationWatchersService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const _prefsViewerKey = 'acc_watcher_session_v1';
  static const staleAfter = Duration(seconds: 90);

  static String? _cachedViewerId;

  DocumentReference<Map<String, dynamic>> _root(int listingId) =>
      _db.collection('accommodation_watchers').doc('$listingId');

  CollectionReference<Map<String, dynamic>> _viewers(int listingId) =>
      _root(listingId).collection('viewers');

  Future<String> viewerId() async {
    if (_cachedViewerId != null && _cachedViewerId!.isNotEmpty) {
      return _cachedViewerId!;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      _cachedViewerId = uid;
      return uid;
    }
    final prefs = await SharedPreferences.getInstance();
    var id = (prefs.getString(_prefsViewerKey) ?? '').trim();
    if (id.isEmpty) {
      id = 'anon_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
      await prefs.setString(_prefsViewerKey, id);
    }
    _cachedViewerId = id;
    return id;
  }

  Future<void> join(int listingId) => _touch(listingId, leaving: false);

  Future<void> heartbeat(int listingId) => _touch(listingId, leaving: false);

  Future<void> leave(int listingId) => _touch(listingId, leaving: true);

  Future<void> _touch(int listingId, {required bool leaving}) async {
    if (listingId <= 0) return;
    final vid = await viewerId();
    final parent = _root(listingId);
    final viewer = _viewers(listingId).doc(vid);
    try {
      if (leaving) {
        final existed = (await viewer.get()).exists;
        await viewer.delete();
        if (existed) {
          await parent.set({
            'activeCount': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        return;
      }

      final prev = await viewer.get();
      var wasActive = false;
      if (prev.exists) {
        final ts = prev.data()?['lastSeen'];
        if (ts is Timestamp) {
          wasActive =
              DateTime.now().difference(ts.toDate()) < staleAfter;
        } else {
          wasActive = true;
        }
      }
      await viewer.set({
        'lastSeen': FieldValue.serverTimestamp(),
      });
      if (!wasActive) {
        await parent.set({
          'activeCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Stream<int> watchCount(int listingId) {
    if (listingId <= 0) return Stream<int>.value(0);
    return _viewers(listingId).snapshots().map((snap) {
      final cutoff = DateTime.now().subtract(staleAfter);
      var n = 0;
      for (final doc in snap.docs) {
        final ts = doc.data()['lastSeen'];
        if (ts is Timestamp) {
          if (ts.toDate().isAfter(cutoff)) n++;
        } else {
          n++;
        }
      }
      return n;
    });
  }

  Future<Map<int, int>> fetchCounts(Iterable<int> listingIds) async {
    final ids = listingIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) return {};
    final out = <int, int>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      try {
        final snap = await _db
            .collection('accommodation_watchers')
            .where(FieldPath.documentId, whereIn: chunk.map((e) => '$e').toList())
            .get();
        for (final doc in snap.docs) {
          final id = int.tryParse(doc.id) ?? 0;
          if (id <= 0) continue;
          final raw = doc.data()['activeCount'];
          final n = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
          if (n > 0) out[id] = n;
        }
      } catch (_) {}
    }
    return out;
  }
}
