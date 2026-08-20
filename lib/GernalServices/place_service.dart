import 'dart:math';
import 'package:geocoding/geocoding.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GernalServices/google_places_service.dart';

class PlaceService {
  static const String mallawiCountryCode = 'MW';

  /// Search for places in Malawi only
  Future<List<Place>> searchPlaces(String query) async {
    try {
      final locations = await locationFromAddress(query);

      return locations
          .where((loc) {
            // Filter to Malawi only - check placemarks
            return true; // Simplified for now, will refine with actual API
          })
          .map((loc) => Place(
                id: '${loc.latitude}-${loc.longitude}',
                name: query,
                address: '$query, Malawi',
                latitude: loc.latitude,
                longitude: loc.longitude,
                type: PlaceType.RECENT,
              ))
          .toList();
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  bool _usablePart(String? value) {
    final s = (value ?? '').trim();
    if (s.isEmpty) return false;
    if (GooglePlacesService.isPlusCodeLabel(s)) return false;
    return true;
  }

  /// Get address from coordinates (reverse geocoding).
  /// Skips Plus Codes like `2QMV+XV` and prefers street / area names.
  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) return null;

      for (final p in placemarks) {
        final parts = <String>[
          if (_usablePart(p.street)) p.street!.trim(),
          if (_usablePart(p.thoroughfare) &&
              (p.street ?? '').trim() != (p.thoroughfare ?? '').trim())
            p.thoroughfare!.trim(),
          if (_usablePart(p.subLocality)) p.subLocality!.trim(),
          if (_usablePart(p.locality)) p.locality!.trim(),
          if (_usablePart(p.subAdministrativeArea))
            p.subAdministrativeArea!.trim(),
          if (_usablePart(p.administrativeArea)) p.administrativeArea!.trim(),
          if (_usablePart(p.country)) p.country!.trim(),
        ];
        // Deduplicate while keeping order
        final seen = <String>{};
        final unique = parts
            .where((e) => seen.add(e.toLowerCase()))
            .toList(growable: false);
        if (unique.isNotEmpty) return unique.join(', ');
      }
      return null;
    } catch (e) {
      print('Error getting address: $e');
      return null;
    }
  }

  /// Calculate distance between two locations (in km)
  double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * (pi / 180);
}
