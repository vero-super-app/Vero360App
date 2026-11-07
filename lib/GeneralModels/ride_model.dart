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
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    return Vehicle(
      id: parseInt(json['id']),
      driverId: parseInt(json['driverId']),
      vehicleClass: json['vehicleClass'] as String? ??
          json['taxiClass'] as String? ??
          'STANDARD',
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      year: parseInt(json['year']),
      licensePlate: json['licensePlate'] as String? ?? '',
      color: json['color'] as String?,
      seats: parseInt(json['seats']),
      isAvailable: parseBool(json['isAvailable']),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      rating: parseDouble(json['rating']),
      totalRides: parseInt(json['totalRides']),
      driver: json['driver'] != null && json['driver'] is Map
          ? DriverInfo.fromJson(json['driver'] as Map<String, dynamic>)
          : null,
      distanceFromUser: parseDouble(json['distanceFromUser']),
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
  final bool isVerified;
  final bool backgroundCheckPassed;

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
    this.isVerified = false,
    this.backgroundCheckPassed = false,
  });

  /// Ride-share trust badge: background check or verified driver flag.
  bool get isRideShareVerified => backgroundCheckPassed || isVerified;

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    // Handle nested user object from backend
    var userData = json;
    if (json.containsKey('user') && json['user'] is Map) {
      userData = Map<String, dynamic>.from(json['user'] as Map)
        ..addAll(Map<String, dynamic>.from(json));
    }

    // Helper to safely parse numbers
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic value) {
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
      id: parseInt(json['id']),
      firstName: firstName.isEmpty ? 'Driver' : firstName,
      lastName: lastName,
      phone: userData['phone'] as String?,
      rating: parseDouble(userData['rating']),
      completedRides: parseInt(userData['completedRides']),
      vehicleType:
          json['vehicleType'] as String? ?? userData['vehicleClass'] as String?,
      vehiclePlate:
          json['vehiclePlate'] as String? ?? json['licensePlate'] as String?,
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      avatar: userData['avatar'] as String? ??
          userData['profilepicture'] as String? ??
          '',
      isVerified: _driverVerified(userData, json),
      backgroundCheckPassed: _driverBackgroundChecked(userData, json),
    );
  }

  static bool _flag(dynamic v) =>
      v == true || v?.toString().trim().toLowerCase() == 'true';

  static bool _driverBackgroundChecked(
    Map<String, dynamic> userData,
    Map<String, dynamic> json,
  ) {
    return _flag(userData['backgroundCheckPassed']) ||
        _flag(json['backgroundCheckPassed']);
  }

  static bool _driverVerified(
    Map<String, dynamic> userData,
    Map<String, dynamic> json,
  ) {
    if (_flag(userData['isVerified']) ||
        _flag(userData['verified']) ||
        _flag(userData['kycVerified']) ||
        _flag(json['isVerified']) ||
        _flag(json['verified'])) {
      return true;
    }
    final status = '${userData['kycStatus'] ?? userData['verificationStatus'] ?? json['status'] ?? ''}'
        .trim()
        .toLowerCase();
    return status == 'verified' || status == 'approved';
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
        'isVerified': isVerified,
        'backgroundCheckPassed': backgroundCheckPassed,
      };
}

class TripSummary {
  final double fare;
  final double distance;
  final int durationMinutes;
  final String pickup;
  final String dropoff;
  final double platformFee;
  final double driverEarnings;
  final String paymentStatus;
  final String? counterpartyName;
  final String? vehiclePlate;
  final String? vehicleClass;

  TripSummary({
    required this.fare,
    required this.distance,
    required this.durationMinutes,
    required this.pickup,
    required this.dropoff,
    required this.platformFee,
    required this.driverEarnings,
    required this.paymentStatus,
    this.counterpartyName,
    this.vehiclePlate,
    this.vehicleClass,
  });

  factory TripSummary.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return TripSummary(
      fare: parseDouble(json['fare']),
      distance: parseDouble(json['distance']),
      durationMinutes: parseInt(json['durationMinutes']),
      pickup: json['pickup'] as String? ?? 'Pickup',
      dropoff: json['dropoff'] as String? ?? 'Dropoff',
      platformFee: parseDouble(json['platformFee']),
      driverEarnings: parseDouble(json['driverEarnings']),
      paymentStatus: json['paymentStatus'] as String? ?? 'pending',
      counterpartyName: json['counterpartyName'] as String?,
      vehiclePlate: json['vehiclePlate'] as String?,
      vehicleClass: json['vehicleClass'] as String?,
    );
  }
}

class Ride {
  final int id;
  final int passengerId;
  final int? driverId;
  final int? taxiId;
  final double pickupLatitude;
  final double pickupLongitude;
  final String? pickupAddress;
  final double dropoffLatitude;
  final double dropoffLongitude;
  final String? dropoffAddress;
  final double estimatedDistance;
  final double? actualDistance;
  final double estimatedFare;
  /// Demand/supply surge applied at create (typically 1.0–1.5). Null on older rides.
  final double? surgeMultiplier;
  final double? actualFare;
  final double? platformFee;
  final double? driverEarnings;
  /// `actual` (metered) or `estimated` when set by backend complete/cancel.
  final String? fareBasis;
  final double? cancellationFee;
  /// Passenger → driver rating (1–5).
  final int? passengerRating;
  /// Driver → passenger rating (1–5).
  final int? driverRating;
  final String? disputeReason;
  final DateTime? disputedAt;
  final String? paymentStatus;
  final String? paymentChannel;
  final String? paymentTxRef;
  final DateTime? paidAt;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? cancellationReason;
  final String? passengerNotes;
  final DateTime? pickupEarliestAt;
  final DateTime? pickupLatestAt;
  final int? maxWaitMinutes;
  final DateTime? passengerReadyAt;
  final int? driverDelayMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Vehicle? taxi;
  final DriverInfo? driver;
  final String? passengerName;
  final TripSummary? tripSummary;

  Ride({
    required this.id,
    required this.passengerId,
    this.driverId,
    this.taxiId,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.pickupAddress,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    this.dropoffAddress,
    required this.estimatedDistance,
    this.actualDistance,
    required this.estimatedFare,
    this.surgeMultiplier,
    this.actualFare,
    this.platformFee,
    this.driverEarnings,
    this.fareBasis,
    this.cancellationFee,
    this.passengerRating,
    this.driverRating,
    this.disputeReason,
    this.disputedAt,
    this.paymentStatus,
    this.paymentChannel,
    this.paymentTxRef,
    this.paidAt,
    required this.status,
    this.startTime,
    this.endTime,
    this.cancellationReason,
    this.passengerNotes,
    this.pickupEarliestAt,
    this.pickupLatestAt,
    this.maxWaitMinutes,
    this.passengerReadyAt,
    this.driverDelayMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.taxi,
    this.driver,
    this.passengerName,
    this.tripSummary,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse num/string to double
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    DateTime parseDateTime(dynamic value, {DateTime? fallback}) {
      if (value == null) return fallback ?? DateTime.now();
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return fallback ?? DateTime.now();
        }
      }
      return fallback ?? DateTime.now();
    }

    Map<String, dynamic>? extractDriverJson() {
      final directDriver = json['driver'];
      if (directDriver is Map<String, dynamic>) {
        return directDriver;
      }
      if (directDriver is Map) {
        return Map<String, dynamic>.from(directDriver);
      }

      final taxi = json['taxi'];
      if (taxi is Map && taxi['driver'] is Map) {
        return Map<String, dynamic>.from(taxi['driver'] as Map);
      }

      final vehicle = json['vehicle'];
      if (vehicle is Map && vehicle['driver'] is Map) {
        return Map<String, dynamic>.from(vehicle['driver'] as Map);
      }

      return null;
    }

    try {
      return Ride(
        id: parseInt(json['id'] ?? json['rideId']) ?? 0,
        passengerId: parseInt(json['passengerId']) ?? 0,
        driverId: parseInt(json['driverId']),
        taxiId: parseInt(json['taxiId']) ?? parseInt(json['vehicleId']),
        pickupLatitude: parseDouble(json['pickupLatitude']),
        pickupLongitude: parseDouble(json['pickupLongitude']),
        pickupAddress: json['pickupAddress'] as String?,
        dropoffLatitude: parseDouble(json['dropoffLatitude']),
        dropoffLongitude: parseDouble(json['dropoffLongitude']),
        dropoffAddress: json['dropoffAddress'] as String?,
        estimatedDistance: parseDouble(json['estimatedDistance']),
        actualDistance: json['actualDistance'] != null
            ? parseDouble(json['actualDistance'])
            : null,
        estimatedFare: parseDouble(json['estimatedFare']),
        surgeMultiplier: json['surgeMultiplier'] != null
            ? parseDouble(json['surgeMultiplier'])
            : null,
        actualFare:
            json['actualFare'] != null ? parseDouble(json['actualFare']) : null,
        platformFee: json['platformFee'] != null
            ? parseDouble(json['platformFee'])
            : null,
        driverEarnings: json['driverEarnings'] != null
            ? parseDouble(json['driverEarnings'])
            : null,
        fareBasis: (json['fareBasis'] as String?)?.trim(),
        cancellationFee: json['cancellationFee'] != null
            ? parseDouble(json['cancellationFee'])
            : null,
        passengerRating: parseInt(json['passengerRating']),
        driverRating: parseInt(json['driverRating']),
        disputeReason: (json['disputeReason'] as String?)?.trim(),
        disputedAt: json['disputedAt'] != null
            ? parseDateTime(json['disputedAt'])
            : null,
        paymentStatus: json['paymentStatus'] as String?,
        paymentChannel: json['paymentChannel'] as String?,
        paymentTxRef: json['paymentTxRef'] as String?,
        paidAt: json['paidAt'] != null ? parseDateTime(json['paidAt']) : null,
        status: json['status'] as String? ?? 'REQUESTED',
        startTime:
            json['startTime'] != null ? parseDateTime(json['startTime']) : null,
        endTime:
            json['endTime'] != null ? parseDateTime(json['endTime']) : null,
        cancellationReason: json['cancellationReason'] as String?,
        passengerNotes: json['passengerNotes'] as String?,
        pickupEarliestAt: json['pickupEarliestAt'] != null
            ? parseDateTime(json['pickupEarliestAt'])
            : null,
        pickupLatestAt: json['pickupLatestAt'] != null
            ? parseDateTime(json['pickupLatestAt'])
            : null,
        maxWaitMinutes: parseInt(json['maxWaitMinutes']),
        passengerReadyAt: json['passengerReadyAt'] != null
            ? parseDateTime(json['passengerReadyAt'])
            : null,
        driverDelayMinutes: parseInt(json['driverDelayMinutes']),
        createdAt: parseDateTime(json['createdAt']),
        updatedAt: parseDateTime(json['updatedAt']),
        taxi: json['taxi'] != null && json['taxi'] is Map
            ? Vehicle.fromJson(json['taxi'] as Map<String, dynamic>)
            : (json['vehicle'] != null && json['vehicle'] is Map
                ? Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>)
                : null),
        driver: () {
          final driverJson = extractDriverJson();
          if (driverJson != null) {
            try {
              return DriverInfo.fromJson(driverJson);
            } catch (e) {
              print('[Ride.fromJson] Error parsing driver: $e');
              return null;
            }
          }
          return null;
        }(),
        passengerName: () {
          final passenger = json['passenger'];
          if (passenger is Map) {
            return (passenger['name'] as String?)?.trim();
          }
          return null;
        }(),
        tripSummary: json['tripSummary'] is Map
            ? TripSummary.fromJson(
                json['tripSummary'] as Map<String, dynamic>,
              )
            : null,
      );
    } catch (e) {
      print('[Ride.fromJson] Error parsing ride from JSON: $e');
      print('[Ride.fromJson] JSON data: $json');
      rethrow;
    }
  }

  bool get hasFlexibleTime =>
      pickupLatestAt != null || (maxWaitMinutes != null && maxWaitMinutes! > 0);

  /// When the passenger will keep looking. Null for a plain book-now request.
  DateTime? get searchDeadline {
    final times = <DateTime>[];
    if (pickupLatestAt != null) times.add(pickupLatestAt!.toLocal());
    if (maxWaitMinutes != null) {
      times.add(createdAt.toLocal().add(Duration(minutes: maxWaitMinutes!)));
    }
    if (times.isEmpty) return null;
    times.sort();
    return times.first;
  }

  bool get isActive => [
        RideStatus.requested,
        RideStatus.accepted,
        RideStatus.driverArrived,
        RideStatus.inProgress,
      ].contains(status);

  bool get isCompleted => status == RideStatus.completed;
  bool get isCancelled => status == RideStatus.cancelled;

  /// Human label for [fareBasis]: Metered (`actual`) vs Estimated.
  String? get fareBasisLabel {
    final b = (fareBasis ?? '').trim().toLowerCase();
    if (b == 'actual') return 'Metered';
    if (b == 'estimated') return 'Estimated';
    return null;
  }

  bool get hasCancellationFee =>
      cancellationFee != null && cancellationFee! > 0;

  bool get hasDispute =>
      (disputeReason != null && disputeReason!.isNotEmpty) || disputedAt != null;

  /// Completed trip still awaiting passenger digital payment (blocks new bookings).
  /// Cash selected by the passenger does not block — the driver confirms separately.
  bool get needsPayment {
    if (!isCompleted || isPaid) return false;
    return !isCashPayment;
  }

  /// Driver/history: trip is completed but not fully settled yet.
  bool get isSettlementPending => isCompleted && !isPaid;

  bool get isPaid {
    final status =
        (paymentStatus ?? tripSummary?.paymentStatus ?? 'pending')
            .toLowerCase()
            .trim();
    return status == 'paid' ||
        status == 'completed' ||
        status == 'success' ||
        status == 'settled';
  }

  bool get isCashPayment =>
      (paymentChannel ?? '').toLowerCase().trim() == 'cash';

  String get fareDisplay => 'MK${estimatedFare.toStringAsFixed(2)}';
  String get distanceDisplay => '${estimatedDistance.toStringAsFixed(1)} km';

  double get resolvedFare => actualFare ?? estimatedFare;
  double get resolvedDistance => actualDistance ?? estimatedDistance;

  String get routeLabel {
    final from = (pickupAddress ?? '').trim();
    final to = (dropoffAddress ?? '').trim();
    if (from.isNotEmpty && to.isNotEmpty) return '$from → $to';
    if (from.isNotEmpty) return from;
    if (to.isNotEmpty) return to;
    return 'Trip #$id';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'passengerId': passengerId,
        'driverId': driverId,
        'taxiId': taxiId,
        'pickupLatitude': pickupLatitude,
        'pickupLongitude': pickupLongitude,
        'pickupAddress': pickupAddress,
        'dropoffLatitude': dropoffLatitude,
        'dropoffLongitude': dropoffLongitude,
        'dropoffAddress': dropoffAddress,
        'estimatedDistance': estimatedDistance,
        'actualDistance': actualDistance,
        'estimatedFare': estimatedFare,
        'surgeMultiplier': surgeMultiplier,
        'actualFare': actualFare,
        'fareBasis': fareBasis,
        'cancellationFee': cancellationFee,
        'paymentStatus': paymentStatus,
        'status': status,
        'startTime': startTime?.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'cancellationReason': cancellationReason,
        'passengerNotes': passengerNotes,
        'pickupEarliestAt': pickupEarliestAt?.toIso8601String(),
        'pickupLatestAt': pickupLatestAt?.toIso8601String(),
        'maxWaitMinutes': maxWaitMinutes,
        'passengerReadyAt': passengerReadyAt?.toIso8601String(),
        'driverDelayMinutes': driverDelayMinutes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'taxi': taxi?.toJson(),
      };
}

class PickupOffer {
  final int id;
  final int rideId;
  final int taxiId;
  final int driverId;
  final int etaMinutes;
  final String status;
  final String driverName;

  const PickupOffer({
    required this.id,
    required this.rideId,
    required this.taxiId,
    required this.driverId,
    required this.etaMinutes,
    required this.status,
    this.driverName = 'Driver',
  });

  factory PickupOffer.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return PickupOffer(
      id: asInt(json['id'] ?? json['offerId']),
      rideId: asInt(json['rideId']),
      taxiId: asInt(json['taxiId']),
      driverId: asInt(json['driverId']),
      etaMinutes: asInt(json['etaMinutes']),
      status: json['status'] as String? ?? 'PENDING',
      driverName: (json['driverName'] as String?)?.trim().isNotEmpty == true
          ? json['driverName'] as String
          : 'Driver',
    );
  }
}

/// Preview of cancel fee for disclosure before confirm (matches backend defaults).
class CancelFeePreview {
  final int rideId;
  final String status;
  final double cancellationFee;
  final String currency;

  const CancelFeePreview({
    required this.rideId,
    required this.status,
    required this.cancellationFee,
    this.currency = 'MWK',
  });

  factory CancelFeePreview.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return CancelFeePreview(
      rideId: asInt(json['rideId'] ?? json['id']),
      status: json['status'] as String? ?? '',
      cancellationFee: asDouble(json['cancellationFee']),
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'] as String
          : 'MWK',
    );
  }

  /// Local fallback matching backend env defaults when preview API is unavailable.
  static double feeForStatus(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'ACCEPTED':
        return 500;
      case 'DRIVER_ARRIVED':
        return 1500;
      case 'IN_PROGRESS':
        return 3000;
      case 'REQUESTED':
      default:
        return 0;
    }
  }
}

class FareEstimate {
  final double estimatedFare;
  final double estimatedDistance;
  final double surgeMultiplier;
  final double baseFareBeforeSurge;
  final FareBreakdown breakdown;

  FareEstimate({
    required this.estimatedFare,
    required this.estimatedDistance,
    this.surgeMultiplier = 1.0,
    double? baseFareBeforeSurge,
    required this.breakdown,
  }) : baseFareBeforeSurge = baseFareBeforeSurge ?? estimatedFare;

  bool get hasSurge => surgeMultiplier > 1.0;

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value, [double fallback = 0]) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    final estimatedFare = asDouble(json['estimatedFare']);
    final surgeMultiplier = asDouble(json['surgeMultiplier'], 1.0);
    final baseFareBeforeSurge = json['baseFareBeforeSurge'] != null
        ? asDouble(json['baseFareBeforeSurge'], estimatedFare)
        : estimatedFare;

    final breakdownRaw = json['breakdown'];
    final breakdown = breakdownRaw is Map<String, dynamic>
        ? FareBreakdown.fromJson(breakdownRaw)
        : FareBreakdown(
            baseFare: 0,
            perKmFare: 0,
            totalFare: baseFareBeforeSurge,
            distance: asDouble(json['estimatedDistance']),
          );

    return FareEstimate(
      estimatedFare: estimatedFare,
      estimatedDistance: asDouble(json['estimatedDistance']),
      surgeMultiplier: surgeMultiplier <= 0 ? 1.0 : surgeMultiplier,
      baseFareBeforeSurge: baseFareBeforeSurge,
      breakdown: breakdown,
    );
  }

  Map<String, dynamic> toJson() => {
        'estimatedFare': estimatedFare,
        'estimatedDistance': estimatedDistance,
        'surgeMultiplier': surgeMultiplier,
        'baseFareBeforeSurge': baseFareBeforeSurge,
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
