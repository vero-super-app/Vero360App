import 'dart:convert';

import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class MerchantReviewService {
  const MerchantReviewService();

  static const _fastTimeout = Duration(seconds: 6);
  static const _cacheTtl = Duration(minutes: 5);

  /// Shared across shop page + reviews page so "See all" opens instantly.
  static final Map<
          int,
          ({
            MerchantReviewSummary summary,
            List<MerchantReview> reviews,
            DateTime at
          })> _cache =
      <
          int,
          ({
            MerchantReviewSummary summary,
            List<MerchantReview> reviews,
            DateTime at
          })>{};

  static ({MerchantReviewSummary summary, List<MerchantReview> reviews})?
      peekCache(int merchantId) {
    final e = _cache[merchantId];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _cacheTtl) return null;
    return (summary: e.summary, reviews: List<MerchantReview>.from(e.reviews));
  }

  static void putCache({
    required int merchantId,
    required MerchantReviewSummary summary,
    required List<MerchantReview> reviews,
  }) {
    _cache[merchantId] = (
      summary: summary,
      reviews: List<MerchantReview>.from(reviews),
      at: DateTime.now(),
    );
  }

  static void invalidateCache(int merchantId) => _cache.remove(merchantId);

  static void clearAllCache() => _cache.clear();

  Future<MerchantReviewSummary> getMerchantSummary(int merchantId) async {
    final res = await ApiClient.get(
      '/reviews/merchant/$merchantId/summary',
      timeout: _fastTimeout,
    );
    final map = _unwrapMap(jsonDecode(res.body));
    return MerchantReviewSummary.fromJson(map);
  }

  Future<List<MerchantReview>> getMerchantReviews(int merchantId) async {
    final res = await ApiClient.get(
      '/reviews/merchant/$merchantId',
      timeout: _fastTimeout,
    );
    return _parseReviewList(jsonDecode(res.body));
  }

  MerchantReviewSummary _summaryFromReviews(List<MerchantReview> reviews) {
    if (reviews.isEmpty) {
      return const MerchantReviewSummary(average: 0, count: 0);
    }
    final total = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    return MerchantReviewSummary(
      average: total / reviews.length,
      count: reviews.length,
    );
  }

  /// Uses `/summary` when available; otherwise derives stats from the review list.
  Future<MerchantReviewSummary> getMerchantReviewSummary(int merchantId) async {
    try {
      final summary = await getMerchantSummary(merchantId);
      if (summary.count > 0 || summary.average > 0) return summary;
    } catch (_) {}

    final reviews = await getMerchantReviews(merchantId);
    return _summaryFromReviews(reviews);
  }

  /// Fast path: one reviews fetch (+ optional summary in parallel). Caches result.
  Future<({MerchantReviewSummary summary, List<MerchantReview> reviews})>
      loadFast(
    int merchantId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final hit = peekCache(merchantId);
      if (hit != null) return hit;
    }

    MerchantReviewSummary? summary;
    List<MerchantReview> reviews = const [];

    await Future.wait([
      () async {
        try {
          reviews = await getMerchantReviews(merchantId);
        } catch (_) {}
      }(),
      () async {
        try {
          summary = await getMerchantSummary(merchantId);
        } catch (_) {}
      }(),
    ]);

    var resolved = summary;
    if (resolved == null ||
        (resolved.count <= 0 && resolved.average <= 0 && reviews.isNotEmpty)) {
      resolved = _summaryFromReviews(reviews);
    } else if (resolved.count <= 0 && reviews.isNotEmpty) {
      resolved = MerchantReviewSummary(
        average: resolved.average > 0
            ? resolved.average
            : _summaryFromReviews(reviews).average,
        count: reviews.length,
        bayesian: resolved.bayesian,
        wilson: resolved.wilson,
      );
    }

    putCache(merchantId: merchantId, summary: resolved, reviews: reviews);
    return (summary: resolved, reviews: reviews);
  }

  Future<({MerchantReviewSummary summary, List<MerchantReview> reviews})>
      loadMerchantReviewsBundle(int merchantId) => loadFast(merchantId);

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
      timeout: _fastTimeout,
    );
    invalidateCache(merchantId);
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
      timeout: _fastTimeout,
    );
    return MerchantReview.fromJson(_unwrapMap(jsonDecode(res.body)));
  }

  Future<void> deleteReview(String reviewId) async {
    await ApiClient.delete('/reviews/$reviewId', timeout: _fastTimeout);
  }

  Future<MerchantReview> likeReview(String reviewId) async {
    final res = await ApiClient.patch(
      '/reviews/$reviewId/like',
      timeout: _fastTimeout,
    );
    return MerchantReview.fromJson(_unwrapMap(jsonDecode(res.body)));
  }

  Future<MerchantReview> dislikeReview(String reviewId) async {
    final res = await ApiClient.patch(
      '/reviews/$reviewId/dislike',
      timeout: _fastTimeout,
    );
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
