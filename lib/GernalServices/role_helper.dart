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
    
    // Check if role field explicitly says driver
    final roleIsDriver = role == 'driver' || role == 'taxi';
    
    // Check if roles array contains driver
    final rolesContainsDriver = roles.contains('driver') || roles.contains('taxi');
    
    // Only trust isDriver flag if role field also indicates driver (avoid false positives)
    final isDriverFlag = (u['isDriver'] == true) && roleIsDriver;
    
    // Only consider driverId if it's a non-null, non-empty string/number
    final driverId = u['driverId'];
    final hasDriverId = (driverId != null && 
        driverId.toString().trim().isNotEmpty && 
        driverId.toString() != '0') && roleIsDriver;
    
    return roleIsDriver ||
        rolesContainsDriver ||
        isDriverFlag ||
        hasDriverId ||
        (u['driver'] == true && roleIsDriver);
  }
}
