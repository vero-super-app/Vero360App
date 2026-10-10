import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';

/// Web OAuth client from google-services.json (client_type 3).
/// Required as [GoogleSignIn.initialize] `serverClientId` so Android returns an idToken.
const String kGoogleWebClientId =
    '1010595167807-vl7asia9e4eep8u68g9c8mp5aa3eotgi.apps.googleusercontent.com';

/// iOS OAuth client from GoogleService-Info.plist `CLIENT_ID`.
/// Required as [GoogleSignIn.initialize] `clientId` on Apple platforms.
const String kGoogleIosClientId =
    '1010595167807-3c4t2b7l8ogrioanlbu30s8tiqk9cu5p.apps.googleusercontent.com';

class GoogleSignInHelper {
  GoogleSignInHelper._();

  static final GoogleSignIn _google = GoogleSignIn.instance;
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    final useIosClient = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    await _google.initialize(
      clientId: useIosClient ? kGoogleIosClientId : null,
      serverClientId: kGoogleWebClientId,
    );
    _initialized = true;
  }

  /// Firebase Google sign-in via the native Google account picker only.
  ///
  /// We intentionally do **not** use [FirebaseAuth.signInWithProvider] —
  /// that opens a Firebase-hosted OAuth page that can show the Cloud project
  /// number and developer contact instead of Vero360 branding.
  static Future<User?> signInToFirebase() async {
    try {
      await ensureInitialized();
      if (!kIsWeb && !_google.supportsAuthenticate()) {
        throw FirebaseAuthException(
          code: 'google-ui',
          message:
              'Google Sign-In is not available on this device. Try again or use email.',
        );
      }

      // Do not sign out immediately before authenticate(). On Android that
      // clears Credential Manager state and the account picker comes back
      // as "canceled" before the user can choose an account.
      final account = await _google.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      var idToken = account.authentication.idToken;
      String? accessToken;

      // Some devices/builds omit idToken until scopes are authorized.
      try {
        final authz = await account.authorizationClient.authorizationForScopes(
          const ['email', 'profile', 'openid'],
        );
        accessToken = authz?.accessToken;
      } catch (_) {}

      if (idToken == null || idToken.isEmpty) {
        final retry = await _google.authenticate(
          scopeHint: const ['email', 'profile'],
        );
        idToken = retry.authentication.idToken;
        try {
          final authz =
              await retry.authorizationClient.authorizationForScopes(
            const ['email', 'profile', 'openid'],
          );
          accessToken ??= authz?.accessToken;
        } catch (_) {}
      }

      if (idToken == null || idToken.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[GoogleSignIn] Missing idToken after authenticate '
            '(serverClientId / SHA-1 config?)',
          );
        }
        throw FirebaseAuthException(
          code: 'missing-id-token',
          message:
              'Google sign-in failed. Please try again or use email to sign in.',
        );
      }

      final cred = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(cred);
      return userCred.user;
    } catch (e) {
      if (_isCanceled(e)) return null;
      throw _wrap(e, null);
    }
  }

  static Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
  }

  static bool _isCanceled(Object e) {
    if (e is FirebaseAuthException) {
      final c = e.code.toLowerCase();
      return c == 'web-context-canceled' ||
          c == 'cancelled' ||
          c == 'canceled' ||
          c == 'popup-closed-by-user';
    }
    if (e is GoogleSignInException) {
      if (e.code != GoogleSignInExceptionCode.canceled) return false;
      return !_looksLikeConfigFailure(e.description);
    }
    return false;
  }

  /// Credential Manager reports a bad SHA-1 / OAuth setup as a cancellation.
  static bool _looksLikeConfigFailure(String? raw) {
    final s = (raw ?? '').toLowerCase();
    return s.contains('developer_error') ||
        s.contains('developer error') ||
        s.contains('apiexception: 10') ||
        s.contains('apiexception: 12500') ||
        s.contains('12500') ||
        s.contains('sha-1') ||
        s.contains('sha-256') ||
        s.contains('server client') ||
        s.contains('not set up');
  }

  static Object _wrap(Object e, FirebaseAuthException? providerError) {
    if (e is FirebaseAuthException) {
      return FirebaseAuthException(
        code: e.code,
        message: _safeUserMessage(e.message, code: e.code),
      );
    }
    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return FirebaseAuthException(
            code: 'google-config',
            message:
                'Google sign-in isn’t available right now. Try again or use email.',
          );
        case GoogleSignInExceptionCode.uiUnavailable:
          return FirebaseAuthException(
            code: 'google-ui',
            message:
                'Google Sign-In isn’t available. Update Google Play services and try again.',
          );
        case GoogleSignInExceptionCode.canceled:
          if (_looksLikeConfigFailure(e.description)) {
            return FirebaseAuthException(
              code: 'google-config',
              message:
                  'Google sign-in isn’t available right now. Try again or use email.',
            );
          }
          return FirebaseAuthException(
            code: 'canceled',
            message: 'Google sign-in was cancelled.',
          );
        case GoogleSignInExceptionCode.interrupted:
          return FirebaseAuthException(
            code: 'google-sign-in',
            message: 'Google sign-in was interrupted. Please try again.',
          );
        default:
          return FirebaseAuthException(
            code: 'google-sign-in',
            message: _safeUserMessage(e.description),
          );
      }
    }
    final s = e.toString();
    if (s.contains('ApiException: 10') ||
        s.contains('DEVELOPER_ERROR') ||
        s.contains('12500')) {
      return FirebaseAuthException(
        code: 'google-config',
        message:
            'Google sign-in isn’t available right now. Try again or use email.',
      );
    }
    return providerError ??
        FirebaseAuthException(
          code: 'google-sign-in',
          message: _safeUserMessage(s),
        );
  }

  /// Never surface Firebase project IDs, OAuth client IDs, or developer emails.
  static String _safeUserMessage(String? raw, {String? code}) {
    const fallback = 'Google sign-in failed. Please try again.';
    if (raw == null || raw.trim().isEmpty) return fallback;
    final lower = raw.toLowerCase();
    if (lower.contains('network') || lower.contains('unavailable')) {
      return 'Network error. Check your connection and try again.';
    }
    if (code == 'user-disabled') return 'This account has been disabled.';
    if (code == 'too-many-requests') {
      return 'Too many attempts. Try again later.';
    }
    if (lower.contains('firebase') ||
        lower.contains('googleapis') ||
        lower.contains('apps.googleusercontent') ||
        lower.contains('firebaseapp') ||
        lower.contains('sha-1') ||
        lower.contains('sha-256') ||
        lower.contains('project') ||
        lower.contains('@') ||
        RegExp(r'\d{10,}').hasMatch(raw)) {
      return fallback;
    }
    if (raw.length > 80) return fallback;
    return raw.trim();
  }
}
