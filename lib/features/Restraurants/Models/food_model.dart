class FoodModel {
  final int id;
  final String FoodName;
  final String FoodImage;
  final String RestrauntName;
  final double price;

  // Optional extras
  final String? description;
  final String? category;

  /// Seller / listing coordinates when API provides them (for distance sorting).
  final double? latitude;
  final double? longitude;

  /// Human-readable pickup / listing area when API or Firestore provides it.
  final String? listingLocation;

  // ✅ New: gallery + videos like Marketplace
  final List<String> gallery;
  final List<String> videos;

  /// Firebase merchant / kitchen id (from listing). Required for food_orders routing.
  final String? merchantId;
  /// Firestore `marketplace_items` document id when listing is from Firestore.
  final String? firestoreListingId;

  FoodModel({
    required this.id,
    required this.FoodName,
    required this.FoodImage,
    required this.RestrauntName,
    required this.price,
    this.description,
    this.category,
    this.latitude,
    this.longitude,
    this.listingLocation,
    this.gallery = const [],
    this.videos = const [],
    this.merchantId,
    this.firestoreListingId,
  });

  factory FoodModel.fromJson(Map<String, dynamic> json) {
    int id(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    double safeDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    double? optDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String str(dynamic v) => (v == null) ? '' : v.toString();

    String? _optStr(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    // 🔁 same style as MarketplaceDetailModel
    List<String> arr(dynamic v) =>
        (v is List)
            ? v
                .map((e) => '$e')
                .where((s) => s.isNotEmpty)
                .cast<String>()
                .toList()
            : const <String>[];

    String pickImage() {
      for (final key in [
        'FoodImage',
        'image',
        'imageUrl',
        'photo',
        'picture',
        'coverImage',
        'coverUrl',
      ]) {
        final s = str(json[key]).trim();
        if (s.isNotEmpty) return s;
      }
      final gal = arr(json['gallery']);
      if (gal.isNotEmpty) return gal.first;
      final urls = arr(json['galleryUrls']);
      if (urls.isNotEmpty) return urls.first;
      final images = arr(json['images']);
      if (images.isNotEmpty) return images.first;
      return '';
    }

    final gallery = [
      ...arr(json['gallery']),
      ...arr(json['galleryUrls']),
      ...arr(json['images']),
    ];

    return FoodModel(
      id: id(json['id']),
      FoodName: str(json['FoodName']).isNotEmpty
          ? str(json['FoodName'])
          : str(json['name']),
      FoodImage: pickImage(),
      RestrauntName: str(json['RestrauntName']).isNotEmpty
          ? str(json['RestrauntName'])
          : str(json['merchantName']).isNotEmpty
              ? str(json['merchantName'])
              : str(json['businessName']),
      price: safeDouble(json['price']),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      latitude: optDouble(json['latitude'] ?? json['lat']),
      longitude: optDouble(json['longitude'] ?? json['lng']),
      listingLocation: _optStr(json['listingLocation']),
      gallery: gallery,
      videos: arr(json['videos']),
      merchantId: _optStr(json['merchantId']),
      firestoreListingId: _optStr(json['firestoreListingId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'FoodName': FoodName,
        'FoodImage': FoodImage,
        'RestrauntName': RestrauntName,
        'price': price,
        if (description != null) 'description': description,
        if (category != null) 'category': category,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (listingLocation != null) 'listingLocation': listingLocation,
        if (gallery.isNotEmpty) 'gallery': gallery,
        if (videos.isNotEmpty) 'videos': videos,
        if (merchantId != null) 'merchantId': merchantId,
        if (firestoreListingId != null) 'firestoreListingId': firestoreListingId,
      };
}
