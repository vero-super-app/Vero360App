import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider, StateProvider;

// =============== RIDE-SHARE MESSAGING STATE ===============

/// Current ride being discussed
final currentRideIdProvider = StateProvider<int?>((ref) => null);

/// Ride status state: {rideId: status}
final rideStatusProvider = StateProvider<Map<int, String>>((ref) => {});

/// Driver location state: {rideId: DriverLocation}
final driverLocationProvider =
    StateProvider<Map<int, DriverLocationData>>((ref) => {});

/// Last ride update timestamp
final lastRideUpdateProvider = StateProvider<DateTime?>((ref) => null);

/// Ride chat mapping: {rideId: chatId}
final rideChatMappingProvider = StateProvider<Map<int, String>>((ref) => {});

/// Emergency alerts for rides
final emergencyAlertsProvider = StateProvider<List<EmergencyAlert>>((ref) => []);

// =============== RIDE-SHARE DATA MODELS ===============

class DriverLocationData {
  final double latitude;
  final double longitude;
  final int etaMinutes;
  final int driverId;
  final DateTime timestamp;

  DriverLocationData({
    required this.latitude,
    required this.longitude,
    required this.etaMinutes,
    required this.driverId,
    required this.timestamp,
  });
}

class EmergencyAlert {
  final int rideId;
  final int userId;
  final String message;
  final DateTime timestamp;

  EmergencyAlert({
    required this.rideId,
    required this.userId,
    required this.message,
    required this.timestamp,
  });
}

// =============== RIDE-SHARE EVENT HANDLERS ===============

/// Service for handling ride-share messaging events
class RideShareMessagingNotifier extends StateNotifier<Map<int, String>> {
  RideShareMessagingNotifier() : super({});

  /// Update ride status in local state
  void updateRideStatus(int rideId, String status) {
    state = {...state, rideId: status};
  }

  /// Get current ride status
  String? getRideStatus(int rideId) {
    return state[rideId];
  }

  /// Clear ride status
  void clearRideStatus(int rideId) {
    final newState = Map<int, String>.from(state);
    newState.remove(rideId);
    state = newState;
  }
}

/// Ride-share status notifier provider
final rideShareMessagingNotifierProvider =
    StateNotifierProvider<RideShareMessagingNotifier, Map<int, String>>(
  (ref) => RideShareMessagingNotifier(),
);

// =============== RIDE-SHARE LOCATION HANDLER ===============

class DriverLocationNotifier
    extends StateNotifier<Map<int, DriverLocationData>> {
  DriverLocationNotifier() : super({});

  void updateDriverLocation(int rideId, DriverLocationData location) {
    state = {...state, rideId: location};
  }

  DriverLocationData? getDriverLocation(int rideId) {
    return state[rideId];
  }
}

/// Driver location notifier provider
final driverLocationNotifierProvider =
    StateNotifierProvider<DriverLocationNotifier, Map<int, DriverLocationData>>(
  (ref) => DriverLocationNotifier(),
);

// =============== RIDE-SHARE NOTIFICATION HANDLERS ===============

/// Handle ride-share notification event
Future<void> handleRideShareNotification(
  WidgetRef ref,
  int rideId,
  String notificationType,
  Map<String, dynamic> data,
) async {
  switch (notificationType) {
    case 'status_change':
      ref
          .read(rideShareMessagingNotifierProvider.notifier)
          .updateRideStatus(rideId, data['status'] ?? 'UNKNOWN');
      ref.read(lastRideUpdateProvider.notifier).state = DateTime.now();
      break;

    case 'location_update':
      final location = DriverLocationData(
        latitude: data['latitude'] ?? 0.0,
        longitude: data['longitude'] ?? 0.0,
        etaMinutes: data['etaMinutes'] ?? 0,
        driverId: data['driverId'] ?? 0,
        timestamp: DateTime.now(),
      );
      ref
          .read(driverLocationNotifierProvider.notifier)
          .updateDriverLocation(rideId, location);
      break;

    case 'emergency_alert':
      final alert = EmergencyAlert(
        rideId: rideId,
        userId: data['userId'] ?? 0,
        message: data['alertMessage'] ?? 'Emergency alert',
        timestamp: DateTime.now(),
      );
      ref.read(emergencyAlertsProvider.notifier).state = [
        ...ref.read(emergencyAlertsProvider),
        alert,
      ];
      break;

    case 'trip_summary':
      // Handle trip summary
      break;

    case 'rating_request':
      // Handle rating request
      break;

    case 'cancellation':
      ref
          .read(rideShareMessagingNotifierProvider.notifier)
          .updateRideStatus(rideId, 'CANCELLED');
      break;
  }
}
