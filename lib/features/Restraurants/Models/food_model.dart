class FoodModel {
  final int id;
  final String FoodName;
  final String FoodImage;
  final String RestrauntName;
  final double price;

  // Optional extras
  final String? description;
  final String? category;

  // ✅ New: gallery + videos like Marketplace
  final List<String> gallery;
  final List<String> videos;

  FoodModel({
    required this.id,
    required this.FoodName,
    required this.FoodImage,
    required this.RestrauntName,
    required this.price,
    this.description,
    this.category,
    this.gallery = const [],
    this.videos = const [],
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

    String str(dynamic v) => (v == null) ? '' : v.toString();

    // 🔁 same style as MarketplaceDetailModel
    List<String> arr(dynamic v) =>
        (v is List)
            ? v
                .map((e) => '$e')
                .where((s) => s.isNotEmpty)
                .cast<String>()
                .toList()
            : const <String>[];

    return FoodModel(
      id: id(json['id']),
      FoodName: str(json['FoodName']),
      FoodImage: str(json['FoodImage']),
      RestrauntName: str(json['RestrauntName']),
      price: safeDouble(json['price']),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      gallery: arr(json['gallery']),
      videos: arr(json['videos']),
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
        if (gallery.isNotEmpty) 'gallery': gallery,
        if (videos.isNotEmpty) 'videos': videos,
      };
}
