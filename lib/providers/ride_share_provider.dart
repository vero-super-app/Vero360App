import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Provider, FutureProvider, StreamProvider;
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/models/place_prediction_model.dart';
import 'package:vero360_app/services/ride_share_service.dart';
import 'package:vero360_app/services/location_service.dart';
import 'package:vero360_app/services/place_service.dart';
import 'package:vero360_app/services/google_places_service.dart';
import 'package:vero360_app/services/google_directions_service.dart';
import 'package:vero360_app/config/google_maps_config.dart';

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
