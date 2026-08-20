import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/features/Restraurants/Models/food_model.dart';

/// Tracks food views / clicks / asks so Popular Food ranks real interest.
class FoodEngagementService {
  FoodEngagementService._();

  static final _db = FirebaseFirestore.instance;
  static const _col = 'food_engagement';

  /// Stable doc id for a dish across API / Firestore sources.
  static String itemKey(FoodModel item) {
    final fs = (item.firestoreListingId ?? '').trim();
    if (fs.isNotEmpty) return 'fs_$fs';
    if (item.id > 0) return 'id_${item.id}';
    final mid = (item.merchantId ?? item.restaurantId ?? '').trim();
    final name = item.FoodName.trim().toLowerCase();
    if (mid.isNotEmpty && name.isNotEmpty) {
      return 'm_${mid}_${name.hashCode.abs()}';
    }
    return 'n_${name.hashCode.abs()}';
  }

  static Future<void> recordView(FoodModel item) =>
      _bump(item, field: 'views', weight: 1);

  static Future<void> recordClick(FoodModel item) =>
      _bump(item, field: 'clicks', weight: 3);

  static Future<void> recordAsk(FoodModel item) =>
      _bump(item, field: 'asks', weight: 5);

  static Future<void> _bump(
    FoodModel item, {
    required String field,
    required int weight,
  }) async {
    final key = itemKey(item);
    if (key.isEmpty) return;
    try {
      await _db.collection(_col).doc(key).set({
        field: FieldValue.increment(1),
        'score': FieldValue.increment(weight),
        'name': item.FoodName,
        'restaurant': item.RestrauntName,
        'merchantId': item.merchantId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Map of itemKey → engagement score (higher = more popular).
  static Future<Map<String, int>> fetchScores({int limit = 80}) async {
    try {
      final snap = await _db
          .collection(_col)
          .orderBy('score', descending: true)
          .limit(limit)
          .get();
      final out = <String, int>{};
      for (final d in snap.docs) {
        final score = d.data()['score'];
        out[d.id] = score is num ? score.toInt() : 0;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Sort [items] by engagement (watched / clicked / asked), then name.
  static List<FoodModel> sortPopular(
    List<FoodModel> items,
    Map<String, int> scores, {
    int take = 12,
  }) {
    final copy = List<FoodModel>.from(items);
    copy.sort((a, b) {
      final sa = scores[itemKey(a)] ?? 0;
      final sb = scores[itemKey(b)] ?? 0;
      if (sb != sa) return sb.compareTo(sa);
      return a.FoodName.toLowerCase().compareTo(b.FoodName.toLowerCase());
    });
    if (take <= 0 || copy.length <= take) return copy;
    return copy.take(take).toList();
  }
}
