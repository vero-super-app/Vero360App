import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';

/// Unified state view model for a single active ride
class RideStateVM {
  final Ride? ride;
  final bool isLoading;
  final String? error;
  final DateTime? lastUpdate;

  RideStateVM({
    this.ride,
    this.isLoading = false,
    this.error,
    this.lastUpdate,
  });

  /// Current ride status from the ride object
  String get status => ride?.status ?? RideStatus.requested;

  /// Check if ride is in a specific state
  bool isStatus(String state) => status == state;

  /// Check if ride has progressed beyond a certain state
  bool isPastStatus(String state) {
    const stateOrder = [
      RideStatus.requested,
      RideStatus.accepted,
      RideStatus.driverArrived,
      RideStatus.inProgress,
      RideStatus.completed,
    ];
    final currentIdx = stateOrder.indexOf(status);
    final checkIdx = stateOrder.indexOf(state);
    return currentIdx > checkIdx;
  }

  /// Getters for common states
  bool get isRequested => isStatus(RideStatus.requested);
  bool get isAccepted => isStatus(RideStatus.accepted);
  bool get isDriverArrived => isStatus(RideStatus.driverArrived);
  bool get isInProgress => isStatus(RideStatus.inProgress);
  bool get isCompleted => isStatus(RideStatus.completed);
  bool get isCancelled => isStatus(RideStatus.cancelled);

  /// Active ride states
  bool get isActive => !isCompleted && !isCancelled;

  RideStateVM copyWith({
    Ride? ride,
    bool? isLoading,
    String? error,
    DateTime? lastUpdate,
  }) {
    return RideStateVM(
      ride: ride ?? this.ride,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }
}

/// State notifier for managing ride lifecycle
class RideStateNotifier extends Notifier<RideStateVM> {
  final _httpService = RideShareHttpService();
  StreamSubscription<Ride>? _rideSubscription;
  int? _rideId;

  @override
  RideStateVM build() {
    return RideStateVM();
  }

  /// Subscribe to ride updates
  void subscribeToRide(int rideId) {
    _rideId = rideId;
    _rideSubscription?.cancel();

    _rideSubscription = _httpService.rideUpdateStream.listen(
      (ride) {
        if (ride.id == rideId) {
          state = state.copyWith(
            ride: ride,
            error: null,
            lastUpdate: DateTime.now(),
          );
        }
      },
      onError: (error) {
        state = state.copyWith(
          error: error.toString(),
          lastUpdate: DateTime.now(),
        );
      },
    );
  }

  /// Unsubscribe from ride updates
  void unsubscribeFromRide() {
    _rideSubscription?.cancel();
    _rideSubscription = null;
    _rideId = null;
  }

  /// Mark ride as arrived (driver only)
  Future<void> markArrived() async {
    if (_rideId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Request will be handled via WebSocket update
      await _httpService.markDriverArrived(_rideId!);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Start ride
  Future<void> startRide() async {
    if (_rideId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _httpService.startRide(_rideId!);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Complete ride
  Future<void> completeRide({double? actualDistance}) async {
    if (_rideId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _httpService.completeRide(_rideId!, actualDistance: actualDistance);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Cancel ride
  Future<void> cancelRide(String reason) async {
    if (_rideId == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _httpService.cancelRide(_rideId!, reason: reason);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}

/// Provider for active ride state - shared across passenger and driver
final activeRideProvider = NotifierProvider<RideStateNotifier, RideStateVM>(
  RideStateNotifier.new,
);
