import 'package:flutter_riverpod/flutter_riverpod.dart'
    show StreamProvider, FutureProvider;
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';

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
// Ride status tracking has been consolidated into ride_lifecycle_notifier.dart.
// Use rideLifecycleProvider as the single source of truth for ride state.

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

// ==================== MESSAGING WEBSOCKET STATE ====================

/// WebSocket connection state for messaging
final messagingWebSocketConnectedProvider = StateProvider<bool>((ref) => false);

/// Typing indicator debounce timer tracking
final typingDebounceProvider =
    StateProvider<Map<String, DateTime>>((ref) => {});

/// Last message read time per chat
final lastReadTimeProvider = StateProvider<Map<String, DateTime>>((ref) => {});

// ==================== IMPORTS FOR Colors ====================
// Add these imports at the top of your file:
// import 'package:flutter/material.dart';
