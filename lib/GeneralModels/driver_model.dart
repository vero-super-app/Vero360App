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
  final String status; // PENDING_VERIFICATION, VERIFIED, REJECTED, SUSPENDED, INACTIVE
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>> taxis;

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
    this.rejectionReason,
    this.submittedAt,
    required this.createdAt,
    required this.updatedAt,
    this.taxis = const [],
  });

  bool get isRejected => status == 'REJECTED';
  bool get isPendingVerification => status == 'PENDING_VERIFICATION';
  bool get hasLicenseDocs =>
      licenseImageUrl?.trim().isNotEmpty ?? false;

  Map<String, dynamic>? get primaryTaxi =>
      taxis.isEmpty ? null : taxis.first;

  bool get hasActiveVehicle {
    final t = primaryTaxi;
    if (t == null) return false;
    return (t['status']?.toString() ?? '') == 'ACTIVE';
  }

  bool get hasPendingVehicle {
    final t = primaryTaxi;
    if (t == null) return false;
    return (t['status']?.toString() ?? '') == 'PENDING_REVIEW';
  }

  bool get canGoOnline =>
      isVerified && isActive && hasActiveVehicle && !isRejected;

  factory Driver.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parseTaxis(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return Driver(
      id: json['id'] as int,
      userId: json['userId'] as int,
      licenseNumber: (json['licenseNumber'] as String?) ?? '',
      licenseExpiry: parseDate(json['licenseExpiry']) ?? DateTime.now(),
      licenseImageUrl: json['licenseImageUrl'] as String?,
      nationalId: (json['nationalId'] as String?) ?? '',
      nationalIdImageUrl: json['nationalIdImageUrl'] as String?,
      insuranceNumber: json['insuranceNumber'] as String?,
      insuranceExpiry: parseDate(json['insuranceExpiry']),
      insuranceImageUrl: json['insuranceImageUrl'] as String?,
      dateOfBirth: parseDate(json['dateOfBirth']) ?? DateTime.now(),
      bio: json['bio'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalRides: (json['totalRides'] as num?)?.toInt() ?? 0,
      acceptedRides: (json['acceptedRides'] as num?)?.toInt() ?? 0,
      cancelledRides: (json['cancelledRides'] as num?)?.toInt() ?? 0,
      completedRides: (json['completedRides'] as num?)?.toInt() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      bankAccountName: json['bankAccountName'] as String?,
      bankAccountNumber: json['bankAccountNumber'] as String?,
      bankCode: json['bankCode'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      backgroundCheckPassed: json['backgroundCheckPassed'] as bool? ?? false,
      status: (json['status'] as String?) ?? 'PENDING_VERIFICATION',
      rejectionReason: json['rejectionReason'] as String?,
      submittedAt: parseDate(json['submittedAt']),
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: parseDate(json['updatedAt']) ?? DateTime.now(),
      taxis: parseTaxis(json['taxis']),
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
      'rejectionReason': rejectionReason,
      'submittedAt': submittedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'taxis': taxis,
    };
  }
}
