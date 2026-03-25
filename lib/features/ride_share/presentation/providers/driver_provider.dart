import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';

// ==================== SERVICES ====================
final driverServiceProvider = Provider<DriverService>((ref) {
  return DriverService();
});

// ==================== DRIVER PROFILE ====================

/// Get current authenticated driver profile (uses Firebase token)
final myDriverProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final driverService = ref.watch(driverServiceProvider);
  return await driverService.getMyDriverProfile();
});

/// Get driver by database user ID (legacy - prefer myDriverProfileProvider)
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

// ==================== DRIVER STATUS FROM SHARED PREFERENCES ====================
/// Loads driver status from SharedPreferences (local cache, no network call)
final isCurrentUserDriverProvider = Provider<bool?>((ref) {
  return _isDriverCachedValue;
});

/// Whether ride-request popups should run (avoids blocking on null prefs / stale cache).
final driverRideNotificationsEnabledProvider = Provider<bool>((ref) {
  final cached = ref.watch(isCurrentUserDriverProvider);
  if (cached == true) return true;

  final sync = ref.watch(syncDriverStatusProvider);
  if (sync.hasValue && sync.value == true) return true;

  final profile = ref.watch(myDriverProfileProvider);
  final hasDriverProfile = profile.maybeWhen(
    data: (d) => d['id'] != null,
    orElse: () => false,
  );
  if (hasDriverProfile) return true;

  if (cached == false &&
      sync.hasValue &&
      sync.value == false &&
      !hasDriverProfile) {
    return false;
  }

  return false;
});

/// Syncs driver status with backend (call periodically or on demand)
final syncDriverStatusProvider = FutureProvider<bool>((ref) async {
  try {
    final userId = await AuthStorage.userIdFromToken();
    if (userId == null) {
      await _saveDriverStatusToPrefs(false);
      return false;
    }
    
    final driverService = ref.watch(driverServiceProvider);
    try {
      await driverService.getDriverByUserId(userId);
      await _saveDriverStatusToPrefs(true);
      return true;
    } catch (_) {
      await _saveDriverStatusToPrefs(false);
      return false;
    }
  } catch (_) {
    await _saveDriverStatusToPrefs(false);
    return false;
  }
});

// ==================== SHARED PREFERENCES HELPERS ====================
bool? _isDriverCachedValue;

/// Load driver status from SharedPreferences (checks user_role == 'driver')
Future<bool?> loadDriverStatusFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('user_role') ??
            prefs.getString('role') ??
            '')
        .toLowerCase();
    final value = role == 'driver';
    _isDriverCachedValue = value;
    return value;
  } catch (_) {
    return null;
  }
}

/// Save driver status to SharedPreferences
Future<void> _saveDriverStatusToPrefs(bool isDriver) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (isDriver) {
      await prefs.setString('user_role', 'driver');
      await prefs.setString('role', 'driver');
    }
    _isDriverCachedValue = isDriver;
  } catch (_) {
    // Silent fail
  }
}
