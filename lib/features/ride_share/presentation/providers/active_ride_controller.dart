import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_ride_execution_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/passenger_ride_tracking_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_location_tracker.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_storage.dart';
import 'package:vero360_app/app_nav_key.dart';

/// Coordinates persistence, location tracking, and cold-start resume for active rides.
class ActiveRideController {
  ActiveRideController(this._ref);

  final Ref _ref;
  final ActiveRideLocationTracker _locationTracker = ActiveRideLocationTracker();

  bool get hasActiveRideSession => _locationTracker.isTracking;

  Future<bool> hasPersistedActiveRide() async {
    return (await ActiveRideStorage.load()) != null;
  }

  Future<void> onRideBecameActive({
    required int rideId,
    required ActiveRideRole role,
    required String status,
    int? taxiId,
  }) async {
    await ActiveRideStorage.save(
      rideId: rideId,
      role: role,
      status: status,
      taxiId: taxiId,
    );

    if (role == ActiveRideRole.driver) {
      await _startDriverLocation(rideId: rideId, taxiId: taxiId);
    }
  }

  Future<void> onRideEnded() async {
    await _locationTracker.stop();
    await ActiveRideStorage.clear();
  }

  Future<void> _startDriverLocation({
    required int rideId,
    int? taxiId,
  }) async {
    final http = _ref.read(rideShareHttpServiceProvider);
    final driverService = _ref.read(driverServiceProvider);

    int? resolvedTaxiId = taxiId;
    if (resolvedTaxiId == null) {
      try {
        final profile = await _ref.read(myDriverProfileProvider.future);
        final taxis = profile['taxis'];
        if (taxis is List && taxis.isNotEmpty) {
          final first = taxis.first;
          if (first is Map && first['id'] != null) {
            resolvedTaxiId = int.tryParse(first['id'].toString());
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ActiveRideController] taxi resolve failed: $e');
        }
      }
    }

    await _locationTracker.start(
      rideId: rideId,
      httpService: http,
      driverService: driverService,
      taxiId: resolvedTaxiId,
    );
  }

  /// Resume an active ride after cold start or if the execution screen was dismissed.
  Future<void> resumeIfNeeded() async {
    final persisted = await ActiveRideStorage.load();
    if (persisted == null) return;

    final lifecycle = _ref.read(rideLifecycleProvider);
    if (lifecycle is RideActive && lifecycle.ride.id == persisted.rideId) {
      if (persisted.role == ActiveRideRole.driver) {
        await _startDriverLocation(
          rideId: persisted.rideId,
          taxiId: persisted.taxiId,
        );
      }
      return;
    }

    try {
      if (persisted.role == ActiveRideRole.driver) {
        final profile = await _ref.read(myDriverProfileProvider.future);
        final driverId = int.tryParse(profile['id']?.toString() ?? '');
        if (driverId == null) return;

        final http = _ref.read(rideShareHttpServiceProvider);
        final active = await http.getActiveRidesForDriver(driverId);
        final match = active.where((r) => r.id == persisted.rideId).toList();
        if (match.isEmpty) {
          await onRideEnded();
          return;
        }

        await _ref
            .read(rideLifecycleProvider.notifier)
            .subscribeToRideAsDriver(persisted.rideId);
        await onRideBecameActive(
          rideId: persisted.rideId,
          role: ActiveRideRole.driver,
          status: match.first.status,
          taxiId: persisted.taxiId,
        );
        _navigateToDriverExecution(persisted.rideId);
      } else {
        final http = _ref.read(rideShareHttpServiceProvider);
        final active = await http.getActiveRidesForPassenger();
        final match = active.where((r) => r.id == persisted.rideId).toList();
        if (match.isEmpty) {
          await onRideEnded();
          return;
        }

        await _ref
            .read(rideLifecycleProvider.notifier)
            .subscribeToRideAsPassenger(persisted.rideId);
        _navigateToPassengerTracking(persisted.rideId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ActiveRideController] resume failed: $e');
      }
    }
  }

  void _navigateToDriverExecution(int rideId) {
    final nav = appNavKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => DriverRideExecutionScreen(rideId: rideId),
      ),
    );
  }

  void _navigateToPassengerTracking(int rideId) {
    final nav = appNavKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => PassengerRideTrackingScreen(rideId: rideId),
      ),
    );
  }

  void dispose() {
    _locationTracker.stop();
  }
}

final activeRideControllerProvider = Provider<ActiveRideController>((ref) {
  final controller = ActiveRideController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Widget that resumes active rides once [ProviderScope] is available.
class ActiveRideResumeListener extends ConsumerStatefulWidget {
  final Widget child;

  const ActiveRideResumeListener({super.key, required this.child});

  @override
  ConsumerState<ActiveRideResumeListener> createState() =>
      _ActiveRideResumeListenerState();
}

class _ActiveRideResumeListenerState extends ConsumerState<ActiveRideResumeListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeRideControllerProvider).resumeIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(rideShareHttpServiceProvider).reconnectAndResubscribe();
      ref.read(activeRideControllerProvider).resumeIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
