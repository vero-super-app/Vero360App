import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

/// HTTP-based Ride Share Service replacing Firebase completely
class RideShareHttpService {
  late IO.Socket socket;
  late StreamController<String> _connectionStatusController;
  late StreamController<Map<String, dynamic>> _driverLocationController;
  late StreamController<Map<String, dynamic>> _rideStatusController;
  late StreamController<Ride> _rideUpdateController;

  RideShareHttpService() {
    _initializeControllers();
    _initializeSocket();
  }

  /// Get auth token - tries Firebase first, then falls back to SharedPreferences
  Future<String?> _getAuthToken() async {
    try {
      // Try to get fresh Firebase ID token if user is logged in
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          final freshToken = await firebaseUser.getIdToken();
          if (freshToken != null && freshToken.isNotEmpty) {
            print('[RideShare] Using fresh Firebase ID token');
            return freshToken;
          }
        } catch (e) {
          print('[RideShare] Error getting fresh Firebase token: $e');
        }
      }

      // Fallback to SharedPreferences if Firebase token not available
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('jwt_token') ??
          prefs.getString('token') ??
          prefs.getString('jwt');
      
      if (storedToken != null) {
        print('[RideShare] Using stored token from SharedPreferences');
        return storedToken;
      }

      print('[RideShare] No authentication token available');
      return null;
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
    _rideUpdateController = StreamController<Ride>.broadcast();
  }

  /// Stream getters
  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get driverLocationStream =>
      _driverLocationController.stream;
  Stream<Map<String, dynamic>> get rideStatusStream =>
      _rideStatusController.stream;
  Stream<Ride> get rideUpdateStream => _rideUpdateController.stream;

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

  // ============== RIDE MANAGEMENT ==============

  /// Estimate fare for a trip
  Future<FareEstimate> estimateFare({
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
        return FareEstimate.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to estimate fare: ${response.statusCode}');
      }
    } catch (e) {
      print('Error estimating fare: $e');
      rethrow;
    }
  }

  /// Get available vehicles by location and optional class filter
  Future<List<Vehicle>> getAvailableVehicles({
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
        final data = jsonDecode(response.body);
        if (data is List) {
          return (data as List)
              .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
              .toList();
        } else if (data is Map && data.containsKey('vehicles')) {
          final vehicles = data['vehicles'] as List;
          return vehicles
              .map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to get vehicles: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting vehicles: $e');
      rethrow;
    }
  }

  /// Request a new ride
  Future<Ride> requestRide({
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
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to request ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error requesting ride: $e');
      rethrow;
    }
  }

  /// Get ride details
  Future<Ride> getRideDetails(int rideId) async {
    try {
      final response =
          await http.get(ApiConfig.endpoint('/ride-share/rides/$rideId'));

      if (response.statusCode == 200) {
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting ride: $e');
      rethrow;
    }
  }

  /// Get rides for authenticated user (passenger)
  Future<List<Ride>> getMyRides() async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(
        ApiConfig.endpoint('/ride-share/rides'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return (data as List)
              .map((r) => Ride.fromJson(r as Map<String, dynamic>))
              .toList();
        } else if (data is Map && data.containsKey('rides')) {
          final rides = data['rides'] as List;
          return rides
              .map((r) => Ride.fromJson(r as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to get rides: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting rides: $e');
      rethrow;
    }
  }

  /// Accept a ride (driver)
  Future<Ride> acceptRide(int rideId, int vehicleId) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/accept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'vehicleId': vehicleId}),
      );

      if (response.statusCode == 200) {
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to accept ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error accepting ride: $e');
      rethrow;
    }
  }

  /// Mark driver as arrived at pickup
  Future<Ride> markDriverArrived(int rideId) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/driver-arrived'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to mark driver arrived: ${response.statusCode}');
      }
    } catch (e) {
      print('Error marking driver arrived: $e');
      rethrow;
    }
  }

  /// Start the ride
  Future<Ride> startRide(int rideId) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/start'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to start ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error starting ride: $e');
      rethrow;
    }
  }

  /// Complete the ride
  Future<Ride> completeRide(int rideId, {double? actualDistance}) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'actualDistance': actualDistance}),
      );

      if (response.statusCode == 200) {
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to complete ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error completing ride: $e');
      rethrow;
    }
  }

  /// Cancel a ride
  Future<Ride> cancelRide(int rideId, {String? reason}) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      );

      if (response.statusCode == 200) {
        return Ride.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to cancel ride: ${response.statusCode}');
      }
    } catch (e) {
      print('Error cancelling ride: $e');
      rethrow;
    }
  }

  // ============== VEHICLE MANAGEMENT ==============

  /// Get vehicle details
  Future<Vehicle> getVehicle(int vehicleId) async {
    try {
      final response =
          await http.get(ApiConfig.endpoint('/ride-share/vehicles/$vehicleId'));

      if (response.statusCode == 200) {
        return Vehicle.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get vehicle: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting vehicle: $e');
      rethrow;
    }
  }

  /// Update vehicle location (real-time tracking)
  Future<Vehicle> updateVehicleLocation(
    int vehicleId,
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/vehicles/$vehicleId/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode == 200) {
        return Vehicle.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to update vehicle location: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating vehicle location: $e');
      rethrow;
    }
  }

  /// Get vehicle statistics
  Future<Map<String, dynamic>> getVehicleStats(int vehicleId) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/ride-share/vehicles/$vehicleId/stats'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get vehicle stats: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting vehicle stats: $e');
      rethrow;
    }
  }

  /// Get active rides for driver
  Future<List<Ride>> getActiveRidesForDriver(int driverId) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/ride-share/drivers/$driverId/active-rides'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return (data as List)
              .map((r) => Ride.fromJson(r as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else {
        throw Exception('Failed to get active rides: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting active rides: $e');
      rethrow;
    }
  }

  // ============== REAL-TIME UPDATES VIA WEBSOCKET ==============

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
      try {
        final ride = Ride.fromJson(Map<String, dynamic>.from(data));
        _rideUpdateController.add(ride);
      } catch (e) {
        print('Error parsing ride update: $e');
      }
    });
  }

  /// Unsubscribe from ride tracking
  void unsubscribeFromRideTracking() {
    socket.emit('passenger:unsubscribe');
  }

  /// Subscribe driver to send location updates
  void subscribeDriverTracking(int rideId, int driverId, int vehicleId) {
    socket.emit('driver:subscribe', {
      'rideId': rideId,
      'driverId': driverId,
      'vehicleId': vehicleId,
    });
  }

  /// Update driver location via websocket
  void updateDriverLocationWebSocket(int rideId, double latitude, double longitude) {
    socket.emit('driver:location:update', {
      'rideId': rideId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
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

  /// Disconnect socket
  void disconnect() {
    socket.disconnect();
  }

  /// Dispose resources
  void dispose() {
    _connectionStatusController.close();
    _driverLocationController.close();
    _rideStatusController.close();
    _rideUpdateController.close();
    disconnect();
  }
}
