import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_diagnostics.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
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

/// Driver ride-offers socket connection for UI chrome.
enum DriverRideOffersConnectionStatus {
  connected,
  reconnecting,
  disconnected,
}

/// WebSocket service for driver ride requests
class DriverRideRequestsWebSocketService {
  late IO.Socket socket;
  final _rideRequestsController =
      StreamController<IncomingRideRequest>.broadcast();
  final _connectionStatusController =
      StreamController<DriverRideOffersConnectionStatus>.broadcast();
  bool _isConnected = false;
  bool _socketCreated = false;
  bool _disposed = false;
  bool _manualDisconnect = false;
  bool _connecting = false;
  bool _reconnectScheduled = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  /// Mirrors messaging / passenger WS: exponential backoff, owned reconnect loop.
  static const int _maxReconnectAttempts = 8;
  static const Duration _baseReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  DriverRideOffersConnectionStatus _status =
      DriverRideOffersConnectionStatus.disconnected;

  Stream<IncomingRideRequest> get rideRequestsStream =>
      _rideRequestsController.stream;
  Stream<DriverRideOffersConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;
  bool get isConnected => _isConnected;
  DriverRideOffersConnectionStatus get connectionStatus => _status;

  void _emitStatus(DriverRideOffersConnectionStatus status) {
    _status = status;
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(status);
    }
  }

  Duration _backoffDelay(int attempt) {
    // attempt is 1-based: 1s, 2s, 4s, 8s, … capped at 30s
    final shift = (attempt - 1).clamp(0, 5);
    final seconds = _baseReconnectDelay.inSeconds * (1 << shift);
    return Duration(
      seconds: seconds.clamp(
        _baseReconnectDelay.inSeconds,
        _maxReconnectDelay.inSeconds,
      ),
    );
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || _connecting) return;
    if (_reconnectScheduled) return;
    if (_isConnected) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        debugPrint('[DriverRideRequests] Max reconnect attempts reached');
      }
      _emitStatus(DriverRideOffersConnectionStatus.disconnected);
      return;
    }

    _reconnectScheduled = true;
    _reconnectAttempts++;
    final delay = _backoffDelay(_reconnectAttempts);
    _emitStatus(DriverRideOffersConnectionStatus.reconnecting);

    if (kDebugMode) {
      debugPrint(
        '[DriverRideRequests] Scheduling reconnect '
        '(attempt $_reconnectAttempts/$_maxReconnectAttempts) in ${delay.inSeconds}s',
      );
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      _reconnectScheduled = false;
      if (_disposed || _manualDisconnect || _isConnected || _connecting) {
        return;
      }
      try {
        await connect();
      } catch (_) {
        // connect() schedules the next attempt when needed
      }
    });
  }

  /// Manual retry from UI after max attempts / lost connection.
  Future<void> reconnectNow() async {
    if (_disposed) return;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectScheduled = false;
    _reconnectAttempts = 0;
    _emitStatus(DriverRideOffersConnectionStatus.reconnecting);
    await connect();
  }

  Future<void> connect() async {
    if (_disposed) return;
    if (_connecting) return;
    if (_isConnected && _socketCreated && socket.connected) return;

    _connecting = true;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectScheduled = false;
    if (_status != DriverRideOffersConnectionStatus.connected) {
      _emitStatus(DriverRideOffersConnectionStatus.reconnecting);
    }

    try {
      // Force-refresh: socket handshake caches the token; stale → id-token-expired.
      final token =
          await AuthHandler.getFirebaseTokenForApi(forceRefresh: true);

      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[DriverRideRequests] No Firebase ID token - skipping WebSocket');
        }
        _isConnected = false;
        _emitStatus(DriverRideOffersConnectionStatus.disconnected);
        _scheduleReconnect();
        return;
      }

      if (kDebugMode) {
        debugPrint('[DriverRideRequests] Connecting WebSocket with fresh token');
      }

      try {
        if (_socketCreated) socket.dispose();
      } catch (_) {}

      socket = IO.io(
        ApiConfig.prod,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableForceNew()
            .disableReconnection() // we own reconnect to avoid duplicate loops
            .setExtraHeaders({
              'Authorization': 'Bearer $token',
              ...await AuthDiagnostics.buildHeaders(token: token),
            })
            .setQuery(await AuthDiagnostics.buildSocketQuery(token: token))
            .build(),
      );
      _socketCreated = true;

      socket.onConnect((_) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket connected');
        }
        _isConnected = true;
        _reconnectAttempts = 0;
        _reconnectScheduled = false;
        _emitStatus(DriverRideOffersConnectionStatus.connected);
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
        if (_manualDisconnect || _disposed) {
          _emitStatus(DriverRideOffersConnectionStatus.disconnected);
          return;
        }
        _emitStatus(DriverRideOffersConnectionStatus.reconnecting);
        _scheduleReconnect();
      });

      socket.onError((error) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket error');
        }
        _isConnected = false;
        if (!_manualDisconnect && !_disposed) {
          _emitStatus(DriverRideOffersConnectionStatus.reconnecting);
          _scheduleReconnect();
        } else {
          _emitStatus(DriverRideOffersConnectionStatus.disconnected);
        }
      });

      socket.onConnectError((error) {
        if (kDebugMode) {
          debugPrint('[DriverRideRequests] WebSocket connection error');
        }
        _isConnected = false;
        if (!_manualDisconnect && !_disposed) {
          _emitStatus(DriverRideOffersConnectionStatus.reconnecting);
          _scheduleReconnect();
        } else {
          _emitStatus(DriverRideOffersConnectionStatus.disconnected);
        }
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
      _emitStatus(DriverRideOffersConnectionStatus.disconnected);
      if (!_manualDisconnect && !_disposed) {
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  void _listenForRideRequests() {
    // Fresh socket after reconnect — attach once per socket instance.
    socket.off('ride:ride-request');
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
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectScheduled = false;
    try {
      if (_socketCreated && socket.connected) {
        socket.disconnect();
      }
    } catch (_) {}
    _isConnected = false;
    _emitStatus(DriverRideOffersConnectionStatus.disconnected);
  }

  void dispose() {
    _disposed = true;
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
  final enabled = ref.watch(driverRideNotificationsEnabledProvider);
  if (!enabled) return;
  final service = ref.watch(_driverRideRequestsServiceProvider);
  if (!service.isConnected) {
    await service.connect();
  }
});

/// Stream of incoming ride requests via WebSocket
final driverRideRequestsStreamProvider =
    StreamProvider<IncomingRideRequest>((ref) {
  final enabled = ref.watch(driverRideNotificationsEnabledProvider);
  if (!enabled) return const Stream<IncomingRideRequest>.empty();
  final service = ref.watch(_driverRideRequestsServiceProvider);
  return service.rideRequestsStream;
});

/// Connection status of driver ride requests WebSocket (seeds current value).
final driverRideRequestsConnectionProvider =
    StreamProvider<DriverRideOffersConnectionStatus>((ref) {
  final enabled = ref.watch(driverRideNotificationsEnabledProvider);
  if (!enabled) {
    return Stream.value(DriverRideOffersConnectionStatus.disconnected);
  }
  final service = ref.watch(_driverRideRequestsServiceProvider);
  return Stream<DriverRideOffersConnectionStatus>.multi((controller) {
    controller.add(service.connectionStatus);
    final sub = service.connectionStatusStream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = sub.cancel;
  });
});

/// Manual reconnect after "Offers connection lost — retry".
Future<void> retryDriverRideRequestsConnection(WidgetRef ref) async {
  final service = ref.read(_driverRideRequestsServiceProvider);
  await service.reconnectNow();
}

/// Polling result: rides plus optional error when the pending-rides call fails.
typedef CombinedDriverRidesState = ({
  List<DriverRideRequest> rides,
  String? pollErrorMessage,
});

/// Combined stream of ride requests from both WebSocket and HTTP polling.
/// HTTP poll interval is relaxed to reduce DB load when Redis backs pending-rides;
/// WebSocket still delivers requests in real time.
final combinedDriverRideRequestsProvider =
    StreamProvider<CombinedDriverRidesState>((ref) {
  final enabled = ref.watch(driverRideNotificationsEnabledProvider);
  if (!enabled) {
    return Stream<CombinedDriverRidesState>.value((
      rides: const <DriverRideRequest>[],
      pollErrorMessage: null,
    ));
  }
  ref.watch(driverRideRequestsInitProvider);

  return Stream.periodic(
    const Duration(seconds: 12),
    (_) => DriverRequestService.getIncomingRequestsDetailed(),
  ).asyncExpand((future) => Stream.fromFuture(future)).map((result) {
    return (
      rides: result.requests,
      pollErrorMessage: result.errorMessage,
    );
  });
});
