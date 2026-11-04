import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device keychain/keystore copy of a password the user already signed in with.
/// Used only to refill login and to sign in after a biometric check.
class SavedPasswordStore {
  SavedPasswordStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _key(String identifier) =>
      'vero_login_pw_v1_${identifier.trim().toLowerCase()}';

  static Future<void> save(String identifier, String password) async {
    final id = identifier.trim();
    if (id.isEmpty || password.isEmpty) return;
    try {
      await _storage.write(key: _key(id), value: password);
    } catch (_) {}
  }

  static Future<String?> read(String identifier) async {
    final id = identifier.trim();
    if (id.isEmpty) return null;
    try {
      final value = await _storage.read(key: _key(id));
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String identifier) async {
    final id = identifier.trim();
    if (id.isEmpty) return;
    try {
      await _storage.delete(key: _key(id));
    } catch (_) {}
  }

  /// After a password change, update every identifier this signed-in user uses.
  static Future<void> replaceForCurrentUser(String password) async {
    if (password.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = <String>{
      FirebaseAuth.instance.currentUser?.email?.trim() ?? '',
      prefs.getString('email')?.trim() ?? '',
      prefs.getString('phone')?.trim() ?? '',
      prefs.getString('prefill_login_identifier')?.trim() ?? '',
    }.where((id) => id.isNotEmpty);
    for (final id in ids) {
      await save(id, password);
    }
  }
}
