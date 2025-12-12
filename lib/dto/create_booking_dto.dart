class CreateBookingDto {
  final int carId;
  final DateTime startDate;
  final DateTime endDate;
  final String? pickupLocation;
  final String? returnLocation;
  final bool? includeInsurance;
  final List<String>? extras; // GPS tracking, roadside assistance, etc
  final String? notes;
  final String? promoCode;

  const CreateBookingDto({
    required this.carId,
    required this.startDate,
    required this.endDate,
    this.pickupLocation,
    this.returnLocation,
    this.includeInsurance,
    this.extras,
    this.notes,
    this.promoCode,
  });

  Map<String, dynamic> toJson() => {
        'carId': carId,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'pickupLocation': pickupLocation,
        'returnLocation': returnLocation,
        'includeInsurance': includeInsurance ?? false,
        'extras': extras ?? [],
        'notes': notes,
        'promoCode': promoCode,
      };

  factory CreateBookingDto.fromJson(Map<String, dynamic> json) {
    return CreateBookingDto(
      carId: json['carId'] ?? 0,
      startDate: DateTime.parse(json['startDate'] ?? DateTime.now().toIso8601String()),
      endDate: DateTime.parse(json['endDate'] ?? DateTime.now().toIso8601String()),
      pickupLocation: json['pickupLocation'],
      returnLocation: json['returnLocation'],
      includeInsurance: json['includeInsurance'],
      extras: json['extras'] != null ? List<String>.from(json['extras']) : null,
      notes: json['notes'],
      promoCode: json['promoCode'],
    );
  }
}

class BookingConfirmationDto {
  final int bookingId;
  final String confirmationCode;
  final DateTime confirmedAt;
  final double totalCost;
  final String status;

  const BookingConfirmationDto({
    required this.bookingId,
    required this.confirmationCode,
    required this.confirmedAt,
    required this.totalCost,
    required this.status,
  });

  factory BookingConfirmationDto.fromJson(Map<String, dynamic> json) {
    return BookingConfirmationDto(
      bookingId: json['bookingId'] ?? 0,
      confirmationCode: json['confirmationCode'] ?? '',
      confirmedAt: DateTime.parse(json['confirmedAt'] ?? DateTime.now().toIso8601String()),
      totalCost: (json['totalCost'] ?? 0).toDouble(),
      status: json['status'] ?? 'CONFIRMED',
    );
  }

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'confirmationCode': confirmationCode,
        'confirmedAt': confirmedAt.toIso8601String(),
        'totalCost': totalCost,
        'status': status,
      };
}

class CompleteRentalDto {
  final int bookingId;
  final double finalOdometerReading;
  final String? damageReport;
  final List<String>? damagePhotos;
  final double? additionalCharges;
  final String? notes;

  const CompleteRentalDto({
    required this.bookingId,
    required this.finalOdometerReading,
    this.damageReport,
    this.damagePhotos,
    this.additionalCharges,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'finalOdometerReading': finalOdometerReading,
        'damageReport': damageReport,
        'damagePhotos': damagePhotos ?? [],
        'additionalCharges': additionalCharges ?? 0,
        'notes': notes,
      };
}
