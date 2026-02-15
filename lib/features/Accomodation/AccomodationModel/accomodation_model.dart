// lib/models/hostel_model.dart

import 'dart:convert';
import 'dart:typed_data';

class Owner {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String profilepicture;
  final bool isEmailVerified;
  final String? emailVerificationCode;
  final bool isPhoneVerified;
  final String? phoneVerificationCode;
  final String role;
  final num averageRating;
  final int reviewCount;
  final DateTime createdAt;

  Owner({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.profilepicture,
    required this.isEmailVerified,
    required this.emailVerificationCode,
    required this.isPhoneVerified,
    required this.phoneVerificationCode,
    required this.role,
    required this.averageRating,
    required this.reviewCount,
    required this.createdAt,
  });

  factory Owner.fromJson(Map<String, dynamic> json) => Owner(
        id: (json['id'] ?? 0) as int,
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        profilepicture: (json['profilepicture'] ?? '').toString(),
        isEmailVerified: (json['isEmailVerified'] ?? false) as bool,
        emailVerificationCode: json['emailVerificationCode']?.toString(),
        isPhoneVerified: (json['isPhoneVerified'] ?? false) as bool,
        phoneVerificationCode: json['phoneVerificationCode']?.toString(),
        role: (json['role'] ?? '').toString(),
        averageRating: (json['averageRating'] ?? 0),
        reviewCount: (json['reviewCount'] ?? 0) as int,
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class Accommodation {
  final int id;
  final String name;
  final String location;
  final String description;
  final int price;
  final String accommodationType;
  final Owner? owner;

  /// Image: http(s) url, gs:// url, Firebase Storage path, or base64 string
  final String? image;
  /// Decoded bytes when image is base64
  final Uint8List? imageBytes;
  /// Additional gallery URLs/paths
  final List<String> gallery;

  Accommodation({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.price,
    required this.accommodationType,
    this.owner,
    this.image,
    this.imageBytes,
    this.gallery = const [],
  });

  static bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.length < 150) return false;
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  factory Accommodation.fromJson(Map<String, dynamic> json) {
    final rawImage = (json['image'] ?? json['imageUrl'] ?? '').toString().trim();
    Uint8List? imageBytes;
    if (rawImage.isNotEmpty && _looksLikeBase64(rawImage)) {
      try {
        final base64Part = rawImage.contains(',') ? rawImage.split(',').last : rawImage;
        imageBytes = base64Decode(base64Part);
      } catch (_) {}
    }
    List<String> gallery = const [];
    final galleryRaw = json['gallery'];
    if (galleryRaw is List) {
      gallery = galleryRaw.map((e) => e.toString()).toList();
    }
    return Accommodation(
      id: (json['id'] ?? 0) as int,
      name: (json['name'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: (json['price'] is num)
          ? (json['price'] as num).toInt()
          : int.tryParse(json['price']?.toString() ?? '0') ?? 0,
      accommodationType: (json['accommodationType'] ?? '').toString(),
      owner: json['owner'] != null
          ? Owner.fromJson(Map<String, dynamic>.from(json['owner']))
          : null,
      image: rawImage.isEmpty ? null : rawImage,
      imageBytes: imageBytes,
      gallery: gallery,
    );
  }
}
