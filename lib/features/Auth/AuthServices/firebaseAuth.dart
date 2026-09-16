import 'dart:convert';
import 'dart:math';

import 'dart:async' show unawaited;

import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart';
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
   //   print("Error while creating a user: $e");
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
     // print("Error while authenticating the user: $e");
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    final user = await GoogleSignInHelper.signInToFirebase();
    if (user != null) unawaited(logCurrentIdToken());
    return user;
  }

  /// Returns the signed-in [User], or `null` if the user cancelled.
  /// Throws on configuration / provider failures (missing entitlement, etc.).
  Future<User?> signInWithApple() async {
    try {
      final available = await SignInWithApple.isAvailable();
      if (!available) {
        throw const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.notHandled,
          message: 'Sign in with Apple is not available on this device.',
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

      final idToken = appleCred.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError(
          'Apple did not return an identity token. Check Sign in with Apple '
          'capability, App ID, and provisioning profile.',
        );
      }

      final oauthCred = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
      );
      final userCred = await _auth.signInWithCredential(oauthCred);
      unawaited(logCurrentIdToken());
      return userCred.user;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  /// Apple credential + raw nonce for Firebase reauthentication flows.
  Future<({AuthorizationCredentialAppleID apple, String rawNonce})?>
      getAppleCredentialWithNonce() async {
    try {
      final available = await SignInWithApple.isAvailable();
      if (!available) {
        throw const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.notHandled,
          message: 'Sign in with Apple is not available on this device.',
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

      if (appleCred.identityToken == null ||
          appleCred.identityToken!.isEmpty) {
        throw StateError(
          'Apple did not return an identity token. Check Sign in with Apple '
          'capability, App ID, and provisioning profile.',
        );
      }

      return (apple: appleCred, rawNonce: rawNonce);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  /// Returns the Firebase ID token (JWT), not the UID.
  Future<String?> getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
    //  print("Error while getting ID token: $e");
      return null;
    }
  }

  /// Logs the current Firebase ID token (JWT) to the console.
  Future<void> logCurrentIdToken() async {
    try {
      final token = await getIdToken();
      if (token != null && token.isNotEmpty) {
    //    debugPrint('[JWT] Firebase ID token (JWT): $token');
      } else {
     //   print('[JWT] No current user or empty token');
      }
    } catch (e) {
    //  print('[JWT] Error logging token: $e');
    }
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