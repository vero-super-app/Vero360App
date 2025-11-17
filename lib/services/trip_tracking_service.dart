import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/models/trip_log_model.dart';

class TripTrackingService {
  // Simulates WebSocket connection for GPS updates
  // In production, replace with actual WebSocket: web_socket_channel
  StreamController<TripLogModel>? _positionController;

  /// Stream of live position updates during active rental
  Stream<TripLogModel> get positionStream {
    _positionController ??= StreamController<TripLogModel>.broadcast();
    return _positionController!.stream;
  }

  /// Fetch trip history for a completed rental
  Future<List<TripLogModel>> getTripHistory(int bookingId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final base = await ApiConfig.readBase();
    try {
      final res = await http.get(
        Uri.parse('$base/car-rental/trip-logs/booking/$bookingId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = decoded is List
            ? decoded
            : (decoded is Map && decoded['data'] is List
                ? decoded['data']
                : <dynamic>[]);

        return list
            .map<TripLogModel>(
                (e) => TripLogModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Failed to fetch trip history: ${res.statusCode}');
    } catch (e) {
      throw Exception('Trip history error: $e');
    }
  }

  /// Get live location of active rental
  Future<TripLogModel?> getLiveLocation(int carId) async {
    final token = await _getToken();
    if (token == null) return null;

    final base = await ApiConfig.readBase();
    try {
      final res = await http.get(
        Uri.parse('$base/car-rental/owner/monitoring/live-location/$carId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final log = data is Map
            ? data
            : (data['data'] is Map ? data['data'] : null);
        return log != null ? TripLogModel.fromJson(log as Map<String, dynamic>) : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Calculate total distance from trip logs
  Future<double> getTotalDistance(int bookingId) async {
    try {
      final logs = await getTripHistory(bookingId);
      return _calculateDistanceFromLogs(logs);
    } catch (_) {
      return 0.0;
    }
  }

  /// Simulate receiving position updates (replace with WebSocket in production)
  void simulatePositionUpdates(int carId, Duration interval) {
    final random = Random();
    var latitude = 37.7749;
    var longitude = -122.4194;

    Timer.periodic(interval, (timer) {
      // Add small random movement to simulate car movement
      latitude += (random.nextDouble() - 0.5) * 0.001;
      longitude += (random.nextDouble() - 0.5) * 0.001;

      if (_positionController != null && !_positionController!.isClosed) {
        _positionController!.add(
          TripLogModel(
            id: DateTime.now().millisecondsSinceEpoch,
            carId: carId,
            latitude: latitude,
            longitude: longitude,
            speed: 45.5 + (random.nextDouble() - 0.5) * 10,
            timestamp: DateTime.now(),
          ),
        );
      }
    });
  }

  /// Stop listening to position updates
  void stopTracking() {
    _positionController?.close();
    _positionController = null;
  }

  // ────── Haversine distance calculation ──────
  double _calculateDistanceFromLogs(List<TripLogModel> logs) {
    if (logs.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 0; i < logs.length - 1; i++) {
      final distance = _haversineDistance(
        logs[i].latitude,
        logs[i].longitude,
        logs[i + 1].latitude,
        logs[i + 1].longitude,
      );
      totalDistance += distance;
    }

    return totalDistance;
  }

  /// Haversine formula for geodetic distance
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // Earth radius in km

    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final lat1Rad = _toRad(lat1);
    final lat2Rad = _toRad(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  double _toRad(double degree) => degree * (pi / 180.0);

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }
}
