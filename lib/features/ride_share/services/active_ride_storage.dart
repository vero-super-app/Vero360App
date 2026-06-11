import 'package:shared_preferences/shared_preferences.dart';

enum ActiveRideRole { driver, passenger }

class PersistedActiveRide {
  final int rideId;
  final ActiveRideRole role;
  final String? status;
  final int? taxiId;

  const PersistedActiveRide({
    required this.rideId,
    required this.role,
    this.status,
    this.taxiId,
  });
}

/// Persists the in-progress ride so cold starts can resume the session.
class ActiveRideStorage {
  static const _rideIdKey = 'active_ride_id';
  static const _roleKey = 'active_ride_role';
  static const _statusKey = 'active_ride_status';
  static const _taxiIdKey = 'active_ride_taxi_id';

  static Future<void> save({
    required int rideId,
    required ActiveRideRole role,
    String? status,
    int? taxiId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rideIdKey, rideId);
    await prefs.setString(
      _roleKey,
      role == ActiveRideRole.driver ? 'driver' : 'passenger',
    );
    if (status != null) {
      await prefs.setString(_statusKey, status);
    }
    if (taxiId != null) {
      await prefs.setInt(_taxiIdKey, taxiId);
    }
  }

  static Future<PersistedActiveRide?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rideId = prefs.getInt(_rideIdKey);
    final roleRaw = prefs.getString(_roleKey);
    if (rideId == null || roleRaw == null) return null;

    return PersistedActiveRide(
      rideId: rideId,
      role: roleRaw == 'driver'
          ? ActiveRideRole.driver
          : ActiveRideRole.passenger,
      status: prefs.getString(_statusKey),
      taxiId: prefs.getInt(_taxiIdKey),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rideIdKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_statusKey);
    await prefs.remove(_taxiIdKey);
  }
}
