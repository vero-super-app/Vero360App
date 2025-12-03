// lib/services/auth_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/toasthelper.dart';

class AuthService {
  static const Duration _reqTimeoutWarm = Duration(seconds: 18);

  final GoogleSignIn _google = GoogleSignIn(scopes: ['email', 'profile']);

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _toast(BuildContext ctx, String msg, {bool ok = true}) {
    ToastHelper.showCustomToast(
      ctx,
      msg,
      isSuccess: ok,
      errorMessage: ok ? '' : msg,
    );
  }

  // ---------------------------------------------------------------------------
  //  EMAIL / PHONE + PASSWORD LOGIN  (BACKEND + FIREBASE BACKUP)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> loginWithIdentifier(
    String identifier,
    String password,
    BuildContext context,
  ) async {
    // 1) Try primary NestJS backend
    try {
      final res = await ApiClient.post(
        '/auth/login',
        body: jsonEncode({
          'identifier': identifier,
          'password': password,
        }),
        timeout: _reqTimeoutWarm,
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final normalized = _normalizeAuthResponse(data);

      _toast(context, 'Signed in');

      return {
        'authProvider': 'backend',
        ...normalized,
      };
    } on ApiException catch (e) {
      final msgLower = e.message.toLowerCase();
      final looksUnavailable = msgLower.contains('service unavailable') ||
          msgLower.contains('503') ||
          msgLower.contains('502') ||
          msgLower.contains('unreachable') ||
          msgLower.contains('failed host lookup');

      if (looksUnavailable) {
        // 2) Fallback → Firebase email/password login
        return _fallbackFirebaseEmailPasswordLogin(
          identifier,
          password,
          context,
          reason: e.message,
        );
      }

      _toast(context, e.message, ok: false);
      return null;
    } on SocketException catch (e) {
      // Network / DNS issue → fallback
      return _fallbackFirebaseEmailPasswordLogin(
        identifier,
        password,
        context,
        reason: 'Network error: ${e.message}',
      );
    } on TimeoutException catch (_) {
      // Timeout → fallback
      return _fallbackFirebaseEmailPasswordLogin(
        identifier,
        password,
        context,
        reason: 'Request timed out',
      );
    } catch (_) {
      _toast(context, 'Something went wrong. Please try again.', ok: false);
      return null;
    }
  }

  /// Firebase login backup: supports email directly, and phone via Firestore lookup.
  Future<Map<String, dynamic>?> _fallbackFirebaseEmailPasswordLogin(
    String identifier,
    String password,
    BuildContext context, {
    String? reason,
  }) async {
    try {
      // Resolve email to use with Firebase
      final String emailForFirebase;

      if (identifier.contains('@')) {
        // direct email login
        emailForFirebase = identifier.trim();
      } else {
        // phone login → resolve via Firestore profile
        final normalizedPhone = identifier.trim();
        final snap = await _firestore
            .collection('users')
            .where('phone', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        if (snap.docs.isEmpty) {
          _toast(
            context,
            'Our main server is offline and no backup account is registered for this phone. '
            'Please try using your email instead.',
            ok: false,
          );
          return null;
        }
        final data = snap.docs.first.data();
        final email = data['email']?.toString();
        if (email == null || email.isEmpty) {
          _toast(
            context,
            'Backup account is missing an email. Please try logging in with your email.',
            ok: false,
          );
          return null;
        }
        emailForFirebase = email;
      }

      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: emailForFirebase,
        password: password,
      );
      final fbUser = cred.user;
      if (fbUser == null) {
        _toast(context, 'Could not sign in with Firebase backup.', ok: false);
        return null;
      }

      final idToken = await fbUser.getIdToken();

      Map<String, dynamic> profileData = {};
      try {
        final snap =
            await _firestore.collection('users').doc(fbUser.uid).get();
        if (snap.exists) {
          profileData = (snap.data() as Map<String, dynamic>?) ?? {};
        }
      } catch (_) {}

      final mergedUser = {
        'uid': fbUser.uid,
        'email': fbUser.email,
        'phone': profileData['phone'] ?? fbUser.phoneNumber,
        'name': profileData['name'] ?? fbUser.displayName ?? '',
        'role': (profileData['role'] ?? 'customer').toString(),
        'profilePicture': profileData['profilePicture'] ?? '',
        'preferredVerification':
            profileData['preferredVerification'] ?? 'email',
        'provider': 'firebase',
        ...profileData,
      };

      _toast(context, 'Signed in (backup)', ok: true);

      return {
        'authProvider': 'firebase',
        'token': idToken,
        'user': mergedUser,
      };
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
          msg = 'Incorrect credentials for backup sign-in.';
          break;
        case 'invalid-email':
          msg = 'Invalid email address.';
          break;
        default:
          msg = 'Firebase login failed: ${e.message ?? e.code}';
      }
      _toast(context, msg, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Backup login failed.', ok: false);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  //  OTP (REGISTER FLOW) - still backend only
  // ---------------------------------------------------------------------------
  Future<bool> requestOtp({
    required String channel, // 'email' | 'phone'
    String? email,
    String? phone,
    required BuildContext context,
  }) async {
    try {
      await ApiClient.post(
        '/auth/otp/request',
        body: jsonEncode({
          'channel': channel,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
        }),
        timeout: _reqTimeoutWarm,
      );

      _toast(context, 'Verification code sent');
      return true;
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return false;
    } catch (_) {
      _toast(context, 'Something went wrong. Please try again.', ok: false);
      return false;
    }
  }

  Future<String?> verifyOtpGetTicket({
    required String identifier,
    required String code,
    required BuildContext context,
  }) async {
    try {
      final channel = identifier.contains('@') ? 'email' : 'phone';

      final res = await ApiClient.post(
        '/auth/otp/verify',
        body: jsonEncode({
          'channel': channel,
          if (channel == 'email') 'email': identifier,
          if (channel == 'phone') 'phone': identifier,
          'code': code,
        }),
        timeout: _reqTimeoutWarm,
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final ticket = data['ticket']?.toString();

      if (ticket == null || ticket.isEmpty) {
        _toast(context, 'No ticket in response', ok: false);
        return null;
      }

      _toast(context, 'Verified');
      return ticket;
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Something went wrong. Please try again.', ok: false);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  //  REGISTER USER (BACKEND + FULL FIREBASE MIRROR + BACKUP)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    required String profilePicture,
    required String preferredVerification,
    required String verificationTicket,
    required BuildContext context,
  }) async {
    // 1) Try primary backend registration
    try {
      final res = await ApiClient.post(
        '/auth/register',
        body: jsonEncode({
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'role': role,
          'profilepicture': profilePicture,
          'preferredVerification': preferredVerification,
          'verificationTicket': verificationTicket,
        }),
        timeout: _reqTimeoutWarm,
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final normalized = _normalizeAuthResponse(data);

      _toast(context, 'Account created');

      // Mirror into Firebase for backup
      try {
        await _mirrorBackendUserToFirebase(
          name: name,
          email: email,
          phone: phone,
          password: password,
          role: role,
          profilePicture: profilePicture,
          preferredVerification: preferredVerification,
        );
      } catch (_) {
        // Mirror failure should not block backend success
      }

      return {
        'authProvider': 'backend',
        ...normalized,
      };
    } on ApiException catch (e) {
      final lower = e.message.toLowerCase();
      final looksUnavailable = lower.contains('service unavailable') ||
          lower.contains('503') ||
          lower.contains('502') ||
          lower.contains('unreachable') ||
          lower.contains('failed host lookup');

      if (!looksUnavailable) {
        _toast(context, e.message, ok: false);
        return null;
      }

      // Backend is down → fallback to Firebase-only registration
      return _registerWithFirebaseBackup(
        name: name,
        email: email,
        phone: phone,
        password: password,
        role: role,
        profilePicture: profilePicture,
        preferredVerification: preferredVerification,
        context: context,
      );
    } on SocketException catch (_) {
      // Network down → Firebase backup
      return _registerWithFirebaseBackup(
        name: name,
        email: email,
        phone: phone,
        password: password,
        role: role,
        profilePicture: profilePicture,
        preferredVerification: preferredVerification,
        context: context,
      );
    } on TimeoutException catch (_) {
      // Timeout → Firebase backup
      return _registerWithFirebaseBackup(
        name: name,
        email: email,
        phone: phone,
        password: password,
        role: role,
        profilePicture: profilePicture,
        preferredVerification: preferredVerification,
        context: context,
      );
    } catch (_) {
      _toast(context, 'Something went wrong. Please try again.', ok: false);
      return null;
    }
  }

  /// Used when the backend is unavailable. Creates the user only in Firebase.
  Future<Map<String, dynamic>?> _registerWithFirebaseBackup({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    required String profilePicture,
    required String preferredVerification,
    required BuildContext context,
  }) async {
    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fbUser = cred.user;
      if (fbUser == null) {
        _toast(context, 'Backup signup failed.', ok: false);
        return null;
      }

      await fbUser.updateDisplayName(name.trim());

      await _firestore.collection('users').doc(fbUser.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'role': role,
        'profilePicture': profilePicture,
        'preferredVerification': preferredVerification,
        'provider': 'firebase',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final idToken = await fbUser.getIdToken();

      _toast(context, 'Account created (backup)', ok: true);

      return {
        'authProvider': 'firebase',
        'token': idToken,
        'user': {
          'uid': fbUser.uid,
          'name': name.trim(),
          'email': email.trim(),
          'phone': phone.trim(),
          'role': role,
          'profilePicture': profilePicture,
          'preferredVerification': preferredVerification,
          'provider': 'firebase',
        },
      };
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email already has a backup account. Try logging in instead.';
          break;
        case 'invalid-email':
          msg = 'Invalid email address for backup registration.';
          break;
        case 'weak-password':
          msg = 'Password is too weak for backup registration.';
          break;
        default:
          msg = 'Firebase signup failed: ${e.message ?? e.code}';
      }
      _toast(context, msg, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Backup signup failed.', ok: false);
      return null;
    }
  }

  /// Called after successful backend registration to mirror the user into Firebase.
  Future<void> _mirrorBackendUserToFirebase({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    required String profilePicture,
    required String preferredVerification,
  }) async {
    // We want the user to be able to log in via Firebase with the same email/password
    try {
      UserCredential cred;
      try {
        // Try creating a new account
        cred = await _firebaseAuth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // If it already exists, sign in instead to update the profile
          cred = await _firebaseAuth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final fbUser = cred.user;
      if (fbUser == null) return;

      await fbUser.updateDisplayName(name.trim());

      await _firestore.collection('users').doc(fbUser.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'role': role,
        'profilePicture': profilePicture,
        'preferredVerification': preferredVerification,
        'provider': 'firebase',
        'mirroredFromBackend': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Silently ignore mirror errors — backend registration still succeeded.
    }
  }

  // ---------------------------------------------------------------------------
  //  LOGOUT
  // ---------------------------------------------------------------------------
  Future<bool> logout({BuildContext? context}) async {
    String? token;
    try {
      final sp = await SharedPreferences.getInstance();
      token = sp.getString('token') ??
          sp.getString('jwt_token') ??
          sp.getString('jwt');
    } catch (_) {}

    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient.post(
          '/auth/logout',
          headers: {'Authorization': 'Bearer $token'},
          body: jsonEncode({}),
        );
      } catch (_) {
        // ignore logout errors
      }
    }

    // Google sign out
    try {
      await _google.signOut();
    } catch (_) {}
    try {
      await _google.disconnect();
    } catch (_) {}

    // Firebase sign out (for backup sessions)
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}

    final ok = await _clearLocalSession();
    if (context != null) {
      _toast(
        context,
        ok ? 'Signed out' : 'Signed out (local cleanup error)',
        ok: ok,
      );
    }
    return ok;
  }

  Future<bool> _clearLocalSession() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in const [
        'token',
        'jwt_token',
        'jwt',
        'email',
        'auth_provider',
        'prefill_login_identifier',
        'prefill_login_role',
        'merchant_review_pending',
      ]) {
        await sp.remove(k);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  //  SOCIAL LOGIN: GOOGLE  (backend first, Firebase mirror)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> continueWithGoogle(
    BuildContext context,
  ) async {
    try {
      final acct = await _google.signIn();
      if (acct == null) return null; // cancelled

      final auth = await acct.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        _toast(context, 'No Google ID token', ok: false);
        return null;
      }

      // 1) Try backend social login
      try {
        final res = await ApiClient.post(
          '/auth/google',
          body: jsonEncode({'idToken': idToken}),
          timeout: _reqTimeoutWarm,
        );

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final normalized = _normalizeAuthResponse(data);

        _toast(context, 'Signed in with Google');

        // Also mirror into Firebase
        try {
          await _signIntoFirebaseWithGoogleAndSyncProfile(acct);
        } catch (_) {}

        return {
          'authProvider': 'backend',
          ...normalized,
        };
      } on ApiException catch (e) {
        final lower = e.message.toLowerCase();
        final looksUnavailable = lower.contains('service unavailable') ||
            lower.contains('503') ||
            lower.contains('502') ||
            lower.contains('unreachable') ||
            lower.contains('failed host lookup');

        if (!looksUnavailable) {
          _toast(context, e.message, ok: false);
          return null;
        }

        // Backend is down → Firebase only
        return _signIntoFirebaseWithGoogleAndReturn(acct, context);
      } on SocketException catch (_) {
        // Network → Firebase only
        return _signIntoFirebaseWithGoogleAndReturn(acct, context);
      } on TimeoutException catch (_) {
        // Timeout → Firebase only
        return _signIntoFirebaseWithGoogleAndReturn(acct, context);
      }
    } catch (e) {
      _toast(context, 'Google sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  Future<void> _signIntoFirebaseWithGoogleAndSyncProfile(
    GoogleSignInAccount acct,
  ) async {
    final googleAuth = await acct.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final fbCred = await _firebaseAuth.signInWithCredential(cred);
    final fbUser = fbCred.user;
    if (fbUser == null) return;

    await _firestore.collection('users').doc(fbUser.uid).set({
      'name': fbUser.displayName ?? acct.displayName ?? '',
      'email': fbUser.email ?? acct.email,
      'phone': fbUser.phoneNumber,
      'role': 'customer',
      'profilePicture': fbUser.photoURL ?? '',
      'preferredVerification': 'email',
      'provider': 'firebase-google',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> _signIntoFirebaseWithGoogleAndReturn(
    GoogleSignInAccount acct,
    BuildContext context,
  ) async {
    try {
      final googleAuth = await acct.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final fbCred = await _firebaseAuth.signInWithCredential(cred);
      final fbUser = fbCred.user;
      if (fbUser == null) {
        _toast(context, 'Google backup sign-in failed.', ok: false);
        return null;
      }

      await _firestore.collection('users').doc(fbUser.uid).set({
        'name': fbUser.displayName ?? acct.displayName ?? '',
        'email': fbUser.email ?? acct.email,
        'phone': fbUser.phoneNumber,
        'role': 'customer',
        'profilePicture': fbUser.photoURL ?? '',
        'preferredVerification': 'email',
        'provider': 'firebase-google',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final idToken = await fbUser.getIdToken();

      _toast(context, 'Signed in with Google (backup)', ok: true);

      return {
        'authProvider': 'firebase',
        'token': idToken,
        'user': {
          'uid': fbUser.uid,
          'name': fbUser.displayName ?? acct.displayName ?? '',
          'email': fbUser.email ?? acct.email,
          'phone': fbUser.phoneNumber,
          'role': 'customer',
          'profilePicture': fbUser.photoURL ?? '',
          'preferredVerification': 'email',
          'provider': 'firebase-google',
        },
      };
    } catch (_) {
      _toast(context, 'Google backup sign-in failed.', ok: false);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  //  SOCIAL LOGIN: APPLE  (backend first, Firebase mirror)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> continueWithApple(
    BuildContext context,
  ) async {
    try {
      if (!Platform.isIOS) {
        _toast(
          context,
          'Apple Sign-In is only available on iOS',
          ok: false,
        );
        return null;
      }

      final rawNonce = _randomNonce();
      final nonce = _sha256of(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        _toast(context, 'No Apple identity token', ok: false);
        return null;
      }

      final fullName = [
        credential.givenName ?? '',
        credential.familyName ?? '',
      ].where((s) => s.trim().isNotEmpty).join(' ').trim();

      // 1) Try backend first
      try {
        final res = await ApiClient.post(
          '/auth/apple',
          body: jsonEncode({
            'identityToken': identityToken,
            'rawNonce': rawNonce,
            if (fullName.isNotEmpty) 'fullName': fullName,
          }),
          timeout: _reqTimeoutWarm,
        );

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final normalized = _normalizeAuthResponse(data);

        _toast(context, 'Signed in with Apple');

        // Mirror to Firebase (best-effort)
        try {
          await _signIntoFirebaseWithAppleAndSyncProfile(
            identityToken: identityToken,
            rawNonce: rawNonce,
            fullName: fullName,
          );
        } catch (_) {}

        return {
          'authProvider': 'backend',
          ...normalized,
        };
      } on ApiException catch (e) {
        final lower = e.message.toLowerCase();
        final looksUnavailable = lower.contains('service unavailable') ||
            lower.contains('503') ||
            lower.contains('502') ||
            lower.contains('unreachable') ||
            lower.contains('failed host lookup');

        if (!looksUnavailable) {
          _toast(context, e.message, ok: false);
          return null;
        }

        // Backend down → Firebase only
        return _signIntoFirebaseWithAppleAndReturn(
          identityToken: identityToken,
          rawNonce: rawNonce,
          fullName: fullName,
          context: context,
        );
      } on SocketException catch (_) {
        return _signIntoFirebaseWithAppleAndReturn(
          identityToken: identityToken,
          rawNonce: rawNonce,
          fullName: fullName,
          context: context,
        );
      } on TimeoutException catch (_) {
        return _signIntoFirebaseWithAppleAndReturn(
          identityToken: identityToken,
          rawNonce: rawNonce,
          fullName: fullName,
          context: context,
        );
      }
    } catch (_) {
      _toast(context, 'Apple sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  Future<void> _signIntoFirebaseWithAppleAndSyncProfile({
    required String identityToken,
    required String rawNonce,
    required String fullName,
  }) async {
    final appleProvider = OAuthProvider('apple.com');
    final credential = appleProvider.credential(
      idToken: identityToken,
      rawNonce: rawNonce,
    );
    final fbCred = await _firebaseAuth.signInWithCredential(credential);
    final fbUser = fbCred.user;
    if (fbUser == null) return;

    await _firestore.collection('users').doc(fbUser.uid).set({
      'name': fullName.isNotEmpty ? fullName : (fbUser.displayName ?? ''),
      'email': fbUser.email,
      'phone': fbUser.phoneNumber,
      'role': 'customer',
      'profilePicture': fbUser.photoURL ?? '',
      'preferredVerification': 'email',
      'provider': 'firebase-apple',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> _signIntoFirebaseWithAppleAndReturn({
    required String identityToken,
    required String rawNonce,
    required String fullName,
    required BuildContext context,
  }) async {
    try {
      final appleProvider = OAuthProvider('apple.com');
      final credential = appleProvider.credential(
        idToken: identityToken,
        rawNonce: rawNonce,
      );
      final fbCred = await _firebaseAuth.signInWithCredential(credential);
      final fbUser = fbCred.user;
      if (fbUser == null) {
        _toast(context, 'Apple backup sign-in failed.', ok: false);
        return null;
      }

      final name = fullName.isNotEmpty ? fullName : (fbUser.displayName ?? '');

      await _firestore.collection('users').doc(fbUser.uid).set({
        'name': name,
        'email': fbUser.email,
        'phone': fbUser.phoneNumber,
        'role': 'customer',
        'profilePicture': fbUser.photoURL ?? '',
        'preferredVerification': 'email',
        'provider': 'firebase-apple',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final idToken = await fbUser.getIdToken();

      _toast(context, 'Signed in with Apple (backup)', ok: true);

      return {
        'authProvider': 'firebase',
        'token': idToken,
        'user': {
          'uid': fbUser.uid,
          'name': name,
          'email': fbUser.email,
          'phone': fbUser.phoneNumber,
          'role': 'customer',
          'profilePicture': fbUser.photoURL ?? '',
          'preferredVerification': 'email',
          'provider': 'firebase-apple',
        },
      };
    } catch (_) {
      _toast(context, 'Apple backup sign-in failed.', ok: false);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  //  MISC HELPERS
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _normalizeAuthResponse(Map<String, dynamic> data) {
    final token = data['access_token'] ?? data['token'] ?? data['jwt'];
    return {
      'token': token?.toString(),
      'user': data['user'] ?? data,
    };
  }

  String _randomNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => charset[rand.nextInt(charset.length)],
    ).join();
  }

  String _sha256of(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Optional: call once at app start to pre-warm backend.
  static Future<void> prewarm() => ApiConfig.ensureBackendUp();
}
