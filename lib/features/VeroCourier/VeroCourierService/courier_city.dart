/// Supported Vero Courier cities — intra-city deliveries only.
enum CourierServiceCity {
  lilongwe,
  blantyre,
  zomba,
}

class CourierCityHelper {
  CourierCityHelper._();

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

  /// Resolves free text / GPS locality / airport codes to a supported city.
  static CourierServiceCity? resolve(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;

    // Airport / short codes first (whole-token friendly).
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
        'Vero Courier is within-city only — not $required to $otherNames.';
  }

  static bool isSupported(String? raw) => resolve(raw) != null;
}
