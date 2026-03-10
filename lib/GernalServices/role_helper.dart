/// Centralized role detection logic - single source of truth
class RoleHelper {
  static bool isMerchant(Map<String, dynamic> u) {
    final role = (u['role'] ?? u['accountType'] ?? '').toString().toLowerCase();
    final roles = (u['roles'] is List)
        ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final flags = {
      'isMerchant': u['isMerchant'] == true,
      'merchant': u['merchant'] == true,
      'merchantId': (u['merchantId'] ?? '').toString().isNotEmpty,
    };
    return role == 'merchant' ||
        roles.contains('merchant') ||
        flags.values.any((v) => v == true);
  }

  static bool isDriver(Map<String, dynamic> u) {
    final role = (u['role'] ?? u['accountType'] ?? '').toString().toLowerCase();
    final roles = (u['roles'] is List)
        ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final flags = {
      'isDriver': u['isDriver'] == true,
      'driver': u['driver'] == true,
      'driverId': (u['driverId'] ?? '').toString().isNotEmpty,
    };
    return role == 'driver' ||
        roles.contains('driver') ||
        flags.values.any((v) => v == true);
  }
}
