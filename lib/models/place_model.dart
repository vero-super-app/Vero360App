enum PlaceType { HOME, WORK, FAVORITE, RECENT }

class Place {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final bool isBookmarked;
  final DateTime? savedAt;
  final PlaceType type;

  Place({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.isBookmarked = false,
    this.savedAt,
    this.type = PlaceType.FAVORITE,
  });

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    isBookmarked: json['isBookmarked'] as bool? ?? false,
    savedAt: json['savedAt'] != null ? DateTime.parse(json['savedAt'] as String) : null,
    type: PlaceType.values.byName(json['type'] as String? ?? 'FAVORITE'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'isBookmarked': isBookmarked,
    'savedAt': savedAt?.toIso8601String(),
    'type': type.name,
  };

  Place copyWith({
    String? id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    bool? isBookmarked,
    DateTime? savedAt,
    PlaceType? type,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      savedAt: savedAt ?? this.savedAt,
      type: type ?? this.type,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Place &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => id.hashCode ^ latitude.hashCode ^ longitude.hashCode;
}
