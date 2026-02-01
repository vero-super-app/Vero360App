class MarketplaceDetailModel {
  final int id;
  final String name;
  final String image;
  final double price;
  final String location;
  final String description;
  final String? comment;

  MarketplaceDetailModel({
    required this.id,
    required this.name,
    required this.image,
    required this.location,
    required this.price,
    required this.description,
    this.comment,
  });

  factory MarketplaceDetailModel.fromJson(Map<String, dynamic> json) {
    return MarketplaceDetailModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown Item',
      image: json['image'] ?? 'https://via.placeholder.com/300', // Placeholder image
      price: (json['price'] ?? 0).toDouble(),
      location: json['Location'] ?? 'Unknown Location',
      description: json['description'] ?? 'No description available.',
      comment: json['comment'] ?? '',
    );
  }
}
