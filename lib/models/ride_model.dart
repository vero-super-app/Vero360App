class VehicleClass {
  static const String economy = 'ECONOMY';
  static const String comfort = 'COMFORT';
  static const String premium = 'PREMIUM';
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
    return Vehicle(
      id: json['id'] as int,
      driverId: json['driverId'] as int,
      vehicleClass: json['vehicleClass'] as String,
      make: json['make'] as String,
      model: json['model'] as String,
      year: json['year'] as int,
      licensePlate: json['licensePlate'] as String,
      color: json['color'] as String?,
      seats: json['seats'] as int,
      isAvailable: json['isAvailable'] as bool,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalRides: json['totalRides'] as int? ?? 0,
      driver: json['driver'] != null
          ? DriverInfo.fromJson(json['driver'] as Map<String, dynamic>)
          : null,
      distanceFromUser: (json['distanceFromUser'] as num?)?.toDouble(),
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

  DriverInfo({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.phone,
  });

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    return DriverInfo(
      id: json['id'] as int,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      phone: json['phone'] as String?,
    );
  }

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
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
    return Ride(
      id: json['id'] as int,
      passengerId: json['passengerId'] as int,
      driverId: json['driverId'] as int?,
      vehicleId: json['vehicleId'] as int?,
      pickupLatitude: (json['pickupLatitude'] as num).toDouble(),
      pickupLongitude: (json['pickupLongitude'] as num).toDouble(),
      pickupAddress: json['pickupAddress'] as String?,
      dropoffLatitude: (json['dropoffLatitude'] as num).toDouble(),
      dropoffLongitude: (json['dropoffLongitude'] as num).toDouble(),
      dropoffAddress: json['dropoffAddress'] as String?,
      estimatedDistance: (json['estimatedDistance'] as num).toDouble(),
      actualDistance: (json['actualDistance'] as num?)?.toDouble(),
      estimatedFare: (json['estimatedFare'] as num).toDouble(),
      actualFare: (json['actualFare'] as num?)?.toDouble(),
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
      driver: json['driver'] != null && json['driver'] is Map
          ? DriverInfo.fromJson(json['driver'] as Map<String, dynamic>)
          : null,
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

  String get fareDisplay => '\MK${estimatedFare.toStringAsFixed(2)}';
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
