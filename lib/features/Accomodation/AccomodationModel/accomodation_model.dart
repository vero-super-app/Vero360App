// lib/models/hostel_model.dart

import 'dart:convert';
import 'dart:typed_data';

/// How [Accommodation.price] is quoted (create/update sends `pricingPeriod` to the API).
enum AccommodationPricePeriod {
  night,
  day,
  month,
}

extension AccommodationPricePeriodX on AccommodationPricePeriod {
  /// JSON body value (`pricingPeriod`) when creating or updating a listing.
  String get apiValue => name;

  /// Listing suffix, e.g. ` / night`.
  String get uiSuffix => switch (this) {
        AccommodationPricePeriod.night => ' / night',
        AccommodationPricePeriod.day => ' / day',
        AccommodationPricePeriod.month => ' / month',
      };
}

AccommodationPricePeriod accommodationPricePeriodFromDynamic(Object? v) {
  if (v is num) {
    final i = v.toInt();
    if (i >= 0 && i < AccommodationPricePeriod.values.length) {
      return AccommodationPricePeriod.values[i];
    }
  }
  final s = v?.toString().trim().toLowerCase() ?? '';
  final compact = s.replaceAll(RegExp(r'[\s_-]+'), '');
  if (compact == 'perday' ||
      s == 'day' ||
      s == 'per_day' ||
      s == 'daily' ||
      compact == 'daily') {
    return AccommodationPricePeriod.day;
  }
  if (compact == 'permonth' ||
      s == 'month' ||
      s == 'per_month' ||
      s == 'monthly' ||
      compact == 'monthly') {
    return AccommodationPricePeriod.month;
  }
  if (compact == 'pernight' ||
      s == 'night' ||
      s == 'per_night' ||
      s == 'nightly' ||
      compact == 'nightly') {
    return AccommodationPricePeriod.night;
  }
  return AccommodationPricePeriod.night;
}

String labelForAccommodationPricePeriod(AccommodationPricePeriod p) {
  switch (p) {
    case AccommodationPricePeriod.night:
      return 'Per night';
    case AccommodationPricePeriod.day:
      return 'Per day';
    case AccommodationPricePeriod.month:
      return 'Per month';
  }
}

/// First non-null pricing-period hint from common API / nested `pricing` shapes.
Object? pricingPeriodRawFromAccommodationJson(Map<String, dynamic> json) {
  const keys = [
    'pricingPeriod',
    'pricePeriod',
    'billingPeriod',
    'billing_period',
    'priceUnit',
    'price_unit',
    'billingUnit',
    'billing_unit',
    'ratePeriod',
    'rate_period',
    'rateType',
    'rate_type',
  ];
  for (final k in keys) {
    if (!json.containsKey(k)) continue;
    final v = json[k];
    if (v != null) return v;
  }
  final pricing = json['pricing'];
  if (pricing is Map) {
    final m = Map<String, dynamic>.from(pricing);
    for (final k in keys) {
      if (!m.containsKey(k)) continue;
      final v = m[k];
      if (v != null) return v;
    }
    for (final k in ['period', 'unit', 'interval']) {
      final v = m[k];
      if (v != null) return v;
    }
  }
  return null;
}

class Owner {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String profilepicture;
  final bool isEmailVerified;
  final String? emailVerificationCode;
  final bool isPhoneVerified;
  final String? phoneVerificationCode;
  final String role;
  final num averageRating;
  final int reviewCount;
  final DateTime createdAt;

  Owner({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.profilepicture,
    required this.isEmailVerified,
    required this.emailVerificationCode,
    required this.isPhoneVerified,
    required this.phoneVerificationCode,
    required this.role,
    required this.averageRating,
    required this.reviewCount,
    required this.createdAt,
  });

  factory Owner.fromJson(Map<String, dynamic> json) => Owner(
        id: (json['id'] ?? 0) as int,
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        profilepicture: (json['profilepicture'] ?? '').toString(),
        isEmailVerified: (json['isEmailVerified'] ?? false) as bool,
        emailVerificationCode: json['emailVerificationCode']?.toString(),
        isPhoneVerified: (json['isPhoneVerified'] ?? false) as bool,
        phoneVerificationCode: json['phoneVerificationCode']?.toString(),
        role: (json['role'] ?? '').toString(),
        averageRating: (json['averageRating'] ?? 0),
        reviewCount: (json['reviewCount'] ?? 0) as int,
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class Accommodation {
  final int id;
  final String name;
  final String location;
  final String description;
  final int price;
  final AccommodationPricePeriod? _pricePeriod;

  /// Rate unit for [price]. Defaults to per-night when the API omits or sends an unknown value.
  AccommodationPricePeriod get pricePeriod =>
      _pricePeriod ?? AccommodationPricePeriod.night;

  final String accommodationType;
  final Owner? owner;

  /// Host Firebase UID when API exposes it (escrow / wallet). Optional.
  final String? hostMerchantUid;

  /// Image: http(s) url, gs:// url, Firebase Storage path, or base64 string
  final String? image;
  /// Decoded bytes when image is base64
  final Uint8List? imageBytes;
  /// Additional gallery URLs/paths
  final List<String> gallery;

  Accommodation({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.price,
    AccommodationPricePeriod? pricePeriod,
    required this.accommodationType,
    this.owner,
    this.hostMerchantUid,
    this.image,
    this.imageBytes,
    this.gallery = const [],
  }) : _pricePeriod = pricePeriod;

  /// Same listing with an explicit rate unit (e.g. after merging Firestore `pricingPeriod`).
  Accommodation withPricingPeriod(AccommodationPricePeriod period) {
    return Accommodation(
      id: id,
      name: name,
      location: location,
      description: description,
      price: price,
      pricePeriod: period,
      accommodationType: accommodationType,
      owner: owner,
      hostMerchantUid: hostMerchantUid,
      image: image,
      imageBytes: imageBytes,
      gallery: gallery,
    );
  }

  /// Prefer values that look like Firebase Auth UIDs for escrow + `order_party_alerts`.
  static bool _looksLikeFirebaseUid(String s) {
    return looksLikeFirebaseAuthUid(s);
  }

  /// Public for booking / notifications when the API may send numeric ids elsewhere.
  static bool looksLikeFirebaseAuthUid(String? s) {
    if (s == null) return false;
    final t = s.trim();
    if (t.length < 20 || t.length > 128) return false;
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(t);
  }

  static String? _resolveHostFirebaseUid(
    Map<String, dynamic> json,
    Map<String, dynamic>? ownerMap,
  ) {
    final candidates = <String>[];

    void take(Object? o) {
      final s = o?.toString().trim();
      if (s != null && s.isNotEmpty) candidates.add(s);
    }

    if (ownerMap != null) {
      for (final k in [
        'firebaseUid',
        'firebase_uid',
        'firebaseUserId',
        'firebase_user_id',
        'uid',
        'merchantUid',
        'userId',
        'id',
      ]) {
        take(ownerMap[k]);
      }
    }
    for (final k in [
      'hostUid',
      'hostMerchantUid',
      'merchantFirebaseUid',
      'merchantFirebase',
      'merchantId',
    ]) {
      take(json[k]);
    }

    for (final c in candidates) {
      if (_looksLikeFirebaseUid(c)) return c;
    }
    return candidates.isNotEmpty ? candidates.first : null;
  }

  static bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.length < 150) return false;
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  factory Accommodation.fromJson(Map<String, dynamic> json) {
    final rawImage = (json['image'] ?? json['imageUrl'] ?? '').toString().trim();
    Uint8List? imageBytes;
    if (rawImage.isNotEmpty && _looksLikeBase64(rawImage)) {
      try {
        final base64Part = rawImage.contains(',') ? rawImage.split(',').last : rawImage;
        imageBytes = base64Decode(base64Part);
      } catch (_) {}
    }
    List<String> gallery = const [];
    final galleryRaw = json['gallery'];
    if (galleryRaw is List) {
      gallery = galleryRaw.map((e) => e.toString()).toList();
    }
    final priceRaw = json['pricePerNight'] ?? json['price'];
    final ownerMap = json['owner'] is Map
        ? Map<String, dynamic>.from(json['owner'] as Map)
        : null;
    // Firestore host alerts need the host’s Firebase UID, not always numeric merchantId.
    final hostUid = _resolveHostFirebaseUid(json, ownerMap);
    return Accommodation(
      id: (json['id'] ?? 0) as int,
      name: (json['name'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: priceRaw is num
          ? priceRaw.toInt()
          : int.tryParse(priceRaw?.toString() ?? '0') ?? 0,
      pricePeriod: accommodationPricePeriodFromDynamic(
        pricingPeriodRawFromAccommodationJson(json),
      ),
      accommodationType: (json['accommodationType'] ?? '').toString(),
      owner: ownerMap != null ? Owner.fromJson(ownerMap) : null,
      hostMerchantUid: hostUid,
      image: rawImage.isEmpty ? null : rawImage,
      imageBytes: imageBytes,
      gallery: gallery,
    );
  }
}
