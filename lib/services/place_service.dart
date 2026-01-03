import 'dart:math';
import 'package:geocoding/geocoding.dart';
import 'package:vero360_app/models/place_model.dart';

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

  /// Get address from coordinates (reverse geocoding)
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

      final p = placemarks.first;
      return '${p.street}, ${p.locality}, ${p.administrativeArea}';
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
