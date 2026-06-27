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

  /// Structured view of [additionalInformation] plus top-level sender fields.
  CourierDeliveryView get view => CourierDeliveryView.fromDelivery(this);
}

/// Parsed sender/receiver/notes from pipe-separated [additionalInformation].
class CourierDeliveryView {
  final String? senderName;
  final String senderPhone;
  final String senderCity;
  final String? recipientName;
  final String? recipientPhone;
  final String? recipientAddress;
  final String? notes;

  const CourierDeliveryView({
    this.senderName,
    required this.senderPhone,
    required this.senderCity,
    this.recipientName,
    this.recipientPhone,
    this.recipientAddress,
    this.notes,
  });

  factory CourierDeliveryView.fromDelivery(CourierDelivery d) {
    final parsed = _parseAdditionalInfo(d.additionalInformation);
    return CourierDeliveryView(
      senderName: parsed.senderName,
      senderPhone: d.courierPhone.trim(),
      senderCity: d.courierCity.trim(),
      recipientName: parsed.recipientName,
      recipientPhone: parsed.recipientPhone,
      recipientAddress: parsed.recipientAddress,
      notes: parsed.notes,
    );
  }

  static ({
    String? senderName,
    String? recipientName,
    String? recipientPhone,
    String? recipientAddress,
    String? notes,
  }) _parseAdditionalInfo(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return (
        senderName: null,
        recipientName: null,
        recipientPhone: null,
        recipientAddress: null,
        notes: null,
      );
    }

    String? senderName;
    String? recipientName;
    String? recipientPhone;
    String? recipientAddress;
    final noteParts = <String>[];

    for (final part in raw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      final lower = part.toLowerCase();
      if (lower.startsWith('sender:')) {
        senderName = part.substring(part.indexOf(':') + 1).trim();
      } else if (lower.startsWith('recipient phone:')) {
        recipientPhone = part.substring(part.indexOf(':') + 1).trim();
      } else if (lower.startsWith('recipient address:')) {
        recipientAddress = part.substring(part.indexOf(':') + 1).trim();
      } else if (lower.startsWith('recipient:')) {
        recipientName = part.substring(part.indexOf(':') + 1).trim();
      } else {
        noteParts.add(part);
      }
    }

    final notes = noteParts.isEmpty ? null : noteParts.join(' · ');
    return (
      senderName: senderName,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      recipientAddress: recipientAddress,
      notes: notes,
    );
  }
}
