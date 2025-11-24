import 'package:vero360_app/models/car_model.dart';

class MerchantModel {
  final int id;
  final int userId;
  final String businessName;
  final String businessLicense;
  final String? taxId;
  final String? bankAccountNumber;
  final String? bankName;
  final bool verified;
  final DateTime createdAt;
  final DateTime? verifiedAt;
  final List<CarModel>? cars;
  final int totalBookings;
  final double totalEarnings;
  final double averageRating;

  MerchantModel({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.businessLicense,
    this.taxId,
    this.bankAccountNumber,
    this.bankName,
    required this.verified,
    required this.createdAt,
    this.verifiedAt,
    this.cars,
    this.totalBookings = 0,
    this.totalEarnings = 0,
    this.averageRating = 0,
  });

  factory MerchantModel.fromJson(Map<String, dynamic> json) {
    return MerchantModel(
      id: json['id'] ?? 0,
      userId: json['userId'] ?? json['user_id'] ?? 0,
      businessName: json['businessName'] ?? json['business_name'] ?? '',
      businessLicense: json['businessLicense'] ?? json['business_license'] ?? '',
      taxId: json['taxId'] ?? json['tax_id'],
      bankAccountNumber: json['bankAccountNumber'] ?? json['bank_account_number'],
      bankName: json['bankName'] ?? json['bank_name'],
      verified: json['verified'] ?? false,
      createdAt: DateTime.parse(
        json['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.parse(json['verifiedAt'])
          : (json['verified_at'] != null ? DateTime.parse(json['verified_at']) : null),
      cars: json['cars'] != null
          ? (json['cars'] as List).map((e) => CarModel.fromJson(e)).toList()
          : null,
      totalBookings: json['totalBookings'] ?? json['total_bookings'] ?? 0,
      totalEarnings: (json['totalEarnings'] ?? json['total_earnings'] ?? 0).toDouble(),
      averageRating: (json['averageRating'] ?? json['average_rating'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'businessName': businessName,
        'businessLicense': businessLicense,
        'taxId': taxId,
        'bankAccountNumber': bankAccountNumber,
        'bankName': bankName,
        'verified': verified,
        'createdAt': createdAt.toIso8601String(),
        'verifiedAt': verifiedAt?.toIso8601String(),
        'cars': cars?.map((c) => c.toJson()).toList(),
        'totalBookings': totalBookings,
        'totalEarnings': totalEarnings,
        'averageRating': averageRating,
      };

  MerchantModel copyWith({
    int? id,
    int? userId,
    String? businessName,
    String? businessLicense,
    String? taxId,
    String? bankAccountNumber,
    String? bankName,
    bool? verified,
    DateTime? createdAt,
    DateTime? verifiedAt,
    List<CarModel>? cars,
    int? totalBookings,
    double? totalEarnings,
    double? averageRating,
  }) {
    return MerchantModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      businessName: businessName ?? this.businessName,
      businessLicense: businessLicense ?? this.businessLicense,
      taxId: taxId ?? this.taxId,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankName: bankName ?? this.bankName,
      verified: verified ?? this.verified,
      createdAt: createdAt ?? this.createdAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      cars: cars ?? this.cars,
      totalBookings: totalBookings ?? this.totalBookings,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      averageRating: averageRating ?? this.averageRating,
    );
  }
}
