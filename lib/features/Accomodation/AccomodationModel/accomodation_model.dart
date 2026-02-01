// lib/models/hostel_model.dart

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

  Accommodation({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.price,
    required this.accommodationType,
    this.owner,
  });

  factory Accommodation.fromJson(Map<String, dynamic> json) => Accommodation(
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
      );
}
