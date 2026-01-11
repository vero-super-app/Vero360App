import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_config.dart';

class RideShareService {
  // ✅ Use ApiConfig for ride-share endpoint instead of hardcoded URL
  late IO.Socket socket;

  // Stream controllers for WebSocket events
  late StreamController<String> _connectionStatusController;
  late StreamController<Map<String, dynamic>> _driverLocationController;
  late StreamController<Map<String, dynamic>> _rideStatusController;

  RideShareService() {
    _initializeControllers();
    _initializeSocket();
  }

  /// Get auth token from shared preferences
  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token') ??
          prefs.getString('token') ??
          prefs.getString('jwt');
    } catch (e) {
      print('Error reading auth token: $e');
      return null;
    }
  }

  /// Initialize stream controllers
  void _initializeControllers() {
    _connectionStatusController = StreamController<String>.broadcast();
    _driverLocationController =
        StreamController<Map<String, dynamic>>.broadcast();
    _rideStatusController = StreamController<Map<String, dynamic>>.broadcast();
  }

  /// Get connection status stream
  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;

  /// Get driver location stream
  Stream<Map<String, dynamic>> get driverLocationStream =>
      _driverLocationController.stream;

  /// Get ride status stream
  Stream<Map<String, dynamic>> get rideStatusStream =>
      _rideStatusController.stream;

  void _initializeSocket() {
    socket = IO.io(
      ApiConfig.prod,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();
    socket.onConnect((_) {
      print('Socket connected');
      _connectionStatusController.add('connected');
    });

    socket.onDisconnect((_) {
      print('Socket disconnected');
      _connectionStatusController.add('disconnected');
    });

    socket.onError((error) {
      print('Socket error: $error');
      _connectionStatusController.add('error');
    });
  }

  /// Estimate fare for a trip
  Future<Map<String, dynamic>> estimateFare({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String vehicleClass,
  }) async {
    try {
      final response = await http.post(
        ApiConfig.endpoint('/ride-share/estimate-fare'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pickupLatitude': pickupLatitude,
          'pickupLongitude': pickupLongitude,
          'dropoffLatitude': dropoffLatitude,
          'dropoffLongitude': dropoffLongitude,
          'vehicleClass': vehicleClass,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to estimate fare: ${response.statusCode}');
      }
    } catch (e) {
      print('Error estimating fare: $e');
      rethrow;
    }
  }

  /// Get available vehicles by location and optional class filter
  Future<dynamic> getAvailableVehicles({
    required double latitude,
    required double longitude,
    String? vehicleClass,
    double radiusKm = 5,
  }) async {
    try {
      String path =
          '/ride-share/vehicles?latitude=$latitude&longitude=$longitude&radiusKm=$radiusKm';
      if (vehicleClass != null) {
        path += '&vehicleClass=$vehicleClass';
      }

      final response = await http.get(ApiConfig.endpoint(path));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get vehicles: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting vehicles: $e');
      rethrow;
    }
  }

  /// Request a new ride
  Future<Map<String, dynamic>> requestRide({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String vehicleClass,
    String? pickupAddress,
    String? dropoffAddress,
    String? notes,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth token if available
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.post(
        ApiConfig.endpoint('/ride-share/rides'),
        headers: headers,
        body: jsonEncode({
          'pickupLatitude': pickupLatitude,
          'pickupLongitude': pickupLongitude,
          'pickupAddress': pickupAddress,
          'dropoffLatitude': dropoffLatitude,
          'dropoffLongitude': dropoffLongitude,
          'dropoffAddress': dropoffAddress,
          'preferredVehicleClass': vehicleClass,
          'notes': notes,
        }),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to request ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error requesting ride: $e');
      rethrow;
    }
  }

  /// Get ride details
  Future<Map<String, dynamic>> getRideDetails(int rideId) async {
    try {
      final response = await http.get(ApiConfig.endpoint('/ride-share/rides/$rideId'));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting ride: $e');
      rethrow;
    }
  }

  /// Cancel a ride
  Future<Map<String, dynamic>> cancelRide(int rideId, {String? reason}) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to cancel ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error cancelling ride: $e');
      rethrow;
    }
  }

  /// Subscribe to passenger ride tracking
  void subscribeToRideTracking(int rideId) {
    socket.emit('passenger:subscribe', {'rideId': rideId});

    // Listen for driver location updates
    socket.on('driver:location:updated', (data) {
      print('Driver location updated: $data');
      _driverLocationController.add(Map<String, dynamic>.from(data));
    });

    // Listen for ride status updates
    socket.on('ride:status:updated', (data) {
      print('Ride status updated: $data');
      _rideStatusController.add(Map<String, dynamic>.from(data));
    });
  }

  /// Unsubscribe from ride tracking
  void unsubscribeFromRideTracking() {
    socket.emit('passenger:unsubscribe');
  }

  /// Listen to driver location updates
  void onDriverLocationUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('driver:location:updated', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  /// Listen to ride status changes
  void onRideStatusUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('ride:status:updated', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  /// Disconnect socket
  void disconnect() {
    socket.disconnect();
  }

  /// Reconnect websocket with retry logic
  Future<void> reconnectWebSocket() async {
    try {
      if (!socket.connected) {
        socket.connect();
        print('WebSocket reconnected');
        _connectionStatusController.add('connected');
      }
    } catch (e) {
      print('Error reconnecting WebSocket: $e');
      _connectionStatusController.add('error');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _connectionStatusController.close();
    _driverLocationController.close();
    _rideStatusController.close();
    disconnect();
  }
}
