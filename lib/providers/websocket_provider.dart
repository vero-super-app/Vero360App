import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Provider, StreamProvider, FutureProvider, AsyncValue, Ref;
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:vero360_app/services/ride_share_service.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';

// ==================== CONNECTION STATE ====================

/// Stream of WebSocket connection status
/// Values: 'connected', 'disconnected', 'error'
final webSocketConnectionProvider = StreamProvider<String>((ref) {
  final rideService = ref.watch(rideShareServiceProvider);
  return rideService.connectionStatusStream;
});

// ==================== DRIVER LOCATION ====================

/// Model for driver location update
class DriverLocation {
  final int driverId;
  final int vehicleId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  DriverLocation({
    required this.driverId,
    required this.vehicleId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory DriverLocation.fromJson(Map<String, dynamic> json) {
    try {
      return DriverLocation(
        driverId: json['driverId'] as int? ?? 0,
        vehicleId: json['vehicleId'] as int? ?? 0,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to parse driver location: $e');
    }
  }

  @override
  String toString() =>
      'DriverLocation(id: $driverId, lat: $latitude, lng: $longitude)';
}

/// Stream of driver location updates
final driverLocationProvider = StreamProvider<DriverLocation?>((ref) {
  final rideService = ref.watch(rideShareServiceProvider);

  return rideService.driverLocationStream.map((data) {
    try {
      return DriverLocation.fromJson(data);
    } catch (e) {
      print('Error parsing driver location: $e');
      return null;
    }
  });
});

/// Store latest driver location for easy access
final latestDriverLocationProvider = StateProvider<DriverLocation?>(
  (ref) => null,
);

// ==================== RIDE STATUS ====================

/// Enum for ride status
enum RideStatus {
  REQUESTED,
  ACCEPTED,
  DRIVER_ARRIVED,
  IN_PROGRESS,
  COMPLETED,
  CANCELLED,
}

/// Model for ride status update
class RideStatusUpdate {
  final int rideId;
  final RideStatus status;
  final int? driverId;
  final int? vehicleId;
  final String? driverName;
  final String? vehicleInfo;
  final double? driverRating;
  final String? driverPhone;

  RideStatusUpdate({
    required this.rideId,
    required this.status,
    this.driverId,
    this.vehicleId,
    this.driverName,
    this.vehicleInfo,
    this.driverRating,
    this.driverPhone,
  });

  factory RideStatusUpdate.fromJson(Map<String, dynamic> json) {
    try {
      final statusString = json['status'] as String? ?? 'REQUESTED';
      final status = RideStatus.values.firstWhere(
        (e) => e.name == statusString,
        orElse: () => RideStatus.REQUESTED,
      );

      return RideStatusUpdate(
        rideId: json['rideId'] as int? ?? 0,
        status: status,
        driverId: json['driverId'] as int?,
        vehicleId: json['vehicleId'] as int?,
        driverName: json['driverName'] as String?,
        vehicleInfo: json['vehicleInfo'] as String?,
        driverRating: (json['driverRating'] as num?)?.toDouble(),
        driverPhone: json['driverPhone'] as String?,
      );
    } catch (e) {
      throw Exception('Failed to parse ride status: $e');
    }
  }

  @override
  String toString() => 'RideStatusUpdate(id: $rideId, status: ${status.name})';
}

/// Stream of ride status updates
final rideStatusProvider = StreamProvider<RideStatusUpdate?>((ref) {
  final rideService = ref.watch(rideShareServiceProvider);

  return rideService.rideStatusStream.map((data) {
    try {
      return RideStatusUpdate.fromJson(data);
    } catch (e) {
      print('Error parsing ride status: $e');
      return null;
    }
  });
});

/// Store current ride status for easy access
final currentRideStatusProvider = StateProvider<RideStatusUpdate?>(
  (ref) => null,
);

// ==================== ACTIVE RIDE ====================

/// Track the currently active ride ID
final activeRideIdProvider = StateProvider<int?>(
  (ref) => null,
);

/// Notifier for managing ride tracking
class RideTrackingNotifier {
  final Ref ref;

  RideTrackingNotifier(this.ref);

  /// Start tracking a specific ride
  void startTracking(int rideId) {
    print('[RideTracking] Starting tracking for ride: $rideId');
    final rideService = ref.read(rideShareServiceProvider);
    rideService.subscribeToRideTracking(rideId);
    ref.read(activeRideIdProvider.notifier).state = rideId;

    // Reset status when starting new ride
    ref.read(currentRideStatusProvider.notifier).state = null;
  }

  /// Stop tracking the current ride
  void stopTracking() {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId != null) {
      print('[RideTracking] Stopping tracking for ride: $rideId');
      final rideService = ref.read(rideShareServiceProvider);
      rideService.unsubscribeFromRideTracking();
    }

    ref.read(activeRideIdProvider.notifier).state = null;
    ref.read(currentRideStatusProvider.notifier).state = null;
    ref.read(latestDriverLocationProvider.notifier).state = null;
  }

  /// Get current active ride ID
  int? getActiveRideId() => ref.read(activeRideIdProvider);

  /// Check if currently tracking a ride
  bool isTracking() => ref.read(activeRideIdProvider) != null;
}

/// Provider for ride tracking notifier
final rideTrackingProvider = Provider<RideTrackingNotifier>((ref) {
  return RideTrackingNotifier(ref);
});

// ==================== HELPER PROVIDERS ====================

/// Get formatted status message for display
final rideStatusMessageProvider =
    Provider.family<String, RideStatusUpdate?>((ref, status) {
  if (status == null) return 'Finding drivers...';

  switch (status.status) {
    case RideStatus.REQUESTED:
      return 'Looking for drivers...';
    case RideStatus.ACCEPTED:
      return 'Driver ${status.driverName ?? 'John'} accepted your ride!';
    case RideStatus.DRIVER_ARRIVED:
      return '${status.driverName ?? 'Your driver'} has arrived. Vehicle: ${status.vehicleInfo ?? 'Unknown'}';
    case RideStatus.IN_PROGRESS:
      return 'You\'re on your way! Driver rating: ${status.driverRating?.toStringAsFixed(1) ?? 'N/A'}★';
    case RideStatus.COMPLETED:
      return 'Ride completed. Thank you for using Vero!';
    case RideStatus.CANCELLED:
      return 'Ride was cancelled.';
  }
});

/// Get color for status badge
final rideStatusColorProvider =
    Provider.family<Color?, RideStatus>((ref, status) {
  switch (status) {
    case RideStatus.REQUESTED:
      return Colors.orange;
    case RideStatus.ACCEPTED:
      return Colors.blue;
    case RideStatus.DRIVER_ARRIVED:
      return Colors.green;
    case RideStatus.IN_PROGRESS:
      return Colors.blue;
    case RideStatus.COMPLETED:
      return Colors.green;
    case RideStatus.CANCELLED:
      return Colors.red;
  }
});

// ==================== ERROR HANDLING ====================

/// Detect if WebSocket connection is lost
final isWebSocketConnectedProvider = StateProvider<bool>(
  (ref) => false,
);

/// Track reconnection attempts
final reconnectionAttemptsProvider = StateProvider<int>(
  (ref) => 0,
);

/// Handle reconnection
final reconnectionProvider = FutureProvider<void>((ref) async {
  final rideService = ref.watch(rideShareServiceProvider);
  final attempts = ref.watch(reconnectionAttemptsProvider);

  if (attempts < 5) {
    print('[WebSocket] Attempting to reconnect... (attempt ${attempts + 1})');
    await rideService.reconnectWebSocket();
    ref.read(reconnectionAttemptsProvider.notifier).state = attempts + 1;
  }
});

// ==================== IMPORTS FOR Colors ====================
// Add these imports at the top of your file:
// import 'package:flutter/material.dart';
