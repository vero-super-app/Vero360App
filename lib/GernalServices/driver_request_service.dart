import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';

/// Model for driver-specific ride request
class DriverRideRequest {
  final String id;
  final String passengerId;
  final String passengerName;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String pickupAddress;
  final String dropoffAddress;
  final String status; // pending, accepted, arrived, in_progress, completed
  final DateTime createdAt;
  final int estimatedTime;
  final double estimatedDistance;
  final double estimatedFare;
  final String? passengerPhone;

  DriverRideRequest({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.status,
    required this.createdAt,
    required this.estimatedTime,
    required this.estimatedDistance,
    required this.estimatedFare,
    this.passengerPhone,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'estimatedTime': estimatedTime,
      'estimatedDistance': estimatedDistance,
      'estimatedFare': estimatedFare,
      'passengerPhone': passengerPhone,
    };
  }

  factory DriverRideRequest.fromMap(Map<String, dynamic> map, dynamic idParam) {
    // Handle both ISO string and millisecond timestamps
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return DateTime.now();
        }
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.now();
    }

    // Parse numeric values that might come as strings or numbers
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // Parse ID from various formats to string
    String parseId(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is int) return value.toString();
      return value.toString();
    }

    // Get passenger name from nested passenger object if available
    String getPassengerName(dynamic passengerData) {
      if (passengerData is Map && passengerData.containsKey('name')) {
        return passengerData['name'] ?? 'Unknown';
      }
      return 'Unknown';
    }

    return DriverRideRequest(
      id: parseId(map['id'] ?? idParam),
      passengerId: parseId(map['passengerId']),
      passengerName: getPassengerName(map['passenger']) ?? (map['passengerName'] ?? 'Unknown'),
      pickupLat: parseDouble(map['pickupLatitude'] ?? map['pickupLat']),
      pickupLng: parseDouble(map['pickupLongitude'] ?? map['pickupLng']),
      dropoffLat: parseDouble(map['dropoffLatitude'] ?? map['dropoffLat']),
      dropoffLng: parseDouble(map['dropoffLongitude'] ?? map['dropoffLng']),
      pickupAddress: map['pickupAddress'] ?? '',
      dropoffAddress: map['dropoffAddress'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: parseDate(map['createdAt']),
      estimatedTime: (map['estimatedTime'] as num?)?.toInt() ?? 0,
      estimatedDistance: parseDouble(map['estimatedDistance']),
      estimatedFare: parseDouble(map['estimatedFare']),
      passengerPhone: map['passengerPhone'],
    );
  }

  DriverRideRequest copyWith({
    String? id,
    String? passengerId,
    String? passengerName,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
    String? status,
    DateTime? createdAt,
    int? estimatedTime,
    double? estimatedDistance,
    double? estimatedFare,
    String? passengerPhone,
  }) {
    return DriverRideRequest(
      id: id ?? this.id,
      passengerId: passengerId ?? this.passengerId,
      passengerName: passengerName ?? this.passengerName,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      estimatedFare: estimatedFare ?? this.estimatedFare,
      passengerPhone: passengerPhone ?? this.passengerPhone,
    );
  }
}

class DriverRequestService {
  static const String _baseUrl = '/ride-share';

  /// Get pending ride requests for a driver
  /// Note: For real-time updates, use WebSocket instead of polling
  static Future<List<DriverRideRequest>> getIncomingRequests() async {
    try {
      // Get auth token
      final token = await _getAuthToken();
      print('[DriverRequest] Token: ${token?.substring(0, 20)}...');
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final url = ApiConfig.endpoint('$_baseUrl/pending-rides');
      print('[DriverRequest] GET $url');
      
      final response = await http.get(url, headers: headers);
      print('[DriverRequest] Response status: ${response.statusCode}');
      print('[DriverRequest] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final requests = decoded is List
            ? decoded.cast<Map<String, dynamic>>()
            : (decoded['requests'] is List
                ? (decoded['requests'] as List)
                    .cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[]);

        print('[DriverRequest] Found ${requests.length} requests');

        // Sort by most recent first
        requests.sort(
          (a, b) {
            final dateA = DateTime.tryParse(a['createdAt'] ?? '');
            final dateB = DateTime.tryParse(b['createdAt'] ?? '');
            if (dateA != null && dateB != null) {
              return dateB.compareTo(dateA);
            }
            return 0;
          },
        );

        final result = requests
            .map((r) =>
                DriverRideRequest.fromMap(Map<String, dynamic>.from(r), r['id']))
            .toList();
        
        print('[DriverRequest] Returning ${result.length} ride requests');
        return result;
      } else {
        print('[DriverRequest] ❌ Request failed with status ${response.statusCode}');
      }
      return [];
    } catch (e) {
      print('[DriverRequest] ❌ Error getting incoming requests: $e');
      return [];
    }
  }

  /// Get a single ride request details
  static Future<DriverRideRequest?> getRideRequest(String rideId) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded is Map ? decoded : decoded['ride'];
        return DriverRideRequest.fromMap(
          Map<String, dynamic>.from(data),
          rideId,
        );
      }
      return null;
    } catch (e) {
      print('Error getting ride request: $e');
      return null;
    }
  }

  /// Accept a ride request as a driver
  static Future<void> acceptRideRequest({
    required String rideId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String? driverAvatar,
    int? vehicleId,
  }) async {
    try {
      final body = <String, dynamic>{
        'vehicleId': vehicleId,
      };
      
      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/accept'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to accept ride');
      }
    } catch (e) {
      print('Error accepting ride request: $e');
      rethrow;
    }
  }

  /// Reject a ride request
  static Future<void> rejectRideRequest(String rideId) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/reject'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to reject ride');
      }
    } catch (e) {
      print('Error rejecting ride request: $e');
      rethrow;
    }
  }

  /// Update ride status (arrived, in_progress, completed)
  static Future<void> updateRideStatus({
    required String rideId,
    required String status,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final body = <String, dynamic>{'status': status};
      if (additionalData != null) {
        body.addAll(additionalData);
      }

      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/status'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to update ride status');
      }
    } catch (e) {
      print('Error updating ride status: $e');
      rethrow;
    }
  }

  /// Get driver's active rides
  static Future<List<DriverRideRequest>> getActiveRides(
    String driverId,
  ) async {
    try {
      final response = await http.get(
        ApiConfig.endpoint('$_baseUrl/drivers/$driverId/active-rides'),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final rides = decoded is List
            ? decoded.cast<Map<String, dynamic>>()
            : (decoded['rides'] is List
                ? (decoded['rides'] as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[]);

        // Sort by created time (oldest first)
        rides.sort(
          (a, b) {
            final dateA = DateTime.tryParse(a['createdAt'] ?? '');
            final dateB = DateTime.tryParse(b['createdAt'] ?? '');
            if (dateA != null && dateB != null) {
              return dateA.compareTo(dateB);
            }
            return 0;
          },
        );

        return rides
            .map((r) =>
                DriverRideRequest.fromMap(Map<String, dynamic>.from(r), r['id'] ?? ''))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error getting active rides: $e');
      return [];
    }
  }

  /// Complete a ride and calculate final fare
  static Future<void> completeRide({
    required String rideId,
    required double actualDistance,
    required int actualTime,
    required double finalFare,
  }) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/complete'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'actualDistance': actualDistance,
          'actualTime': actualTime,
          'finalFare': finalFare,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to complete ride');
      }
    } catch (e) {
      print('Error completing ride: $e');
      rethrow;
    }
  }

  /// Cancel a ride request
  static Future<void> cancelRide({
    required String rideId,
    required String reason,
  }) async {
    try {
      final response = await http.patch(
        ApiConfig.endpoint('$_baseUrl/rides/$rideId/cancel'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reason': reason,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to cancel ride');
      }
    } catch (e) {
      print('Error cancelling ride: $e');
      rethrow;
    }
  }

  /// Get auth token - tries Firebase first, then falls back to SharedPreferences
  static Future<String?> _getAuthToken() async {
    try {
      // Try to get fresh Firebase ID token if user is logged in
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          final freshToken = await firebaseUser.getIdToken();
          if (freshToken != null && freshToken.isNotEmpty) {
            print('[DriverRequest] Using fresh Firebase ID token');
            return freshToken;
          }
        } catch (e) {
          print('[DriverRequest] Error getting fresh Firebase token: $e');
        }
      }

      // Fallback to SharedPreferences if Firebase token not available
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('jwt_token') ??
          prefs.getString('token') ??
          prefs.getString('jwt');
      
      if (storedToken != null) {
        print('[DriverRequest] Using stored token from SharedPreferences');
        return storedToken;
      }

      print('[DriverRequest] No authentication token available');
      return null;
    } catch (e) {
      print('Error reading auth token: $e');
      return null;
    }
  }
}
