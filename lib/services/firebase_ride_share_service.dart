import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';

/// Models for Ride Share
class RideRequest {
  final String id;
  final String passengerId;
  final String? driverId;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String pickupAddress;
  final String dropoffAddress;
  final String status; // pending, accepted, in_progress, completed, cancelled
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final int estimatedTime;
  final double estimatedDistance;
  final double estimatedFare;
  final double? actualFare;
  final int? rating;
  final String? feedback;

  RideRequest({
    required this.id,
    required this.passengerId,
    this.driverId,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
    required this.estimatedTime,
    required this.estimatedDistance,
    required this.estimatedFare,
    this.actualFare,
    this.rating,
    this.feedback,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'passengerId': passengerId,
      'driverId': driverId,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'acceptedAt': acceptedAt?.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'estimatedTime': estimatedTime,
      'estimatedDistance': estimatedDistance,
      'estimatedFare': estimatedFare,
      'actualFare': actualFare,
      'rating': rating,
      'feedback': feedback,
    };
  }

  factory RideRequest.fromMap(Map<dynamic, dynamic> map, String id) {
    return RideRequest(
      id: id,
      passengerId: map['passengerId'] ?? '',
      driverId: map['driverId'],
      pickupLat: (map['pickupLat'] as num?)?.toDouble() ?? 0.0,
      pickupLng: (map['pickupLng'] as num?)?.toDouble() ?? 0.0,
      dropoffLat: (map['dropoffLat'] as num?)?.toDouble() ?? 0.0,
      dropoffLng: (map['dropoffLng'] as num?)?.toDouble() ?? 0.0,
      pickupAddress: map['pickupAddress'] ?? '',
      dropoffAddress: map['dropoffAddress'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      acceptedAt: map['acceptedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['acceptedAt'])
          : null,
      completedAt: map['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'])
          : null,
      estimatedTime: map['estimatedTime'] ?? 0,
      estimatedDistance: (map['estimatedDistance'] as num?)?.toDouble() ?? 0.0,
      estimatedFare: (map['estimatedFare'] as num?)?.toDouble() ?? 0.0,
      actualFare: map['actualFare'] != null
          ? (map['actualFare'] as num?)?.toDouble()
          : null,
      rating: map['rating'],
      feedback: map['feedback'],
    );
  }
}

class Driver {
  final String id;
  final String name;
  final String avatar;
  final double latitude;
  final double longitude;
  final String status; // online, offline, on_ride
  final double rating;
  final int completedRides;
  final String vehicleType; // car, bike, etc
  final String vehiclePlate;
  final DateTime lastUpdated;
  final bool isActive;

  Driver({
    required this.id,
    required this.name,
    required this.avatar,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.rating,
    required this.completedRides,
    required this.vehicleType,
    required this.vehiclePlate,
    required this.lastUpdated,
    required this.isActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
      'rating': rating,
      'completedRides': completedRides,
      'vehicleType': vehicleType,
      'vehiclePlate': vehiclePlate,
      'lastUpdated': lastUpdated.millisecondsSinceEpoch,
      'isActive': isActive,
    };
  }

  factory Driver.fromMap(Map<dynamic, dynamic> map, String id) {
    return Driver(
      id: id,
      name: map['name'] ?? '',
      avatar: map['avatar'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'offline',
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      completedRides: map['completedRides'] ?? 0,
      vehicleType: map['vehicleType'] ?? '',
      vehiclePlate: map['vehiclePlate'] ?? '',
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] ?? 0),
      isActive: map['isActive'] ?? false,
    );
  }
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String avatar;
  final double rating;
  final String userType; // passenger, driver, both
  final bool isVerified;
  final DateTime createdAt;
  final DateTime lastUpdated;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.avatar,
    required this.rating,
    required this.userType,
    required this.isVerified,
    required this.createdAt,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'avatar': avatar,
      'rating': rating,
      'userType': userType,
      'isVerified': isVerified,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastUpdated': lastUpdated.millisecondsSinceEpoch,
    };
  }

  factory AppUser.fromMap(Map<dynamic, dynamic> map, String id) {
    return AppUser(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      avatar: map['avatar'] ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      userType: map['userType'] ?? 'passenger',
      isVerified: map['isVerified'] ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] ?? 0),
    );
  }
}

class FirebaseRideShareService {
  static final FirebaseDatabase _realtimeDb = FirebaseDatabase.instance;

  // Database references
  static final _rideRequestsRef = _realtimeDb.ref().child('ride_requests');
  static final _activeDriversRef = _realtimeDb.ref().child('active_drivers');
  static final _driversRef = _realtimeDb.ref().child('drivers');
  static final _usersRef = _realtimeDb.ref().child('users');

  // ============== RIDE REQUESTS ==============

  /// Create a new ride request (passenger initiates)
  static Future<String> createRideRequest({
    required String passengerId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required String pickupAddress,
    required String dropoffAddress,
    required int estimatedTime,
    required double estimatedDistance,
    required double estimatedFare,
  }) async {
    try {
      final rideId = _rideRequestsRef.push().key ?? '';
      final rideRequest = RideRequest(
        id: rideId,
        passengerId: passengerId,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        status: 'pending',
        createdAt: DateTime.now(),
        estimatedTime: estimatedTime,
        estimatedDistance: estimatedDistance,
        estimatedFare: estimatedFare,
      );

      await _rideRequestsRef.child(rideId).set(rideRequest.toMap());
      return rideId;
    } catch (e) {
      print('Error creating ride request: $e');
      rethrow;
    }
  }

  /// Stream of all pending ride requests (for drivers)
  static Stream<List<RideRequest>> getPendingRideRequestsStream() {
    return _rideRequestsRef
        .orderByChild('status')
        .equalTo('pending')
        .onValue
        .map((event) {
      final map = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      final List<RideRequest> requests = [];

      map.forEach((key, value) {
        try {
          final request = RideRequest.fromMap(value, key);
          requests.add(request);
        } catch (e) {
          print('Error parsing ride request: $e');
        }
      });

      return requests;
    });
  }

  /// Stream of ride requests for a specific passenger
  static Stream<List<RideRequest>> getPassengerRideRequestsStream(
    String passengerId,
  ) {
    return _rideRequestsRef
        .orderByChild('passengerId')
        .equalTo(passengerId)
        .onValue
        .map((event) {
      final map = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      final List<RideRequest> requests = [];

      map.forEach((key, value) {
        try {
          final request = RideRequest.fromMap(value, key);
          requests.add(request);
        } catch (e) {
          print('Error parsing ride request: $e');
        }
      });

      // Sort by creation time, newest first
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  /// Stream of active ride requests for a specific driver
  static Stream<List<RideRequest>> getDriverRideRequestsStream(
      String driverId) {
    return _rideRequestsRef
        .orderByChild('driverId')
        .equalTo(driverId)
        .onValue
        .map((event) {
      final map = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      final List<RideRequest> requests = [];

      map.forEach((key, value) {
        try {
          final request = RideRequest.fromMap(value, key);
          // Filter to only active rides
          if (['pending', 'accepted', 'in_progress'].contains(request.status)) {
            requests.add(request);
          }
        } catch (e) {
          print('Error parsing ride request: $e');
        }
      });

      return requests;
    });
  }

  /// Get a specific ride request
  static Future<RideRequest?> getRideRequest(String rideId) async {
    try {
      final snapshot = await _rideRequestsRef.child(rideId).get();
      if (!snapshot.exists) return null;

      return RideRequest.fromMap(
          snapshot.value as Map<dynamic, dynamic>, rideId);
    } catch (e) {
      print('Error getting ride request: $e');
      return null;
    }
  }

  /// Stream a specific ride request
  static Stream<RideRequest?> getRideRequestStream(String rideId) {
    return _rideRequestsRef.child(rideId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      try {
        return RideRequest.fromMap(
          event.snapshot.value as Map<dynamic, dynamic>,
          rideId,
        );
      } catch (e) {
        print('Error parsing ride request: $e');
        return null;
      }
    });
  }

  /// Accept a ride request (driver accepts)
  static Future<void> acceptRideRequest({
    required String rideId,
    required String driverId,
  }) async {
    try {
      await _rideRequestsRef.child(rideId).update({
        'driverId': driverId,
        'status': 'accepted',
        'acceptedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Update driver status
      await updateDriverStatus(driverId, 'on_ride');
    } catch (e) {
      print('Error accepting ride request: $e');
      rethrow;
    }
  }

  /// Update ride request status
  static Future<void> updateRideRequestStatus(
    String rideId,
    String newStatus,
  ) async {
    try {
      final updates = <String, dynamic>{
        'status': newStatus,
      };

      if (newStatus == 'completed') {
        updates['completedAt'] = DateTime.now().millisecondsSinceEpoch;
      }

      await _rideRequestsRef.child(rideId).update(updates);

      // If ride is completed, update driver status back to online
      if (newStatus == 'completed') {
        final snapshot = await _rideRequestsRef.child(rideId).get();
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          final driverId = data['driverId'];
          if (driverId != null) {
            await updateDriverStatus(driverId, 'online');
          }
        }
      }
    } catch (e) {
      print('Error updating ride request status: $e');
      rethrow;
    }
  }

  /// Complete a ride and add rating/feedback
  static Future<void> completeRideWithRating({
    required String rideId,
    required double actualFare,
    required int rating,
    required String feedback,
  }) async {
    try {
      await _rideRequestsRef.child(rideId).update({
        'status': 'completed',
        'completedAt': DateTime.now().millisecondsSinceEpoch,
        'actualFare': actualFare,
        'rating': rating,
        'feedback': feedback,
      });
    } catch (e) {
      print('Error completing ride with rating: $e');
      rethrow;
    }
  }

  /// Cancel a ride request
  static Future<void> cancelRideRequest(String rideId) async {
    try {
      final snapshot = await _rideRequestsRef.child(rideId).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final driverId = data['driverId'];

        await _rideRequestsRef.child(rideId).update({
          'status': 'cancelled',
        });

        // If driver was assigned, update their status back to online
        if (driverId != null) {
          await updateDriverStatus(driverId, 'online');
        }
      }
    } catch (e) {
      print('Error cancelling ride request: $e');
      rethrow;
    }
  }

  // ============== ACTIVE DRIVERS ==============

  /// Update driver location (real-time GPS tracking)
  static Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _activeDriversRef.child(driverId).set({
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      print('Error updating driver location: $e');
      rethrow;
    }
  }

  /// Stream all active drivers locations
  static Stream<List<Driver>> getActiveDriversStream() {
    return _activeDriversRef.onValue.map((event) {
      final map = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      final List<Driver> drivers = [];

      map.forEach((key, value) {
        try {
          // Get full driver data from drivers collection
          _driversRef.child(key).get().then((snapshot) {
            if (snapshot.exists) {
              final driver = Driver.fromMap(snapshot.value as Map<dynamic, dynamic>, key);
              drivers.add(driver);
            }
          });
        } catch (e) {
          print('Error parsing active driver: $e');
        }
      });

      return drivers;
    });
  }

  /// Stream active drivers near a location
  static Stream<List<Driver>> getNearbyActiveDriversStream({
    required double latitude,
    required double longitude,
    double radiusInKm = 5.0,
  }) {
    // Note: Firebase Realtime Database has limitations for geo-queries
    // This streams all active drivers; filter on client side for distance
    return _activeDriversRef.onValue.map((event) {
      final map = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      final List<Driver> nearbyDrivers = [];

      map.forEach((key, value) async {
        try {
          final driverSnapshot = await _driversRef.child(key).get();
          if (driverSnapshot.exists) {
            final driver = Driver.fromMap(driverSnapshot.value as Map<dynamic, dynamic>, key);

            // Calculate distance (simple Haversine approximation)
            final distance = _calculateDistance(
              latitude,
              longitude,
              driver.latitude,
              driver.longitude,
            );

            if (distance <= radiusInKm) {
              nearbyDrivers.add(driver);
            }
          }
        } catch (e) {
          print('Error parsing nearby driver: $e');
        }
      });

      return nearbyDrivers;
    });
  }

  /// Get online drivers count
  static Future<int> getOnlineDriversCount() async {
    try {
      final snapshot = await _activeDriversRef.get();
      return snapshot.children.length;
    } catch (e) {
      print('Error getting online drivers count: $e');
      return 0;
    }
  }

  // ============== DRIVERS ==============

  /// Create or update driver profile
  static Future<void> updateDriverProfile({
    required String driverId,
    required String name,
    required String avatar,
    required String vehicleType,
    required String vehiclePlate,
  }) async {
    try {
      await _driversRef.child(driverId).update({
        'name': name,
        'avatar': avatar,
        'vehicleType': vehicleType,
        'vehiclePlate': vehiclePlate,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('Error updating driver profile: $e');
      rethrow;
    }
  }

  /// Update driver status (online, offline, on_ride)
  static Future<void> updateDriverStatus(String driverId, String status) async {
    try {
      await _driversRef.child(driverId).update({
        'status': status,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // If driver is going offline, remove from active drivers
      if (status == 'offline') {
        await _activeDriversRef.child(driverId).remove();
      }
    } catch (e) {
      print('Error updating driver status: $e');
      rethrow;
    }
  }

  /// Get driver profile
  static Future<Driver?> getDriverProfile(String driverId) async {
    try {
      final snapshot = await _driversRef.child(driverId).get();
      if (!snapshot.exists) return null;

      return Driver.fromMap(snapshot.value as Map<dynamic, dynamic>, driverId);
    } catch (e) {
      print('Error getting driver profile: $e');
      return null;
    }
  }

  /// Stream driver profile
  static Stream<Driver?> getDriverProfileStream(String driverId) {
    return _driversRef.child(driverId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      try {
        return Driver.fromMap(
          event.snapshot.value as Map<dynamic, dynamic>,
          driverId,
        );
      } catch (e) {
        print('Error parsing driver profile: $e');
        return null;
      }
    });
  }

  /// Update driver rating (after ride completion)
  static Future<void> updateDriverRating(
    String driverId,
    double newRating,
  ) async {
    try {
      final snapshot = await _driversRef.child(driverId).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final currentRating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final completedRides = (data['completedRides'] ?? 0) as int;

        // Calculate average rating
        final averageRating =
            (currentRating * completedRides + newRating) / (completedRides + 1);

        await _driversRef.child(driverId).update({
          'rating': averageRating,
          'completedRides': completedRides + 1,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      print('Error updating driver rating: $e');
      rethrow;
    }
  }

  // ============== USERS ==============

  /// Create or update user profile
  static Future<void> createOrUpdateUser({
    required String userId,
    required String name,
    required String email,
    required String phone,
    String avatar = '',
    String userType = 'passenger',
  }) async {
    try {
      await _usersRef.child(userId).set({
        'id': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'avatar': avatar,
        'rating': 0.0,
        'userType': userType,
        'isVerified': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('Error creating/updating user: $e');
      rethrow;
    }
  }

  /// Get user profile
  static Future<AppUser?> getUserProfile(String userId) async {
    try {
      final snapshot = await _usersRef.child(userId).get();
      if (!snapshot.exists) return null;

      return AppUser.fromMap(snapshot.value as Map<dynamic, dynamic>, userId);
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  /// Stream user profile
  static Stream<AppUser?> getUserProfileStream(String userId) {
    return _usersRef.child(userId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      try {
        return AppUser.fromMap(
          event.snapshot.value as Map<dynamic, dynamic>,
          userId,
        );
      } catch (e) {
        print('Error parsing user profile: $e');
        return null;
      }
    });
  }

  /// Update user rating
  static Future<void> updateUserRating(
    String userId,
    double rating,
  ) async {
    try {
      final snapshot = await _usersRef.child(userId).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final currentRating = (data['rating'] as num?)?.toDouble() ?? 0.0;

        // Simple average (in production, track rating count)
        final newRating = (currentRating + rating) / 2;

        await _usersRef.child(userId).update({
          'rating': newRating,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      print('Error updating user rating: $e');
      rethrow;
    }
  }

  // ============== UTILITY FUNCTIONS ==============

  /// Calculate distance between two coordinates (in km) using Haversine formula
  static double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusKm = 6371;
    final double dLat = _toRadian(lat2 - lat1);
    final double dLng = _toRadian(lng2 - lng1);

    final double a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_toRadian(lat1)) *
            cos(_toRadian(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2));

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadian(double degree) {
    return degree * (pi / 180);
  }
}
