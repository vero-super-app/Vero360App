// lib/services/vero_bike_service.dart

import 'dart:convert';

import 'package:vero360_app/models/vero_bike.models.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';

class VeroBikeService {
  const VeroBikeService();

  /// Fetch list of available bikes for a city.
  /// city example: "Lilongwe" or "Blantyre".
  /// authToken is optional (guest user is allowed).
  Future<List<VeroBikeDriver>> fetchAvailableBikes({
    String? city,
    String? authToken,
  }) async {
    final headers = <String, String>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    final query = (city == null || city.trim().isEmpty)
        ? ''
        : '?city=${Uri.encodeQueryComponent(city.trim())}';

    final path = 'verobike/bikes/available$query';

    final res = await ApiClient.get(path, headers: headers);
    // ApiClient will throw ApiException on non-2xx
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }

      return decoded
          .map((e) => VeroBikeDriver.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const ApiException(
        message: 'Failed to parse bike list. Please try again.',
      );
    }
  }
}
