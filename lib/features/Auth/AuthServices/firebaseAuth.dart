import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _google = GoogleSignIn.instance;

  static bool _googleInitialized = false;

  static const String _serverClientId =
      '1010595167807-vl7asia9e4eep8u68g9c8mp5aa3eotgi.apps.googleusercontent.com';

  Future<User?> signupWithEmailAndPassword(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await logCurrentIdToken();
      return credential.user;
    } catch (e) {
      print("Error while creating a user: $e");
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
      print("Error while authenticating the user: $e");
      return null;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await _google.initialize(serverClientId: _serverClientId);
        _googleInitialized = true;
      }
      if (!_google.supportsAuthenticate()) {
        print('Google Sign-In not supported on this platform');
        return null;
      }
      final GoogleSignInAccount account = await _google.authenticate();
      if (account == null) return null;
      final auth = account.authentication;
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
      final userCred = await _auth.signInWithCredential(credential);
      await logCurrentIdToken();
      return userCred.user;
    } catch (e) {
      print('Google sign-in failed: $e');
      return null;
    }
  }

  Future<User?> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256of(rawNonce);
      final appleCred = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final oauthCred = OAuthProvider('apple.com').credential(
        idToken: appleCred.identityToken,
        rawNonce: rawNonce,
      );
      final userCred = await _auth.signInWithCredential(oauthCred);
      await logCurrentIdToken();
      return userCred.user;
    } catch (e) {
      print('Apple sign-in failed: $e');
      return null;
    }
  }

  /// Returns the Firebase ID token (JWT), not the UID.
  Future<String?> getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      print("Error while getting ID token: $e");
      return null;
    }
  }

  /// Logs the current Firebase ID token (JWT) to the console.
  Future<void> logCurrentIdToken() async {
    try {
      final token = await getIdToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('[JWT] Firebase ID token (JWT): $token');
      } else {
        print('[JWT] No current user or empty token');
      }
    } catch (e) {
      print('[JWT] Error logging token: $e');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _google.signOut();
    } catch (_) {}
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