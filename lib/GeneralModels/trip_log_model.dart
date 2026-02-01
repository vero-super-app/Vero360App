class TripLogModel {
  final int id;
  final int carId;
  final double latitude;
  final double longitude;
  final double? speed;
  final double? mileage;
  final DateTime timestamp;

  TripLogModel({
    required this.id,
    required this.carId,
    required this.latitude,
    required this.longitude,
    this.speed,
    this.mileage,
    required this.timestamp,
  });

  factory TripLogModel.fromJson(Map<String, dynamic> json) {
    return TripLogModel(
      id: json['id'] ?? 0,
      carId: json['carId'] ?? json['car_id'] ?? 0,
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      speed: json['speed'] != null ? (json['speed']).toDouble() : null,
      mileage: json['mileage'] != null ? (json['mileage']).toDouble() : null,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'mileage': mileage,
        'timestamp': timestamp.toIso8601String(),
      };

  TripLogModel copyWith({
    int? id,
    int? carId,
    double? latitude,
    double? longitude,
    double? speed,
    double? mileage,
    DateTime? timestamp,
  }) {
    return TripLogModel(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speed: speed ?? this.speed,
      mileage: mileage ?? this.mileage,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
