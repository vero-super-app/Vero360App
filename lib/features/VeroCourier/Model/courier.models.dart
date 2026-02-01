// lib/models/courier.models.dart

/// Local (Lilongwe-only) courier request payload
class CourierLocalRequestPayload {
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final String vehicleId; // "bike" | "car" | "van"
  final double? clientFareEstimate;
  final String? notes;

  const CourierLocalRequestPayload({
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.vehicleId,
    this.clientFareEstimate,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'vehicleId': vehicleId,
        if (clientFareEstimate != null)
          'clientFareEstimate': clientFareEstimate,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
      };
}

/// Inter-district courier request payload
class CourierIntercityRequestPayload {
  final double pickupLat;
  final double pickupLng;
  final String destinationDistrict;
  final String destinationAddressText; // receiver name, phone, address
  final String courierName; // "Speed Courier", "CTS Courier", etc.
  final String? notes;

  const CourierIntercityRequestPayload({
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationDistrict,
    required this.destinationAddressText,
    required this.courierName,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'destinationDistrict': destinationDistrict,
        'destinationAddressText': destinationAddressText,
        'courierName': courierName,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
      };
}

/// Mirrors src/entities/courier-delivery.entity.ts
class CourierDeliveryBooking {
  final int id;
  final int? userId;
  final String mode; // "LOCAL" | "INTERCITY"
  final double pickupLat;
  final double pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? destinationDistrict;
  final String? destinationAddressText;
  final String? courierName;
  final String? vehicleId;
  final String? vehicleLabel;
  final double? distanceKm;
  final int? estimatedFare; // MWK
  final int? clientFareEstimate; // MWK
  final String? notes;
  final String status; // "PENDING", "ON_THE_WAY", etc.
  final DateTime createdAt;
  final DateTime updatedAt;

  CourierDeliveryBooking({
    required this.id,
    required this.userId,
    required this.mode,
    required this.pickupLat,
    required this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.destinationDistrict,
    this.destinationAddressText,
    this.courierName,
    this.vehicleId,
    this.vehicleLabel,
    this.distanceKm,
    this.estimatedFare,
    this.clientFareEstimate,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CourierDeliveryBooking.fromJson(Map<String, dynamic> json) {
    return CourierDeliveryBooking(
      id: json['id'] as int,
      userId: json['userId'] as int?,
      mode: json['mode'] as String,
      pickupLat: (json['pickupLat'] as num).toDouble(),
      pickupLng: (json['pickupLng'] as num).toDouble(),
      dropoffLat: (json['dropoffLat'] as num?)?.toDouble(),
      dropoffLng: (json['dropoffLng'] as num?)?.toDouble(),
      destinationDistrict: json['destinationDistrict'] as String?,
      destinationAddressText: json['destinationAddressText'] as String?,
      courierName: json['courierName'] as String?,
      vehicleId: json['vehicleId'] as String?,
      vehicleLabel: json['vehicleLabel'] as String?,
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      estimatedFare: (json['estimatedFare'] as num?)?.toInt(),
      clientFareEstimate: (json['clientFareEstimate'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
