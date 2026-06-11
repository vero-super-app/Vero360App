import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/active_ride_controller.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_storage.dart';

/// Single notifier that owns the entire ride lifecycle.
///
/// Replaces the old dual-system of [RideStateNotifier] + [RideTrackingNotifier].
/// Only one WebSocket subscription exists at a time, managed here.
class RideLifecycleNotifier extends Notifier<RideLifecycleState> {
  late RideShareHttpService _httpService;
  StreamSubscription<Ride>? _rideSub;
  int? _activeRideId;
  ActiveRideRole? _activeRole;

  @override
  RideLifecycleState build() {
    _httpService = ref.watch(rideShareHttpServiceProvider);
    ref.onDispose(_cleanup);
    return const RideIdle();
  }

  void _cleanup() {
    _rideSub?.cancel();
    _rideSub = null;
    _activeRideId = null;
    _activeRole = null;
    _httpService.clearRideSubscription();
  }

  ActiveRideController get _activeRideController =>
      ref.read(activeRideControllerProvider);

  // --------------- Passenger: request a new ride ---------------

  Future<void> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required String vehicleClass,
    String? pickupAddress,
    String? dropoffAddress,
    String? notes,
  }) async {
    state = const RideRequesting();
    try {
      final ride = await _httpService.requestRide(
        pickupLatitude: pickupLat,
        pickupLongitude: pickupLng,
        dropoffLatitude: dropoffLat,
        dropoffLongitude: dropoffLng,
        vehicleClass: vehicleClass,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        notes: notes,
      );

      if (ride.isCancelled) {
        state = RideCancelled(ride: ride);
        return;
      }

      state = RideActive(ride: ride);
      _subscribeToUpdates(ride.id, role: ActiveRideRole.passenger);
      unawaited(_activeRideController.onRideBecameActive(
        rideId: ride.id,
        role: ActiveRideRole.passenger,
        status: ride.status,
      ));
    } catch (e) {
      if (kDebugMode) debugPrint('[RideLifecycle] requestRide error: $e');
      state = RideError(message: e.toString());
    }
  }

  // --------------- Join an existing ride (driver or resume) ---------------

  Future<void> subscribeToRide(int rideId) async {
    await subscribeToRideAsPassenger(rideId);
  }

  Future<void> subscribeToRideAsDriver(int rideId) async {
    await _subscribeToRideInternal(rideId, ActiveRideRole.driver);
  }

  Future<void> subscribeToRideAsPassenger(int rideId) async {
    await _subscribeToRideInternal(rideId, ActiveRideRole.passenger);
  }

  Future<void> _subscribeToRideInternal(
    int rideId,
    ActiveRideRole role,
  ) async {
    if (_activeRideId != rideId || _rideSub == null || _activeRole != role) {
      _subscribeToUpdates(rideId, role: role);
    }

    // Always merge HTTP snapshot — do not gate on RideIdle. Otherwise a stale
    // RideCancelled/RideCompleted from a previous trip blocks loading the new ride.
    try {
      final ride = await _httpService.getRideDetails(rideId);
      if (ride.id != rideId) return;
      if (ride.isCompleted) {
        state = RideCompleted(ride: ride);
      } else if (ride.isCancelled) {
        state = RideCancelled(ride: ride);
      } else {
        state = RideActive(ride: ride);
        unawaited(_activeRideController.onRideBecameActive(
          rideId: ride.id,
          role: role,
          status: ride.status,
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RideLifecycle] initial fetch error: $e');
      }
    }
  }

  // --------------- Driver actions ---------------

  Future<void> markArrived() async {
    final current = state;
    if (current is! RideActive || _activeRideId == null) return;
    state = current.copyWith(isLoading: true, actionError: null);
    try {
      await _httpService.markDriverArrived(_activeRideId!);
    } catch (e) {
      state = current.copyWith(isLoading: false, actionError: e.toString());
    }
  }

  Future<void> startRide() async {
    final current = state;
    if (current is! RideActive || _activeRideId == null) return;
    state = current.copyWith(isLoading: true, actionError: null);
    try {
      await _httpService.startRide(_activeRideId!);
    } catch (e) {
      state = current.copyWith(isLoading: false, actionError: e.toString());
    }
  }

  Future<void> completeRide({double? actualDistance}) async {
    final current = state;
    if (current is! RideActive || _activeRideId == null) return;
    state = current.copyWith(isLoading: true, actionError: null);
    try {
      await _httpService.completeRide(_activeRideId!, actualDistance: actualDistance);
    } catch (e) {
      state = current.copyWith(isLoading: false, actionError: e.toString());
    }
  }

  // --------------- Shared: cancel ---------------

  Future<void> cancelRide(String reason) async {
    final current = state;
    if (current is! RideActive || _activeRideId == null) return;
    state = current.copyWith(isLoading: true, actionError: null);
    try {
      final cancelled = await _httpService.cancelRide(_activeRideId!, reason: reason);
      state = RideCancelled(ride: cancelled);
      unawaited(_activeRideController.onRideEnded());
    } catch (e) {
      state = current.copyWith(isLoading: false, actionError: e.toString());
      rethrow;
    }
  }

  // --------------- Reset to idle ---------------

  /// Clears UI-bound state only when the trip has fully ended.
  void reset() {
    _cleanup();
    unawaited(_activeRideController.onRideEnded());
    state = const RideIdle();
  }

  /// Detach a screen without tearing down an in-progress ride session.
  void detachScreen() {
    // Intentionally keep subscription + persisted session alive.
  }

  // --------------- Internal ---------------

  void _subscribeToUpdates(int rideId, {required ActiveRideRole role}) {
    _rideSub?.cancel();
    _activeRideId = rideId;
    _activeRole = role;

    final subscribeFuture = role == ActiveRideRole.driver
        ? _httpService.subscribeDriverTracking(rideId)
        : _httpService.subscribeToRideTracking(rideId);
    subscribeFuture.catchError((e) {
      if (kDebugMode) debugPrint('[RideLifecycle] subscribe error: $e');
    });
    _httpService.registerRideSubscription(rideId: rideId, role: role);

    _rideSub = _httpService.rideUpdateStream.listen(
      (ride) {
        if (ride.id != rideId) return;

        if (ride.isCompleted) {
          state = RideCompleted(ride: ride);
          unawaited(_activeRideController.onRideEnded());
          return;
        }
        if (ride.isCancelled) {
          state = RideCancelled(ride: ride);
          unawaited(_activeRideController.onRideEnded());
          return;
        }

        final current = state;
        state = current is RideActive
            ? current.copyWith(ride: ride, isLoading: false)
            : RideActive(ride: ride);

        unawaited(ActiveRideStorage.save(
          rideId: ride.id,
          role: role,
          status: ride.status,
        ));
        if (role == ActiveRideRole.driver) {
          unawaited(_activeRideController.onRideBecameActive(
            rideId: ride.id,
            role: role,
            status: ride.status,
          ));
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[RideLifecycle] stream error: $e');
      },
    );
  }
}

/// The single source of truth for ride state across the entire app.
final rideLifecycleProvider =
    NotifierProvider<RideLifecycleNotifier, RideLifecycleState>(
  RideLifecycleNotifier.new,
);
