import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

/// Model for incoming ride request from WebSocket
class IncomingRideRequest {
  final int rideId;
  final double pickupLatitude;
  final double pickupLongitude;
  final String? pickupAddress;
  final String vehicleClass;
  final double searchRadiusKm;
  final double estimatedFare;
  final double estimatedDistance;
  final List<AvailableVehicle> availableVehicles;
  final DateTime timestamp;

  IncomingRideRequest({
    required this.rideId,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.pickupAddress,
    required this.vehicleClass,
    required this.searchRadiusKm,
    required this.estimatedFare,
    required this.estimatedDistance,
    required this.availableVehicles,
    required this.timestamp,
  });

  factory IncomingRideRequest.fromJson(Map<String, dynamic> json) {
    return IncomingRideRequest(
      rideId: json['rideId'] as int? ?? 0,
      pickupLatitude: (json['pickupLatitude'] as num?)?.toDouble() ?? 0.0,
      pickupLongitude: (json['pickupLongitude'] as num?)?.toDouble() ?? 0.0,
      pickupAddress: json['pickupAddress'] as String?,
      vehicleClass: json['vehicleClass'] as String? ?? 'STANDARD',
      searchRadiusKm: (json['searchRadiusKm'] as num?)?.toDouble() ?? 5.0,
      estimatedFare: (json['estimatedFare'] as num?)?.toDouble() ?? 0.0,
      estimatedDistance: (json['estimatedDistance'] as num?)?.toDouble() ?? 0.0,
      availableVehicles: (json['availableVehicles'] as List?)
              ?.map((v) => AvailableVehicle.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}

class AvailableVehicle {
  final int vehicleId;
  final int driverId;
  final double distance;
  final String licensePlate;
  final String make;
  final String model;

  AvailableVehicle({
    required this.vehicleId,
    required this.driverId,
    required this.distance,
    required this.licensePlate,
    required this.make,
    required this.model,
  });

  factory AvailableVehicle.fromJson(Map<String, dynamic> json) {
    return AvailableVehicle(
      vehicleId: json['taxiId'] as int? ?? json['vehicleId'] as int? ?? 0,
      driverId: json['driverId'] as int? ?? 0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      licensePlate: json['licensePlate'] as String? ?? '',
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
    );
  }
}

/// WebSocket service for driver ride requests
class DriverRideRequestsWebSocketService {
  late IO.Socket socket;
  final _rideRequestsController =
      StreamController<IncomingRideRequest>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  bool _isConnected = false;

  Stream<IncomingRideRequest> get rideRequestsStream =>
      _rideRequestsController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    try {
      // Get auth token
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (kDebugMode) {
        debugPrint('[DriverRideRequests] Firebase user present');
      }
      
      String? token;

      if (firebaseUser != null) {
        try {
          token = await firebaseUser.getIdToken();
          if (kDebugMode) {
            debugPrint('[DriverRideRequests] Got Firebase token');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[DriverRideRequests] Error getting Firebase token');
          }
          token = null;
        }
      } else {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] No Firebase user logged in');
        }
      }

      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] No auth token - skipping WebSocket');
        }
        _connectionStatusController.add(false);
        return;
      }

      if (kDebugMode) {
        debugPrint('[DriverRideRequests] Connecting WebSocket');
      }

      socket = IO.io(
        ApiConfig.prod,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .build(),
      );

      socket.onConnect((_) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket connected');
        }
        _isConnected = true;
        _connectionStatusController.add(true);
        _listenForRideRequests();
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] Ride listeners registered');
        }
      });

      socket.onDisconnect((_) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket disconnected');
        }
        _isConnected = false;
        _connectionStatusController.add(false);
      });

      socket.onError((error) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket error');
        }
        _isConnected = false;
        _connectionStatusController.add(false);
      });

      socket.onConnectError((error) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket connection error');
        }
        _isConnected = false;
        _connectionStatusController.add(false);
      });

      if (kDebugMode) {
        debugPrint('[DriverRideRequests] Calling socket.connect()');
      }
      socket.connect();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DriverRideRequests] Error connecting WebSocket');
      }
      _isConnected = false;
      _connectionStatusController.add(false);
    }
  }

  void _listenForRideRequests() {
    // Listen for ride requests globally
    socket.on('ride:ride-request', (data) {
      try {
        final request = IncomingRideRequest.fromJson(data as Map<String, dynamic>);
        if (kDebugMode) {
          debugPrint(
              '[DriverRideRequests] Ride request received (rideId=${request.rideId})');
        }
        _rideRequestsController.add(request);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] Error parsing ride request: $e');
        }
      }
    });

    // Debug: Log all incoming events
    socket.onAny((event, data) {
      if (event.contains('ride') || event.contains('notification')) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] Event received: $event');
        }
      }
    });
  }

  void disconnect() {
    if (socket.connected) {
      socket.disconnect();
    }
    _isConnected = false;
    _connectionStatusController.add(false);
  }

  void dispose() {
    disconnect();
    _rideRequestsController.close();
    _connectionStatusController.close();
  }
}

// Global singleton
final _driverRideRequestsServiceProvider =
    Provider<DriverRideRequestsWebSocketService>((ref) {
  return DriverRideRequestsWebSocketService();
});

/// Initialize WebSocket connection for driver ride requests
final driverRideRequestsInitProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(_driverRideRequestsServiceProvider);
  if (!service.isConnected) {
    await service.connect();
  }
});

/// Stream of incoming ride requests via WebSocket
final driverRideRequestsStreamProvider =
    StreamProvider<IncomingRideRequest>((ref) {
  final service = ref.watch(_driverRideRequestsServiceProvider);
  return service.rideRequestsStream;
});

/// Connection status of driver ride requests WebSocket
final driverRideRequestsConnectionProvider =
    StreamProvider<bool>((ref) {
  final service = ref.watch(_driverRideRequestsServiceProvider);
  return service.connectionStatusStream;
});

/// Combined stream of ride requests from both WebSocket and HTTP polling
final combinedDriverRideRequestsProvider =
    StreamProvider<List<DriverRideRequest>>((ref) {
  // Start WebSocket connection
  ref.watch(driverRideRequestsInitProvider);

  // Create a stream that combines both sources
  return Stream.periodic(
    const Duration(seconds: 3),
    (_) => DriverRequestService.getIncomingRequests(),
  ).asyncExpand((future) => Stream.fromFuture(future));
});
