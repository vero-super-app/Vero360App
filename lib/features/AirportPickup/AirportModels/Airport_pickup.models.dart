class AirportPickupRequestPayload {
  final String airportCode;       // e.g. "LLW" or "BTZ"
  final String serviceCity;       // "Lilongwe" or "Blantyre"
  final double dropoffLat;
  final double dropoffLng;
  final String vehicleId;         // "standard" | "executive"
  final double? clientFareEstimate;
  final String? dropoffAddressText;

  // Guest / contact details
  final String customerName;
  final String customerPhone;

  const AirportPickupRequestPayload({
    required this.airportCode,
    required this.serviceCity,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.vehicleId,
    this.clientFareEstimate,
    this.dropoffAddressText,
    required this.customerName,
    required this.customerPhone,
  });

  Map<String, dynamic> toJson() => {
        'airportCode': airportCode,
        'serviceCity': serviceCity,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'vehicleId': vehicleId,
        if (clientFareEstimate != null)
          'clientFareEstimate': clientFareEstimate,
        if (dropoffAddressText != null)
          'dropoffAddressText': dropoffAddressText,
        'customerName': customerName,
        'customerPhone': customerPhone,
      };
}


class AirportPickupBooking {
  final int id;
  final String airportCode;
  final String airportName;
  final String serviceCity;
  final String vehicleId;
  final String vehicleLabel;
  final double distanceKm;
  final int estimatedFare; // MWK
  final String status;     // "pending", "on_the_way", etc.

  // Optional: echo back contact details from backend if you added them
  final String? customerName;
  final String? customerPhone;
  final String? dropoffAddressText;

  AirportPickupBooking({
    required this.id,
    required this.airportCode,
    required this.airportName,
    required this.serviceCity,
    required this.vehicleId,
    required this.vehicleLabel,
    required this.distanceKm,
    required this.estimatedFare,
    required this.status,
    this.customerName,
    this.customerPhone,
    this.dropoffAddressText,
  });

  factory AirportPickupBooking.fromJson(Map<String, dynamic> json) {
    return AirportPickupBooking(
      id: json['id'] as int,
      airportCode: json['airportCode'] as String,
      airportName: json['airportName'] as String,
      serviceCity: json['serviceCity'] as String,
      vehicleId: json['vehicleId'] as String,
      vehicleLabel: json['vehicleLabel'] as String,
      distanceKm: (json['distanceKm'] as num).toDouble(),
      estimatedFare: (json['estimatedFare'] as num).toInt(),
      status: json['status'] as String,
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
      dropoffAddressText: json['dropoffAddressText'] as String?,
    );
  }
}
