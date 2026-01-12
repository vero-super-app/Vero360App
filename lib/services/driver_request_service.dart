import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  factory DriverRideRequest.fromMap(Map<dynamic, dynamic> map, String id) {
    return DriverRideRequest(
      id: id,
      passengerId: map['passengerId'] ?? '',
      passengerName: map['passengerName'] ?? 'Unknown',
      pickupLat: (map['pickupLat'] as num?)?.toDouble() ?? 0.0,
      pickupLng: (map['pickupLng'] as num?)?.toDouble() ?? 0.0,
      dropoffLat: (map['dropoffLat'] as num?)?.toDouble() ?? 0.0,
      dropoffLng: (map['dropoffLng'] as num?)?.toDouble() ?? 0.0,
      pickupAddress: map['pickupAddress'] ?? '',
      dropoffAddress: map['dropoffAddress'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      estimatedTime: map['estimatedTime'] ?? 0,
      estimatedDistance: (map['estimatedDistance'] as num?)?.toDouble() ?? 0.0,
      estimatedFare: (map['estimatedFare'] as num?)?.toDouble() ?? 0.0,
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
  static final FirebaseDatabase _db = FirebaseDatabase.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Listen to incoming ride requests for a specific driver
  /// Only returns pending requests
  static Stream<List<DriverRideRequest>> getIncomingRequestsStream(
    String driverId,
  ) {
    return _db
        .ref()
        .child('ride_requests')
        .orderByChild('status')
        .equalTo('pending')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) {
        return [];
      }

      final requests = <DriverRideRequest>[];
      final data = event.snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          try {
            final request = DriverRideRequest.fromMap(value, key);
            // Only include requests that are still pending
            if (request.status == 'pending') {
              requests.add(request);
            }
          } catch (_) {
            // Skip malformed requests
          }
        }
      });

      // Sort by most recent first
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  /// Get a single ride request details
  static Future<DriverRideRequest?> getRideRequest(String rideId) async {
    try {
      final snapshot = await _db.ref().child('ride_requests').child(rideId).get();

      if (snapshot.exists && snapshot.value is Map<dynamic, dynamic>) {
        return DriverRideRequest.fromMap(
          snapshot.value as Map<dynamic, dynamic>,
          rideId,
        );
      }
      return null;
    } catch (e) {
      print('Error getting ride request: $e');
      return null;
    }
  }

  /// Stream for single ride request real-time updates
  static Stream<DriverRideRequest?> getRideRequestStream(String rideId) {
    return _db
        .ref()
        .child('ride_requests')
        .child(rideId)
        .onValue
        .map((event) {
      if (event.snapshot.exists && event.snapshot.value is Map<dynamic, dynamic>) {
        return DriverRideRequest.fromMap(
          event.snapshot.value as Map<dynamic, dynamic>,
          rideId,
        );
      }
      return null;
    });
  }

  /// Accept a ride request as a driver
  static Future<void> acceptRideRequest({
    required String rideId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String? driverAvatar,
  }) async {
    try {
      final now = DateTime.now();

      // Get current request status first
      final snapshot = await _db.ref().child('ride_requests').child(rideId).get();

      if (!snapshot.exists) {
        throw Exception('Ride request not found');
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      if (data['status'] != 'pending') {
        throw Exception('Ride was already accepted by another driver');
      }

      // Update the ride request with driver info
      await _db
          .ref()
          .child('ride_requests')
          .child(rideId)
          .update({
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'driverAvatar': driverAvatar ?? '',
        'status': 'accepted',
        'acceptedAt': now.millisecondsSinceEpoch,
      });

      // Add to driver's active rides
      await _db
          .ref()
          .child('drivers')
          .child(driverId)
          .child('activeRides')
          .update({
        rideId: true,
      });
    } catch (e) {
      print('Error accepting ride request: $e');
      rethrow;
    }
  }

  /// Reject a ride request
  static Future<void> rejectRideRequest(String rideId) async {
    try {
      // Just mark locally that driver rejected it
      // The request remains pending for other drivers
      await _db
          .ref()
          .child('ride_requests')
          .child(rideId)
          .child('rejectedBy')
          .child(_auth.currentUser?.uid ?? 'unknown')
          .set(true);
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
      final updateData = <String, dynamic>{'status': status};

      if (additionalData != null) {
        updateData.addAll(additionalData);
      }

      await _db
          .ref()
          .child('ride_requests')
          .child(rideId)
          .update(updateData);
    } catch (e) {
      print('Error updating ride status: $e');
      rethrow;
    }
  }

  /// Get driver's active rides
  static Stream<List<DriverRideRequest>> getActiveRidesStream(String driverId) {
    return _db
        .ref()
        .child('ride_requests')
        .orderByChild('driverId')
        .equalTo(driverId)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) {
        return [];
      }

      final rides = <DriverRideRequest>[];
      final data = event.snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          try {
            final request = DriverRideRequest.fromMap(value, key);
            // Only include non-completed rides
            if (request.status != 'completed') {
              rides.add(request);
            }
          } catch (_) {
            // Skip malformed requests
          }
        }
      });

      // Sort by accepted time (oldest first)
      rides.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return rides;
    });
  }

  /// Complete a ride and calculate final fare
  static Future<void> completeRide({
    required String rideId,
    required double actualDistance,
    required int actualTime,
    required double finalFare,
  }) async {
    try {
      final now = DateTime.now();

      await _db
          .ref()
          .child('ride_requests')
          .child(rideId)
          .update({
        'status': 'completed',
        'completedAt': now.millisecondsSinceEpoch,
        'actualDistance': actualDistance,
        'actualTime': actualTime,
        'actualFare': finalFare,
      });
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
      await _db
          .ref()
          .child('ride_requests')
          .child(rideId)
          .update({
        'status': 'cancelled',
        'cancelledAt': DateTime.now().millisecondsSinceEpoch,
        'cancelReason': reason,
      });
    } catch (e) {
      print('Error cancelling ride: $e');
      rethrow;
    }
  }
}
