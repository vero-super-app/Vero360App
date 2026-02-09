import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;

  /// Get current user location with error handling. Prefers fresh GPS fix over stale cache.
  Future<Position?> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return position;
    } catch (e) {
      print('Error getting location: $e');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes > 5) {
          return null;
        }
        return lastKnown;
      }
      return null;
    }
  }

  /// Stream continuous location updates
  Stream<Position> getLocationStream({
    int distanceFilter = 10, // Update every 10 meters
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    );
  }

  /// Check if location is within Malawi bounds
  bool isInMalawi(double latitude, double longitude) {
    // Malawi bounds: ~9.2-17.7°S, 32.6-35.9°E
    return latitude >= -17.7 &&
        latitude <= -9.2 &&
        longitude >= 32.6 &&
        longitude <= 35.9;
  }

  void dispose() {
    _positionStream?.cancel();
  }
}
