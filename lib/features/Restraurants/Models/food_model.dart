class FoodVariant {
  final String name;
  final double priceDeltaMwk;

  const FoodVariant({
    required this.name,
    this.priceDeltaMwk = 0,
  });

  factory FoodVariant.fromJson(Map<String, dynamic> json) {
    double safeDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    return FoodVariant(
      name: (json['name'] ?? '').toString().trim(),
      priceDeltaMwk: safeDouble(
        json['priceDeltaMwk'] ?? json['priceDelta'] ?? json['delta'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceDeltaMwk': priceDeltaMwk,
      };
}

class FoodAddOn {
  final String name;
  final double priceMwk;
  final bool isDefault;

  const FoodAddOn({
    required this.name,
    this.priceMwk = 0,
    this.isDefault = false,
  });

  factory FoodAddOn.fromJson(Map<String, dynamic> json) {
    double safeDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      return s == 'true' || s == '1';
    }

    return FoodAddOn(
      name: (json['name'] ?? '').toString().trim(),
      priceMwk: safeDouble(json['priceMwk'] ?? json['price']),
      isDefault: asBool(json['isDefault']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceMwk': priceMwk,
        'isDefault': isDefault,
      };
}

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
  /// Firestore `restaurants` document id. Null on legacy `food_menu_items` until backfill.
  final String? restaurantId;
  /// Firestore `marketplace_items` document id when listing is from Firestore.
  final String? firestoreListingId;

  /// Size / option rows. Empty = single fixed price (legacy dishes).
  final List<FoodVariant> variants;
  /// Optional extras. Empty = none.
  final List<FoodAddOn> addOns;
  /// Item-level kitchen prep. Null → restaurant avg → hardcoded ETA fallback.
  final int? prepTimeMinutes;
  /// Denormalized from [RestaurantModel.avgPrepTimeMinutes] at fetch time.
  final int? restaurantAvgPrepTimeMinutes;

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
    this.restaurantId,
    this.firestoreListingId,
    this.variants = const [],
    this.addOns = const [],
    this.prepTimeMinutes,
    this.restaurantAvgPrepTimeMinutes,
  });

  /// Item prep if set, else the restaurant average. Null when neither exists.
  int? get effectivePrepTimeMinutes {
    final item = prepTimeMinutes;
    if (item != null && item > 0) return item;
    final kitchen = restaurantAvgPrepTimeMinutes;
    if (kitchen != null && kitchen > 0) return kitchen;
    return null;
  }

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

    int? optInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
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

    List<FoodVariant> parseVariants(dynamic v) {
      if (v is! List) return const [];
      final out = <FoodVariant>[];
      for (final e in v) {
        try {
          if (e is! Map) continue;
          final parsed = FoodVariant.fromJson(Map<String, dynamic>.from(e));
          if (parsed.name.isEmpty) continue;
          out.add(parsed);
        } catch (_) {}
      }
      return out;
    }

    List<FoodAddOn> parseAddOns(dynamic v) {
      if (v is! List) return const [];
      final out = <FoodAddOn>[];
      for (final e in v) {
        try {
          if (e is! Map) continue;
          final parsed = FoodAddOn.fromJson(Map<String, dynamic>.from(e));
          if (parsed.name.isEmpty) continue;
          out.add(parsed);
        } catch (_) {}
      }
      return out;
    }

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

    final prep = optInt(json['prepTimeMinutes']);
    final restPrep = optInt(json['restaurantAvgPrepTimeMinutes']);

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
      restaurantId: _optStr(json['restaurantId']),
      firestoreListingId: _optStr(json['firestoreListingId']),
      variants: parseVariants(json['variants']),
      addOns: parseAddOns(json['addOns'] ?? json['addons']),
      prepTimeMinutes: (prep != null && prep > 0) ? prep : null,
      restaurantAvgPrepTimeMinutes:
          (restPrep != null && restPrep > 0) ? restPrep : null,
    );
  }

  FoodModel copyWith({
    int? id,
    String? FoodName,
    String? FoodImage,
    String? RestrauntName,
    double? price,
    String? description,
    String? category,
    double? latitude,
    double? longitude,
    String? listingLocation,
    List<String>? gallery,
    List<String>? videos,
    String? merchantId,
    String? restaurantId,
    String? firestoreListingId,
    List<FoodVariant>? variants,
    List<FoodAddOn>? addOns,
    int? prepTimeMinutes,
    int? restaurantAvgPrepTimeMinutes,
  }) {
    return FoodModel(
      id: id ?? this.id,
      FoodName: FoodName ?? this.FoodName,
      FoodImage: FoodImage ?? this.FoodImage,
      RestrauntName: RestrauntName ?? this.RestrauntName,
      price: price ?? this.price,
      description: description ?? this.description,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      listingLocation: listingLocation ?? this.listingLocation,
      gallery: gallery ?? this.gallery,
      videos: videos ?? this.videos,
      merchantId: merchantId ?? this.merchantId,
      restaurantId: restaurantId ?? this.restaurantId,
      firestoreListingId: firestoreListingId ?? this.firestoreListingId,
      variants: variants ?? this.variants,
      addOns: addOns ?? this.addOns,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      restaurantAvgPrepTimeMinutes:
          restaurantAvgPrepTimeMinutes ?? this.restaurantAvgPrepTimeMinutes,
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
        if (restaurantId != null) 'restaurantId': restaurantId,
        if (firestoreListingId != null) 'firestoreListingId': firestoreListingId,
        if (variants.isNotEmpty)
          'variants': variants.map((e) => e.toJson()).toList(),
        if (addOns.isNotEmpty) 'addOns': addOns.map((e) => e.toJson()).toList(),
        if (prepTimeMinutes != null) 'prepTimeMinutes': prepTimeMinutes,
        if (restaurantAvgPrepTimeMinutes != null)
          'restaurantAvgPrepTimeMinutes': restaurantAvgPrepTimeMinutes,
      };
}
