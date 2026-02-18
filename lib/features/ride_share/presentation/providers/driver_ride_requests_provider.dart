import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final List<AvailableVehicle> availableVehicles;
  final DateTime timestamp;

  IncomingRideRequest({
    required this.rideId,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.pickupAddress,
    required this.vehicleClass,
    required this.searchRadiusKm,
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
      vehicleId: json['vehicleId'] as int? ?? 0,
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
      String? token;

      if (firebaseUser != null) {
        token = await firebaseUser.getIdToken();
      }

      if (token == null || token.isEmpty) {
        print('[DriverRideRequests] No auth token available');
        _connectionStatusController.add(false);
        return;
      }

      socket = IO.io(
        ApiConfig.prod,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setExtraHeaders({
              'Authorization': 'Bearer $token',
            })
            .build(),
      );

      socket.onConnect((_) {
        print('[DriverRideRequests] WebSocket connected');
        _isConnected = true;
        _connectionStatusController.add(true);
        _listenForRideRequests();
      });

      socket.onDisconnect((_) {
        print('[DriverRideRequests] WebSocket disconnected');
        _isConnected = false;
        _connectionStatusController.add(false);
      });

      socket.onError((error) {
        print('[DriverRideRequests] WebSocket error: $error');
        _isConnected = false;
        _connectionStatusController.add(false);
      });

      socket.onConnectError((error) {
        print('[DriverRideRequests] WebSocket connection error: $error');
        _isConnected = false;
        _connectionStatusController.add(false);
      });

      socket.connect();
    } catch (e) {
      print('[DriverRideRequests] Error connecting WebSocket: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
    }
  }

  void _listenForRideRequests() {
    // Listen for ride requests globally
    socket.on('ride:ride-request', (data) {
      print('[DriverRideRequests] Received ride request: $data');
      try {
        final request = IncomingRideRequest.fromJson(data as Map<String, dynamic>);
        _rideRequestsController.add(request);
      } catch (e) {
        print('[DriverRideRequests] Error parsing ride request: $e');
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
