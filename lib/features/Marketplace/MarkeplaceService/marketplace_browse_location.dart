import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/location_service.dart';

/// Facebook-style marketplace browse location (city chip + optional GPS).
class MarketplaceBrowseLocation {
  MarketplaceBrowseLocation._();

  static const prefsCityKey = 'marketplace_browse_city';
  static const prefsNearMeKey = 'marketplace_browse_near_me';

  /// Cities shown in the location picker (Malawi).
  static const cities = <String>[
    'Lilongwe',
    'Blantyre',
    'Mzuzu',
    'Zomba',
    'Mangochi',
    'Karonga',
    'Kasungu',
    'Salima',
  ];

  /// Approximate city centers for soft distance ranking when GPS is on.
  static const cityCoords = <String, List<double>>{
    'Lilongwe': [-13.9626, 33.7741],
    'Blantyre': [-15.7861, 35.0058],
    'Mzuzu': [-11.4587, 34.0151],
    'Zomba': [-15.3833, 35.3333],
    'Mangochi': [-14.4781, 35.2645],
    'Karonga': [-9.9333, 33.9333],
    'Kasungu': [-13.0333, 33.4833],
    'Salima': [-13.7800, 34.4500],
  };

  static Future<String?> loadSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    final city = (prefs.getString(prefsCityKey) ?? '').trim();
    return city.isEmpty ? null : city;
  }

  static Future<bool> loadNearMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsNearMeKey) ?? true;
  }

  static Future<void> save({
    required String? city,
    required bool nearMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (city == null || city.trim().isEmpty) {
      await prefs.remove(prefsCityKey);
    } else {
      await prefs.setString(prefsCityKey, city.trim());
    }
    await prefs.setBool(prefsNearMeKey, nearMe);
  }

  /// Resolve a friendly city label from GPS (falls back to nearest known city).
  static Future<({String? city, double? lat, double? lng})> detect() async {
    final loc = LocationService();
    Position? pos = await loc.getQuickPosition();
    pos ??= await loc.getCurrentLocation();
    if (pos == null) {
      final saved = await loadSavedCity();
      return (city: saved, lat: null, lng: null);
    }
    await loc.persistPosition(pos);

    String? city;
    try {
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        final m = marks.first;
        final candidates = [
          m.locality,
          m.subAdministrativeArea,
          m.administrativeArea,
          m.name,
        ];
        for (final c in candidates) {
          final hit = matchKnownCity(c);
          if (hit != null) {
            city = hit;
            break;
          }
        }
      }
    } catch (_) {}

    city ??= nearestKnownCity(pos.latitude, pos.longitude);
    return (city: city, lat: pos.latitude, lng: pos.longitude);
  }

  static String? matchKnownCity(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final c in cities) {
      if (t.contains(c.toLowerCase())) return c;
    }
    if (t.contains('llw') || t.contains('llz')) return 'Lilongwe';
    if (t.contains('blantyre') || t.contains('bt')) return 'Blantyre';
    return null;
  }

  static String? nearestKnownCity(double lat, double lng) {
    String? best;
    var bestKm = double.infinity;
    for (final e in cityCoords.entries) {
      final d = distanceKm(lat, lng, e.value[0], e.value[1]);
      if (d != null && d < bestKm) {
        bestKm = d;
        best = e.key;
      }
    }
    // Only auto-label if within ~80km of a known city.
    if (best != null && bestKm <= 80) return best;
    return best;
  }

  static double? distanceKm(
    double? lat1,
    double? lng1,
    double? lat2,
    double? lng2,
  ) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return null;
    }
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
