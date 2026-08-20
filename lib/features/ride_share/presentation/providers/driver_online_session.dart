import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';

/// Driver "Go Online" session that survives leaving [DriverDashboard].
///
/// The toggle stays on until explicit [goOffline] or logout. Backgrounding,
/// dashboard reloads, taxi cleanup, and trip-busy availability must not flip it.
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

  /// Used by auth logout (no [Ref] available) to stop broadcasting.
  static Future<void> forceOfflineGlobally() async {
    final session = _active;
    if (session == null) return;
    await session.goOffline();
  }

  Timer? _broadcastTimer;
  bool _resumeBroadcastAfterForeground = false;
  final DriverService _driverService = DriverService();

  @override
  DriverOnlineSessionState build() {
    ref.keepAlive();
    _active = this;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _cancelBroadcastTimer();
      if (_active == this) _active = null;
    });
    return const DriverOnlineSessionState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do not mark unavailable on pause/detached — drivers must keep receiving
    // offers while the app is backgrounded. Only pause the local timer.
    // Note: `state` here is AppLifecycleState; online flags live on `this.state`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (this.state.isOnline) {
        _resumeBroadcastAfterForeground = true;
      }
      _cancelBroadcastTimer();
    } else if (state == AppLifecycleState.resumed) {
      LocationPermissionHelper.onAppResumed();
      if (_resumeBroadcastAfterForeground && this.state.isOnline) {
        _resumeBroadcastAfterForeground = false;
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
      }
      if (_broadcastTimer == null) {
        _startBroadcastTimer();
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
        _broadcastTimer != null &&
        !setAvailabilityOnBackend) {
      return;
    }

    final previous = state;
    state = state.copyWith(isOnline: true, taxiId: taxiId);

    try {
      if (setAvailabilityOnBackend) {
        await _setTaxiAvailability(taxiId, true);
      }
      _startBroadcastTimer();
    } catch (e) {
      state = previous;
      _cancelBroadcastTimer();
      rethrow;
    }
  }

  /// Explicit offline (manual toggle / logout). Does not run on page leave.
  Future<void> goOffline({bool syncBackend = true}) async {
    _resumeBroadcastAfterForeground = false;
    _cancelBroadcastTimer();
    final taxiId = state.taxiId;
    state = state.copyWith(isOnline: false);

    if (syncBackend && taxiId != null) {
      await _setTaxiAvailability(taxiId, false);
    }
  }

  Future<void> _reassertOnline({int? taxiId}) async {
    final id = taxiId ?? state.taxiId;
    if (!state.isOnline || id == null) return;
    if (_onActiveTrip) {
      if (_broadcastTimer == null) _startBroadcastTimer();
      return;
    }
    try {
      await goOnline(taxiId: id, setAvailabilityOnBackend: true);
    } catch (e) {
      if (kDebugMode) {
        print('[DriverOnlineSession] ✗ reassert online: $e');
      }
      if (_broadcastTimer == null) {
        _startBroadcastTimer();
      }
    }
  }

  bool get _onActiveTrip {
    final life = ref.read(rideLifecycleProvider);
    return life is RideActive &&
        (life.isAccepted || life.isDriverArrived || life.isInProgress);
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
    if (!state.isOnline) return;
    final taxiId = state.taxiId;
    if (taxiId == null) return;

    try {
      final position =
          await LocationPermissionHelper.getCurrentPositionIfGranted(
        timeLimit: const Duration(seconds: 5),
      );
      if (position == null) return;

      state = state.copyWith(lastPosition: position);

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
