class GpsTrackerModel {
  final int id;
  final int carId;
  final String deviceId;
  final String? traccarDeviceId;
  final double? lastLatitude;
  final double? lastLongitude;
  final double? lastSpeed;
  final double? lastAltitude;
  final double? batteryLevel;
  final DateTime? lastUpdate;
  final bool isActive;
  final bool isOnline;

  GpsTrackerModel({
    required this.id,
    required this.carId,
    required this.deviceId,
    this.traccarDeviceId,
    this.lastLatitude,
    this.lastLongitude,
    this.lastSpeed,
    this.lastAltitude,
    this.batteryLevel,
    this.lastUpdate,
    required this.isActive,
    required this.isOnline,
  });

  factory GpsTrackerModel.fromJson(Map<String, dynamic> json) {
    return GpsTrackerModel(
      id: json['id'] ?? 0,
      carId: json['carId'] ?? json['car_id'] ?? 0,
      deviceId: json['deviceId'] ?? json['device_id'] ?? '',
      traccarDeviceId: json['traccarDeviceId'] ?? json['traccar_device_id'],
      lastLatitude: json['lastLatitude'] != null ? (json['lastLatitude']).toDouble() : null,
      lastLongitude: json['lastLongitude'] != null ? (json['lastLongitude']).toDouble() : null,
      lastSpeed: json['lastSpeed'] != null ? (json['lastSpeed']).toDouble() : null,
      lastAltitude: json['lastAltitude'] != null ? (json['lastAltitude']).toDouble() : null,
      batteryLevel: json['batteryLevel'] != null ? (json['batteryLevel']).toDouble() : null,
      lastUpdate: json['lastUpdate'] != null ? DateTime.parse(json['lastUpdate']) : null,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      isOnline: json['isOnline'] ?? json['is_online'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'deviceId': deviceId,
        'traccarDeviceId': traccarDeviceId,
        'lastLatitude': lastLatitude,
        'lastLongitude': lastLongitude,
        'lastSpeed': lastSpeed,
        'lastAltitude': lastAltitude,
        'batteryLevel': batteryLevel,
        'lastUpdate': lastUpdate?.toIso8601String(),
        'isActive': isActive,
        'isOnline': isOnline,
      };

  GpsTrackerModel copyWith({
    int? id,
    int? carId,
    String? deviceId,
    String? traccarDeviceId,
    double? lastLatitude,
    double? lastLongitude,
    double? lastSpeed,
    double? lastAltitude,
    double? batteryLevel,
    DateTime? lastUpdate,
    bool? isActive,
    bool? isOnline,
  }) {
    return GpsTrackerModel(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      deviceId: deviceId ?? this.deviceId,
      traccarDeviceId: traccarDeviceId ?? this.traccarDeviceId,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastSpeed: lastSpeed ?? this.lastSpeed,
      lastAltitude: lastAltitude ?? this.lastAltitude,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isActive: isActive ?? this.isActive,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class GpsLocation {
  final double latitude;
  final double longitude;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final double accuracy;

  GpsLocation({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    required this.timestamp,
    required this.accuracy,
  });

  factory GpsLocation.fromJson(Map<String, dynamic> json) {
    return GpsLocation(
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      speed: (json['speed'] ?? 0).toDouble(),
      heading: (json['heading'] ?? 0).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      accuracy: (json['accuracy'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'heading': heading,
        'timestamp': timestamp.toIso8601String(),
        'accuracy': accuracy,
      };
}
