import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/GernalServices/nearby_vehicles_service.dart';
import 'package:vero360_app/GernalServices/taxi_realtime_service.dart' show TaxiRealtimeService, TaxiLocationUpdate;

/// Provider for NearbyTaxisService instance
final nearbyVehiclesServiceProvider = Provider((ref) {
  return NearbyTaxisService();
});

/// Provider for TaxiRealtimeService instance
final vehicleRealtimeServiceProvider = Provider((ref) {
  final service = TaxiRealtimeService();
  ref.onDispose(() async {
    await service.dispose();
  });
  return service;
});

/// State for nearby taxis
class NearbyVehiclesState {
  final List<NearbyTaxi> vehicles;
  final bool isLoading;
  final String? error;
  final double? userLatitude;
  final double? userLongitude;
  final double radiusKm;
  final DateTime? lastUpdated;

  const NearbyVehiclesState({
    this.vehicles = const [],
    this.isLoading = false,
    this.error,
    this.userLatitude,
    this.userLongitude,
    this.radiusKm = 5.0,
    this.lastUpdated,
  });

  NearbyVehiclesState copyWith({
    List<NearbyTaxi>? vehicles,
    bool? isLoading,
    String? error,
    double? userLatitude,
    double? userLongitude,
    double? radiusKm,
    DateTime? lastUpdated,
  }) {
    return NearbyVehiclesState(
      vehicles: vehicles ?? this.vehicles,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userLatitude: userLatitude ?? this.userLatitude,
      userLongitude: userLongitude ?? this.userLongitude,
      radiusKm: radiusKm ?? this.radiusKm,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Notifier for managing nearby taxis state
class NearbyVehiclesNotifier extends StateNotifier<NearbyVehiclesState> {
  final NearbyTaxisService _taxisService;
  final TaxiRealtimeService _realtimeService;
  StreamSubscription<TaxiLocationUpdate>? _locationSubscription;
  Timer? _pollTimer;

  NearbyVehiclesNotifier(this._taxisService, this._realtimeService)
      : super(const NearbyVehiclesState());

  /// Fetch nearby taxis and start real-time updates
  Future<void> fetchAndSubscribe({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      userLatitude: latitude,
      userLongitude: longitude,
      radiusKm: radiusKm,
    );

    try {
      // Initial fetch
      final taxis = await _taxisService.fetchNearbyTaxis(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );

      await _taxisService.cacheTaxis(taxis);

      state = state.copyWith(
        vehicles: taxis,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );

      // Connect to real-time updates
      _connectToRealtimeUpdates();
    } catch (e) {
      print('[NearbyVehiclesNotifier] Error fetching taxis: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Connect to real-time location updates
  void _connectToRealtimeUpdates() {
    _locationSubscription?.cancel();

    // Attempt to connect to WebSocket
    _realtimeService.connect().then((connected) {
      if (connected) {
        _realtimeService.subscribeToTaxiUpdates();

        // Listen to real-time location updates
        _locationSubscription =
            _realtimeService.locationUpdates.listen((update) {
          _updateTaxiLocation(update);
        });

        print('[NearbyVehiclesNotifier] Connected to real-time updates');
      } else {
        print(
          '[NearbyVehiclesNotifier] WebSocket connection failed, '
          'using polling fallback',
        );
        _startPollingUpdates();
      }
    });
  }

  /// Update a single taxi's location
  void _updateTaxiLocation(TaxiLocationUpdate update) {
    final updatedTaxis = state.vehicles.map((taxi) {
      if (taxi.id == update.taxiId) {
        return NearbyTaxi(
          id: taxi.id,
          driverId: taxi.driverId,
          latitude: update.latitude,
          longitude: update.longitude,
          distance: taxi.distance,
          taxiClass: taxi.taxiClass,
          make: taxi.make,
          model: taxi.model,
          licensePlate: taxi.licensePlate,
          rating: taxi.rating,
          totalRides: taxi.totalRides,
        );
      }
      return taxi;
    }).toList();

    state = state.copyWith(
      vehicles: updatedTaxis,
      lastUpdated: DateTime.now(),
    );
  }

  /// Fallback: poll for updates every 3 seconds
  void _startPollingUpdates() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (state.userLatitude != null && state.userLongitude != null) {
        try {
          final taxis = await _taxisService.fetchNearbyTaxis(
            latitude: state.userLatitude!,
            longitude: state.userLongitude!,
            radiusKm: state.radiusKm,
          );

          state = state.copyWith(
            vehicles: taxis,
            lastUpdated: DateTime.now(),
          );
        } catch (e) {
          print('[NearbyVehiclesNotifier] Polling error: $e');
        }
      }
    });
  }

  /// Stop real-time updates
  void stopTracking() {
    _locationSubscription?.cancel();
    _pollTimer?.cancel();
  }

  /// Cleanup
  @override
  void dispose() {
    _locationSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// StateNotifier provider for nearby vehicles
final nearbyVehiclesProvider =
    StateNotifierProvider<NearbyVehiclesNotifier, NearbyVehiclesState>((ref) {
  final vehiclesService = ref.watch(nearbyVehiclesServiceProvider);
  final realtimeService = ref.watch(vehicleRealtimeServiceProvider);

  return NearbyVehiclesNotifier(vehiclesService, realtimeService);
});

/// Filtered taxis by taxi class (optional)
final filteredVehiclesProvider =
    Provider.family<List<NearbyTaxi>, String?>((ref, taxiClass) {
  final state = ref.watch(nearbyVehiclesProvider);

  if (taxiClass == null || taxiClass.isEmpty) {
    return state.vehicles;
  }

  return state.vehicles.where((t) => t.taxiClass == taxiClass).toList();
});

/// Get closest taxi
final closestVehicleProvider = Provider((ref) {
  final state = ref.watch(nearbyVehiclesProvider);

  if (state.vehicles.isEmpty) return null;

  return state.vehicles.reduce((a, b) => a.distance < b.distance ? a : b);
});

/// Get taxis sorted by distance
final vehiclesByDistanceProvider = Provider((ref) {
  final state = ref.watch(nearbyVehiclesProvider);

  final sorted = [...state.vehicles];
  sorted.sort((a, b) => a.distance.compareTo(b.distance));
  return sorted;
});
