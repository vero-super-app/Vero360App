import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';

/// Broadcasts driver GPS during an active trip (foreground + background).
class ActiveRideLocationTracker {
  StreamSubscription<Position>? _positionSub;
  Timer? _fallbackTimer;
  int? _rideId;
  int? _taxiId;
  RideShareHttpService? _httpService;
  DriverService? _driverService;

  bool get isTracking => _rideId != null;

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

    final settings = _buildLocationSettings();
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

  LocationSettings _buildLocationSettings() {
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
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 8,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );
  }

  Future<void> _publish(double lat, double lng) async {
    final rideId = _rideId;
    final http = _httpService;
    final driverService = _driverService;
    if (rideId == null || http == null || driverService == null) return;

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
  }
}
