import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper function to safely parse double values from JSON
double _parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

class NearbyTaxi {
  final int id;
  final int driverId;
  double latitude;
  double longitude;
  final double distance;
  final String taxiClass;
  final String make;
  final String model;
  final String licensePlate;
  final double rating;
  final int totalRides;

  NearbyTaxi({
    required this.id,
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.taxiClass,
    required this.make,
    required this.model,
    required this.licensePlate,
    required this.rating,
    required this.totalRides,
  });

  factory NearbyTaxi.fromJson(Map<String, dynamic> json) {
    return NearbyTaxi(
      id: json['id'] ?? 0,
      driverId: json['driverId'] ?? 0,
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      distance: _parseDouble(json['distance']),
      taxiClass: json['taxiClass'] ?? 'BIKE',
      make: json['make'] ?? '',
      model: json['model'] ?? '',
      licensePlate: json['licensePlate'] ?? '',
      rating: _parseDouble(json['rating']),
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
      'taxiClass': taxiClass,
      'make': make,
      'model': model,
      'licensePlate': licensePlate,
      'rating': rating,
      'totalRides': totalRides,
    };
  }
}

/// Service to fetch and manage nearby taxis in real-time
class NearbyTaxisService {
  final http.Client _httpClient;

  NearbyTaxisService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Fetch nearby taxis from backend
  Future<List<NearbyTaxi>> fetchNearbyTaxis({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    try {
      final baseUrl = await ApiConfig.readBase();
      final uri = Uri.parse(
        '$baseUrl/vero/taxis'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&radiusKm=$radiusKm',
      );

      // Get Firebase auth token
      final user = FirebaseAuth.instance.currentUser;
      final token = user != null ? await user.getIdToken() : null;

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final taxisJson = (json['taxis'] as List?) ?? [];

        return taxisJson
            .map((t) => NearbyTaxi.fromJson(t as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(
          'Failed to fetch nearby taxis: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('[NearbyTaxisService] Error fetching taxis: $e');
      rethrow;
    }
  }

  /// Get cached taxis (fallback)
  Future<List<NearbyTaxi>> getCachedTaxis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('nearby_taxis_cache');
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return decoded
            .map((t) => NearbyTaxi.fromJson(t as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('[NearbyTaxisService] Error reading cache: $e');
    }
    return [];
  }

  /// Cache taxis locally
  Future<void> cacheTaxis(List<NearbyTaxi> taxis) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = taxis.map((t) => t.toJson()).toList();
      await prefs.setString('nearby_taxis_cache', jsonEncode(json));
    } catch (e) {
      print('[NearbyTaxisService] Error caching taxis: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
