import 'package:vero360_app/GeneralModels/ride_model.dart';

/// Sealed class representing every possible state of a ride lifecycle.
/// Use Dart 3 exhaustive switch to handle all cases in the UI.
sealed class RideLifecycleState {
  const RideLifecycleState();
}

/// No active ride — the default/idle state.
class RideIdle extends RideLifecycleState {
  const RideIdle();
}

/// Ride request is being sent to the server.
class RideRequesting extends RideLifecycleState {
  const RideRequesting();
}

/// Ride exists and is active (status: REQUESTED, ACCEPTED, DRIVER_ARRIVED, or IN_PROGRESS).
/// All real-time updates mutate this state via [copyWith].
class RideActive extends RideLifecycleState {
  final Ride ride;
  final bool isLoading;
  final String? actionError;

  const RideActive({
    required this.ride,
    this.isLoading = false,
    this.actionError,
  });

  String get status => ride.status;
  bool get isRequested => status == RideStatus.requested;
  bool get isAccepted => status == RideStatus.accepted;
  bool get isDriverArrived => status == RideStatus.driverArrived;
  bool get isInProgress => status == RideStatus.inProgress;

  RideActive copyWith({Ride? ride, bool? isLoading, String? actionError}) {
    return RideActive(
      ride: ride ?? this.ride,
      isLoading: isLoading ?? this.isLoading,
      actionError: actionError,
    );
  }
}

/// Ride finished successfully.
class RideCompleted extends RideLifecycleState {
  final Ride ride;
  const RideCompleted({required this.ride});
}

/// Ride was cancelled (by passenger, driver, or server).
class RideCancelled extends RideLifecycleState {
  final Ride ride;
  String get reason => ride.cancellationReason ?? 'Ride was cancelled';
  const RideCancelled({required this.ride});
}

/// An error occurred during ride request or lifecycle.
class RideError extends RideLifecycleState {
  final String message;
  const RideError({required this.message});
}
