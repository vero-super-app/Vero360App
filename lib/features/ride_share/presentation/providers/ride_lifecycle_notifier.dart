import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';

/// Single notifier that owns the entire ride lifecycle.
///
/// Replaces the old dual-system of [RideStateNotifier] + [RideTrackingNotifier].
/// Only one WebSocket subscription exists at a time, managed here.
class RideLifecycleNotifier extends Notifier<RideLifecycleState> {
  late RideShareHttpService _httpService;
  StreamSubscription<Ride>? _rideSub;
  int? _activeRideId;

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
  }

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
      _subscribeToUpdates(ride.id);
    } catch (e) {
      if (kDebugMode) debugPrint('[RideLifecycle] requestRide error: $e');
      state = RideError(message: e.toString());
    }
  }

  // --------------- Join an existing ride (driver or resume) ---------------

  Future<void> subscribeToRide(int rideId) async {
    if (_activeRideId == rideId && _rideSub != null) return;
    _subscribeToUpdates(rideId);

    // Immediately fetch current ride data so UI doesn't stay empty
    // while waiting for the first WebSocket event.
    try {
      final ride = await _httpService.getRideDetails(rideId);
      if (state is RideIdle || state is RideRequesting) {
        if (ride.isCompleted) {
          state = RideCompleted(ride: ride);
        } else if (ride.isCancelled) {
          state = RideCancelled(ride: ride);
        } else {
          state = RideActive(ride: ride);
        }
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
    } catch (e) {
      state = current.copyWith(isLoading: false, actionError: e.toString());
      rethrow;
    }
  }

  // --------------- Reset to idle ---------------

  void reset() {
    _cleanup();
    state = const RideIdle();
  }

  // --------------- Internal ---------------

  void _subscribeToUpdates(int rideId) {
    _rideSub?.cancel();
    _activeRideId = rideId;

    _httpService.subscribeToRideTracking(rideId).catchError((e) {
      if (kDebugMode) debugPrint('[RideLifecycle] subscribe error: $e');
    });

    _rideSub = _httpService.rideUpdateStream.listen(
      (ride) {
        if (ride.id != rideId) return;

        if (ride.isCompleted) {
          state = RideCompleted(ride: ride);
          return;
        }
        if (ride.isCancelled) {
          state = RideCancelled(ride: ride);
          return;
        }

        final current = state;
        state = current is RideActive
            ? current.copyWith(ride: ride, isLoading: false)
            : RideActive(ride: ride);
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
