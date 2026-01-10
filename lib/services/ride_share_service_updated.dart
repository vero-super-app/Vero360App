import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced RideShareService with WebSocket integration for real-time updates
class RideShareService {
  static const String baseUrl =
      'https://unbigamous-unappositely-kory.ngrok-free.dev/vero/ride-share';
  late IO.Socket socket;

  // Token management
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

  // Stream controllers for real-time events
  late StreamController<Map<String, dynamic>> _driverLocationController;
  late StreamController<Map<String, dynamic>> _rideStatusController;
  late StreamController<String> _connectionStatusController;

  int? _currentRideId;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  RideShareService() {
    _driverLocationController =
        StreamController<Map<String, dynamic>>.broadcast();
    _rideStatusController = StreamController<Map<String, dynamic>>.broadcast();
    _connectionStatusController = StreamController<String>.broadcast();
    _initializeSocket();
  }

  // ==================== STREAMS ====================

  /// Stream of driver location updates
  Stream<Map<String, dynamic>> get driverLocationStream =>
      _driverLocationController.stream;

  /// Stream of ride status updates
  Stream<Map<String, dynamic>> get rideStatusStream =>
      _rideStatusController.stream;

  /// Stream of WebSocket connection status
  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;

  // ==================== INITIALIZATION ====================

  void _initializeSocket() {
    _initializeSocketAsync();
  }

  /// Initialize socket asynchronously with auth token
  void _initializeSocketAsync() async {
    try {
      final token = await _getAuthToken();

      socket = IO.io(
        'https://unbigamous-unappositely-kory.ngrok-free.dev',
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            // Include auth token in query parameters
            .setExtraHeaders({
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            })
            .setAuth({
              if (token != null && token.isNotEmpty) 'token': token,
            })
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(5)
            .build(),
      );

      socket.connect();
    } catch (e) {
      print('[WebSocket] Failed to initialize socket: $e');
    }

    socket.onConnect((_) {
      print('[WebSocket] Connected');
      _connectionStatusController.add('connected');
      _reconnectAttempts = 0;

      // Resubscribe to current ride if any
      if (_currentRideId != null) {
        subscribeToRideTracking(_currentRideId!);
      }
    });

    socket.onDisconnect((_) {
      print('[WebSocket] Disconnected');
      _connectionStatusController.add('disconnected');
    });

    socket.onConnectError((error) {
      print('[WebSocket] Connection error: $error');
      _connectionStatusController.add('error');
    });

    socket.onError((error) {
      print('[WebSocket] Error: $error');
      _connectionStatusController.add('error');
    });

    socket.onReconnect((_) {
      print('[WebSocket] Reconnected');
      _reconnectAttempts = 0;
    });
  }

  // ==================== REST ENDPOINTS ====================

  /// Estimate fare for a trip
  Future<Map<String, dynamic>> estimateFare({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String vehicleClass,
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

      final response = await http
          .post(
            Uri.parse('$baseUrl/estimate-fare'),
            headers: headers,
            body: jsonEncode({
              'pickupLatitude': pickupLatitude,
              'pickupLongitude': pickupLongitude,
              'dropoffLatitude': dropoffLatitude,
              'dropoffLongitude': dropoffLongitude,
              'vehicleClass': vehicleClass,
            }),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Fare estimation request timeout'),
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
      String url =
          '$baseUrl/vehicles?latitude=$latitude&longitude=$longitude&radiusKm=$radiusKm';
      if (vehicleClass != null) {
        url += '&vehicleClass=$vehicleClass';
      }

      final response = await http.get(Uri.parse(url));

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

      final response = await http
          .post(
            Uri.parse('$baseUrl/rides'),
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
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Ride request timeout'),
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
      final response = await http.get(Uri.parse('$baseUrl/rides/$rideId'));

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
        Uri.parse('$baseUrl/rides/$rideId/cancel'),
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

  // ==================== WEBSOCKET EVENTS ====================

  /// Subscribe to ride tracking and listen for updates
  void subscribeToRideTracking(int rideId) {
    _currentRideId = rideId;

    print('[WebSocket] Subscribing to ride: $rideId');

    // Emit subscription event to server
    socket.emit('passenger:subscribe', {'rideId': rideId});

    // Remove old listeners to avoid duplicates
    socket.off('driver:location:updated');
    socket.off('ride:status:updated');
    socket.off('passenger:subscribed');

    // Listen for confirmation
    socket.on('passenger:subscribed', (data) {
      print('[WebSocket] Subscribed to ride: $data');
    });

    // Listen for driver location updates
    socket.on('driver:location:updated', (data) {
      print('[WebSocket] Driver location: $data');
      _driverLocationController.add(Map<String, dynamic>.from(data as Map));
    });

    // Listen for ride status updates
    socket.on('ride:status:updated', (data) {
      print('[WebSocket] Ride status: $data');
      _rideStatusController.add(Map<String, dynamic>.from(data as Map));
    });
  }

  /// Unsubscribe from ride tracking
  void unsubscribeFromRideTracking() {
    if (_currentRideId != null) {
      print('[WebSocket] Unsubscribing from ride: $_currentRideId');
      socket.emit('passenger:unsubscribe');
      _currentRideId = null;
    }

    socket.off('driver:location:updated');
    socket.off('ride:status:updated');
  }

  /// Manually trigger location update listener
  void onDriverLocationUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('driver:location:updated', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  /// Manually trigger status update listener
  void onRideStatusUpdated(Function(Map<String, dynamic>) callback) {
    socket.on('ride:status:updated', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  // ==================== CONNECTION MANAGEMENT ====================

  /// Manually reconnect WebSocket
  Future<void> reconnectWebSocket() async {
    if (!socket.connected) {
      print('[WebSocket] Attempting to reconnect...');
      socket.connect();
    }
  }

  /// Check if WebSocket is connected
  bool isConnected() => socket.connected;

  /// Emit driver location update (for testing)
  void emitDriverLocation({
    required int rideId,
    required int driverId,
    required int vehicleId,
    required double latitude,
    required double longitude,
  }) {
    socket.emit('driver:location', {
      'rideId': rideId,
      'driverId': driverId,
      'vehicleId': vehicleId,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  // ==================== CLEANUP ====================

  /// Cleanup resources
  void dispose() {
    unsubscribeFromRideTracking();
    _driverLocationController.close();
    _rideStatusController.close();
    _connectionStatusController.close();
    socket.disconnect();
    print('[WebSocket] Service disposed');
  }
}
