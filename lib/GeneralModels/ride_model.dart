class VehicleClass {
  static const String bike = 'BIKE';
  static const String standard = 'STANDARD';
  static const String executive = 'EXECUTIVE';
  static const String business = 'BUSINESS';
}

class RideStatus {
  static const String requested = 'REQUESTED';
  static const String accepted = 'ACCEPTED';
  static const String driverArrived = 'DRIVER_ARRIVED';
  static const String inProgress = 'IN_PROGRESS';
  static const String completed = 'COMPLETED';
  static const String cancelled = 'CANCELLED';
}

class Vehicle {
  final int id;
  final int driverId;
  final String vehicleClass;
  final String make;
  final String model;
  final int year;
  final String licensePlate;
  final String? color;
  final int seats;
  final bool isAvailable;
  final double? latitude;
  final double? longitude;
  final double rating;
  final int totalRides;
  final DriverInfo? driver;
  final double? distanceFromUser;

  Vehicle({
    required this.id,
    required this.driverId,
    required this.vehicleClass,
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    this.color,
    required this.seats,
    required this.isAvailable,
    this.latitude,
    this.longitude,
    required this.rating,
    required this.totalRides,
    this.driver,
    this.distanceFromUser,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse doubles
    double _parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int _parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    bool _parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    return Vehicle(
      id: _parseInt(json['id']),
      driverId: _parseInt(json['driverId']),
      vehicleClass: json['vehicleClass'] as String? ?? json['taxiClass'] as String? ?? 'STANDARD',
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      year: _parseInt(json['year']),
      licensePlate: json['licensePlate'] as String? ?? '',
      color: json['color'] as String?,
      seats: _parseInt(json['seats']),
      isAvailable: _parseBool(json['isAvailable']),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      rating: _parseDouble(json['rating']),
      totalRides: _parseInt(json['totalRides']),
      driver: json['driver'] != null && json['driver'] is Map
          ? DriverInfo.fromJson(json['driver'] as Map<String, dynamic>)
          : null,
      distanceFromUser: _parseDouble(json['distanceFromUser']),
    );
  }

  String get displayName => '$make $model';
  String get vehicleInfo => '$year • $seats seats';

  Map<String, dynamic> toJson() => {
        'id': id,
        'driverId': driverId,
        'vehicleClass': vehicleClass,
        'make': make,
        'model': model,
        'year': year,
        'licensePlate': licensePlate,
        'color': color,
        'seats': seats,
        'isAvailable': isAvailable,
        'latitude': latitude,
        'longitude': longitude,
        'rating': rating,
        'totalRides': totalRides,
        'driver': driver?.toJson(),
        'distanceFromUser': distanceFromUser,
      };
}

class DriverInfo {
  final int id;
  final String firstName;
  final String lastName;
  final String? phone;
  final double rating;
  final int completedRides;
  final String? vehicleType;
  final String? vehiclePlate;
  final double? latitude;
  final double? longitude;
  final String avatar;

  DriverInfo({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.rating,
    required this.completedRides,
    this.vehicleType,
    this.vehiclePlate,
    this.latitude,
    this.longitude,
    this.avatar = '',
  });

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    // Handle nested user object from backend
    var userData = json;
    if (json.containsKey('user') && json['user'] is Map) {
      userData = (json['user'] as Map<String, dynamic>)..addAll(json);
    }
    
    // Helper to safely parse numbers
    double _parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int _parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }
    
    // Handle both firstName/lastName and name field
    String firstName = userData['firstName'] as String? ?? '';
    String lastName = userData['lastName'] as String? ?? '';
    
    if (firstName.isEmpty && lastName.isEmpty && userData.containsKey('name')) {
      // If firstName/lastName are missing, try to split "name" field
      final fullName = userData['name'] as String? ?? '';
      final parts = fullName.split(' ');
      firstName = parts.isNotEmpty ? parts[0] : 'Driver';
      lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    
    return DriverInfo(
      id: _parseInt(json['id']),
      firstName: firstName.isEmpty ? 'Driver' : firstName,
      lastName: lastName,
      phone: userData['phone'] as String?,
      rating: _parseDouble(userData['rating']),
      completedRides: _parseInt(userData['completedRides']),
      vehicleType: json['vehicleType'] as String? ?? userData['vehicleClass'] as String?,
      vehiclePlate: json['vehiclePlate'] as String? ?? json['licensePlate'] as String?,
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      avatar: userData['avatar'] as String? ?? '',
    );
  }

  String get fullName => '$firstName $lastName';
  String get name => fullName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'rating': rating,
        'completedRides': completedRides,
        'vehicleType': vehicleType,
        'vehiclePlate': vehiclePlate,
        'latitude': latitude,
        'longitude': longitude,
        'avatar': avatar,
      };
}

class Ride {
  final int id;
  final int passengerId;
  final int? driverId;
  final int? vehicleId;
  final double pickupLatitude;
  final double pickupLongitude;
  final String? pickupAddress;
  final double dropoffLatitude;
  final double dropoffLongitude;
  final String? dropoffAddress;
  final double estimatedDistance;
  final double? actualDistance;
  final double estimatedFare;
  final double? actualFare;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? cancellationReason;
  final String? passengerNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Vehicle? vehicle;
  final DriverInfo? driver;

  Ride({
    required this.id,
    required this.passengerId,
    this.driverId,
    this.vehicleId,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.pickupAddress,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    this.dropoffAddress,
    required this.estimatedDistance,
    this.actualDistance,
    required this.estimatedFare,
    this.actualFare,
    required this.status,
    this.startTime,
    this.endTime,
    this.cancellationReason,
    this.passengerNotes,
    required this.createdAt,
    required this.updatedAt,
    this.vehicle,
    this.driver,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse num/string to double
    double _parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int? _parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    return Ride(
      id: _parseInt(json['id']) ?? 0,
      passengerId: _parseInt(json['passengerId']) ?? 0,
      driverId: _parseInt(json['driverId']),
      vehicleId: _parseInt(json['vehicleId']),
      pickupLatitude: _parseDouble(json['pickupLatitude']),
      pickupLongitude: _parseDouble(json['pickupLongitude']),
      pickupAddress: json['pickupAddress'] as String?,
      dropoffLatitude: _parseDouble(json['dropoffLatitude']),
      dropoffLongitude: _parseDouble(json['dropoffLongitude']),
      dropoffAddress: json['dropoffAddress'] as String?,
      estimatedDistance: _parseDouble(json['estimatedDistance']),
      actualDistance: json['actualDistance'] != null
          ? _parseDouble(json['actualDistance'])
          : null,
      estimatedFare: _parseDouble(json['estimatedFare']),
      actualFare: json['actualFare'] != null
          ? _parseDouble(json['actualFare'])
          : null,
      status: json['status'] as String,
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      cancellationReason: json['cancellationReason'] as String?,
      passengerNotes: json['passengerNotes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      vehicle: json['vehicle'] != null
          ? Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>)
          : null,
      driver: () {
        // Try to get driver from direct field first
        if (json['driver'] != null && json['driver'] is Map) {
          return DriverInfo.fromJson(json['driver'] as Map<String, dynamic>);
        }
        // Fallback: try to get driver from taxi object
        if (json['taxi'] != null && json['taxi'] is Map) {
          final taxi = json['taxi'] as Map<String, dynamic>;
          if (taxi['driver'] != null && taxi['driver'] is Map) {
            return DriverInfo.fromJson(taxi['driver'] as Map<String, dynamic>);
          }
        }
        return null;
      }(),
    );
  }

  bool get isActive => [
        RideStatus.requested,
        RideStatus.accepted,
        RideStatus.driverArrived,
        RideStatus.inProgress,
      ].contains(status);

  bool get isCompleted => status == RideStatus.completed;
  bool get isCancelled => status == RideStatus.cancelled;

  String get fareDisplay => 'MK${estimatedFare.toStringAsFixed(2)}';
  String get distanceDisplay => '${estimatedDistance.toStringAsFixed(1)} km';

  Map<String, dynamic> toJson() => {
        'id': id,
        'passengerId': passengerId,
        'driverId': driverId,
        'vehicleId': vehicleId,
        'pickupLatitude': pickupLatitude,
        'pickupLongitude': pickupLongitude,
        'pickupAddress': pickupAddress,
        'dropoffLatitude': dropoffLatitude,
        'dropoffLongitude': dropoffLongitude,
        'dropoffAddress': dropoffAddress,
        'estimatedDistance': estimatedDistance,
        'actualDistance': actualDistance,
        'estimatedFare': estimatedFare,
        'actualFare': actualFare,
        'status': status,
        'startTime': startTime?.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'cancellationReason': cancellationReason,
        'passengerNotes': passengerNotes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'vehicle': vehicle?.toJson(),
      };
}

class FareEstimate {
  final double estimatedFare;
  final double estimatedDistance;
  final FareBreakdown breakdown;

  FareEstimate({
    required this.estimatedFare,
    required this.estimatedDistance,
    required this.breakdown,
  });

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    return FareEstimate(
      estimatedFare: (json['estimatedFare'] as num).toDouble(),
      estimatedDistance: (json['estimatedDistance'] as num).toDouble(),
      breakdown: FareBreakdown.fromJson(
          json['breakdown'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'estimatedFare': estimatedFare,
        'estimatedDistance': estimatedDistance,
        'breakdown': breakdown.toJson(),
      };
}

class FareBreakdown {
  final double baseFare;
  final double perKmFare;
  final double totalFare;
  final double distance;

  FareBreakdown({
    required this.baseFare,
    required this.perKmFare,
    required this.totalFare,
    required this.distance,
  });

  factory FareBreakdown.fromJson(Map<String, dynamic> json) {
    return FareBreakdown(
      baseFare: (json['baseFare'] as num).toDouble(),
      perKmFare: (json['perKmFare'] as num).toDouble(),
      totalFare: (json['totalFare'] as num).toDouble(),
      distance: (json['distance'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'baseFare': baseFare,
        'perKmFare': perKmFare,
        'totalFare': totalFare,
        'distance': distance,
      };
}
