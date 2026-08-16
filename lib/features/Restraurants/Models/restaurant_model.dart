import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore collection: `restaurants`.
///
/// Migration: existing `food_menu_items` documents do not have `restaurantId`
/// yet. Until a backfill script runs (not in this pass), the app must not
/// crash when `restaurantId` is null — keep using [businessName] /
/// [FoodModel.RestrauntName] as the grouping/display fallback, same as today.
class RestaurantModel {
  final String id;
  final String ownerUid;
  final String businessName;
  final String logoUrl;
  final String coverImageUrl;
  final String description;
  final String address;
  final double? latitude;
  final double? longitude;
  final double deliveryRadiusKm;
  final double minOrderMwk;
  final int avgPrepTimeMinutes;
  final bool isOpen;
  final Map<String, String> openingHours;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RestaurantModel({
    required this.id,
    required this.ownerUid,
    required this.businessName,
    this.logoUrl = '',
    this.coverImageUrl = '',
    this.description = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.deliveryRadiusKm = 15,
    this.minOrderMwk = 0,
    this.avgPrepTimeMinutes = 25,
    this.isOpen = false,
    this.openingHours = const {},
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory RestaurantModel.fromJson(Map<String, dynamic> json) {
    int safeInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    double safeDouble(dynamic v, {double fallback = 0}) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }

    double? optDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String str(dynamic v) => (v == null) ? '' : v.toString();

    String? optStr(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    bool asBool(dynamic v, {bool fallback = false}) {
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return fallback;
    }

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          v > 9999999999 ? v : v * 1000,
        );
      }
      return DateTime.tryParse(v.toString());
    }

    Map<String, String> hours(dynamic v) {
      if (v is! Map) return const {};
      final out = <String, String>{};
      v.forEach((key, val) {
        final k = key.toString().trim();
        final s = val?.toString().trim() ?? '';
        if (k.isNotEmpty && s.isNotEmpty) out[k] = s;
      });
      return out;
    }

    return RestaurantModel(
      id: optStr(json['id']) ?? '',
      ownerUid: optStr(json['ownerUid']) ?? optStr(json['merchantId']) ?? '',
      businessName: str(json['businessName']).trim().isNotEmpty
          ? str(json['businessName']).trim()
          : str(json['name']).trim(),
      logoUrl: str(json['logoUrl']).trim().isNotEmpty
          ? str(json['logoUrl']).trim()
          : str(json['logo']).trim(),
      coverImageUrl: str(json['coverImageUrl']).trim().isNotEmpty
          ? str(json['coverImageUrl']).trim()
          : str(json['coverUrl']).trim(),
      description: str(json['description']),
      address: str(json['address']),
      latitude: optDouble(json['latitude'] ?? json['lat']),
      longitude: optDouble(json['longitude'] ?? json['lng']),
      deliveryRadiusKm: safeDouble(json['deliveryRadiusKm'], fallback: 15),
      minOrderMwk: safeDouble(json['minOrderMwk']),
      avgPrepTimeMinutes: safeInt(json['avgPrepTimeMinutes'], fallback: 25),
      isOpen: asBool(json['isOpen']),
      openingHours: hours(json['openingHours']),
      isActive: asBool(json['isActive'], fallback: true),
      createdAt: asDate(json['createdAt']),
      updatedAt: asDate(json['updatedAt']),
    );
  }

  factory RestaurantModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return RestaurantModel.fromJson({...data, 'id': doc.id});
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerUid': ownerUid,
        'businessName': businessName,
        'logoUrl': logoUrl,
        'coverImageUrl': coverImageUrl,
        'description': description,
        'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'deliveryRadiusKm': deliveryRadiusKm,
        'minOrderMwk': minOrderMwk,
        'avgPrepTimeMinutes': avgPrepTimeMinutes,
        'isOpen': isOpen,
        'openingHours': openingHours,
        'isActive': isActive,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
