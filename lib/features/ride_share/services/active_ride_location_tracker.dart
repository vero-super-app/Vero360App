import 'dart:async';
import 'dart:math' as math;

import 'package:universal_io/io.dart' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';

/// Broadcasts driver GPS during an active trip (foreground + background).
///
/// While [meteringEnabled] is true (typically IN_PROGRESS), accumulates
/// haversine distance between samples into [tripDistanceKm], ignoring jumps
/// larger than [_maxJumpKm] (GPS glitches / teleport).
class ActiveRideLocationTracker {
  static const double _maxJumpKm = 0.5;

  StreamSubscription<Position>? _positionSub;
  Timer? _fallbackTimer;
  int? _rideId;
  int? _taxiId;
  RideShareHttpService? _httpService;
  DriverService? _driverService;

  bool _meteringEnabled = false;
  double _tripDistanceKm = 0;
  double? _lastLat;
  double? _lastLng;

  final ValueNotifier<double> tripDistanceKmListenable = ValueNotifier<double>(0);

  bool get isTracking => _rideId != null;
  bool get meteringEnabled => _meteringEnabled;
  double get tripDistanceKm => _tripDistanceKm;

  /// Enable GPS distance metering for an in-progress trip.
  /// Turning metering on resets the odometer for a fresh trip segment.
  void setMeteringEnabled(bool enabled) {
    if (enabled == _meteringEnabled) return;
    _meteringEnabled = enabled;
    if (enabled) {
      _tripDistanceKm = 0;
      _lastLat = null;
      _lastLng = null;
      tripDistanceKmListenable.value = 0;
    } else {
      _lastLat = null;
      _lastLng = null;
    }
  }

  Future<void> start({
    required int rideId,
    required RideShareHttpService httpService,
    required DriverService driverService,
    int? taxiId,
  }) async {
    if (_rideId == rideId && _positionSub != null) return;

    await stop();
    _rideId = rideId;
    _taxiId = taxiId;
    _httpService = httpService;
    _driverService = driverService;

    await httpService.subscribeDriverTracking(rideId);

    final granted = await LocationPermissionHelper.isAccessGranted();
    if (!granted) {
      await LocationPermissionHelper.requestAccess();
    }

    final settings = await _buildLocationSettings();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      (position) => _publish(position.latitude, position.longitude),
      onError: (e) {
        if (kDebugMode) {
          debugPrint('[ActiveRideLocationTracker] stream error: $e');
        }
      },
    );

    // HTTP fallback if the stream stalls (common on some OEMs).
    _fallbackTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      final pos = await LocationPermissionHelper.getCurrentPositionIfGranted(
        timeLimit: const Duration(seconds: 6),
      );
      if (pos != null) {
        await _publish(pos.latitude, pos.longitude);
      }
    });
  }

  Future<LocationSettings> _buildLocationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Trip in progress',
          notificationText: 'Vero is sharing your location with the passenger',
          enableWakeLock: true,
        ),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      final allowBackground =
          await LocationPermissionHelper.isAlwaysGranted();
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 8,
        allowBackgroundLocationUpdates: allowBackground,
        showBackgroundLocationIndicator: allowBackground,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );
  }

  void _accumulateDistance(double lat, double lng) {
    if (!_meteringEnabled) return;

    final prevLat = _lastLat;
    final prevLng = _lastLng;
    _lastLat = lat;
    _lastLng = lng;
    if (prevLat == null || prevLng == null) return;

    final deltaKm = _haversineKm(prevLat, prevLng, lat, lng);
    if (deltaKm <= 0 || deltaKm > _maxJumpKm) {
      if (kDebugMode && deltaKm > _maxJumpKm) {
        debugPrint(
          '[ActiveRideLocationTracker] ignored jump ${deltaKm.toStringAsFixed(2)}km',
        );
      }
      return;
    }

    _tripDistanceKm += deltaKm;
    tripDistanceKmListenable.value = _tripDistanceKm;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRad(double degrees) => degrees * (math.pi / 180.0);

  Future<void> _publish(double lat, double lng) async {
    final rideId = _rideId;
    final http = _httpService;
    final driverService = _driverService;
    if (rideId == null || http == null || driverService == null) return;

    _accumulateDistance(lat, lng);

    try {
      await http.updateDriverLocationWebSocket(rideId, lat, lng);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ActiveRideLocationTracker] WS location failed: $e');
      }
    }

    final taxiId = _taxiId;
    if (taxiId != null) {
      try {
        await driverService.updateTaxiLocation(taxiId, lat, lng);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ActiveRideLocationTracker] REST location failed: $e');
        }
      }
    }
  }

  Future<void> stop() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    _rideId = null;
    _taxiId = null;
    _httpService = null;
    _driverService = null;
    _meteringEnabled = false;
    _lastLat = null;
    _lastLng = null;
    // Keep last tripDistanceKm readable until the next start/setMeteringEnabled
    // so completeRide can still read it before stop clears session.
  }

  void resetOdometer() {
    _tripDistanceKm = 0;
    _lastLat = null;
    _lastLng = null;
    tripDistanceKmListenable.value = 0;
  }
}
