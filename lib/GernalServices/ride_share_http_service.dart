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
  Future<void>? _initializationFuture;

  RideShareHttpService() {
    _initializeControllers();
    // Initialize socket asynchronously without blocking constructor
    _initializationFuture = _initializeSocket().catchError((e) {
      print('[RideShareHttpService] Error initializing socket in constructor: $e');
    });
  }

  /// Ensure socket is initialized before using it
  Future<void> _ensureSocketInitialized() async {
    print('[RideShareHttpService] _ensureSocketInitialized called');
    if (_initializationFuture == null) {
      print('[RideShareHttpService] Creating new initialization future');
      _initializationFuture = _initializeSocketNow();
    }
    await _initializationFuture;
    print('[RideShareHttpService] Socket initialization complete');
  }

  /// Actual socket initialization
  Future<void> _initializeSocketNow() async {
    await _initializeSocket();
    // Wait a brief moment for socket to establish connection
    await Future.delayed(const Duration(milliseconds: 500));
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

  Future<void> _initializeSocket() async {
    // Get auth token before connecting
    final token = await _getAuthToken();
    
    socket = IO.io(
      ApiConfig.prod,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setQuery({'token': token})
          .build(),
    );

    socket.connect();
    socket.onConnect((_) {
      print('[RideShareHttpService] Socket connected with token');
      _connectionStatusController.add('connected');
    });

    socket.onDisconnect((_) {
      print('[RideShareHttpService] Socket disconnected');
      _connectionStatusController.add('disconnected');
    });

    socket.onError((error) {
      print('[RideShareHttpService] Socket error: $error');
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


<<<<<<< HEAD
      final response = await http.get(ApiConfig.endpoint(path));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return (data)
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
=======
>>>>>>> cf36011d6d2fd3f62745c8b7fc705c63ad4326d7

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
        print('[RideShareHttpService] Ride creation failed: ${response.statusCode}');
        print('[RideShareHttpService] Response: ${response.body}');
        throw Exception('Failed to request ride: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('[RideShareHttpService] Error requesting ride: $e');
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
          return (data)
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
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth token if available
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/accept'),
        headers: headers,
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
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth token if available
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/driver-arrived'),
        headers: headers,
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
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth token if available
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/start'),
        headers: headers,
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
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth token if available
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/complete'),
        headers: headers,
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
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth token if available
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/cancel'),
        headers: headers,
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

  // ============== TAXI MANAGEMENT ==============
  // Note: Taxi management is handled through DriverService
  // This service focuses on ride operations, not vehicle/taxi registration

  /// Get active rides for driver
  Future<List<Ride>> getActiveRidesForDriver(int driverId) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('/ride-share/drivers/$driverId/active-rides'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return (data)
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
  Future<void> subscribeToRideTracking(int rideId) async {
    print('[RideShareHttpService] subscribeToRideTracking called for ride $rideId');
    await _ensureSocketInitialized();
    print('[RideShareHttpService] Socket initialized, connected: ${socket.connected}');
    
    socket.emit('passenger:subscribe', {'rideId': rideId});
    print('[RideShareHttpService] Emitted passenger:subscribe for ride $rideId');

    // Listen for driver location updates
    socket.on('driver:location:updated', (data) {
      print('[RideShareHttpService] Driver location updated: $data');
      _driverLocationController.add(Map<String, dynamic>.from(data));
    });

    // Listen for ride status updates
    socket.on('ride:status:updated', (data) {
      print('[RideShareHttpService] 🎉 Ride status updated received: $data');
      _rideStatusController.add(Map<String, dynamic>.from(data));
      try {
        final ride = Ride.fromJson(Map<String, dynamic>.from(data));
        print('[RideShareHttpService] Parsed ride: ${ride.id}, status: ${ride.status}, driverId: ${ride.driverId}');
        _rideUpdateController.add(ride);
      } catch (e) {
        print('[RideShareHttpService] ❌ Error parsing ride update: $e');
        print('[RideShareHttpService] Data was: $data');
      }
    });
    
    print('[RideShareHttpService] Listeners registered for ride $rideId');
  }

  /// Unsubscribe from ride tracking
  Future<void> unsubscribeFromRideTracking() async {
    await _ensureSocketInitialized();
    socket.emit('passenger:unsubscribe');
  }

  /// Subscribe driver to send location updates
  Future<void> subscribeDriverTracking(int rideId, int driverId, int vehicleId) async {
    await _ensureSocketInitialized();
    socket.emit('driver:subscribe', {
      'rideId': rideId,
      'driverId': driverId,
      'vehicleId': vehicleId,
    });
  }

  /// Update driver location via websocket
  Future<void> updateDriverLocationWebSocket(int rideId, double latitude, double longitude) async {
    await _ensureSocketInitialized();
    // Event name must match the backend SubscribeMessage('driver:location') handler
    socket.emit('driver:location', {
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
