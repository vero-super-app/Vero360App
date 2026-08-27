import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Web-safe geocoding helpers for courier fare estimates.
///
/// Google Geocoding/Directions JSON APIs are blocked by CORS in browsers, so
/// on web we fall back to OpenStreetMap Nominatim + Lilongwe landmark hints.
class CourierGeocode {
  CourierGeocode._();

  static const _timeout = Duration(seconds: 8);

  /// Approximate known Lilongwe places when network geocode fails.
  static const Map<String, (double, double)> lilongweLandmarks = {
    'area 3': (-13.9833, 33.7875),
    'area 6': (-13.9750, 33.7850),
    'area 9': (-13.9680, 33.7900),
    'area 10': (-13.9620, 33.7870),
    'area 12': (-13.9550, 33.7800),
    'area 15': (-13.9580, 33.7700),
    'area 18': (-13.9500, 33.7600),
    'area 22': (-13.9450, 33.7750),
    'area 25': (-13.9400, 33.7800),
    'area 43': (-14.0000, 33.7500),
    'area 47': (-14.0200, 33.7800),
    'area 49': (-14.0300, 33.7850),
    'city centre': (-13.9830, 33.7740),
    'city center': (-13.9830, 33.7740),
    'old town': (-13.9890, 33.7700),
    'capital hill': (-13.9670, 33.7890),
    'kanengo': (-13.9200, 33.7400),
    'kawale': (-13.9900, 33.8000),
    'falls': (-14.0200, 33.7700),
    'crossroads': (-13.9700, 33.7800),
    'gateway': (-13.9600, 33.7900),
    'gateway mall': (-13.9600, 33.7900),
    'bunda': (-14.1700, 33.7700),
    'kamuzu central': (-13.9780, 33.7870),
    'kamuzu international': (-13.7890, 33.7810),
    'airport': (-13.7890, 33.7810),
    'lilongwe': (-13.9626, 33.7741),
  };

  static (double, double)? landmarkPoint(String label) {
    final t = label.toLowerCase().trim();
    if (t.isEmpty) return null;

    final areaMatch = RegExp(r'\barea\s*(\d+)\b').firstMatch(t);
    if (areaMatch != null) {
      final key = 'area ${areaMatch.group(1)}';
      final hit = lilongweLandmarks[key];
      if (hit != null) return hit;
    }

    for (final entry in lilongweLandmarks.entries) {
      if (entry.key == 'lilongwe') continue;
      if (t.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Nominatim search (CORS-friendly). Prefer for Flutter web.
  static Future<(double, double)?> nominatim(String label) async {
    final q = label.trim();
    if (q.isEmpty) return null;
    final query = q.toLowerCase().contains('malawi') ? q : '$q, Malawi';
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'json',
          'limit': '1',
          'countrycodes': 'mw',
          'addressdetails': '0',
        },
      );
      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          // Browsers override User-Agent; still set for non-web isolates.
          'User-Agent': 'Vero360Courier/1.0 (fare-estimate)',
        },
      ).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      if (lat == null || lon == null) return null;
      if (lat.abs() < 0.0001 || lon.abs() < 0.0001) return null;
      return (lat, lon);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CourierGeocode] nominatim failed for "$q": $e');
      }
      return null;
    }
  }
}
