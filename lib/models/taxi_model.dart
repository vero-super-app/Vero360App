class Taxi {
  final int id;
  final int driverId;
  final String taxiClass; // ECONOMY, COMFORT, PREMIUM, BUSINESS
  final String make;
  final String model;
  final int year;
  final String licensePlate;
  final String? color;
  final int seats;
  final String? registrationNumber;
  final DateTime? registrationExpiry;
  final String? registrationImageUrl;
  final bool isAvailable;
  final String status; // ACTIVE, MAINTENANCE, INACTIVE
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final DateTime? lastLocationUpdate;
  final double rating;
  final int totalRides;
  final List<String>? features; // AC, WiFi, Phone charger, etc.
  final DateTime createdAt;
  final DateTime updatedAt;

  Taxi({
    required this.id,
    required this.driverId,
    required this.taxiClass,
    required this.make,
    required this.model,
    required this.year,
    required this.licensePlate,
    this.color,
    required this.seats,
    this.registrationNumber,
    this.registrationExpiry,
    this.registrationImageUrl,
    required this.isAvailable,
    required this.status,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.lastLocationUpdate,
    required this.rating,
    required this.totalRides,
    this.features,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Taxi.fromJson(Map<String, dynamic> json) {
    return Taxi(
      id: json['id'] as int,
      driverId: json['driverId'] as int,
      taxiClass: json['taxiClass'] as String,
      make: json['make'] as String,
      model: json['model'] as String,
      year: json['year'] as int,
      licensePlate: json['licensePlate'] as String,
      color: json['color'] as String?,
      seats: json['seats'] as int,
      registrationNumber: json['registrationNumber'] as String?,
      registrationExpiry: json['registrationExpiry'] != null
          ? DateTime.parse(json['registrationExpiry'] as String)
          : null,
      registrationImageUrl: json['registrationImageUrl'] as String?,
      isAvailable: json['isAvailable'] as bool,
      status: json['status'] as String,
      imageUrl: json['imageUrl'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      lastLocationUpdate: json['lastLocationUpdate'] != null
          ? DateTime.parse(json['lastLocationUpdate'] as String)
          : null,
      rating: (json['rating'] as num).toDouble(),
      totalRides: json['totalRides'] as int,
      features: json['features'] != null ? List<String>.from(json['features'] as List) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'taxiClass': taxiClass,
      'make': make,
      'model': model,
      'year': year,
      'licensePlate': licensePlate,
      'color': color,
      'seats': seats,
      'registrationNumber': registrationNumber,
      'registrationExpiry': registrationExpiry?.toIso8601String(),
      'registrationImageUrl': registrationImageUrl,
      'isAvailable': isAvailable,
      'status': status,
      'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'lastLocationUpdate': lastLocationUpdate?.toIso8601String(),
      'rating': rating,
      'totalRides': totalRides,
      'features': features,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  String get displayName => '$make $model ($year)';

  bool get isActive => status == 'ACTIVE';

  bool get needsMaintenance => status == 'MAINTENANCE';
}
