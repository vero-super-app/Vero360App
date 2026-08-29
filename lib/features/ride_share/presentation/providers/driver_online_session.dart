import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';

/// Driver "Go Online" session that survives leaving [DriverDashboard],
/// backgrounding the app, and process death (restored from prefs).
///
/// The toggle stays on until explicit [goOffline] or logout. Matching GPS
/// keeps running in the background via a foreground location service — the
/// same pattern as active-trip tracking.
class DriverOnlineSessionState {
  final bool isOnline;
  final int? taxiId;
  final Position? lastPosition;

  const DriverOnlineSessionState({
    this.isOnline = false,
    this.taxiId,
    this.lastPosition,
  });

  DriverOnlineSessionState copyWith({
    bool? isOnline,
    int? taxiId,
    Position? lastPosition,
    bool clearTaxiId = false,
    bool clearLastPosition = false,
  }) {
    return DriverOnlineSessionState(
      isOnline: isOnline ?? this.isOnline,
      taxiId: clearTaxiId ? null : (taxiId ?? this.taxiId),
      lastPosition:
          clearLastPosition ? null : (lastPosition ?? this.lastPosition),
    );
  }
}

class DriverOnlineSessionNotifier extends Notifier<DriverOnlineSessionState>
    with WidgetsBindingObserver {
  static DriverOnlineSessionNotifier? _active;

  static const _prefsOnlineKey = 'driver_online_session_active';
  static const _prefsTaxiIdKey = 'driver_online_session_taxi_id';

  /// Used by auth logout (no [Ref] available) to stop broadcasting.
  static Future<void> forceOfflineGlobally() async {
    final session = _active;
    if (session == null) {
      await _clearPersistedSession();
      return;
    }
    await session.goOffline();
  }

  Timer? _broadcastTimer;
  StreamSubscription<Position>? _positionSub;
  int _streamEpoch = 0;
  final DriverService _driverService = DriverService();

  @override
  DriverOnlineSessionState build() {
    ref.keepAlive();
    _active = this;
    WidgetsBinding.instance.addObserver(this);
    ref.listen<RideLifecycleState>(rideLifecycleProvider, (prev, next) {
      if (!state.isOnline) return;
      if (_tripOwnsGps(next)) {
        _stopPublishers();
      } else if (_positionSub == null && _broadcastTimer == null) {
        _startPublishers();
      }
    });
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _stopPublishers();
      if (_active == this) _active = null;
    });
    unawaited(_restorePersistedSession());
    return const DriverOnlineSessionState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep matching GPS while backgrounded. Only heal the publishers if they
    // died (OEM kill, permission revoke) when we return to the foreground.
    if (state == AppLifecycleState.resumed) {
      LocationPermissionHelper.onAppResumed();
      if (this.state.isOnline &&
          !_onActiveTrip &&
          _positionSub == null &&
          _broadcastTimer == null) {
        unawaited(_reassertOnline());
      }
    }
  }

  /// Resume from backend taxi availability after returning to the dashboard.
  ///
  /// A live local session is sticky: the toggle does not turn off unless the
  /// driver (or logout) calls [goOffline]. Stale profile cache, taxi cleanup,
  /// and trip-busy `isAvailable=false` must not flip the switch.
  Future<void> syncFromDriverProfile(
    Map<String, dynamic> driver, {
    bool hasActiveTrip = false,
  }) async {
    final taxiId = _primaryTaxiId(driver, preferId: state.taxiId);
    if (taxiId == null) {
      return;
    }

    final busy = hasActiveTrip || _onActiveTrip;
    final available = _bool(_primaryTaxi(driver, preferId: taxiId)?['isAvailable']);
    final verified = _bool(driver['isVerified']);
    final hasTaxi =
        driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;

    if (state.isOnline) {
      if (!busy && !available) {
        // Cleanup / stale cache dropped availability. Keep the toggle on.
        await _reassertOnline(taxiId: taxiId);
      } else if (state.taxiId != taxiId) {
        state = state.copyWith(taxiId: taxiId);
        await _persistSession();
      }
      if (!_onActiveTrip && _positionSub == null && _broadcastTimer == null) {
        _startPublishers();
      }
      return;
    }

    if ((available || hasActiveTrip) && verified && hasTaxi) {
      await goOnline(
        taxiId: taxiId,
        setAvailabilityOnBackend: false,
      );
    }
  }

  Future<void> goOnline({
    required int taxiId,
    bool setAvailabilityOnBackend = true,
  }) async {
    if (state.isOnline &&
        state.taxiId == taxiId &&
        (_positionSub != null || _broadcastTimer != null) &&
        !setAvailabilityOnBackend) {
      return;
    }

    final previous = state;
    state = state.copyWith(isOnline: true, taxiId: taxiId);
    await _persistSession();

    try {
      if (setAvailabilityOnBackend) {
        await _setTaxiAvailability(taxiId, true);
      }
      _startPublishers();
    } catch (e) {
      state = previous;
      _stopPublishers();
      await _persistSession();
      rethrow;
    }
  }

  /// Explicit offline (manual toggle / logout / leaving driver mode).
  Future<void> goOffline({bool syncBackend = true}) async {
    _stopPublishers();
    final taxiId = state.taxiId;
    state = state.copyWith(isOnline: false);
    await _clearPersistedSession();

    if (syncBackend && taxiId != null) {
      await _setTaxiAvailability(taxiId, false);
    }
  }

  Future<void> _reassertOnline({int? taxiId}) async {
    final id = taxiId ?? state.taxiId;
    if (!state.isOnline || id == null) return;
    if (_onActiveTrip) {
      _stopPublishers();
      return;
    }
    try {
      await goOnline(taxiId: id, setAvailabilityOnBackend: true);
    } catch (e) {
      if (kDebugMode) {
        print('[DriverOnlineSession] ✗ reassert online: $e');
      }
      if (_positionSub == null && _broadcastTimer == null) {
        _startPublishers();
      }
    }
  }

  bool get _onActiveTrip => _tripOwnsGps(ref.read(rideLifecycleProvider));

  bool _tripOwnsGps(RideLifecycleState life) {
    return life is RideActive &&
        (life.isAccepted || life.isDriverArrived || life.isInProgress);
  }

  void _startPublishers() {
    if (_onActiveTrip) {
      _stopPublishers();
      return;
    }
    _startLocationStream();
    _startBroadcastTimer();
  }

  void _stopPublishers() {
    _streamEpoch++;
    _cancelBroadcastTimer();
    unawaited(_positionSub?.cancel());
    _positionSub = null;
  }

  void _startLocationStream() {
    final epoch = ++_streamEpoch;
    unawaited(_positionSub?.cancel());
    _positionSub = null;
    unawaited(() async {
      try {
        final granted = await LocationPermissionHelper.isAccessGranted();
        if (epoch != _streamEpoch || !granted || !state.isOnline) return;
        final settings = await _buildLocationSettings();
        if (epoch != _streamEpoch || !state.isOnline) return;
        _positionSub = Geolocator.getPositionStream(locationSettings: settings)
            .listen(
          (position) {
            unawaited(_publishPosition(position));
          },
          onError: (e) {
            if (kDebugMode) {
              print('[DriverOnlineSession] ✗ location stream: $e');
            }
          },
        );
      } catch (e) {
        if (kDebugMode) {
          print('[DriverOnlineSession] ✗ start location stream: $e');
        }
      }
    }());
  }

  Future<LocationSettings> _buildLocationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'You are online',
          notificationText: 'Vero is sharing your location with nearby riders',
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
        distanceFilter: 20,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: allowBackground,
        showBackgroundLocationIndicator: allowBackground,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );
  }

  void _startBroadcastTimer() {
    _cancelBroadcastTimer();
    // Immediate ping so matching geo stays fresh after resume/navigation.
    unawaited(_broadcastOnce());
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_broadcastOnce());
    });
  }

  void _cancelBroadcastTimer() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  Future<void> _broadcastOnce() async {
    if (!state.isOnline || _onActiveTrip) return;
    try {
      final position =
          await LocationPermissionHelper.getCurrentPositionIfGranted(
        timeLimit: const Duration(seconds: 5),
      );
      if (position == null) return;
      await _publishPosition(position);
    } catch (e) {
      if (kDebugMode) {
        print('[DriverOnlineSession] ✗ location broadcast: $e');
      }
    }
  }

  Future<void> _publishPosition(Position position) async {
    if (!state.isOnline) return;
    final taxiId = state.taxiId;
    if (taxiId == null) return;

    state = state.copyWith(lastPosition: position);

    try {
      await _driverService.updateTaxiLocation(
        taxiId,
        position.latitude,
        position.longitude,
      );
      if (kDebugMode) {
        print(
          '[DriverOnlineSession] ✓ location → taxi $taxiId '
          '(${position.latitude}, ${position.longitude})',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DriverOnlineSession] ✗ location broadcast: $e');
      }
    }
  }

  Future<void> _setTaxiAvailability(int taxiId, bool isAvailable) async {
    try {
      await _driverService.setTaxiAvailability(taxiId, isAvailable);
      if (kDebugMode) {
        print(
          '[DriverOnlineSession] ✓ availability=$isAvailable taxi=$taxiId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DriverOnlineSession] ✗ set availability: $e');
      }
      rethrow;
    }
  }

  void noteLastPosition(Position position) {
    state = state.copyWith(lastPosition: position);
  }

  Future<void> _restorePersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = RoleHelper.normalizeAccountRole(
            prefs.getString('user_role') ?? prefs.getString('role'),
          ) ??
          '';
      final online = prefs.getBool(_prefsOnlineKey) ?? false;
      final taxiId = prefs.getInt(_prefsTaxiIdKey);
      if (!online || taxiId == null || role != RoleHelper.driver) {
        if (role != RoleHelper.driver) {
          await _clearPersistedSession();
        }
        return;
      }
      if (_active != this) return;
      state = state.copyWith(isOnline: true, taxiId: taxiId);
      _startPublishers();
      unawaited(_reassertOnline(taxiId: taxiId));
    } catch (e) {
      if (kDebugMode) {
        print('[DriverOnlineSession] ✗ restore session: $e');
      }
    }
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state.isOnline && state.taxiId != null) {
        await prefs.setBool(_prefsOnlineKey, true);
        await prefs.setInt(_prefsTaxiIdKey, state.taxiId!);
      } else {
        await prefs.remove(_prefsOnlineKey);
        await prefs.remove(_prefsTaxiIdKey);
      }
    } catch (_) {}
  }

  static Future<void> _clearPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsOnlineKey);
      await prefs.remove(_prefsTaxiIdKey);
    } catch (_) {}
  }

  Map<String, dynamic>? _primaryTaxi(
    Map<String, dynamic> driver, {
    int? preferId,
  }) {
    final raw = driver['taxis'];
    if (raw is! List || raw.isEmpty) return null;
    final taxis = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (taxis.isEmpty) return null;
    if (preferId != null) {
      for (final taxi in taxis) {
        if (int.tryParse('${taxi['id']}') == preferId) return taxi;
      }
    }
    for (final taxi in taxis) {
      if ((taxi['status']?.toString() ?? '') == 'ACTIVE') return taxi;
    }
    return taxis.first;
  }

  int? _primaryTaxiId(Map<String, dynamic> driver, {int? preferId}) {
    final taxi = _primaryTaxi(driver, preferId: preferId);
    if (taxi == null) return null;
    return int.tryParse('${taxi['id']}');
  }

  bool _bool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is num) return value != 0;
    return false;
  }
}

final driverOnlineSessionProvider =
    NotifierProvider<DriverOnlineSessionNotifier, DriverOnlineSessionState>(
  DriverOnlineSessionNotifier.new,
);

/// Profile / Settings driver-mode toggle. Persists the role locally first
/// (works offline), refreshes the session cache, and drops taxi availability
/// when leaving driver mode so a later server sync cannot undo the switch.
Future<bool> applySessionRole(String role) async {
  final prefs = await SharedPreferences.getInstance();
  final previous = RoleSessionService.readCachedRole(prefs);
  final normalized =
      RoleHelper.normalizeAccountRole(role) ?? RoleHelper.customer;
  final ok = await RoleSessionService.setAccountRole(normalized);
  await loadDriverStatusFromPrefs();
  if (previous == RoleHelper.driver && normalized != RoleHelper.driver) {
    await DriverOnlineSessionNotifier.forceOfflineGlobally();
  }
  return ok;
}
