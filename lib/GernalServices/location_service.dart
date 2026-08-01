import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;

  static const _latKey = 'vero_last_lat';
  static const _lngKey = 'vero_last_lng';
  static const _tsKey = 'vero_last_loc_ts';

  /// Instant position for food ranking: memory prefs / last-known GPS (no wait).
  Future<Position?> getQuickPosition() async {
    // 1) App-persisted coords (fastest)
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_latKey);
      final lng = prefs.getDouble(_lngKey);
      final tsMs = prefs.getInt(_tsKey);
      if (lat != null && lng != null) {
        final ts = tsMs != null
            ? DateTime.fromMillisecondsSinceEpoch(tsMs)
            : DateTime.now();
        final age = DateTime.now().difference(ts);
        if (age.inDays <= 7) {
          return Position(
            latitude: lat,
            longitude: lng,
            timestamp: ts,
            accuracy: 100,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        }
      }
    } catch (_) {}

    // 2) OS last-known (still no GPS wait)
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inDays <= 7) {
          unawaited(persistPosition(lastKnown));
          return lastKnown;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> persistPosition(Position pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_latKey, pos.latitude);
      await prefs.setDouble(_lngKey, pos.longitude);
      await prefs.setInt(_tsKey, pos.timestamp.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Fast fix for food / nearby ranking. Low accuracy + short timeout.
  /// Never hangs: falls back to [getQuickPosition] after a few seconds.
  Future<Position?> getCurrentLocation({
    Duration timeLimit = const Duration(seconds: 4),
  }) async {
    final quick = await getQuickPosition();

    try {
      if (!LocationPermissionHelper.isKnownGranted) {
        final issue = await LocationPermissionHelper.checkAccessIssue()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        if (issue == LocationAccessIssue.permissionDenied) {
          await LocationPermissionHelper.requestAccess()
              .timeout(const Duration(seconds: 6), onTimeout: () => false);
        }
      }

      final fresh = await LocationPermissionHelper.getCurrentPositionIfGranted(
        accuracy: LocationAccuracy.low,
        timeLimit: timeLimit,
      ).timeout(timeLimit + const Duration(milliseconds: 400), onTimeout: () => null);

      if (fresh != null) {
        unawaited(persistPosition(fresh));
        return fresh;
      }
    } catch (_) {}

    // Prefer any recent last-known over null.
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        unawaited(persistPosition(lastKnown));
        return lastKnown;
      }
    } catch (_) {}

    return quick;
  }

  /// Stream continuous location updates
  Stream<Position> getLocationStream({
    int distanceFilter = 10, // Update every 10 meters
  }) async* {
    if (!await LocationPermissionHelper.isAccessGranted()) return;

    yield* Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.low,
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
