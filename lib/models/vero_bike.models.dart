// lib/models/vero_bike.models.dart

class VeroBikeDriver {
  final int id;
  final String name;
  final String phone;
  final String city;
  final String status; // "OFFLINE" | "ONLINE_AVAILABLE" | "ONLINE_ON_TRIP"

  final String? photoUrl;
  final String? baseLocationText;
  final double? currentLat;
  final double? currentLng;

  VeroBikeDriver({
    required this.id,
    required this.name,
    required this.phone,
    required this.city,
    required this.status,
    this.photoUrl,
    this.baseLocationText,
    this.currentLat,
    this.currentLng,
  });

  factory VeroBikeDriver.fromJson(Map<String, dynamic> json) {
    return VeroBikeDriver(
      id: json['id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String,
      city: json['city'] as String,
      status: json['status'] as String,
      photoUrl: json['photoUrl'] as String?,
      baseLocationText: json['baseLocationText'] as String?,
      currentLat: (json['currentLat'] as num?)?.toDouble(),
      currentLng: (json['currentLng'] as num?)?.toDouble(),
    );
  }
}
