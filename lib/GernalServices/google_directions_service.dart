import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/config/google_maps_config.dart';

/// Model for route information
class RouteInfo {
  final double distanceKm;
  final int durationMinutes;
  final String polyline;

  RouteInfo({
    required this.distanceKm,
    required this.durationMinutes,
    required this.polyline,
  });

  @override
  String toString() =>
      'RouteInfo(${distanceKm}km, ${durationMinutes}min)';
}

/// Google Directions API Service
/// 
/// Calculates distance, duration, and route between two locations
class GoogleDirectionsService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const Duration _timeout = Duration(seconds: 10);

  late final String _apiKey;

  GoogleDirectionsService({String? apiKey}) {
    _apiKey = apiKey ?? GoogleMapsConfig.apiKey;
    if (_apiKey.isEmpty) {
      throw const ApiException(
        message: 'Google Maps API key not configured. '
            'Run: flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key',
      );
    }
    if (kDebugMode) {
      debugPrint('[GoogleDirections] Service initialized');
    }
  }

  /// Calculate route details between two locations
  /// 
  /// Returns [RouteInfo] with distance in kilometers and duration in minutes
  Future<RouteInfo> getRouteInfo({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final origin = '$originLat,$originLng';
      final destination = '$destLat,$destLng';

      final queryParams = {
        'origin': origin,
        'destination': destination,
        'key': _apiKey,
        'mode': 'driving',
      };

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

      if (kDebugMode) {
        debugPrint('[GoogleDirections] Requesting route: $origin → $destination');
      }

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw ApiException(
          message: 'HTTP ${response.statusCode}: Failed to fetch directions',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final status = jsonResponse['status'] as String? ?? '';

      if (kDebugMode) {
        debugPrint('[GoogleDirections] Status: $status');
      }

      if (status == 'ZERO_RESULTS') {
        throw ApiException(
          message: 'No route found between these locations',
        );
      }

      if (status != 'OK') {
        final errorMsg = jsonResponse['error_message'] as String? ?? 'Unknown error';
        
        if (status == 'REQUEST_DENIED') {
          throw ApiException(
            message: 'Google Maps billing not enabled. '
                'Enable billing at: https://console.cloud.google.com/project/_/billing/enable',
          );
        }
        
        throw ApiException(message: 'API Error [$status]: $errorMsg');
      }

      final routes = jsonResponse['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty) {
        throw ApiException(message: 'No routes returned from API');
      }

      final route = routes.first as Map<String, dynamic>;
      final legs = (route['legs'] as List<dynamic>? ?? []);

      if (legs.isEmpty) {
        throw ApiException(message: 'No route legs found');
      }

      final leg = legs.first as Map<String, dynamic>;

      // Extract distance and duration
      final distanceData = leg['distance'] as Map<String, dynamic>?;
      final durationData = leg['duration'] as Map<String, dynamic>?;

      final distanceMeters = (distanceData?['value'] as num?)?.toInt() ?? 0;
      final durationSeconds = (durationData?['value'] as num?)?.toInt() ?? 0;

      final distanceKm = distanceMeters / 1000;
      final durationMinutes = (durationSeconds / 60).round();

      // Extract polyline
      final polylineData = route['overview_polyline'] as Map<String, dynamic>?;
      final polyline = polylineData?['points'] as String? ?? '';

      if (kDebugMode) {
        debugPrint(
            '[GoogleDirections] ✅ Route found: ${distanceKm.toStringAsFixed(2)}km, ${durationMinutes}min');
      }

      return RouteInfo(
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        polyline: polyline,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GoogleDirections] Error: $e');
      }
      throw ApiException(
        message: 'Error fetching route: ${e.toString()}',
      );
    }
  }
}
