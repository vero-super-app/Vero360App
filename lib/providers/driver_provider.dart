import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vero360_app/services/driver_service.dart';

// ==================== SERVICES ====================
final driverServiceProvider = Provider<DriverService>((ref) {
  return DriverService();
});

// ==================== DRIVER PROFILE ====================
final driverProfileProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, userId) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.getDriverByUserId(userId);
});

// ==================== CREATE DRIVER PROFILE ====================
final createDriverProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, dynamic>>(
        (ref, data) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.createDriver(data);
});

// ==================== DRIVER TAXIS ====================
final driverTaxisProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>(
        (ref, driverId) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.getTaxisByDriver(driverId);
});

// ==================== CREATE TAXI ====================
final createTaxiProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, dynamic>>(
        (ref, data) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.createTaxi(data);
});

// ==================== UPDATE TAXI LOCATION ====================
final updateTaxiLocationProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, dynamic>>(
        (ref, data) async {
  final driverService = ref.watch(driverServiceProvider);
  final taxiId = data['taxiId'] as int;
  final latitude = data['latitude'] as double;
  final longitude = data['longitude'] as double;
  return await driverService.updateTaxiLocation(taxiId, latitude, longitude);
});

// ==================== NEARBY DRIVERS ====================
final nearbyDriversProvider =
    FutureProvider.family<List<Map<String, dynamic>>, NearbyDriversParams>(
        (ref, params) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.getNearbyDrivers(
      params.latitude, params.longitude, params.radius);
});

class NearbyDriversParams {
  final double latitude;
  final double longitude;
  final double radius;

  NearbyDriversParams({
    required this.latitude,
    required this.longitude,
    this.radius = 5.0,
  });
}

// ==================== DRIVER UI STATE ====================
final driverModeActiveProvider = StateProvider<bool>((ref) => false);

final selectedTaxiProvider = StateProvider<int?>((ref) => null);

final driverCurrentLocationProvider =
    StateProvider<({double lat, double lng})?>(
  (ref) => null,
);

// ==================== VERIFY DRIVER ====================
final verifyDriverProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, driverId) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.verifyDriver(driverId);
});

// ==================== UPDATE TAXI AVAILABILITY ====================
final updateTaxiAvailabilityProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, dynamic>>(
        (ref, data) async {
  final driverService = ref.watch(driverServiceProvider);
  final taxiId = data['taxiId'] as int;
  final isAvailable = data['isAvailable'] as bool;
  return await driverService.setTaxiAvailability(taxiId, isAvailable);
});

// ==================== VERIFIED DRIVERS ====================
final verifiedDriversProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.getVerifiedDrivers();
});
