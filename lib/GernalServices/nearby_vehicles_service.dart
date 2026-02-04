import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vero360_app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NearbyVehicle {
  final int id;
  final int driverId;
  double latitude;
  double longitude;
  final double distance;
  final String vehicleClass;
  final String make;
  final String model;
  final String licensePlate;
  final double rating;
  final int totalRides;

  NearbyVehicle({
    required this.id,
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.vehicleClass,
    required this.make,
    required this.model,
    required this.licensePlate,
    required this.rating,
    required this.totalRides,
  });

  factory NearbyVehicle.fromJson(Map<String, dynamic> json) {
    return NearbyVehicle(
      id: json['id'] ?? 0,
      driverId: json['driverId'] ?? 0,
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      distance: (json['distance'] ?? 0.0).toDouble(),
      vehicleClass: json['vehicleClass'] ?? 'ECONOMY',
      make: json['make'] ?? '',
      model: json['model'] ?? '',
      licensePlate: json['licensePlate'] ?? '',
      rating: (json['rating'] ?? 0.0).toDouble(),
      totalRides: json['totalRides'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'latitude': latitude,
      'longitude': longitude,
      'distance': distance,
      'vehicleClass': vehicleClass,
      'make': make,
      'model': model,
      'licensePlate': licensePlate,
      'rating': rating,
      'totalRides': totalRides,
    };
  }
}

/// Service to fetch and manage nearby vehicles in real-time
class NearbyVehiclesService {
  final http.Client _httpClient;

  NearbyVehiclesService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Fetch nearby vehicles from backend
  Future<List<NearbyVehicle>> fetchNearbyVehicles({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    try {
      final baseUrl = await ApiConfig.readBase();
      final uri = Uri.parse(
        '$baseUrl/vero/ride-share/map/nearby-vehicles'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&radiusKm=$radiusKm',
      );

      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final vehiclesJson = (json['vehicles'] as List?) ?? [];

        return vehiclesJson
            .map((v) => NearbyVehicle.fromJson(v as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(
          'Failed to fetch nearby vehicles: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('[NearbyVehiclesService] Error fetching vehicles: $e');
      rethrow;
    }
  }

  /// Get cached vehicles (fallback)
  Future<List<NearbyVehicle>> getCachedVehicles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('nearby_vehicles_cache');
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return decoded
            .map((v) => NearbyVehicle.fromJson(v as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('[NearbyVehiclesService] Error reading cache: $e');
    }
    return [];
  }

  /// Cache vehicles locally
  Future<void> cacheVehicles(List<NearbyVehicle> vehicles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = vehicles.map((v) => v.toJson()).toList();
      await prefs.setString('nearby_vehicles_cache', jsonEncode(json));
    } catch (e) {
      print('[NearbyVehiclesService] Error caching vehicles: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
