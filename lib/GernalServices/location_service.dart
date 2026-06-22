import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;

  /// Get current user location with error handling. Prefers fresh GPS fix over stale cache.
  Future<Position?> getCurrentLocation() async {
    try {
      if (LocationPermissionHelper.isKnownGranted) {
        final position =
            await LocationPermissionHelper.getCurrentPositionIfGranted(
          timeLimit: const Duration(seconds: 15),
        );
        if (position != null) return position;
      }

      final issue = await LocationPermissionHelper.checkAccessIssue();
      if (issue == LocationAccessIssue.permissionDenied) {
        await LocationPermissionHelper.requestAccess();
      }

      final position =
          await LocationPermissionHelper.getCurrentPositionIfGranted(
        timeLimit: const Duration(seconds: 15),
      );
      if (position != null) return position;
    } catch (e) {
      print('Error getting location: $e');
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      final age = DateTime.now().difference(lastKnown.timestamp);
      if (age.inMinutes <= 5) {
        return lastKnown;
      }
    }
    return null;
  }

  /// Stream continuous location updates
  Stream<Position> getLocationStream({
    int distanceFilter = 10, // Update every 10 meters
  }) async* {
    if (!await LocationPermissionHelper.isAccessGranted()) return;

    yield* Geolocator.getPositionStream(
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
