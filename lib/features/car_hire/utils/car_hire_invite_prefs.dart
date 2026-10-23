import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that the marketplace "Rent out your cars" invite has been shown.
///
/// The invite is a first-open card. After that, the application lives in
/// Settings so it is not shown on every car hire visit.
class CarHireInvitePrefs {
  CarHireInvitePrefs._();

  static const key = 'car_hire_rentout_invite_seen_v1';

  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
