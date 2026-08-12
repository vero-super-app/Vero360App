import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Denormalized "X people added this to cart" stats (unique users per listing).
class MarketplaceCartSocialService {
  MarketplaceCartSocialService._();

  static final _db = FirebaseFirestore.instance;
  static const collection = 'item_cart_stats';

  /// Call after a successful local add-to-cart. Increments unique people once per uid.
  static Future<void> recordAdd({
    required String itemDocId,
    required String uid,
  }) async {
    final id = itemDocId.trim();
    final user = uid.trim();
    if (id.isEmpty || user.isEmpty || user == 'unknown') return;

    final statsRef = _db.collection(collection).doc(id);
    final adderRef = statsRef.collection('adders').doc(user);

    try {
      await _db.runTransaction((tx) async {
        final adderSnap = await tx.get(adderRef);
        final isNew = !adderSnap.exists;
        tx.set(
          statsRef,
          {
            'cartAddCount': FieldValue.increment(1),
            if (isNew) 'peopleCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (isNew) {
          tx.set(adderRef, {
            'uid': user,
            'addedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MarketplaceCartSocial] recordAdd failed: $e');
      }
    }
  }

  /// Batch-load unique people counts for marketplace cards.
  static Future<Map<String, int>> fetchPeopleCounts(
    Iterable<String> itemDocIds,
  ) async {
    final ids = itemDocIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return {};

    final out = <String, int>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      try {
        final snap = await _db
            .collection(collection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final n = doc.data()['peopleCount'];
          final v = n is num ? n.toInt() : int.tryParse('$n') ?? 0;
          if (v > 0) out[doc.id] = v;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MarketplaceCartSocial] fetchPeopleCounts: $e');
        }
      }
    }
    return out;
  }
}
