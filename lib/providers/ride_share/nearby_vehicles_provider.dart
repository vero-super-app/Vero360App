import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/GernalServices/nearby_vehicles_service.dart';
import 'package:vero360_app/GernalServices/vehicle_realtime_service.dart';

/// Provider for NearbyVehiclesService instance
final nearbyVehiclesServiceProvider = Provider((ref) {
  return NearbyVehiclesService();
});

/// Provider for VehicleRealtimeService instance
final vehicleRealtimeServiceProvider = Provider((ref) {
  final service = VehicleRealtimeService();
  ref.onDispose(() async {
    await service.dispose();
  });
  return service;
});

/// State for nearby vehicles
class NearbyVehiclesState {
  final List<NearbyVehicle> vehicles;
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
    List<NearbyVehicle>? vehicles,
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

/// Notifier for managing nearby vehicles state
class NearbyVehiclesNotifier extends StateNotifier<NearbyVehiclesState> {
  final NearbyVehiclesService _vehiclesService;
  final VehicleRealtimeService _realtimeService;
  StreamSubscription<VehicleLocationUpdate>? _locationSubscription;
  Timer? _pollTimer;

  NearbyVehiclesNotifier(this._vehiclesService, this._realtimeService)
      : super(const NearbyVehiclesState());

  /// Fetch nearby vehicles and start real-time updates
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
      final vehicles = await _vehiclesService.fetchNearbyVehicles(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );

      await _vehiclesService.cacheVehicles(vehicles);

      state = state.copyWith(
        vehicles: vehicles,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );

      // Connect to real-time updates
      _connectToRealtimeUpdates();
    } catch (e) {
      print('[NearbyVehiclesNotifier] Error fetching vehicles: $e');
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
        _realtimeService.subscribeToVehicleUpdates();

        // Listen to real-time location updates
        _locationSubscription =
            _realtimeService.locationUpdates.listen((update) {
          _updateVehicleLocation(update);
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

  /// Update a single vehicle's location
  void _updateVehicleLocation(VehicleLocationUpdate update) {
    final updatedVehicles = state.vehicles.map((vehicle) {
      if (vehicle.id == update.vehicleId) {
        return NearbyVehicle(
          id: vehicle.id,
          driverId: vehicle.driverId,
          latitude: update.latitude,
          longitude: update.longitude,
          distance: vehicle.distance,
          vehicleClass: vehicle.vehicleClass,
          make: vehicle.make,
          model: vehicle.model,
          licensePlate: vehicle.licensePlate,
          rating: vehicle.rating,
          totalRides: vehicle.totalRides,
        );
      }
      return vehicle;
    }).toList();

    state = state.copyWith(
      vehicles: updatedVehicles,
      lastUpdated: DateTime.now(),
    );
  }

  /// Fallback: poll for updates every 3 seconds
  void _startPollingUpdates() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (state.userLatitude != null && state.userLongitude != null) {
        try {
          final vehicles = await _vehiclesService.fetchNearbyVehicles(
            latitude: state.userLatitude!,
            longitude: state.userLongitude!,
            radiusKm: state.radiusKm,
          );

          state = state.copyWith(
            vehicles: vehicles,
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

/// Filtered vehicles by vehicle class (optional)
final filteredVehiclesProvider =
    Provider.family<List<NearbyVehicle>, String?>((ref, vehicleClass) {
  final state = ref.watch(nearbyVehiclesProvider);

  if (vehicleClass == null || vehicleClass.isEmpty) {
    return state.vehicles;
  }

  return state.vehicles.where((v) => v.vehicleClass == vehicleClass).toList();
});

/// Get closest vehicle
final closestVehicleProvider = Provider((ref) {
  final state = ref.watch(nearbyVehiclesProvider);

  if (state.vehicles.isEmpty) return null;

  return state.vehicles.reduce((a, b) => a.distance < b.distance ? a : b);
});

/// Get vehicles sorted by distance
final vehiclesByDistanceProvider = Provider((ref) {
  final state = ref.watch(nearbyVehiclesProvider);

  final sorted = [...state.vehicles];
  sorted.sort((a, b) => a.distance.compareTo(b.distance));
  return sorted;
});
