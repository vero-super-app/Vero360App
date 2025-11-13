class MarketplaceItem {
  final String name;
  final double price;
  final String image;                 // cover URL
  final String? description;
  final String location;
  final bool isActive;
  final String? category;
  final List<String>? gallery;        // extra image URLs
  final List<String>? videos;         // video URLs

  MarketplaceItem({
    required this.name,
    required this.price,
    required this.image,
    required this.location,
    this.description,
    this.isActive = true,
    this.category,
    this.gallery,
    this.videos,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'image': image,
        'location': location,
        if (description != null) 'description': description,
        'isActive': isActive,
        if (category != null) 'category': category,
        if (gallery != null && gallery!.isNotEmpty) 'gallery': gallery,
        if (videos != null && videos!.isNotEmpty) 'videos': videos,
      };
}

class MarketplaceDetailModel {
  final int id;
  final String name;
  final String image;
  final double price;
  final String description;
  final String location;
  final String? comment;
  final String? category;
  final List<String> gallery;
  final List<String> videos;

  // (optional) seller fields
  final String? sellerBusinessName;
  final String? sellerOpeningHours;
  final String? sellerStatus;
  final String? sellerBusinessDescription;
  final double? sellerRating;
  final String? sellerLogoUrl;
  final String? serviceProviderId;
  final String? sellerUserId;

  MarketplaceDetailModel({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.description,
    required this.location,
    this.comment,
    this.category,
    this.gallery = const [],
    this.videos = const [],
    this.sellerBusinessName,
    this.sellerOpeningHours,
    this.sellerStatus,
    this.sellerBusinessDescription,
    this.sellerRating,
    this.sellerLogoUrl,
    this.serviceProviderId,
    this.sellerUserId,
  });

 factory MarketplaceDetailModel.fromJson(Map<String, dynamic> j) {
  List<String> _arr(dynamic v) =>
      (v is List) ? v.map((e) => '$e').where((s) => s.isNotEmpty).cast<String>().toList() : const <String>[];
  double _num(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  // fallback: if backend doesn’t send sellerUserId but sends ownerId, use it
  final String? _sellerUserId =
      (j['sellerUserId'] ?? j['ownerId'])?.toString();

  return MarketplaceDetailModel(
    id: j['id'] ?? 0,
    name: '${j['name'] ?? ''}',
    image: '${j['image'] ?? ''}',
    price: _num(j['price'] ?? 0),
    description: '${j['description'] ?? ''}',
    location: '${j['location'] ?? ''}',
    comment: j['comment']?.toString(),
    category: j['category']?.toString(),
    gallery: _arr(j['gallery']),
    videos: _arr(j['videos']),
    sellerBusinessName: j['sellerBusinessName']?.toString(),
    sellerOpeningHours: j['sellerOpeningHours']?.toString(),
    sellerStatus: j['sellerStatus']?.toString(),
    sellerBusinessDescription: j['sellerBusinessDescription']?.toString(),
    sellerRating: (j['sellerRating'] is num)
        ? (j['sellerRating'] as num).toDouble()
        : double.tryParse('${j['sellerRating']}'),
    sellerLogoUrl: j['sellerLogoUrl']?.toString(),
    serviceProviderId: j['serviceProviderId']?.toString(),
    sellerUserId: _sellerUserId, // <- now set
  );
}

}
