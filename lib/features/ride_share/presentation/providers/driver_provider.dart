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
/// Active session role only — set at login/register, never inferred from driver API rows.
bool? _isDriverCachedValue;

const _hasDriverProfileKey = 'has_driver_profile';

/// Load whether the current session is driver mode (`user_role == 'driver'`).
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

/// Clears in-memory driver session cache (call after logout).
void resetDriverSessionCache() {
  _isDriverCachedValue = false;
}

/// Whether ride-request popups should run (explicit driver session only).
final driverRideNotificationsEnabledProvider = Provider<bool>((ref) {
  final cached = ref.watch(isCurrentUserDriverProvider);
  return cached == true;
});

/// Loads driver status from SharedPreferences (local cache, no network call)
final isCurrentUserDriverProvider = Provider<bool?>((ref) {
  return _isDriverCachedValue;
});

/// Optional: user has a driver row on the server (does not change session role).
final hasDriverProfileProvider = Provider<bool?>((ref) {
  final sync = ref.watch(syncDriverStatusProvider);
  return sync.maybeWhen(data: (v) => v, orElse: () => null);
});

/// Syncs whether a driver profile exists on the backend (does not set user_role).
final syncDriverStatusProvider = FutureProvider<bool>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final sessionRole = (prefs.getString('user_role') ??
            prefs.getString('role') ??
            '')
        .toLowerCase();
    // Never infer session role from driver API — only explicit driver login counts.
    if (sessionRole == 'merchant' || sessionRole == 'customer') {
      await _saveDriverProfileAvailability(false);
      return false;
    }

    final userId = await AuthStorage.userIdFromToken();
    if (userId == null) {
      await _saveDriverProfileAvailability(false);
      return false;
    }

    final driverService = ref.watch(driverServiceProvider);
    try {
      await driverService.getDriverByUserId(userId);
      await _saveDriverProfileAvailability(true);
      return true;
    } catch (_) {
      await _saveDriverProfileAvailability(false);
      return false;
    }
  } catch (_) {
    await _saveDriverProfileAvailability(false);
    return false;
  }
});

/// Saves driver-profile availability only — never overwrites [user_role].
Future<void> _saveDriverProfileAvailability(bool hasProfile) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasDriverProfileKey, hasProfile);
  } catch (_) {
    // Silent fail
  }
}
