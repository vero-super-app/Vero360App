class Driver {
  final int id;
  final int userId;
  final String licenseNumber;
  final DateTime licenseExpiry;
  final String? licenseImageUrl;
  final String nationalId;
  final String? nationalIdImageUrl;
  final String? insuranceNumber;
  final DateTime? insuranceExpiry;
  final String? insuranceImageUrl;
  final DateTime dateOfBirth;
  final String? bio;
  final double rating;
  final int totalRides;
  final int acceptedRides;
  final int cancelledRides;
  final int completedRides;
  final int reviewCount;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankCode;
  final bool isVerified;
  final bool isActive;
  final bool backgroundCheckPassed;
  final String status; // PENDING_VERIFICATION, VERIFIED, SUSPENDED, INACTIVE
  final DateTime createdAt;
  final DateTime updatedAt;

  Driver({
    required this.id,
    required this.userId,
    required this.licenseNumber,
    required this.licenseExpiry,
    this.licenseImageUrl,
    required this.nationalId,
    this.nationalIdImageUrl,
    this.insuranceNumber,
    this.insuranceExpiry,
    this.insuranceImageUrl,
    required this.dateOfBirth,
    this.bio,
    required this.rating,
    required this.totalRides,
    required this.acceptedRides,
    required this.cancelledRides,
    required this.completedRides,
    required this.reviewCount,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankCode,
    required this.isVerified,
    required this.isActive,
    required this.backgroundCheckPassed,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'] as int,
      userId: json['userId'] as int,
      licenseNumber: json['licenseNumber'] as String,
      licenseExpiry: DateTime.parse(json['licenseExpiry'] as String),
      licenseImageUrl: json['licenseImageUrl'] as String?,
      nationalId: json['nationalId'] as String,
      nationalIdImageUrl: json['nationalIdImageUrl'] as String?,
      insuranceNumber: json['insuranceNumber'] as String?,
      insuranceExpiry: json['insuranceExpiry'] != null
          ? DateTime.parse(json['insuranceExpiry'] as String)
          : null,
      insuranceImageUrl: json['insuranceImageUrl'] as String?,
      dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
      bio: json['bio'] as String?,
      rating: (json['rating'] as num).toDouble(),
      totalRides: json['totalRides'] as int,
      acceptedRides: json['acceptedRides'] as int,
      cancelledRides: json['cancelledRides'] as int,
      completedRides: json['completedRides'] as int,
      reviewCount: json['reviewCount'] as int,
      bankAccountName: json['bankAccountName'] as String?,
      bankAccountNumber: json['bankAccountNumber'] as String?,
      bankCode: json['bankCode'] as String?,
      isVerified: json['isVerified'] as bool,
      isActive: json['isActive'] as bool,
      backgroundCheckPassed: json['backgroundCheckPassed'] as bool,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'licenseNumber': licenseNumber,
      'licenseExpiry': licenseExpiry.toIso8601String(),
      'licenseImageUrl': licenseImageUrl,
      'nationalId': nationalId,
      'nationalIdImageUrl': nationalIdImageUrl,
      'insuranceNumber': insuranceNumber,
      'insuranceExpiry': insuranceExpiry?.toIso8601String(),
      'insuranceImageUrl': insuranceImageUrl,
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'bio': bio,
      'rating': rating,
      'totalRides': totalRides,
      'acceptedRides': acceptedRides,
      'cancelledRides': cancelledRides,
      'completedRides': completedRides,
      'reviewCount': reviewCount,
      'bankAccountName': bankAccountName,
      'bankAccountNumber': bankAccountNumber,
      'bankCode': bankCode,
      'isVerified': isVerified,
      'isActive': isActive,
      'backgroundCheckPassed': backgroundCheckPassed,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
