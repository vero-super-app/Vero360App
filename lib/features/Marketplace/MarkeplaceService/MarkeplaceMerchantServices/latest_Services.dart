// lib/services/latest_Services.dart
// Uses ApiClient which attaches auth via AuthHandler.getTokenForApi() (single source of truth).
import 'dart:convert';

import 'package:vero360_app/features/Marketplace/MarkeplaceModel/Latest_model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class LatestArrivalServices {
  Future<List<LatestArrivalModels>> fetchLatestArrivals() async {
    try {
      // ApiClient auto-attaches Bearer token from AuthHandler (Firebase then SP).
      final response = await ApiClient.get('/latestarrivals');

      final decoded = jsonDecode(response.body);

      // Accept either `[{...}, ...]` or `{"data":[{...}]}`.
      final List list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List)
              ? decoded['data'] as List
              : <dynamic>[];

      final items = list
          .whereType<Map<String, dynamic>>()
          .map<LatestArrivalModels>((m) => LatestArrivalModels.fromJson(m))
          .toList();

      // Only show arrivals created in the last 24 hours when timestamps are present.
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final withDates =
          items.where((it) => it.createdAt != null).toList();
      if (withDates.isEmpty) {
        // If backend doesn't send createdAt yet, fall back to all.
        return items;
      }

      withDates.retainWhere((it) => !it.createdAt!.isBefore(cutoff));
      withDates.sort((a, b) =>
          (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      return withDates;
    } on ApiException {
      // Re-throw so UI can handle a clean message
      rethrow;
    } catch (_) {
      // Any weird decode errors, etc.
      throw const ApiException(
        message: 'Failed to load today\'s latest arrivals. Please check your internet and try again.',
      );
    }
  }
}
