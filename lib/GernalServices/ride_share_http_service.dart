import 'dart:core';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GeneralModels/ride_history_model.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_storage.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_diagnostics.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// HTTP-based Ride Share Service. Auth is Firebase ID token only (no Nest JWT).
class RideShareHttpService {
  IO.Socket? socket;
  late StreamController<String> _connectionStatusController;
  late StreamController<Map<String, dynamic>> _driverLocationController;
  late StreamController<Map<String, dynamic>> _rideStatusController;
  late StreamController<Ride> _rideUpdateController;
  Future<void>? _initializationFuture;
  bool _globalSocketListenersRegistered = false;
  bool _socketCreated = false;
  bool _socketAuthRetryInFlight = false;
  int _socketAuthRetries = 0;
  int? _subscribedRideId;
  ActiveRideRole? _subscribedRole;

  RideShareHttpService() {
    _initializeControllers();
  }

  /// Ensure socket is initialized before using it.
  /// Waits briefly for Firebase session restore — do not connect tokenless.
  Future<void> _ensureSocketInitialized() async {
    print('[RideShareHttpService] _ensureSocketInitialized called');
    if (!_socketCreated || _initializationFuture == null) {
      print('[RideShareHttpService] Creating new initialization future');
      _initializationFuture = _initializeSocketNow();
    }
    await _initializationFuture;
    if (!_socketCreated) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _initializationFuture = _initializeSocketNow();
      await _initializationFuture;
    }
    print('[RideShareHttpService] Socket initialization complete');
  }

  /// Actual socket initialization
  Future<void> _initializeSocketNow() async {
    await _initializeSocket();
    // Wait a brief moment for socket to establish connection
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Firebase ID token only — ride-share backend rejects Nest access_token.
  Future<String?> _getAuthToken({bool forceRefresh = false}) async {
    try {
      final token = await AuthHandler.getFirebaseTokenForApi(
        forceRefresh: forceRefresh,
      );
      if (token == null || token.isEmpty) {
        print('[RideShare] No Firebase ID token (user must be signed in)');
      }
      return token;
    } catch (e) {
      print('Error reading Firebase auth token: $e');
      return null;
    }
  }

  Future<Map<String, String>> _authHeaders({
    bool forceRefresh = false,
    bool json = true,
  }) async {
    final token = await _getAuthToken(forceRefresh: forceRefresh);
    final diag = await AuthDiagnostics.buildHeaders(token: token);
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...diag,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    await RoleSessionService.applyIntendedRoleHeader(headers);
    return headers;
  }

  Exception _httpError(String action, http.Response response) {
    final api = _apiErrorMessage(response.body);
    if (api != null && api.isNotEmpty) {
      return Exception(api);
    }
    return Exception('Failed to $action: ${response.statusCode}');
  }

  Future<Ride> _sendRide(
    String action,
    Future<http.Response> Function(Map<String, String> headers) send, {
    int successCode = 200,
  }) async {
    final response = await _withFirebaseAuth(send);
    if (response.statusCode == successCode) {
      return Ride.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw _httpError(action, response);
  }

  /// Run an authorized HTTP call; on 401/403 force-refresh Firebase token once.
  Future<http.Response> _withFirebaseAuth(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var headers = await _authHeaders();
    var res = await send(headers);
    if (res.statusCode == 401 || res.statusCode == 403) {
      final body = res.body.toLowerCase();
      final provisionConflict = body.contains('creation conflict') ||
          body.contains('user_provision_failed');
      if (provisionConflict) {
        unawaited(
          AuthDiagnostics.reportFailure(
            reason: 'ride_share_http_${res.statusCode}',
            channel: 'http',
            lastError: res.body.length > 200
                ? res.body.substring(0, 200)
                : res.body,
            idToken: headers['Authorization']?.replaceFirst('Bearer ', ''),
          ),
        );
        return res;
      }
      final refreshed = await AuthHandler.refreshTokenAfterUnauthorized();
      if (refreshed != null && refreshed.isNotEmpty) {
        headers = await _authHeaders(forceRefresh: true);
        headers['Authorization'] = 'Bearer $refreshed';
        res = await send(headers);
      } else {
        headers = await _authHeaders(forceRefresh: true);
        if (headers['Authorization'] != null) {
          res = await send(headers);
        }
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        unawaited(
          AuthDiagnostics.reportFailure(
            reason: 'ride_share_http_${res.statusCode}',
            channel: 'http',
            lastError: res.body.length > 200
                ? res.body.substring(0, 200)
                : res.body,
            idToken: headers['Authorization']?.replaceFirst('Bearer ', ''),
          ),
        );
      }
    }
    return res;
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
    // Always force-refresh: Socket.IO caches the handshake token; a cached
    // Firebase ID token expires after ~1h and causes auth/id-token-expired.
    final token = await _getAuthToken(forceRefresh: true);
    if (token == null || token.isEmpty) {
      print('[RideShareHttpService] No Firebase token — skipping socket connect');
      // Only report when Firebase already has a user (token fetch failed),
      // not when the service is constructed before sign-in.
      if (FirebaseAuth.instance.currentUser != null) {
        unawaited(
          AuthDiagnostics.reportFailure(
            reason: 'socket_missing_token',
            channel: 'websocket',
            lastError: 'No Firebase ID token before socket connect',
          ),
        );
      }
      return;
    }

    if (_socketCreated) {
      try {
        socket?.dispose();
      } catch (_) {}
    }

    final query = await AuthDiagnostics.buildSocketQuery(token: token);
    final diagHeaders = await AuthDiagnostics.buildHeaders(token: token);
    await RoleSessionService.applyIntendedRoleHeader(diagHeaders);
    if (diagHeaders.containsKey(RoleSessionService.intendedRoleHeader)) {
      query[RoleSessionService.intendedRoleHeader] =
          diagHeaders[RoleSessionService.intendedRoleHeader];
    }

    final sock = IO.io(
      ApiConfig.prod,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .setExtraHeaders({
            'Authorization': 'Bearer $token',
            ...diagHeaders,
          })
          .setQuery(query)
          .build(),
    );
    socket = sock;
    _socketCreated = true;

    _globalSocketListenersRegistered = false;

    sock.onConnect((_) {
      print('[RideShareHttpService] Socket connected with fresh token');
      _socketAuthRetries = 0;
      _connectionStatusController.add('connected');
      _resubscribeIfNeeded();
    });

    sock.onDisconnect((_) {
      print('[RideShareHttpService] Socket disconnected');
      _connectionStatusController.add('disconnected');
    });

    sock.onError((error) {
      print('[RideShareHttpService] Socket error');
      _connectionStatusController.add('error');
      unawaited(_retrySocketAuthIfNeeded(error));
    });

    sock.on('error', (data) {
      unawaited(_retrySocketAuthIfNeeded(data));
    });

    _registerGlobalSocketListeners();
    sock.connect();
  }

  String _socketErrorBlob(Object? error) {
    if (error is Map) {
      return '${error['reason'] ?? ''} ${error['message'] ?? ''} ${error['code'] ?? ''}'
          .toLowerCase();
    }
    return error?.toString().toLowerCase() ?? '';
  }

  /// Backend emits auth failures then disconnects; rebuild with a new ID token.
  Future<void> _retrySocketAuthIfNeeded(Object? error) async {
    final msg = _socketErrorBlob(error);
    final provisionFailed = msg.contains('user_provision_failed') ||
        msg.contains('creation conflict');
    final looksExpired = msg.contains('expired') ||
        msg.contains('id-token') ||
        msg.contains('id_token_expired');
    final looksAuth = looksExpired ||
        msg.contains('unauthorized') ||
        msg.contains('authentication required') ||
        provisionFailed;
    if (!looksAuth || _socketAuthRetryInFlight) return;
    if (_socketAuthRetries >= (provisionFailed ? 1 : 3)) return;

    _socketAuthRetryInFlight = true;
    _socketAuthRetries += 1;
    try {
      print('[RideShareHttpService] Auth failed on socket — refreshing token');
      unawaited(
        AuthDiagnostics.reportFailure(
          reason: 'socket_auth_retry',
          channel: 'websocket',
          lastError: error?.toString(),
        ),
      );
      _initializationFuture = null;
      _socketCreated = false;
      await Future<void>.delayed(
        Duration(milliseconds: provisionFailed ? 1200 : 400),
      );
      await _initializeSocketNow();
    } catch (e) {
      print('[RideShareHttpService] Socket auth retry failed');
    } finally {
      _socketAuthRetryInFlight = false;
    }
  }

  /// Single registration — [subscribeToRideTracking] used to add duplicate
  /// `socket.on` handlers every time, causing spurious lifecycle updates.
  void _registerGlobalSocketListeners() {
    final sock = socket;
    if (_globalSocketListenersRegistered || sock == null) return;
    _globalSocketListenersRegistered = true;

    sock.on('driver:location:updated', (data) {
      print('[RideShareHttpService] Driver location updated: $data');
      _driverLocationController.add(Map<String, dynamic>.from(data));
    });

    sock.on('ride:driver-location-stale', (data) {
      print('[RideShareHttpService] Driver location stale: $data');
      _rideStatusController.add(Map<String, dynamic>.from(data as Map));
    });

    sock.on('ride:status:updated', (data) {
      print('[RideShareHttpService] 🎉 Ride status updated received: $data');
      _rideStatusController.add(Map<String, dynamic>.from(data));
      try {
        final rideMap = Map<String, dynamic>.from(data);
        if (rideMap['id'] == null && rideMap['rideId'] != null) {
          rideMap['id'] = rideMap['rideId'];
        }
        final rideData = {
          'id': rideMap['id'] ?? rideMap['rideId'] ?? 0,
          'passengerId': rideMap['passengerId'] ?? 0,
          'pickupLatitude': rideMap['pickupLatitude'] ?? 0.0,
          'pickupLongitude': rideMap['pickupLongitude'] ?? 0.0,
          'dropoffLatitude': rideMap['dropoffLatitude'] ?? 0.0,
          'dropoffLongitude': rideMap['dropoffLongitude'] ?? 0.0,
          'estimatedDistance': rideMap['estimatedDistance'] ?? 0.0,
          'estimatedFare': rideMap['estimatedFare'] ?? 0.0,
          'status': rideMap['status'] ?? 'REQUESTED',
          'createdAt': rideMap['createdAt'] ?? DateTime.now().toIso8601String(),
          'updatedAt': rideMap['updatedAt'] ?? DateTime.now().toIso8601String(),
          ...rideMap,
        };
        final ride = Ride.fromJson(rideData);
        print(
            '[RideShareHttpService] Parsed ride: ${ride.id}, status: ${ride.status}, driverId: ${ride.driverId}');
        _rideUpdateController.add(ride);
      } catch (e) {
        print('[RideShareHttpService] ❌ Error parsing ride update');
        print('[RideShareHttpService] Data was: $data');
      }
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
      print('Error estimating fare');
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
      final response = await _withFirebaseAuth(
        (headers) => http.post(
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
        ),
      );

      if (response.statusCode == 201) {
        try {
          final rideData = jsonDecode(response.body);
          final ride = Ride.fromJson(rideData);

          // Check if ride was auto-cancelled due to no drivers
          if (ride.status == RideStatus.cancelled &&
              ride.cancellationReason == 'No drivers available in your area') {
            print(
                '[RideShareHttpService] Ride auto-cancelled: ${ride.cancellationReason}');
          } else if (ride.isCancelled) {
            print(
                '[RideShareHttpService] Ride returned as cancelled: ${ride.cancellationReason}');
          }

          return ride;
        } catch (parseError) {
          print(
              '[RideShareHttpService] Error parsing ride response: $parseError');
          rethrow;
        }
      } else if (response.statusCode == 400) {
        print('[RideShareHttpService] Bad request (400): ${response.body}');
        var message = 'Invalid request parameters';
        try {
          final errorData = jsonDecode(response.body);
          final raw = errorData is Map ? errorData['message'] : null;
          if (raw is String && raw.trim().isNotEmpty) {
            message = raw.trim();
          } else if (raw is List && raw.isNotEmpty) {
            message = raw.map((e) => e.toString()).join(', ');
          }
        } catch (_) {}
        throw Exception(message);
      } else {
        print(
            '[RideShareHttpService] Ride creation failed: ${response.statusCode}');
        print('[RideShareHttpService] Response: ${response.body}');
        throw _httpError('request ride', response);
      }
    } catch (e) {
      print('[RideShareHttpService] Error requesting ride');
      rethrow;
    }
  }

  /// Get ride details
  Future<Ride> getRideDetails(int rideId) async {
    return _sendRide(
      'get ride',
      (headers) => http.get(
        ApiConfig.endpoint('/ride-share/rides/$rideId'),
        headers: headers,
      ),
    );
  }

  String? _apiErrorMessage(String body) {
    try {
      final errorData = jsonDecode(body);
      final raw = errorData is Map ? errorData['message'] : null;
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => e.toString()).join(', ');
      }
    } catch (_) {}
    return null;
  }

  RideHistoryPage _parseRideHistoryResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return RideHistoryPage.fromJson(data);
    }
    if (data is List) {
      final rides = data
          .map((r) => Ride.fromJson(r as Map<String, dynamic>))
          .toList();
      return RideHistoryPage(
        rides: rides,
        total: rides.length,
        page: 1,
        limit: rides.length,
        summary: RideHistorySummary(
          completedCount:
              rides.where((r) => r.isCompleted).length,
          cancelledCount:
              rides.where((r) => r.isCancelled).length,
          totalSpent: rides
              .where((r) => r.isCompleted)
              .fold<double>(0, (s, r) => s + r.resolvedFare),
        ),
      );
    }
    return RideHistoryPage(
      rides: const [],
      total: 0,
      page: 1,
      limit: 20,
      summary: RideHistorySummary(completedCount: 0, cancelledCount: 0),
    );
  }

  /// Get paginated ride history for authenticated passenger
  Future<RideHistoryPage> getPassengerRideHistory({
    String status = 'ALL',
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = ApiConfig.endpoint('/ride-share/rides').replace(
        queryParameters: {
          'status': status,
          'page': '$page',
          'limit': '$limit',
        },
      );
      final response = await _withFirebaseAuth(
        (headers) => http.get(uri, headers: headers),
      );

      if (response.statusCode == 200) {
        return _parseRideHistoryResponse(jsonDecode(response.body));
      }
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null) {
          return RideHistoryPage(
            rides: const [],
            total: 0,
            page: page,
            limit: limit,
            summary: RideHistorySummary(
              completedCount: 0,
              cancelledCount: 0,
              totalSpent: 0,
              totalEarnings: 0,
            ),
          );
        }
      }
      throw Exception('Failed to get rides: ${response.statusCode}');
    } catch (e) {
      print('Error getting passenger ride history: $e');
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        return RideHistoryPage(
          rides: const [],
          total: 0,
          page: page,
          limit: limit,
          summary: RideHistorySummary(
            completedCount: 0,
            cancelledCount: 0,
            totalSpent: 0,
            totalEarnings: 0,
          ),
        );
      }
      rethrow;
    }
  }

  /// Newest completed trip that still blocks booking, if any.
  Future<Ride?> findUnpaidCompletedRide() async {
    try {
      final response = await _withFirebaseAuth(
        (headers) => http.get(
          ApiConfig.endpoint('/ride-share/rides/unpaid-completed'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.isEmpty || body == 'null') return null;
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) {
          final ride = Ride.fromJson(data);
          return ride.needsPayment ? ride : null;
        }
        return null;
      }
    } catch (e) {
      print('Error fetching unpaid completed ride: $e');
    }

    final page = await getPassengerRideHistory(
      status: 'COMPLETED',
      page: 1,
      limit: 50,
    );
    for (final ride in page.rides) {
      if (ride.needsPayment) return ride;
    }
    return null;
  }

  /// Get paginated ride history for authenticated driver
  Future<RideHistoryPage> getDriverRideHistory({
    String status = 'ALL',
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri =
          ApiConfig.endpoint('/ride-share/drivers/me/rides').replace(
        queryParameters: {
          'status': status,
          'page': '$page',
          'limit': '$limit',
        },
      );
      final response = await _withFirebaseAuth(
        (headers) => http.get(uri, headers: headers),
      );

      if (response.statusCode == 200) {
        return _parseRideHistoryResponse(jsonDecode(response.body));
      }
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null) {
          return RideHistoryPage(
            rides: const [],
            total: 0,
            page: page,
            limit: limit,
            summary: RideHistorySummary(
              completedCount: 0,
              cancelledCount: 0,
              totalSpent: 0,
              totalEarnings: 0,
            ),
          );
        }
      }
      throw Exception('Failed to get driver rides: ${response.statusCode}');
    } catch (e) {
      print('Error getting driver ride history: $e');
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        return RideHistoryPage(
          rides: const [],
          total: 0,
          page: page,
          limit: limit,
          summary: RideHistorySummary(
            completedCount: 0,
            cancelledCount: 0,
            totalSpent: 0,
            totalEarnings: 0,
          ),
        );
      }
      rethrow;
    }
  }

  /// Get driver earnings summary by period
  Future<DriverEarningsSummary> getDriverEarningsSummary() async {
    try {
      final response = await _withFirebaseAuth(
        (headers) => http.get(
          ApiConfig.endpoint('/ride-share/drivers/me/earnings/summary'),
          headers: headers,
        ),
      );

      if (response.statusCode == 200) {
        return DriverEarningsSummary.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null) {
          return DriverEarningsSummary(
            today: EarningsPeriod(trips: 0, earnings: 0),
            thisWeek: EarningsPeriod(trips: 0, earnings: 0),
            thisMonth: EarningsPeriod(trips: 0, earnings: 0),
            allTime: EarningsPeriod(trips: 0, earnings: 0),
          );
        }
      }
      throw Exception(
        'Failed to get driver earnings: ${response.statusCode}',
      );
    } catch (e) {
      print('Error getting driver earnings summary: $e');
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        return DriverEarningsSummary(
          today: EarningsPeriod(trips: 0, earnings: 0),
          thisWeek: EarningsPeriod(trips: 0, earnings: 0),
          thisMonth: EarningsPeriod(trips: 0, earnings: 0),
          allTime: EarningsPeriod(trips: 0, earnings: 0),
        );
      }
      rethrow;
    }
  }

  /// Legacy alias — returns ride list from passenger history
  Future<List<Ride>> getMyRides() async {
    final page = await getPassengerRideHistory();
    return page.rides;
  }

  /// Accept a ride (driver)
  Future<Ride> acceptRide(int rideId, int vehicleId) async {
    return _sendRide(
      'accept ride',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/accept'),
        headers: headers,
        body: jsonEncode({'taxiId': vehicleId}),
      ),
    );
  }

  /// Mark driver as arrived at pickup
  Future<Ride> markDriverArrived(int rideId) async {
    return _sendRide(
      'mark driver arrived',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/driver-arrived'),
        headers: headers,
      ),
    );
  }

  /// Start the ride
  Future<Ride> startRide(int rideId) async {
    return _sendRide(
      'start ride',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/start'),
        headers: headers,
      ),
    );
  }

  /// Complete the ride
  Future<Ride> completeRide(int rideId, {double? actualDistance}) async {
    final body = <String, dynamic>{};
    if (actualDistance != null) {
      body['actualDistance'] = actualDistance;
    }
    return _sendRide(
      'complete ride',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/complete'),
        headers: headers,
        body: jsonEncode(body),
      ),
    );
  }

  /// Passenger selects cash for a completed ride.
  Future<Ride> selectCashPayment(int rideId) async {
    return _sendRide(
      'select cash payment',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/payment/cash'),
        headers: headers,
      ),
    );
  }

  /// Driver confirms cash was received.
  Future<Ride> confirmCashPayment(int rideId) async {
    return _sendRide(
      'confirm cash payment',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/payment/cash/confirm'),
        headers: headers,
      ),
    );
  }

  /// Confirm passenger payment for a completed ride
  Future<Ride> confirmRidePayment(int rideId, String txRef) async {
    return _sendRide(
      'confirm ride payment',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/payment'),
        headers: headers,
        body: jsonEncode({'txRef': txRef}),
      ),
    );
  }

  /// Cancel a ride
  Future<Ride> cancelRide(int rideId, {String? reason}) async {
    return _sendRide(
      'cancel ride',
      (headers) => http.patch(
        ApiConfig.endpoint('/ride-share/rides/$rideId/cancel'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ),
    );
  }

  // ============== TAXI MANAGEMENT ==============
  // Note: Taxi management is handled through DriverService
  // This service focuses on ride operations, not vehicle/taxi registration

  void registerRideSubscription({
    required int rideId,
    required ActiveRideRole role,
  }) {
    _subscribedRideId = rideId;
    _subscribedRole = role;
  }

  void clearRideSubscription() {
    _subscribedRideId = null;
    _subscribedRole = null;
  }

  Future<void> _resubscribeIfNeeded() async {
    final rideId = _subscribedRideId;
    final role = _subscribedRole;
    final sock = socket;
    if (rideId == null || role == null || sock == null || !sock.connected) {
      return;
    }

    if (role == ActiveRideRole.driver) {
      sock.emit('driver:subscribe', {'rideId': rideId});
    } else {
      sock.emit('passenger:subscribe', {'rideId': rideId});
    }
    print(
        '[RideShareHttpService] Re-subscribed to ride $rideId as ${role.name}');
  }

  Future<void> reconnectAndResubscribe() async {
    await reconnectWebSocket();
    await _resubscribeIfNeeded();
  }

  Future<List<Ride>> _parseRideList(http.Response response, String action) async {
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data
            .map((r) => Ride.fromJson(r as Map<String, dynamic>))
            .toList();
      }
      return [];
    }
    throw _httpError(action, response);
  }

  /// Get active rides for passenger
  Future<List<Ride>> getActiveRidesForPassenger() async {
    final response = await _withFirebaseAuth(
      (headers) => http.get(
        ApiConfig.endpoint('/ride-share/passengers/me/active-rides'),
        headers: headers,
      ),
    );
    return _parseRideList(response, 'get passenger active rides');
  }

  /// Get active rides for driver
  Future<List<Ride>> getActiveRidesForDriver(int driverId) async {
    final response = await _withFirebaseAuth(
      (headers) => http.get(
        ApiConfig.endpoint('/ride-share/drivers/$driverId/active-rides'),
        headers: headers,
      ),
    );
    return _parseRideList(response, 'get active rides');
  }

  // ============== REAL-TIME UPDATES VIA WEBSOCKET ==============

  /// Subscribe to passenger ride tracking
  Future<void> subscribeToRideTracking(int rideId) async {
    print(
        '[RideShareHttpService] subscribeToRideTracking called for ride $rideId');
    await _ensureSocketInitialized();
    final sock = socket;
    print(
        '[RideShareHttpService] Socket initialized, connected: ${sock?.connected}');
    sock?.emit('passenger:subscribe', {'rideId': rideId});
    print(
        '[RideShareHttpService] Emitted passenger:subscribe for ride $rideId (global WS listeners already attached)');
  }

  /// Unsubscribe from ride tracking
  Future<void> unsubscribeFromRideTracking() async {
    try {
      await _ensureSocketInitialized();
      final sock = socket;
      if (sock != null && sock.connected) {
        sock.emit('passenger:unsubscribe');
      }
    } catch (e) {
      print('[RideShareHttpService] Error unsubscribing from ride');
      // Don't rethrow - unsubscribe is cleanup, not critical
    }
  }

  /// Subscribe driver to send location updates
  Future<void> subscribeDriverTracking(int rideId) async {
    await _ensureSocketInitialized();
    socket?.emit('driver:subscribe', {
      'rideId': rideId,
    });
  }

  /// Update driver location via websocket
  Future<void> updateDriverLocationWebSocket(
      int rideId, double latitude, double longitude) async {
    await _ensureSocketInitialized();
    // Event name must match the backend SubscribeMessage('driver:location') handler
    socket?.emit('driver:location', {
      'rideId': rideId,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Listen to driver location updates
  void onDriverLocationUpdated(Function(Map<String, dynamic>) callback) {
    try {
      socket?.on('driver:location:updated', (data) {
        callback(Map<String, dynamic>.from(data));
      });
    } catch (e) {
      print(
          '[RideShareHttpService] Error registering driver location listener');
    }
  }

  /// Listen to ride status changes
  void onRideStatusUpdated(Function(Map<String, dynamic>) callback) {
    try {
      socket?.on('ride:status:updated', (data) {
        callback(Map<String, dynamic>.from(data));
      });
    } catch (e) {
      print('[RideShareHttpService] Error registering ride status listener');
    }
  }

  /// Reconnect websocket with a fresh Firebase ID token (never reuse handshake).
  Future<void> reconnectWebSocket() async {
    try {
      _initializationFuture = null;
      _socketCreated = false;
      await _initializeSocketNow();
      print('WebSocket reconnected with fresh token');
      await _resubscribeIfNeeded();
    } catch (e) {
      print('Error reconnecting WebSocket');
      _connectionStatusController.add('error');
      rethrow;
    }
  }

  /// Disconnect socket
  void disconnect() {
    try {
      socket?.disconnect();
    } catch (e) {
      print('[RideShareHttpService] Error disconnecting socket');
    }
  }

  /// Dispose resources
  void dispose() {
    try {
      _connectionStatusController.close();
    } catch (e) {
      print(
          '[RideShareHttpService] Error closing connection status controller');
    }
    try {
      _driverLocationController.close();
    } catch (e) {
      print('[RideShareHttpService] Error closing driver location controller');
    }
    try {
      _rideStatusController.close();
    } catch (e) {
      print('[RideShareHttpService] Error closing ride status controller');
    }
    try {
      _rideUpdateController.close();
    } catch (e) {
      print('[RideShareHttpService] Error closing ride update controller');
    }
    try {
      disconnect();
    } catch (e) {
      print('[RideShareHttpService] Error in disconnect during dispose');
    }
  }
}
