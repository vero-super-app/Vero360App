import 'package:cloud_firestore/cloud_firestore.dart';

class MarketplaceDetailModel {
  final String? id;
  final String name;
  final String image;
  final double price;
  final String? description;
  final String location;
  final bool isActive;
  final String? category;
  final List<String> gallery;
  final List<String> videos;
  final String? sellerUserId;
  final Timestamp? createdAt; // Firestore timestamp for now

  MarketplaceDetailModel({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    this.description,
    required this.location,
    required this.isActive,
    this.category,
    this.gallery = const [],
    this.videos = const [],
    this.sellerUserId,
    this.createdAt,
  });

  factory MarketplaceDetailModel.fromMap(Map<String, dynamic> data) {
    return MarketplaceDetailModel(
      id: data['id'] as String?,
      name: data['name'] as String? ?? '',
      image: data['image'] as String? ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String?,
      location: data['location'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? true,
      category: data['category'] as String?,
      gallery: (data['gallery'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      videos: (data['videos'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sellerUserId: data['sellerUserId'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'image': image,
      'price': price,
      'description': description,
      'location': location,
      'isActive': isActive,
      'category': category,
      'gallery': gallery,
      'videos': videos,
      'sellerUserId': sellerUserId,
      'createdAt': createdAt,
    };
  }
}
