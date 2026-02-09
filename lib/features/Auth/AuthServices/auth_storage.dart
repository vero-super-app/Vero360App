// lib/services/auth_storage.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

class AuthStorage {
  static const _tokenKeys = ['token', 'jwt_token', 'jwt'];

  /// Returns Firebase token first (stays valid after 1hr refresh), then SP.
  static Future<String?> readToken() async => AuthHandler.getTokenForApi();

  /// Single source of truth: Firebase session first, then SP token.
  static Future<bool> isLoggedIn() async {
    if (await AuthHandler.isAuthenticated()) return true;
    final sp = await SharedPreferences.getInstance();
    for (final k in _tokenKeys) {
      final v = sp.getString(k);
      if (v != null && v.isNotEmpty) return true;
    }
    return false;
  }

  /// Try to get numeric userId from the JWT: payload.sub | payload.id | payload.userId
  static Future<int?> userIdFromToken() async {
    final t = await readToken();
    if (t == null) return null;
    final payload = _decodeJwtPayload(t);
    final raw = payload['sub'] ?? payload['id'] ?? payload['userId'];
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  /// Try to get user name from JWT: payload.name | payload.username | payload.email
  static Future<String?> userNameFromToken() async {
    final t = await readToken();
    if (t == null) return null;
    final payload = _decodeJwtPayload(t);
    final name = payload['name'] ?? payload['username'] ?? payload['email'];
    if (name == null) return null;
    return name.toString();
  }

  // ---- internals: safe base64url decode
  static Map<String, dynamic> _decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return {};
      final payload = _b64UrlDecode(parts[1]);
      final map = jsonDecode(payload);
      return map is Map<String, dynamic> ? map : {};
    } catch (_) {
      return {};
    }
  }

  static String _b64UrlDecode(String input) {
    var out = input.replaceAll('-', '+').replaceAll('_', '/');
    while (out.length % 4 != 0) { out += '='; }
    return utf8.decode(base64.decode(out));
  }
}
