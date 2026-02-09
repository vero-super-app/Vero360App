import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Provider, FutureProvider, StreamProvider;
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/place_prediction_model.dart';
import 'package:vero360_app/GernalServices/ride_share_service.dart';
import 'package:vero360_app/GernalServices/location_service.dart';
import 'package:vero360_app/GernalServices/place_service.dart';
import 'package:vero360_app/GernalServices/google_places_service.dart';
import 'package:vero360_app/GernalServices/google_directions_service.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';

// ==================== SERVICES ====================
final rideShareServiceProvider = Provider<RideShareService>((ref) {
  return RideShareService();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final placeServiceProvider = Provider<PlaceService>((ref) {
  return PlaceService();
});

final googlePlacesServiceProvider = Provider<GooglePlacesService>((ref) {
  try {
    return GooglePlacesService(apiKey: GoogleMapsConfig.getApiKey());
  } catch (e) {
    // Fallback: try to use the apiKey even if empty, let GooglePlacesService handle the error
    return GooglePlacesService(apiKey: GoogleMapsConfig.apiKey);
  }
});

final googleDirectionsServiceProvider =
    Provider<GoogleDirectionsService>((ref) {
  try {
    return GoogleDirectionsService(apiKey: GoogleMapsConfig.getApiKey());
  } catch (e) {
    return GoogleDirectionsService(apiKey: GoogleMapsConfig.apiKey);
  }
});

// ==================== CURRENT LOCATION ====================
final currentLocationProvider = FutureProvider<Position?>((ref) async {
  final locationService = ref.watch(locationServiceProvider);
  return await locationService.getCurrentLocation();
});

final locationStreamProvider = StreamProvider<Position>((ref) {
  final locationService = ref.watch(locationServiceProvider);
  return locationService.getLocationStream();
});

/// Resolved address for current location (reverse geocoding). Use for pickup card.
final currentLocationAddressProvider = FutureProvider<String?>((ref) async {
  final position = await ref.watch(currentLocationProvider.future);
  if (position == null) return null;
  final placeService = ref.watch(placeServiceProvider);
  return placeService.getAddressFromCoordinates(
    position.latitude,
    position.longitude,
  );
});

/// Pickup display: user's name, profile picture URL, and address (Google reverse-geocoded when available).
class PickupDisplay {
  final String userName;
  final String profilePictureUrl;
  final String address;

  PickupDisplay({
    required this.userName,
    required this.profilePictureUrl,
    required this.address,
  });
}

final pickupDisplayProvider = FutureProvider<PickupDisplay>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final rawName = prefs.getString('fullName') ??
      prefs.getString('name') ??
      await AuthStorage.userNameFromToken();
  final String userName = (rawName == null || rawName.trim().isEmpty)
      ? 'Your Location'
      : rawName.trim();
  final String profilePictureUrl =
      prefs.getString('profilepicture')?.trim() ??
      prefs.getString('profilePicture')?.trim() ??
      '';

  // Prefer current location reverse-geocoded (Google-detected) address when we have position
  final position = await ref.watch(currentLocationProvider.future);
  if (position != null) {
    final placeService = ref.watch(placeServiceProvider);
    final addr = await placeService.getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (addr != null && addr.isNotEmpty) {
      return PickupDisplay(
        userName: userName,
        profilePictureUrl: profilePictureUrl,
        address: addr,
      );
    }
  }

  // Fallback: saved profile address or "Current Location"
  final savedAddr = prefs.getString('address')?.trim();
  final useSavedAddress = savedAddr != null &&
      savedAddr.isNotEmpty &&
      savedAddr.toLowerCase() != 'no address';

  if (useSavedAddress && savedAddr != null) {
    return PickupDisplay(
      userName: userName,
      profilePictureUrl: profilePictureUrl,
      address: savedAddr,
    );
  }

  return PickupDisplay(
    userName: userName,
    profilePictureUrl: profilePictureUrl,
    address: 'Current Location',
  );
});

// ==================== PLACE SEARCH ====================
/// Google Places Autocomplete search provider
/// Returns list of place predictions from Google Places API
final placeSearchProvider =
    FutureProvider.family<List<PlacePrediction>, String>((ref, query) async {
  if (query.isEmpty) return [];

  final googlePlacesService = ref.watch(googlePlacesServiceProvider);
  return await googlePlacesService.autocompleteSearch(query);
});

/// Get detailed information about a place using Google Places Details API
/// Enriches PlacePrediction with coordinates (latitude/longitude)
final placeDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, placeId) async {
  if (placeId.isEmpty) return {};

  final googlePlacesService = ref.watch(googlePlacesServiceProvider);
  return await googlePlacesService.getPlaceDetails(placeId);
});

/// Convert PlacePrediction to Place model with full details
final placeDetailsWithCoordinatesProvider =
    FutureProvider.family<Place?, String>(
  (ref, placeId) async {
    if (placeId.isEmpty) return null;

    try {
      final details = await ref.watch(placeDetailsProvider(placeId).future);
      final geometry = details['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;

      return Place(
        id: placeId,
        name: details['name'] as String? ??
            details['formatted_address'] as String? ??
            '',
        address: details['formatted_address'] as String? ?? '',
        latitude: (location?['lat'] as num?)?.toDouble() ?? 0.0,
        longitude: (location?['lng'] as num?)?.toDouble() ?? 0.0,
        type: PlaceType.RECENT,
      );
    } catch (e) {
      return null;
    }
  },
);

/// Selected destination place provider
final selectedDropoffPlaceProvider = StateProvider<Place?>((ref) => null);

/// Selected pickup place provider
final selectedPickupPlaceProvider = StateProvider<Place?>((ref) => null);

/// Google Places Autocomplete provider (alias for place search)
final serpapiPlacesAutocompleteProvider =
    FutureProvider.family<List<PlacePrediction>, String>((ref, query) async {
  if (query.isEmpty) return [];

  final googlePlacesService = ref.watch(googlePlacesServiceProvider);
  return await googlePlacesService.autocompleteSearch(query);
});

// ==================== RECENT PLACES (from search history) ====================
const String _recentPlacesStorageKey = 'ride_share_recent_places';
const int _maxRecentPlaces = 15;

final recentPlacesProvider = StateProvider<List<Place>>((ref) => []);

class RecentPlacesManager {
  /// Load recent places from SharedPreferences and update provider
  static Future<void> loadAndSet(dynamic ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_recentPlacesStorageKey);
      if (jsonList == null || jsonList.isEmpty) {
        return;
      }
      final places = <Place>[];
      for (final jsonStr in jsonList) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          places.add(Place.fromJson(map));
        } catch (_) {
          // Skip invalid entries
        }
      }
      ref.read(recentPlacesProvider.notifier).state = places;
    } catch (e) {
      // Ignore load errors
    }
  }

  /// Add a place to recent (e.g. when user selects a destination). Dedupes by id, keeps latest first, caps at [_maxRecentPlaces].
  static Future<void> addPlace(dynamic ref, Place place) async {
    final list = ref.read(recentPlacesProvider);
    final updated = [
      place.copyWith(type: PlaceType.RECENT),
      ...list.where((p) => p.id != place.id),
    ].take(_maxRecentPlaces).toList();
    ref.read(recentPlacesProvider.notifier).state = updated;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList =
          updated.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(_recentPlacesStorageKey, jsonList);
    } catch (_) {}
  }
}

// ==================== BOOKMARKED PLACES ====================
final bookmarkedPlacesProvider = StateProvider<List<Place>>(
  (ref) {
    // TODO: Load from local storage (Hive/SharedPreferences)
    return [];
  },
);

// ==================== ADD/REMOVE BOOKMARKED PLACES ====================
// Helper functions for managing bookmarked places
class BookmarkedPlacesManager {
  /// Add a place to bookmarked places
  static Future<void> addPlace(dynamic ref, Place place) async {
    final places = ref.read(bookmarkedPlacesProvider);
    ref.read(bookmarkedPlacesProvider.notifier).state = [...places, place];
    // TODO: Implement local storage persistence
  }

  /// Remove a place from bookmarked places
  static Future<void> removePlace(dynamic ref, String placeId) async {
    final places = ref.read(bookmarkedPlacesProvider);
    ref.read(bookmarkedPlacesProvider.notifier).state =
        places.where((p) => p.id != placeId).toList();
    // TODO: Implement local storage persistence
  }
}

// ==================== RIDE REQUEST ====================
final rideRequestProvider =
    FutureProvider.family<Map<String, dynamic>, RideRequestParams>(
        (ref, params) async {
  final rideService = ref.watch(rideShareServiceProvider);

  return await rideService.requestRide(
    pickupLatitude: params.pickupLatitude,
    pickupLongitude: params.pickupLongitude,
    dropoffLatitude: params.dropoffLatitude,
    dropoffLongitude: params.dropoffLongitude,
    vehicleClass: params.vehicleClass,
    pickupAddress: params.pickupAddress,
    dropoffAddress: params.dropoffAddress,
    notes: params.notes,
  );
});

class RideRequestParams {
  final double pickupLatitude;
  final double pickupLongitude;
  final double dropoffLatitude;
  final double dropoffLongitude;
  final String vehicleClass;
  final String? pickupAddress;
  final String? dropoffAddress;
  final String? notes;

  RideRequestParams({
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    required this.vehicleClass,
    this.pickupAddress,
    this.dropoffAddress,
    this.notes,
  });
}

// ==================== FARE ESTIMATION ====================
final fareEstimateProvider =
    FutureProvider.family<Map<String, dynamic>, FareEstimateParams>(
        (ref, params) async {
  final rideService = ref.watch(rideShareServiceProvider);

  return await rideService.estimateFare(
    pickupLatitude: params.pickupLatitude,
    pickupLongitude: params.pickupLongitude,
    dropoffLatitude: params.dropoffLatitude,
    dropoffLongitude: params.dropoffLongitude,
    vehicleClass: params.vehicleClass,
  );
});

class FareEstimateParams {
  final double pickupLatitude;
  final double pickupLongitude;
  final double dropoffLatitude;
  final double dropoffLongitude;
  final String vehicleClass;

  FareEstimateParams({
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.dropoffLatitude,
    required this.dropoffLongitude,
    required this.vehicleClass,
  });
}

// ==================== VEHICLE SELECTION ====================
final selectedVehicleClassProvider = StateProvider<String?>(
  (ref) => null,
);

// ==================== DISTANCE CALCULATION ====================
final distanceCalculationProvider =
    Provider.family<double, (double, double, double, double)>((ref, params) {
  final placeService = ref.watch(placeServiceProvider);
  final (lat1, lng1, lat2, lng2) = params;
  return placeService.calculateDistance(lat1, lng1, lat2, lng2);
});

// ==================== ROUTE & POLYLINE ====================
/// Get route details between pickup and dropoff using Google Directions API
final routeProvider =
    FutureProvider.family<Map<String, dynamic>, (Place, Place)>(
  (ref, places) async {
    final (pickupPlace, dropoffPlace) = places;
    final directionsService = ref.watch(googleDirectionsServiceProvider);

    try {
      final routeInfo = await directionsService.getRouteInfo(
        originLat: pickupPlace.latitude,
        originLng: pickupPlace.longitude,
        destLat: dropoffPlace.latitude,
        destLng: dropoffPlace.longitude,
      );

      return {
        'distanceKm': routeInfo.distanceKm,
        'durationMinutes': routeInfo.durationMinutes,
        'polyline': routeInfo.polyline,
      };
    } catch (e) {
      return {
        'distanceKm': 0.0,
        'durationMinutes': 0,
        'polyline': '',
        'error': e.toString(),
      };
    }
  },
);

/// Get accurate distance in kilometers between pickup and dropoff
final distanceKmProvider =
    FutureProvider.family<double, (Place, Place)>((ref, places) async {
  final (pickupPlace, dropoffPlace) = places;
  final directionsService = ref.watch(googleDirectionsServiceProvider);

  try {
    final routeInfo = await directionsService.getRouteInfo(
      originLat: pickupPlace.latitude,
      originLng: pickupPlace.longitude,
      destLat: dropoffPlace.latitude,
      destLng: dropoffPlace.longitude,
    );
    return routeInfo.distanceKm;
  } catch (e) {
    return 0.0;
  }
});

/// Get estimated duration in minutes between pickup and dropoff
final durationMinutesProvider =
    FutureProvider.family<int, (Place, Place)>((ref, places) async {
  final (pickupPlace, dropoffPlace) = places;
  final directionsService = ref.watch(googleDirectionsServiceProvider);

  try {
    final routeInfo = await directionsService.getRouteInfo(
      originLat: pickupPlace.latitude,
      originLng: pickupPlace.longitude,
      destLat: dropoffPlace.latitude,
      destLng: dropoffPlace.longitude,
    );
    return routeInfo.durationMinutes;
  } catch (e) {
    return 0;
  }
});
