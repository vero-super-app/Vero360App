class CreateCourierDeliveryDto {
  final String courierPhone;
  final String courierEmail;
  final String courierCity;
  final String pickupLocation;
  final String dropoffLocation;
  final String? typeOfGoods;
  final String? descriptionOfGoods;
  final String? additionalInformation;

  const CreateCourierDeliveryDto({
    required this.courierPhone,
    required this.courierEmail,
    required this.courierCity,
    required this.pickupLocation,
    required this.dropoffLocation,
    this.typeOfGoods,
    this.descriptionOfGoods,
    this.additionalInformation,
  });

  Map<String, dynamic> toJson() => {
        'CourierPhone': courierPhone,
        'CourierEmail': courierEmail,
        'CourierCity': courierCity,
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        if (typeOfGoods != null && typeOfGoods!.trim().isNotEmpty)
          'TypeOfGoods': typeOfGoods,
        if (descriptionOfGoods != null && descriptionOfGoods!.trim().isNotEmpty)
          'DescriptionOfGoods': descriptionOfGoods,
        if (additionalInformation != null &&
            additionalInformation!.trim().isNotEmpty)
          'AdditionalInformation': additionalInformation,
      };
}

enum CourierStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  onTheWay('ON_THE_WAY'),
  delivered('DELIVERED'),
  cancelled('CANCELLED');

  final String value;
  const CourierStatus(this.value);

  static CourierStatus fromValue(String raw) {
    return CourierStatus.values.firstWhere(
      (s) => s.value == raw.toUpperCase(),
      orElse: () => CourierStatus.pending,
    );
  }
}

class CourierDelivery {
  final int courierId;
  final String courierPhone;
  final String courierEmail;
  final String courierCity;
  final String pickupLocation;
  final String dropoffLocation;
  final String? typeOfGoods;
  final String? descriptionOfGoods;
  final String? additionalInformation;
  final CourierStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CourierDelivery({
    required this.courierId,
    required this.courierPhone,
    required this.courierEmail,
    required this.courierCity,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.typeOfGoods,
    required this.descriptionOfGoods,
    required this.additionalInformation,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CourierDelivery.fromJson(Map<String, dynamic> json) {
    final statusRaw = (json['CourierStatus'] ?? json['status'] ?? 'PENDING')
        .toString();
    return CourierDelivery(
      courierId: _toInt(json['CourierID'] ?? json['id']) ?? 0,
      courierPhone: (json['CourierPhone'] ?? '').toString(),
      courierEmail: (json['CourierEmail'] ?? '').toString(),
      courierCity: (json['CourierCity'] ?? '').toString(),
      pickupLocation: (json['pickupLocation'] ?? '').toString(),
      dropoffLocation: (json['dropoffLocation'] ?? '').toString(),
      typeOfGoods: _toNullableString(json['TypeOfGoods']),
      descriptionOfGoods: _toNullableString(json['DescriptionOfGoods']),
      additionalInformation: _toNullableString(json['AdditionalInformation']),
      status: CourierStatus.fromValue(statusRaw),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _toNullableString(dynamic value) {
    if (value == null) return null;
    final parsed = value.toString().trim();
    return parsed.isEmpty ? null : parsed;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
