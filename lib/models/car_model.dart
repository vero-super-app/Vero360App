class CarModel {
  final int id;
  final String brand;
  final String model;
  final String licensePlate;
  final double dailyRate;
  final bool isAvailable;
  final String gpsTrackerId;
  final String? imageUrl;
  final int seats;
  final String fuelType;
  final double rating;
  final int reviews;
  final String? ownerName;
  final int year;
  final String? description;
  final String? color;
  final double? latitude;
  final double? longitude;

  CarModel({
    required this.id,
    required this.brand,
    required this.model,
    required this.licensePlate,
    required this.dailyRate,
    required this.isAvailable,
    required this.gpsTrackerId,
    this.imageUrl,
    this.seats = 5,
    this.fuelType = 'Petrol',
    this.rating = 0,
    this.reviews = 0,
    this.ownerName,
    this.year = 2020,
    this.description,
    this.color,
    this.latitude,
    this.longitude,
  });

  factory CarModel.fromJson(Map<String, dynamic> json) {
    return CarModel(
      id: json['id'] ?? 0,
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      licensePlate: json['licensePlate'] ?? json['license_plate'] ?? '',
      dailyRate: (json['dailyRate'] ?? json['daily_rate'] ?? 0).toDouble(),
      isAvailable: json['isAvailable'] ?? json['is_available'] ?? true,
      gpsTrackerId: json['gpsTrackerId'] ?? json['gps_tracker_id'] ?? '',
      imageUrl: json['imageUrl'] ?? json['image_url'],
      seats: json['seats'] ?? 5,
      fuelType: json['fuelType'] ?? json['fuel_type'] ?? 'Petrol',
      rating: (json['rating'] ?? 0).toDouble(),
      reviews: json['reviews'] ?? 0,
      ownerName: json['ownerName'] ?? json['owner_name'],
      year: json['year'] ?? 2020,
      description: json['description'],
      color: json['color'],
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'model': model,
        'licensePlate': licensePlate,
        'dailyRate': dailyRate,
        'isAvailable': isAvailable,
        'gpsTrackerId': gpsTrackerId,
        'imageUrl': imageUrl,
        'seats': seats,
        'fuelType': fuelType,
        'rating': rating,
        'reviews': reviews,
        'ownerName': ownerName,
        'year': year,
        'description': description,
        'color': color,
        'latitude': latitude,
        'longitude': longitude,
      };

  CarModel copyWith({
    int? id,
    String? brand,
    String? model,
    String? licensePlate,
    double? dailyRate,
    bool? isAvailable,
    String? gpsTrackerId,
    String? imageUrl,
    int? seats,
    String? fuelType,
    double? rating,
    int? reviews,
    String? ownerName,
    int? year,
    String? description,
    String? color,
    double? latitude,
    double? longitude,
  }) {
    return CarModel(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      licensePlate: licensePlate ?? this.licensePlate,
      dailyRate: dailyRate ?? this.dailyRate,
      isAvailable: isAvailable ?? this.isAvailable,
      gpsTrackerId: gpsTrackerId ?? this.gpsTrackerId,
      imageUrl: imageUrl ?? this.imageUrl,
      seats: seats ?? this.seats,
      fuelType: fuelType ?? this.fuelType,
      rating: rating ?? this.rating,
      reviews: reviews ?? this.reviews,
      ownerName: ownerName ?? this.ownerName,
      year: year ?? this.year,
      description: description ?? this.description,
      color: color ?? this.color,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
