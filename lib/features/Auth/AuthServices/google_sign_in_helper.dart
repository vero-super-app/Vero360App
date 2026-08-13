import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Web OAuth client from google-services.json (client_type 3).
/// Required as [GoogleSignIn.initialize] `serverClientId` so Android returns an idToken.
const String kGoogleWebClientId =
    '1010595167807-vl7asia9e4eep8u68g9c8mp5aa3eotgi.apps.googleusercontent.com';

class GoogleSignInHelper {
  GoogleSignInHelper._();

  static final GoogleSignIn _google = GoogleSignIn.instance;
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await _google.initialize(serverClientId: kGoogleWebClientId);
    _initialized = true;
  }

  /// Firebase Google sign-in. Prefers the plugin account picker, then falls
  /// back to Firebase's provider flow (works when Credential Manager fails
  /// on Android 10 / missing Play Sign-In config).
  static Future<User?> signInToFirebase() async {
    FirebaseAuthException? providerError;

    try {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile')
        ..setCustomParameters({'prompt': 'select_account'});
      final cred = await FirebaseAuth.instance.signInWithProvider(provider);
      return cred.user;
    } on FirebaseAuthException catch (e) {
      if (_isCanceled(e)) return null;
      providerError = e;
      debugPrint('Google signInWithProvider failed: ${e.code} ${e.message}');
    } catch (e) {
      if (_isCanceled(e)) return null;
      debugPrint('Google signInWithProvider failed: $e');
    }

    try {
      await ensureInitialized();
      if (!kIsWeb && !_google.supportsAuthenticate()) {
        throw providerError ??
            Exception('Google Sign-In is not supported on this device.');
      }
      final account = await _google.authenticate(
        scopeHint: const ['email', 'profile', 'openid'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-id-token',
          message:
              'Google did not return an ID token. Add the debug SHA-1 of this '
              'app (com.vero265.app) in Firebase Console → Project settings.',
        );
      }
      final cred = GoogleAuthProvider.credential(idToken: idToken);
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(cred);
      return userCred.user;
    } catch (e) {
      if (_isCanceled(e)) return null;
      throw _wrap(e, providerError);
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
      return c.contains('cancel') || c == 'web-context-canceled';
    }
    if (e is GoogleSignInException) {
      return e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted;
    }
    final s = e.toString().toLowerCase();
    return s.contains('cancel') || s.contains('canceled');
  }

  static Object _wrap(Object e, FirebaseAuthException? providerError) {
    if (e is FirebaseAuthException) return e;
    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return FirebaseAuthException(
            code: 'google-config',
            message:
                'Google Sign-In is not configured for com.vero265.app. In Firebase '
                'Console add this app’s SHA-1 (and SHA-256) under Project settings '
                '→ Your apps, then download a new google-services.json.',
          );
        case GoogleSignInExceptionCode.uiUnavailable:
          return FirebaseAuthException(
            code: 'google-ui',
            message:
                'Google Sign-In UI is unavailable. Update Google Play services and try again.',
          );
        default:
          return FirebaseAuthException(
            code: 'google-sign-in',
            message: e.description?.trim().isNotEmpty == true
                ? e.description
                : 'Google sign-in failed. Please try again.',
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
            'Google Sign-In is not configured for com.vero265.app. Add SHA-1 / '
            'SHA-256 in Firebase Console for this package, then rebuild the app.',
      );
    }
    return providerError ?? e;
  }
}
