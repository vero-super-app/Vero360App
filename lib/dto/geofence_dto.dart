class GeofenceDto {
  final int carId;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusMeters;
  final bool enabled;
  final String? name;
  final String? description;
  final List<String>? alertTypes; // ENTRY, EXIT, SPEED_VIOLATION

  const GeofenceDto({
    required this.carId,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusMeters,
    required this.enabled,
    this.name,
    this.description,
    this.alertTypes,
  });

  Map<String, dynamic> toJson() => {
        'carId': carId,
        'centerLatitude': centerLatitude,
        'centerLongitude': centerLongitude,
        'radiusMeters': radiusMeters,
        'enabled': enabled,
        'name': name,
        'description': description,
        'alertTypes': alertTypes ?? ['ENTRY', 'EXIT'],
      };

  factory GeofenceDto.fromJson(Map<String, dynamic> json) {
    return GeofenceDto(
      carId: json['carId'] ?? 0,
      centerLatitude: (json['centerLatitude'] ?? 0).toDouble(),
      centerLongitude: (json['centerLongitude'] ?? 0).toDouble(),
      radiusMeters: (json['radiusMeters'] ?? 1000).toDouble(),
      enabled: json['enabled'] ?? true,
      name: json['name'],
      description: json['description'],
      alertTypes: json['alertTypes'] != null ? List<String>.from(json['alertTypes']) : null,
    );
  }
}
