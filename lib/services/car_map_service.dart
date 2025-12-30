import 'dart:convert';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';

class CarMapService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Get user's current location
  Future<Position?> getUserLocation() async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
          return position;
        } catch (e) {
          // Fallback: get last known position if timeout occurs
          return await Geolocator.getLastKnownPosition();
        }
      }
    } catch (e) {
      // Location is optional for map - return null to use default location
    }
    return null;
  }

  /// Get available cars with location
  Future<List<CarModel>> getAvailableCarsWithLocation() async {
    try {
      final res = await ApiClient.get(
        '/car-rental/cars/available',
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list
          .map<CarModel>((e) => CarModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw CarMapException(e.message);
    }
  }

  /// Get cars near user location
  Future<List<CarModel>> getNearbyAvailableCars({
    required double latitude,
    required double longitude,
    double radiusInKm = 50,
    bool availableOnly = true,
  }) async {
    try {
      final res = await ApiClient.post(
        '/car-rental/cars-map/nearby',
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'radiusInKm': radiusInKm,
          'availableOnly': availableOnly,
        }),
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list
          .map<CarModel>((e) => CarModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw CarMapException(e.message);
    }
  }

  /// Calculate distance between two coordinates (in km) using Haversine formula
  double calculateDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthRadiusKm = 6371.0;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}

class CarMapException implements Exception {
  final String message;
  CarMapException(this.message);

  @override
  String toString() => message;
}
