// lib/models/address_model.dart
import 'dart:convert';

/// Keep these string values aligned with your backend enum.
enum AddressType { home, work, business, other }

AddressType addressTypeFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'home':
      return AddressType.home;
    case 'work':
      return AddressType.work;
    case 'business':
      return AddressType.business;
    default:
      return AddressType.other;
  }
}

String addressTypeToString(AddressType t) {
  switch (t) {
    case AddressType.home:
      return 'home';
    case AddressType.work:
      return 'work';
    case AddressType.business:
      return 'business';
    case AddressType.other:
      return 'other';
  }
}

class Address {
  final String id;                 // maps to backend addressId (stringified)
  final AddressType addressType;
  final String city;               // quick label / manual city
  final String description;
  final bool isDefault;

  // Google-backed fields
  final bool isGoogle;
  final String formattedAddress;   // pretty line from Google
  final String placeId;
  final double? lat;
  final double? lng;

  Address({
    required this.id,
    required this.addressType,
    required this.city,
    required this.description,
    this.isDefault = false,
    this.isGoogle = false,
    this.formattedAddress = '',
    this.placeId = '',
    this.lat,
    this.lng,
  });

  /// Prefer displaying this line in UI.
  String get displayLine =>
      (isGoogle && formattedAddress.isNotEmpty) ? formattedAddress : city;

  factory Address.fromJson(Map<String, dynamic> json) {
    // Some APIs return addressId, others id/_id. We normalize to string.
    final id = (json['addressId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    final latRaw = json['lat'];
    final lngRaw = json['lng'];

    return Address(
      id: id,
      addressType: addressTypeFromString(json['addressType'] as String?),
      city: (json['city'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      isDefault: json['isDefault'] == true,
      isGoogle: json['isGoogle'] == true,
      formattedAddress: (json['formattedAddress'] ?? '').toString(),
      placeId: (json['placeId'] ?? '').toString(),
      lat: latRaw == null ? null : double.tryParse(latRaw.toString()),
      lng: lngRaw == null ? null : double.tryParse(lngRaw.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'addressType': addressTypeToString(addressType),
        'city': city,
        'description': description,
        'isDefault': isDefault,
        'isGoogle': isGoogle,
        'formattedAddress': formattedAddress,
        'placeId': placeId,
        'lat': lat,
        'lng': lng,
      };

  Address copyWith({
    String? id,
    AddressType? addressType,
    String? city,
    String? description,
    bool? isDefault,
    bool? isGoogle,
    String? formattedAddress,
    String? placeId,
    double? lat,
    double? lng,
  }) {
    return Address(
      id: id ?? this.id,
      addressType: addressType ?? this.addressType,
      city: city ?? this.city,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      isGoogle: isGoogle ?? this.isGoogle,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      placeId: placeId ?? this.placeId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Payload for create/update calls.
class AddressPayload {
  final AddressType addressType;
  final String city;
  final String description;

  final bool? isDefault;

  // Optional Google fields
  final bool? isGoogle;
  final String? formattedAddress;
  final String? placeId;
  final double? lat;
  final double? lng;

  AddressPayload({
    required this.addressType,
    required this.city,
    required this.description,
    this.isDefault,
    this.isGoogle,
    this.formattedAddress,
    this.placeId,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'addressType': addressTypeToString(addressType),
        'city': city,
        'description': description,
        if (isDefault != null) 'isDefault': isDefault,
        if (isGoogle != null) 'isGoogle': isGoogle,
        if (formattedAddress != null) 'formattedAddress': formattedAddress,
        if (placeId != null) 'placeId': placeId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  AddressPayload copyWith({
    AddressType? addressType,
    String? city,
    String? description,
    bool? isDefault,
    bool? isGoogle,
    String? formattedAddress,
    String? placeId,
    double? lat,
    double? lng,
  }) {
    return AddressPayload(
      addressType: addressType ?? this.addressType,
      city: city ?? this.city,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      isGoogle: isGoogle ?? this.isGoogle,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      placeId: placeId ?? this.placeId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
