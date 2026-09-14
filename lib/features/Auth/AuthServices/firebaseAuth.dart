import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'dart:async' show unawaited;

import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:vero360_app/features/Auth/AuthServices/google_sign_in_helper.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> signupWithEmailAndPassword(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await logCurrentIdToken();
      return credential.user;
    } catch (e) {
      return null;
    }
  }

  Future<User?> signinWithEmailAndPassword(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await logCurrentIdToken();
      return credential.user;
    } catch (e) {
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    final user = await GoogleSignInHelper.signInToFirebase();
    if (user != null) unawaited(logCurrentIdToken());
    return user;
  }

  Future<User?> signInWithApple() async {
    try {
      if (!Platform.isIOS && !Platform.isMacOS) {
        throw FirebaseAuthException(
          code: 'apple-unsupported',
          message: 'Apple Sign-In is only available on iPhone and iPad.',
        );
      }

      final available = await SignInWithApple.isAvailable();
      if (!available) {
        throw FirebaseAuthException(
          code: 'apple-unavailable',
          message:
              'Apple Sign-In is not available on this device. Try again or use email.',
        );
      }

      final rawNonce = _generateNonce();
      final nonce = _sha256of(rawNonce);
      final appleCred = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final identityToken = appleCred.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-id-token',
          message:
              'Apple sign-in failed. Please try again or use email to sign in.',
        );
      }

      // Firebase expects authorizationCode as accessToken for Apple.
      final oauthCred = OAuthProvider('apple.com').credential(
        idToken: identityToken,
        rawNonce: rawNonce,
        accessToken: appleCred.authorizationCode,
      );
      final userCred = await _auth.signInWithCredential(oauthCred);
      final user = userCred.user;

      // Apple only sends the full name on the first authorization — persist it.
      final given = (appleCred.givenName ?? '').trim();
      final family = (appleCred.familyName ?? '').trim();
      final fullName = [given, family].where((s) => s.isNotEmpty).join(' ');
      if (user != null &&
          fullName.isNotEmpty &&
          ((user.displayName ?? '').trim().isEmpty)) {
        try {
          await user.updateDisplayName(fullName);
          await user.reload();
        } catch (_) {}
      }

      unawaited(logCurrentIdToken());
      return _auth.currentUser ?? user;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      if (kDebugMode) debugPrint('[AppleSignIn] ${e.code}: ${e.message}');
      throw FirebaseAuthException(
        code: 'apple-sign-in',
        message: _appleUserMessage(e),
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppleSignIn] $e');
      final s = e.toString().toLowerCase();
      if (s.contains('cancel')) return null;
      throw FirebaseAuthException(
        code: 'apple-sign-in',
        message: 'Apple sign-in failed. Please try again.',
      );
    }
  }

  static String _appleUserMessage(SignInWithAppleAuthorizationException e) {
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        return 'Apple sign-in was cancelled.';
      case AuthorizationErrorCode.failed:
        return 'Apple sign-in failed. Please try again.';
      case AuthorizationErrorCode.invalidResponse:
        return 'Apple returned an invalid response. Please try again.';
      case AuthorizationErrorCode.notHandled:
      case AuthorizationErrorCode.notInteractive:
        return 'Apple Sign-In is not available right now. Try again or use email.';
      case AuthorizationErrorCode.unknown:
      default:
        return 'Apple sign-in failed. Please try again.';
    }
  }

  /// Returns the Firebase ID token (JWT), not the UID.
  Future<String?> getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      return null;
    }
  }

  /// Logs the current Firebase ID token (JWT) to the console.
  Future<void> logCurrentIdToken() async {
    try {
      final token = await getIdToken();
      if (token != null && token.isNotEmpty) {
        // intentionally quiet in production
      }
    } catch (_) {}
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await GoogleSignInHelper.signOut();
  }

  User? get currentUser => _auth.currentUser;

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(length, (_) => charset[rand.nextInt(charset.length)])
        .join();
  }

  String _sha256of(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
