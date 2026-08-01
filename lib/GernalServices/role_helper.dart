/// Centralized role detection logic - single source of truth.
/// Backend roles: 'customer' | 'merchant' | 'driver'
class RoleHelper {
  static bool isMerchant(Map<String, dynamic> u) {
    final role = (u['role'] ?? '').toString().toLowerCase();
    return role == 'merchant';
  }

  static bool isDriver(Map<String, dynamic> u) {
    final role = (u['role'] ?? '').toString().toLowerCase();
    return role == 'driver';
  }
}
