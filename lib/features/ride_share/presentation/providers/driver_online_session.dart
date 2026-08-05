import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';

/// Driver "Go Online" session that survives leaving [DriverDashboard].
///
/// Availability is only cleared on explicit [goOffline], logout, or when the
/// backend marks the taxi busy/unavailable for other reasons (active trip,
/// stale cleanup, inactive status).
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
        _startBroadcastTimer();
      }
    }
  }

  /// Resume from backend taxi availability after returning to the dashboard.
  ///
  /// [hasActiveTrip]: when true, `isAvailable=false` means busy — keep the
  /// online session so location keeps updating. Only drop online when the taxi
  /// is unavailable and the driver is not on a trip (manual offline, cleanup).
  Future<void> syncFromDriverProfile(
    Map<String, dynamic> driver, {
    bool hasActiveTrip = false,
  }) async {
    final taxiId = _primaryTaxiId(driver);
    if (taxiId == null) {
      if (state.isOnline) {
        await goOffline(syncBackend: false);
      }
      return;
    }

    final available = _bool(_primaryTaxi(driver)?['isAvailable']);
    final verified = _bool(driver['isVerified']);
    final hasTaxi =
        driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;

    if ((available || hasActiveTrip) && verified && hasTaxi) {
      if (!state.isOnline || state.taxiId != taxiId) {
        await goOnline(
          taxiId: taxiId,
          // Trip holds availability=false; idle available already true.
          setAvailabilityOnBackend: false,
        );
      }
    } else if (state.isOnline && !available && !hasActiveTrip) {
      _cancelBroadcastTimer();
      state = state.copyWith(isOnline: false, taxiId: taxiId);
    }
  }

  Future<void> goOnline({
    required int taxiId,
    bool setAvailabilityOnBackend = true,
  }) async {
    if (state.isOnline &&
        state.taxiId == taxiId &&
        _broadcastTimer != null) {
      return;
    }

    state = state.copyWith(isOnline: true, taxiId: taxiId);

    if (setAvailabilityOnBackend) {
      await _setTaxiAvailability(taxiId, true);
    }

    _startBroadcastTimer();
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

  Map<String, dynamic>? _primaryTaxi(Map<String, dynamic> driver) {
    final raw = driver['taxis'];
    if (raw is! List || raw.isEmpty) return null;
    final first = raw.first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  int? _primaryTaxiId(Map<String, dynamic> driver) {
    final taxi = _primaryTaxi(driver);
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
