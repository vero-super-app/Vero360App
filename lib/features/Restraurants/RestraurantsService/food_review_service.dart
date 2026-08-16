import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/GernalServices/api_exception.dart';

/// Firestore `food_reviews` — same fields the merchant dashboard reads.
class FoodReviewService {
  FoodReviewService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const collectionName = 'food_reviews';

  final FirebaseFirestore _db;

  Future<bool> hasReviewedOrder({
    required String orderId,
    required String customerUid,
  }) async {
    final oid = orderId.trim();
    final uid = customerUid.trim();
    if (oid.isEmpty || uid.isEmpty) return false;
    try {
      final snap = await _db
          .collection(collectionName)
          .where('orderId', isEqualTo: oid)
          .limit(20)
          .get();
      for (final d in snap.docs) {
        final cu = (d.data()['customerUid'] ?? '').toString().trim();
        if (cu == uid) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Reviewed [orderId]s for this customer (to hide rate prompts).
  Future<Set<String>> reviewedOrderIdsForCustomer(String customerUid) async {
    final uid = customerUid.trim();
    if (uid.isEmpty) return {};
    try {
      final snap = await _db
          .collection(collectionName)
          .where('customerUid', isEqualTo: uid)
          .limit(100)
          .get();
      return snap.docs
          .map((d) => (d.data()['orderId'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? reviewsStreamForKitchen({
    String? restaurantId,
    String? merchantId,
  }) {
    final rid = restaurantId?.trim() ?? '';
    final mid = merchantId?.trim() ?? '';
    Query<Map<String, dynamic>> q = _db.collection(collectionName);
    if (rid.isNotEmpty) {
      q = q.where('restaurantId', isEqualTo: rid);
    } else if (mid.isNotEmpty) {
      q = q.where('merchantId', isEqualTo: mid);
    } else {
      return null;
    }
    return q.limit(30).snapshots();
  }

  Future<void> submitReview({
    required String orderId,
    required String restaurantId,
    required String merchantId,
    required String customerUid,
    required String customerName,
    required int rating,
    required String comment,
  }) async {
    final oid = orderId.trim();
    final uid = customerUid.trim();
    if (oid.isEmpty || uid.isEmpty) {
      throw const ApiException(message: 'Could not submit review. Try again.');
    }
    final stars = rating.clamp(1, 5);
    final name = customerName.trim().isEmpty ? 'Customer' : customerName.trim();

    final already = await hasReviewedOrder(orderId: oid, customerUid: uid);
    if (already) {
      throw const ApiException(
        message: 'You already reviewed this order.',
      );
    }

    await _db.collection(collectionName).add({
      'orderId': oid,
      'restaurantId': restaurantId.trim(),
      'merchantId': merchantId.trim(),
      'customerUid': uid,
      'customerName': name,
      'rating': stars,
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
