import 'dart:math' as math;

/// Quote for a same-city Vero Courier job (Lilongwe launch pricing).
class CourierPriceQuote {
  final double distanceKm;
  final int etaMinutes;
  final int amountMwk;
  final String goodsType;
  final String summary;

  const CourierPriceQuote({
    required this.distanceKm,
    required this.etaMinutes,
    required this.amountMwk,
    required this.goodsType,
    required this.summary,
  });
}

/// Estimates MWK from driving distance + goods type / description.
class CourierPricing {
  CourierPricing._();

  static const int baseMwk = 1800;
  static const int perKmMwk = 500;
  static const double minChargeKm = 1.5;

  static CourierPriceQuote estimate({
    required double distanceKm,
    String? goodsType,
    String? description,
    int? etaMinutes,
  }) {
    final km = distanceKm.isFinite && distanceKm > 0 ? distanceKm : minChargeKm;
    final billedKm = math.max(km, minChargeKm);
    final type = (goodsType ?? 'Other').trim();
    final desc = (description ?? '').trim();

    var amount = baseMwk + (billedKm * perKmMwk);
    amount *= _goodsMultiplier(type);
    amount *= _descriptionMultiplier('$type $desc');

    final rounded = _roundToFifty(amount.round());
    final eta = etaMinutes ?? math.max(15, (km / 22 * 60).round() + 8);

    return CourierPriceQuote(
      distanceKm: km,
      etaMinutes: eta,
      amountMwk: rounded,
      goodsType: type.isEmpty ? 'Other' : type,
      summary:
          'About MWK ${_fmt(rounded)} · ${km.toStringAsFixed(1)} km · ~$eta min',
    );
  }

  static double _goodsMultiplier(String type) {
    switch (type.toLowerCase()) {
      case 'documents':
        return 1.0;
      case 'clothes':
        return 1.03;
      case 'groceries':
        return 1.08;
      case 'food':
        return 1.10;
      case 'electronics':
        return 1.15;
      case 'fragile item':
        return 1.18;
      default:
        return 1.05;
    }
  }

  static double _descriptionMultiplier(String text) {
    final t = text.toLowerCase();
    var m = 1.0;
    if (RegExp(r'\b(fragile|glass|breakable|ceramic)\b').hasMatch(t)) {
      m += 0.08;
    }
    if (RegExp(r'\b(heavy|bulky|furniture|fridge|mattress)\b').hasMatch(t)) {
      m += 0.12;
    }
    if (RegExp(r'\b(urgent|express|asap|same[- ]?day)\b').hasMatch(t)) {
      m += 0.08;
    }
    if (RegExp(r'\b(envelope|letter|small|light)\b').hasMatch(t)) {
      m -= 0.06;
    }
    return m < 0.92 ? 0.92 : m;
  }

  static int _roundToFifty(int n) {
    if (n < 1000) return 1000;
    return ((n + 25) ~/ 50) * 50;
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static double haversineKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthKm = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
