import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported Vero Courier cities — intra-city deliveries only.
/// Launch city is Lilongwe; other cities stay listed for “expanding soon”.
enum CourierServiceCity {
  lilongwe,
  blantyre,
  zomba,
}

class CourierCityHelper {
  CourierCityHelper._();

  /// Currently live for bookings.
  static const CourierServiceCity launchCity = CourierServiceCity.lilongwe;

  static bool isLive(CourierServiceCity city) => city == launchCity;

  static String displayName(CourierServiceCity city) {
    switch (city) {
      case CourierServiceCity.lilongwe:
        return 'Lilongwe';
      case CourierServiceCity.blantyre:
        return 'Blantyre';
      case CourierServiceCity.zomba:
        return 'Zomba';
    }
  }

  static String shortCode(CourierServiceCity city) {
    switch (city) {
      case CourierServiceCity.lilongwe:
        return 'LLZ';
      case CourierServiceCity.blantyre:
        return 'BTZ';
      case CourierServiceCity.zomba:
        return 'Zomba';
    }
  }

  /// Approximate GPS box for Lilongwe metro (backup if geocode is vague).
  static bool isInLilongweBounds(double lat, double lng) {
    return lat >= -14.22 && lat <= -13.72 && lng >= 33.50 && lng <= 34.18;
  }

  /// Resolves free text / GPS locality / airport codes to a supported city.
  static CourierServiceCity? resolve(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;

    if (RegExp(r'\b(llz|llw)\b').hasMatch(t) ||
        t.contains('lilongwe') ||
        t == 'll') {
      return CourierServiceCity.lilongwe;
    }
    if (RegExp(r'\b(btz|blz)\b').hasMatch(t) ||
        t.contains('blantyre') ||
        t == 'bt' ||
        t == 'btz') {
      return CourierServiceCity.blantyre;
    }
    if (t.contains('zomba')) {
      return CourierServiceCity.zomba;
    }
    return null;
  }

  /// All supported cities mentioned in [text] (for conflict checks).
  static Set<CourierServiceCity> citiesMentioned(String? text) {
    final t = (text ?? '').trim().toLowerCase();
    if (t.isEmpty) return {};
    final found = <CourierServiceCity>{};
    if (RegExp(r'\b(llz|llw)\b').hasMatch(t) || t.contains('lilongwe')) {
      found.add(CourierServiceCity.lilongwe);
    }
    if (RegExp(r'\b(btz|blz)\b').hasMatch(t) || t.contains('blantyre')) {
      found.add(CourierServiceCity.blantyre);
    }
    if (t.contains('zomba')) {
      found.add(CourierServiceCity.zomba);
    }
    return found;
  }

  static String expandingSoonMessage({CourierServiceCity? detected}) {
    if (detected == null) {
      return 'Vero Courier is only available in Lilongwe for now. '
          'We are expanding soon.';
    }
    if (!isLive(detected)) {
      return 'Vero Courier is not in ${displayName(detected)} yet. '
          'It is live in Lilongwe — we are expanding soon.';
    }
    return 'Within Lilongwe only (LLZ → LLZ). Pickup and delivery must stay in Lilongwe.';
  }

  /// Returns a user-facing error if [text] names a different city than [required].
  static String? conflictMessage({
    required String? text,
    required CourierServiceCity requiredCity,
    required String fieldLabel,
  }) {
    final mentioned = citiesMentioned(text);
    if (mentioned.isEmpty) return null;
    if (mentioned.length == 1 && mentioned.contains(requiredCity)) return null;

    final others = mentioned.where((c) => c != requiredCity).toList();
    if (others.isEmpty) return null;

    final required = displayName(requiredCity);
    final otherNames = others.map(displayName).join(' / ');
    return '$fieldLabel must stay in $required. '
        'Vero Courier is Lilongwe-only for now — not $required to $otherNames. '
        'We are expanding soon.';
  }

  static bool isSupported(String? raw) {
    final city = resolve(raw);
    return city != null && isLive(city);
  }

  /// True when free-text and/or GPS place the point in live Lilongwe.
  static bool isLilongwe({
    String? text,
    double? lat,
    double? lng,
  }) {
    if (resolve(text) == CourierServiceCity.lilongwe) return true;
    if (lat != null && lng != null && isInLilongweBounds(lat, lng)) {
      return true;
    }
    return false;
  }

  static String _mapLocationText(Map<String, dynamic> d) {
    return [
      d['city'],
      d['location'],
      d['businessAddress'],
      d['address'],
      d['formattedAddress'],
      d['pickupAddress'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
  }

  static double? _mapDouble(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is num) return v.toDouble();
      final n = double.tryParse('${v ?? ''}');
      if (n != null) return n;
    }
    return null;
  }

  /// Shop / restaurant docs for [merchantId] that look like Lilongwe.
  static Future<bool> merchantIsInLilongwe(String? merchantId) async {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty || id == 'unknown' || id == 'marketplace') return false;
    try {
      final db = FirebaseFirestore.instance;
      for (final col in const [
        'marketplace_merchants',
        'food_merchants',
        'restaurants',
        'users',
      ]) {
        final doc = await db.collection(col).doc(id).get();
        if (!doc.exists || doc.data() == null) continue;
        final d = doc.data()!;
        if (isLilongwe(
          text: _mapLocationText(d),
          lat: _mapDouble(d, const ['latitude', 'lat']),
          lng: _mapDouble(d, const ['longitude', 'lng', 'lon']),
        )) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}
