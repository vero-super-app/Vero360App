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
    int _id(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    double _double(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    String _str(dynamic v) => (v == null) ? '' : v.toString();

    // 🔁 same style as MarketplaceDetailModel
    List<String> _arr(dynamic v) =>
        (v is List)
            ? v
                .map((e) => '$e')
                .where((s) => s.isNotEmpty)
                .cast<String>()
                .toList()
            : const <String>[];

    return FoodModel(
      id: _id(json['id']),
      FoodName: _str(json['FoodName']),
      FoodImage: _str(json['FoodImage']),
      RestrauntName: _str(json['RestrauntName']),
      price: _double(json['price']),
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      gallery: _arr(json['gallery']),
      videos: _arr(json['videos']),
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
