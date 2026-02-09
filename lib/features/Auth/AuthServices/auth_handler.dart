import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for auth: use Firebase first, then SharedPreferences.
/// This avoids "some parts logged in, some not" when SP token is missing/expired
/// but Firebase session is still valid (e.g. after token refresh).
class AuthHandler {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  static const List<String> _spTokenKeys = ['token', 'jwt_token', 'jwt'];

  /// Get the current Firebase ID token, or null if not logged in.
  /// Tries cached first; if null but user exists, forces refresh (helps after ~1hr expiry).
  static Future<String?> getFirebaseToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    var token = await user.getIdToken(false);
    if (token == null || token.isEmpty) {
      token = await user.getIdToken(true);
    }
    return token;
  }

  /// Prefer Firebase token so session stays valid after 1hr refresh; fallback to SP.
  /// Use this everywhere you need a token for API calls (cart, checkout, ride, etc.).
  /// When we get a token from Firebase we sync it to SP so other code paths stay aligned.
  static Future<String?> getTokenForApi() async {
    final firebaseToken = await getFirebaseToken();
    if (firebaseToken != null && firebaseToken.isNotEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[AuthHandler] full token (Firebase): $firebaseToken');
      }
      await persistTokenToSp(firebaseToken);
      return firebaseToken;
    }
    final sp = await SharedPreferences.getInstance();
    for (final k in _spTokenKeys) {
      final v = sp.getString(k);
      if (v != null && v.isNotEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[AuthHandler] full token (SP $k): $v');
        }
        return v;
      }
    }
    return null;
  }

  /// Write token to SharedPreferences so any code that only reads SP stays in sync.
  static Future<void> persistTokenToSp(String token) async {
    if (token.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    for (final k in _spTokenKeys) {
      await sp.setString(k, token);
    }
  }

  /// Single source of truth: logged in if Firebase has a user (and we can get a token).
  static Future<bool> isAuthenticated() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    final token = await user.getIdToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> logout() async {
    await _firebaseAuth.signOut();
  }
}