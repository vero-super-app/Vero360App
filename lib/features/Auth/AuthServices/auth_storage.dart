// lib/services/auth_storage.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';
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

  static const _messagingFirebaseUidKey = 'messaging_firebase_uid';

  /// Sync numeric backend user id from GET /users/me for the current Firebase user.
  static Future<int?> syncBackendUserIdFromMe() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;

    final token = await AuthHandler.getFirebaseToken();
    if (token == null || token.isEmpty) return null;

    final sp = await SharedPreferences.getInstance();
    final storedUid = sp.getString(_messagingFirebaseUidKey);
    if (storedUid != null && storedUid != firebaseUser.uid) {
      await sp.remove('userId');
      await sp.remove('user_id');
    }
    await sp.setString(_messagingFirebaseUidKey, firebaseUser.uid);

    try {
      await ApiConfig.init();
      final res = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return null;
      final data = json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : json;
      final rawId = data['id'] ?? data['userId'];
      if (rawId == null) return null;
      final id = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (id == null || id <= 0) return null;
      await sp.setInt('userId', id);
      await sp.setInt('user_id', id);
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Try to get numeric userId from JWT or SharedPreferences
  /// Checks: SharedPreferences first, then JWT (payload.sub | payload.id | payload.userId)
  static Future<int?> userIdFromToken() async {
    // First check SharedPreferences (set during login)
    final sp = await SharedPreferences.getInstance();
    final spId = sp.getInt('userId') ?? sp.getInt('user_id');
    if (spId != null && spId > 0) {
      return spId;
    }

    // Fallback to JWT token extraction
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
