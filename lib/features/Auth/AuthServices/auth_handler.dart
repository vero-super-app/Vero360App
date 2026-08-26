import 'dart:async';

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
  static const Duration _cachedTokenTimeout = Duration(seconds: 5);
  static const Duration _refreshTokenTimeout = Duration(seconds: 10);

  static Future<String?> getFirebaseToken({bool forceRefresh = false}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    try {
      var token =
          await user.getIdToken(forceRefresh).timeout(_cachedTokenTimeout);
      if (token == null || token.isEmpty) {
        token = await user.getIdToken(true).timeout(_refreshTokenTimeout);
      }
      if (token != null && token.isNotEmpty) {
        await persistTokenToSp(token);
      }
      return token;
    } on TimeoutException {
      try {
        return await user.getIdToken(false).timeout(_cachedTokenTimeout);
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Ride Share and other Firebase-only surfaces: never fall back to Nest JWT.
  static Future<String?> getFirebaseTokenForApi({
    bool forceRefresh = false,
  }) async {
    return getFirebaseToken(forceRefresh: forceRefresh);
  }

  /// Prefer Firebase token so session stays valid after 1hr refresh; fallback to SP.
  /// Use this everywhere you need a token for API calls (cart, checkout, etc.).
  /// When we get a token from Firebase we sync it to SP so other code paths stay aligned.
  static Future<String?> getTokenForApi({bool forceRefresh = false}) async {
    final firebaseToken =
        await getFirebaseToken(forceRefresh: forceRefresh);
    if (firebaseToken != null && firebaseToken.isNotEmpty) {
      return firebaseToken;
    }
    final sp = await SharedPreferences.getInstance();
    for (final k in _spTokenKeys) {
      final v = sp.getString(k);
      if (v != null && v.isNotEmpty) {
        return v;
      }
    }
    return null;
  }

  /// On HTTP 401: force-refresh Firebase ID token once and return it (or null).
  static Future<String?> refreshTokenAfterUnauthorized() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    try {
      final token = await user.getIdToken(true).timeout(_refreshTokenTimeout);
      if (token != null && token.isNotEmpty) {
        await persistTokenToSp(token);
        return token;
      }
    } catch (_) {}
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

  /// Single source of truth for “are we signed in?” — must match [getTokenForApi].
  ///
  /// Fast + flicker-safe:
  /// - Firebase [currentUser] alone means logged in (do not await ID token here;
  ///   waiting caused BottomNavbar to treat the user as logged out for seconds
  ///   while Home/cart still worked).
  /// - Else any non-empty SharedPreferences API token (same keys as [getTokenForApi]).
  static Future<bool> isAuthenticated() async {
    final user = _firebaseAuth.currentUser;
    if (user != null && !user.isAnonymous) return true;

    final sp = await SharedPreferences.getInstance();
    for (final k in _spTokenKeys) {
      final v = sp.getString(k);
      if (v != null && v.isNotEmpty) return true;
    }
    return false;
  }

  static Future<void> logout() async {
    await _firebaseAuth.signOut();
  }

  /// Refreshes Firebase ID token when a session exists (helps Firestore attach auth).
  /// Does not throw — callers should still attempt the Firestore write.
  static Future<void> refreshFirebaseTokenIfSignedIn() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    try {
      await user.getIdToken(true);
    } catch (_) {}
  }

  /// Throws only when a Firebase user is required by app logic (not Firestore rules).
  static Future<User> requireUserForFirestore() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError(
        'Not signed in to Firebase. Sign out and sign in again, then retry.',
      );
    }
    await user.getIdToken(true);
    return user;
  }
}
