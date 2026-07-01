import 'dart:convert';

import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class MerchantReviewService {
  const MerchantReviewService();

  Future<MerchantReviewSummary> getMerchantSummary(int merchantId) async {
    final res = await ApiClient.get('/reviews/merchant/$merchantId/summary');
    final map = _unwrapMap(jsonDecode(res.body));
    return MerchantReviewSummary.fromJson(map);
  }

  Future<List<MerchantReview>> getMerchantReviews(int merchantId) async {
    final res = await ApiClient.get('/reviews/merchant/$merchantId');
    return _parseReviewList(jsonDecode(res.body));
  }

  /// Uses `/summary` when available; otherwise derives stats from the review list.
  Future<MerchantReviewSummary> getMerchantReviewSummary(int merchantId) async {
    try {
      final summary = await getMerchantSummary(merchantId);
      if (summary.count > 0 || summary.average > 0) return summary;
    } catch (_) {}

    final reviews = await getMerchantReviews(merchantId);
    if (reviews.isEmpty) {
      return const MerchantReviewSummary(average: 0, count: 0);
    }

    final total = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    return MerchantReviewSummary(
      average: total / reviews.length,
      count: reviews.length,
    );
  }

  Future<({MerchantReviewSummary summary, List<MerchantReview> reviews})>
      loadMerchantReviewsBundle(int merchantId) async {
    final results = await Future.wait([
      getMerchantReviewSummary(merchantId),
      getMerchantReviews(merchantId),
    ]);
    return (
      summary: results[0] as MerchantReviewSummary,
      reviews: results[1] as List<MerchantReview>,
    );
  }

  Future<MerchantReview> createReview({
    required int merchantId,
    required int customerId,
    required int rating,
    required String comment,
  }) async {
    final res = await ApiClient.post(
      '/reviews',
      body: jsonEncode({
        'merchantId': merchantId,
        'customerId': customerId,
        'rating': rating.clamp(1, 5),
        'comment': comment.trim(),
      }),
    );
    return MerchantReview.fromJson(_unwrapMap(jsonDecode(res.body)));
  }

  Future<MerchantReview> updateReview({
    required String reviewId,
    required int rating,
    required String comment,
  }) async {
    final res = await ApiClient.put(
      '/reviews/$reviewId',
      body: jsonEncode({
        'rating': rating.clamp(1, 5),
        'comment': comment.trim(),
      }),
    );
    return MerchantReview.fromJson(_unwrapMap(jsonDecode(res.body)));
  }

  Future<void> deleteReview(String reviewId) async {
    await ApiClient.delete('/reviews/$reviewId');
  }

  Future<MerchantReview> likeReview(String reviewId) async {
    final res = await ApiClient.patch('/reviews/$reviewId/like');
    return MerchantReview.fromJson(_unwrapMap(jsonDecode(res.body)));
  }

  Future<MerchantReview> dislikeReview(String reviewId) async {
    final res = await ApiClient.patch('/reviews/$reviewId/dislike');
    return MerchantReview.fromJson(_unwrapMap(jsonDecode(res.body)));
  }

  List<MerchantReview> _parseReviewList(dynamic decoded) {
    final list = _unwrapList(decoded);
    return list
        .whereType<Map>()
        .map((e) => MerchantReview.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic> _unwrapMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return decoded;
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const ApiException(message: 'Unexpected response from server.');
  }

  List<dynamic> _unwrapList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;
      if (data is Map && data['reviews'] is List) {
        return data['reviews'] as List;
      }
      if (decoded['reviews'] is List) return decoded['reviews'] as List;
    }
    return const [];
  }
}
