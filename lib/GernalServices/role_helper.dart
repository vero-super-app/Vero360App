/// Centralized role detection logic - single source of truth.
/// Backend roles: 'customer' | 'merchant' | 'driver'
class RoleHelper {
  static const customer = 'customer';
  static const merchant = 'merchant';
  static const driver = 'driver';

  static String? normalizeAccountRole(Object? raw) {
    var s = (raw ?? '').toString().toLowerCase().trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[\s-]+'), '_');
    if (s == merchant || s.contains('merchant')) return merchant;
    if (s == driver || s.contains('driver')) return driver;
    if (s == customer || s == 'user' || s == 'guest' || s == 'buyer') {
      return customer;
    }
    return null;
  }

  static String roleFromUserMap(Map<String, dynamic> u) {
    final direct = normalizeAccountRole(
      u['role'] ?? u['userRole'] ?? u['user_role'] ?? u['accountRole'],
    );
    if (direct != null) return direct;
    final roles = u['roles'];
    if (roles is List) {
      final set = roles.map((e) => e.toString().toLowerCase()).toSet();
      if (set.any((r) => r.contains('merchant'))) return merchant;
      if (set.any((r) => r.contains('driver'))) return driver;
    }
    return customer;
  }

  static bool isMerchant(Map<String, dynamic> u) =>
      roleFromUserMap(u) == merchant;

  static bool isDriver(Map<String, dynamic> u) => roleFromUserMap(u) == driver;

  /// Like [roleFromUserMap] but returns null when the map has no role fields.
  static String? tryRoleFromUserMap(Map<String, dynamic> u) {
    final direct = normalizeAccountRole(
      u['role'] ?? u['userRole'] ?? u['user_role'] ?? u['accountRole'],
    );
    if (direct != null) return direct;
    final roles = u['roles'];
    if (roles is List && roles.isNotEmpty) {
      return roleFromUserMap(u);
    }
    return null;
  }
}
