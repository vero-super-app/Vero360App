import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider, FutureProvider, StreamProvider;
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/models/place_prediction_model.dart';
import 'package:vero360_app/Services/ride_share_service.dart';
import 'package:vero360_app/services/location_service.dart';
import 'package:vero360_app/services/place_service.dart';
import 'package:vero360_app/services/serpapi_places_service.dart';

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

final serpapiPlacesServiceProvider = Provider<SerpapiPlacesService>((ref) {
  return SerpapiPlacesService();
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
final placeSearchProvider = FutureProvider.family<List<Place>, String>((ref, query) async {
  if (query.isEmpty) return [];
  
  final placeService = ref.watch(placeServiceProvider);
  return await placeService.searchPlaces(query);
});

// ==================== SERPAPI PLACES SEARCH ====================
/// Searches using SerpAPI with fallback to local geocoding
/// Requires at least 4 characters to search
final serpapiPlacesAutocompleteProvider = FutureProvider.family<List<PlacePrediction>, String>(
  (ref, query) async {
    // Return empty if query is too short (minimum 4 characters)
    if (query.length < 4) return [];
    
    final serpapiService = ref.watch(serpapiPlacesServiceProvider);
    try {
      return await serpapiService.searchPlaces(query);
    } catch (e) {
      // Fallback to basic geocoding if SerpAPI fails
      // Convert Place results to PlacePrediction format
      final placeService = ref.watch(placeServiceProvider);
      final places = await placeService.searchPlaces(query);
      
      return places
          .map((place) => PlacePrediction(
                placeId: place.id,
                mainText: place.name,
                secondaryText: 'Location',
                fullText: place.address,
                types: ['place'],
              ))
          .toList();
    }
  },
);

final selectedPickupPlaceProvider = StateProvider<Place?>(
  (ref) => null,
);

final selectedDropoffPlaceProvider = StateProvider<Place?>(
  (ref) => null,
);

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
final rideRequestProvider = FutureProvider.family<
    Map<String, dynamic>,
    RideRequestParams
>((ref, params) async {
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
final fareEstimateProvider = FutureProvider.family<
    Map<String, dynamic>,
    FareEstimateParams
>((ref, params) async {
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
final distanceCalculationProvider = Provider.family<
    double,
    (double, double, double, double)
>((ref, params) {
  final placeService = ref.watch(placeServiceProvider);
  final (lat1, lng1, lat2, lng2) = params;
  return placeService.calculateDistance(lat1, lng1, lat2, lng2);
});
