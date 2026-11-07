import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:vero360_app/app_nav_key.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/passenger_ride_tracking_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_location_tracker.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_storage.dart';

/// When set, [ActiveRideResumeListener] shows a "Continue your ride" banner.
final passengerResumeRideIdProvider = StateProvider<int?>((ref) => null);

/// Coordinates persistence, location tracking, and cold-start resume for active rides.
class ActiveRideController {
  ActiveRideController(this._ref);

  final Ref _ref;
  final ActiveRideLocationTracker _locationTracker = ActiveRideLocationTracker();

  bool get hasActiveRideSession => _locationTracker.isTracking;

  /// GPS-metered trip distance while IN_PROGRESS (driver).
  double get tripDistanceKm => _locationTracker.tripDistanceKm;

  ValueListenable<double> get tripDistanceKmListenable =>
      _locationTracker.tripDistanceKmListenable;

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
      final normalized = status.trim().toUpperCase().replaceAll('-', '_');
      _locationTracker.setMeteringEnabled(normalized == 'IN_PROGRESS');
    }
  }

  Future<void> onRideEnded() async {
    _locationTracker.setMeteringEnabled(false);
    await _locationTracker.stop();
    await ActiveRideStorage.clear();
    _ref.read(passengerResumeRideIdProvider.notifier).state = null;
  }

  void _offerPassengerResume(int rideId) {
    _ref.read(passengerResumeRideIdProvider.notifier).state = rideId;
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
      } else {
        // Stay on Home — offer a banner; do not auto-push tracking.
        _offerPassengerResume(persisted.rideId);
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
        // Stay on Home — do not auto-push the ride map on launch.
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
        // Stay on Home — user opens tracking from the resume banner.
        _offerPassengerResume(persisted.rideId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ActiveRideController] resume failed: $e');
      }
    }
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

  void _openPassengerTracking(int rideId) {
    ref.read(passengerResumeRideIdProvider.notifier).state = null;
    final nav = appNavKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => PassengerRideTrackingScreen(rideId: rideId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumeRideId = ref.watch(passengerResumeRideIdProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (resumeRideId != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                elevation: 4,
                color: RideShareColors.primarySoft,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_taxi_rounded,
                        color: RideShareColors.primaryDeep,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Continue your ride',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: RideShareColors.titleText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _openPassengerTracking(resumeRideId),
                        child: const Text(
                          'Open',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: RideShareColors.primaryDeep,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () {
                          ref
                              .read(passengerResumeRideIdProvider.notifier)
                              .state = null;
                        },
                        icon: const Icon(Icons.close, size: 18),
                        color: RideShareColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
