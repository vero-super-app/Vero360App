import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/config/api_config.dart';

/// WebSocket service for real-time car location updates
///
/// Manages WebSocket connection to backend for receiving live car location streams.
/// Handles authentication, subscription management, and automatic reconnection.
class CarWebSocketService {
  static const String _logPrefix = '[CarWS]';

  WebSocketChannel? _channel;
  StreamController<List<CarModel>>? _carUpdatesController;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isDisposed = false;
  Set<String> _subscribedCars = {};

  /// Stream of car location updates
  Stream<List<CarModel>> get carUpdates {
    _carUpdatesController ??= StreamController<List<CarModel>>.broadcast();
    return _carUpdatesController!.stream;
  }

  /// Connect to WebSocket and authenticate
  Future<bool> connect() async {
    if (_isConnected) return true;
    if (_isDisposed) return false;

    try {
      final token = await _getToken();
      if (token == null) {
        _log('Not authenticated - cannot connect');
        return false;
      }

      final base = await ApiConfig.readBase();
      final wsUrl = _buildWebSocketUrl(base, token);

      _log('Connecting to: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for connection to be established
      await _channel!.ready;
      _isConnected = true;
      _log('Connected successfully');

      // Listen for messages
      _listenToMessages();

      return true;
    } catch (e) {
      _log('Connection failed: $e');
      _isConnected = false;
      _scheduleReconnect();
      return false;
    }
  }

  /// Subscribe to real-time updates for specific cars
  ///
  /// The backend will emit position updates for these cars via WebSocket
  ///
  /// @param carIds - List of car IDs to subscribe to
  Future<void> subscribeToCars(List<int> carIds) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) return;
    }

    try {
      for (var carId in carIds) {
        final carIdStr = carId.toString();
        if (_subscribedCars.contains(carIdStr)) continue;

        _log('Subscribing to car $carId');

        _channel!.sink.add(jsonEncode({
          'event': 'subscribe_car',
          'data': {'carId': carIdStr},
        }));

        _subscribedCars.add(carIdStr);
      }
    } catch (e) {
      _log('Subscription error: $e');
      _scheduleReconnect();
    }
  }

  /// Unsubscribe from updates for a car
  Future<void> unsubscribeFromCar(int carId) async {
    if (!_isConnected) return;

    try {
      final carIdStr = carId.toString();
      _log('Unsubscribing from car $carId');

      _channel!.sink.add(jsonEncode({
        'event': 'unsubscribe_car',
        'data': {'carId': carIdStr},
      }));

      _subscribedCars.remove(carIdStr);
    } catch (e) {
      _log('Unsubscription error: $e');
    }
  }

  /// Watch a single car's real-time location
  ///
  /// Returns a stream that emits the car whenever its location changes
  Stream<CarModel> watchCarLocation(CarModel car) async* {
    await subscribeToCars([car.id]);

    yield car;

    // Yield updates from the main stream filtered for this car
    await for (final cars in carUpdates) {
      final updatedCar = cars.firstWhere(
        (c) => c.id == car.id,
        orElse: () => car,
      );
      yield updatedCar;
    }
  }

  /// Disconnect and clean up resources
  Future<void> disconnect() async {
    _log('Disconnecting...');
    _isConnected = false;
    _subscribedCars.clear();
    _reconnectTimer?.cancel();

    try {
      await _channel?.sink.close();
    } catch (e) {
      _log('Error closing channel: $e');
    }
  }

  /// Dispose the service and release all resources
  void dispose() {
    _isDisposed = true;
    _carUpdatesController?.close();
    disconnect();
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────

  void _listenToMessages() {
    _channel!.stream.listen(
      (dynamic message) {
        if (_isDisposed) return;

        try {
          final data = jsonDecode(message as String);

          if (data['type'] == 'position_update') {
            _handlePositionUpdate(data['payload']);
          } else if (data['type'] == 'subscription_ack') {
            _log('Subscription acknowledged for car ${data['carId']}');
          } else if (data['type'] == 'error') {
            _log('Server error: ${data['message']}');
          }
        } catch (e) {
          _log('Message parsing error: $e');
        }
      },
      onError: (error) {
        _log('WebSocket error: $error');
        _isConnected = false;
        _scheduleReconnect();
      },
      onDone: () {
        _log('WebSocket closed');
        _isConnected = false;
        _scheduleReconnect();
      },
    );
  }

  void _handlePositionUpdate(dynamic payload) {
    try {
      if (payload is List) {
        final cars = (payload as List)
            .map((e) => CarModel.fromJson(e as Map<String, dynamic>))
            .toList();

        if (_carUpdatesController != null && !_carUpdatesController!.isClosed) {
          _carUpdatesController!.add(cars);
        }
      } else if (payload is Map) {
        final car = CarModel.fromJson(payload as Map<String, dynamic>);
        if (_carUpdatesController != null && !_carUpdatesController!.isClosed) {
          _carUpdatesController!.add([car]);
        }
      }
    } catch (e) {
      _log('Error handling position update: $e');
    }
  }

  String _buildWebSocketUrl(String baseUrl, String token) {
    final uri = Uri.parse(baseUrl);
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';

    return '$scheme://$host:$port/car-tracking?token=$token';
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isDisposed) {
        _log('Attempting to reconnect...');
        connect();
      }
    });
  }

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token') ?? prefs.getString('token');
    } catch (e) {
      _log('Error getting token: $e');
      return null;
    }
  }

  void _log(String message) {
    print('$_logPrefix $message');
  }
}
