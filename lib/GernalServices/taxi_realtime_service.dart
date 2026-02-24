import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Model for real-time taxi location update
class TaxiLocationUpdate {
  final int taxiId;
  final int driverId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  TaxiLocationUpdate({
    required this.taxiId,
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory TaxiLocationUpdate.fromJson(Map<String, dynamic> json) {
    return TaxiLocationUpdate(
      taxiId: json['taxiId'] ?? 0,
      driverId: json['driverId'] ?? 0,
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

/// Service for real-time taxi location tracking via WebSocket
class TaxiRealtimeService {
  WebSocketChannel? _channel;
  StreamController<TaxiLocationUpdate>? _locationController;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  /// Stream of real-time taxi location updates
  Stream<TaxiLocationUpdate> get locationUpdates {
    _locationController ??= StreamController<TaxiLocationUpdate>.broadcast(
      onCancel: () {
        if (_locationController?.hasListener == false) {
          disconnect();
        }
      },
    );
    return _locationController!.stream;
  }

  bool get isConnected => _isConnected;

  /// Connect to WebSocket for real-time updates
  Future<bool> connect({String? token}) async {
    if (_isConnecting || _isConnected) {
      return _isConnected;
    }

    _isConnecting = true;

    try {
      // Get JWT token if not provided
      final authToken = token ?? await _getAuthToken();
      if (authToken == null) {
        print('[TaxiRealtimeService] No auth token available');
        _isConnecting = false;
        return false;
      }

      // Get WebSocket URL from backend config
      final baseUrl = await ApiConfig.readBase();
      final wsUrl = _convertToWebSocketUrl(baseUrl);

      print('[TaxiRealtimeService] Connecting to $wsUrl');

      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );

      // Wait for connection to establish
      await _channel!.ready;

      // Send authentication message
      _channel!.sink.add(
        jsonEncode({
          'type': 'auth',
          'token': authToken,
        }),
      );

      // Listen to incoming messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleConnectionClosed,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _isConnecting = false;

      print('[TaxiRealtimeService] Connected ✅');
      return true;
    } catch (e) {
      print('[TaxiRealtimeService] Connection failed: $e');
      _isConnecting = false;
      _scheduleReconnect();
      return false;
    }
  }

  /// Subscribe to taxi location updates (optional filter by rideId)
  void subscribeToTaxiUpdates({int? rideId}) {
    if (!_isConnected) {
      print('[TaxiRealtimeService] Not connected, attempting to connect');
      connect();
      return;
    }

    try {
      _channel?.sink.add(
        jsonEncode({
          'type': 'subscribe_taxis',
          if (rideId != null) 'rideId': rideId,
        }),
      );
      print('[TaxiRealtimeService] Subscribed to taxi updates');
    } catch (e) {
      print('[TaxiRealtimeService] Error subscribing: $e');
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message);
      final type = decoded['type'] ?? '';

      if (type == 'driver:location:updated' || type == 'taxi_location') {
        final update = TaxiLocationUpdate.fromJson(decoded);
        _locationController?.add(update);
        print(
          '[TaxiRealtimeService] Location update: '
          'Taxi ${update.taxiId} at (${update.latitude}, ${update.longitude})',
        );
      } else if (type == 'subscribed') {
        print('[TaxiRealtimeService] Subscription confirmed');
      }
    } catch (e) {
      print('[TaxiRealtimeService] Error parsing message: $e');
    }
  }

  /// Handle WebSocket errors
  void _handleError(error) {
    print('[TaxiRealtimeService] WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Handle WebSocket connection closed
  void _handleConnectionClosed() {
    print('[TaxiRealtimeService] Connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[TaxiRealtimeService] Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    print(
      '[TaxiRealtimeService] '
      'Scheduling reconnect (attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );

    _reconnectTimer = Timer(_reconnectDelay, () {
      connect();
    });
  }

  /// Get JWT auth token from Firebase
  Future<String?> _getAuthToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
    } catch (e) {
      print('[TaxiRealtimeService] Error getting auth token: $e');
    }
    return null;
  }

  /// Convert HTTP URL to WebSocket URL
  String _convertToWebSocketUrl(String httpUrl) {
    final uri = Uri.parse(httpUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final host = uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://$host$port';
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    try {
      await _channel?.sink.close(status.goingAway);
      _channel = null;
      _isConnected = false;
      print('[TaxiRealtimeService] Disconnected');
    } catch (e) {
      print('[TaxiRealtimeService] Error disconnecting: $e');
    }
  }

  /// Dispose service
  Future<void> dispose() async {
    await disconnect();
    await _locationController?.close();
    _locationController = null;
  }
}
