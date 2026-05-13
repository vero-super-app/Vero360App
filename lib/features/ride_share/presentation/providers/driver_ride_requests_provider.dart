import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

/// Model for incoming ride request from WebSocket
class IncomingRideRequest {
  final int rideId;

  /// DB user id of the passenger (same as JWT user id when using backend auth).
  final int? passengerId;
  final String passengerName;
  final String? passengerPhone;
  final double pickupLatitude;
  final double pickupLongitude;
  final String? pickupAddress;
  final double dropoffLatitude;
  final double dropoffLongitude;
  final String? dropoffAddress;
  final String vehicleClass;
  final double searchRadiusKm;
  final double estimatedFare;
  final double estimatedDistance;
  final List<AvailableVehicle> availableVehicles;
  final DateTime timestamp;

  IncomingRideRequest({
    required this.rideId,
    this.passengerId,
    required this.passengerName,
    this.passengerPhone,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.pickupAddress,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    this.dropoffAddress,
    required this.vehicleClass,
    required this.searchRadiusKm,
    required this.estimatedFare,
    required this.estimatedDistance,
    required this.availableVehicles,
    required this.timestamp,
  });

  static List<AvailableVehicle> _parseAvailableVehicles(
      Map<String, dynamic> json) {
    final raw = json['availableVehicles'] ?? json['availableTaxis'];
    if (raw is! List) return [];
    return raw
        .map((v) => AvailableVehicle.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  factory IncomingRideRequest.fromJson(Map<String, dynamic> json) {
    final pid = json['passengerId'];
    return IncomingRideRequest(
      rideId: json['rideId'] as int? ?? 0,
      passengerId: pid is int ? pid : int.tryParse(pid?.toString() ?? ''),
      passengerName: json['passengerName'] as String? ?? 'Passenger',
      passengerPhone: json['passengerPhone'] as String?,
      pickupLatitude: (json['pickupLatitude'] as num?)?.toDouble() ?? 0.0,
      pickupLongitude: (json['pickupLongitude'] as num?)?.toDouble() ?? 0.0,
      pickupAddress: json['pickupAddress'] as String?,
      dropoffLatitude: (json['dropoffLatitude'] as num?)?.toDouble() ?? 0.0,
      dropoffLongitude: (json['dropoffLongitude'] as num?)?.toDouble() ?? 0.0,
      dropoffAddress: json['dropoffAddress'] as String?,
      vehicleClass: json['vehicleClass'] as String? ?? 'STANDARD',
      searchRadiusKm: (json['searchRadiusKm'] as num?)?.toDouble() ?? 5.0,
      estimatedFare: (json['estimatedFare'] as num?)?.toDouble() ?? 0.0,
      estimatedDistance: (json['estimatedDistance'] as num?)?.toDouble() ?? 0.0,
      availableVehicles: _parseAvailableVehicles(json),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  int? recommendedTaxiIdForDriver(int? driverId) {
    if (driverId == null) return null;
    for (final vehicle in availableVehicles) {
      if (vehicle.driverId == driverId) {
        return vehicle.vehicleId;
      }
    }
    return null;
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
    socket.on('ride:ride-request', (data) {
      unawaited(Future(() async {
        try {
          final request =
              IncomingRideRequest.fromJson(data as Map<String, dynamic>);
          final uid = await AuthStorage.userIdFromToken();
          if (request.passengerId != null &&
              uid != null &&
              request.passengerId == uid) {
            if (kDebugMode) {
              debugPrint(
                  '[DriverRideRequests] Ignoring own passenger ride ${request.rideId}');
            }
            return;
          }
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
      }));
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
final driverRideRequestsConnectionProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(_driverRideRequestsServiceProvider);
  return service.connectionStatusStream;
});

/// Polling result: rides plus optional error when the pending-rides call fails.
typedef CombinedDriverRidesState = ({
  List<DriverRideRequest> rides,
  String? pollErrorMessage,
});

/// Combined stream of ride requests from both WebSocket and HTTP polling
final combinedDriverRideRequestsProvider =
    StreamProvider<CombinedDriverRidesState>((ref) {
  ref.watch(driverRideRequestsInitProvider);

  return Stream.periodic(
    const Duration(seconds: 3),
    (_) => DriverRequestService.getIncomingRequestsDetailed(),
  ).asyncExpand((future) => Stream.fromFuture(future)).map((result) {
    return (
      rides: result.requests,
      pollErrorMessage: result.errorMessage,
    );
  });
});
