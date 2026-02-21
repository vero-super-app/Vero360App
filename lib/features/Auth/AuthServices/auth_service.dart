// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/utils/toasthelper.dart';

enum DeleteAccountStatus { success, requiresRecentLogin, failed }

class AuthService {
  static const Duration _reqTimeoutWarm = Duration(seconds: 18);

  // ✅ google_sign_in 7.x
  final GoogleSignIn _google = GoogleSignIn.instance;

  static const List<String> _googleScopes = <String>[
    'openid',
    'email',
    'profile',
  ];

  static bool _googleInitialized = false;

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // -------------------- Helpers --------------------

  void _toast(BuildContext ctx, String msg, {bool ok = true}) {
    ToastHelper.showCustomToast(
      ctx,
      msg,
      isSuccess: ok,
      errorMessage: ok ? '' : msg,
    );
  }

  bool _is2xx(int code) => code >= 200 && code < 300;

  bool _looksLikeServerDown(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('service unavailable') ||
        msg.contains('temporarily unavailable') ||
        msg.contains('503') ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('timed out');
  }

  Future<void> _ensureGoogleInit() async {
    if (_googleInitialized) return;

    // If you have specific clientId/serverClientId, pass them here.
    // await _google.initialize(clientId: "...", serverClientId: "...");
    await _google.initialize();

    _googleInitialized = true;
  }

  Future<String?> _readAnyToken() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString('jwt_token') ??
          sp.getString('token') ??
          sp.getString('authToken') ??
          sp.getString('jwt');
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _normalizeBackendAuthResponse(
      Map<String, dynamic> data) {
    final token = data['access_token'] ?? data['token'] ?? data['jwt'];

    final rawUser = data['user'] ?? data;
    final Map<String, dynamic> user = rawUser is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{'raw': rawUser};

    final role = (user['role'] ?? user['userRole'] ?? 'customer')
        .toString()
        .toLowerCase();
    user['role'] = role;

    return {
      'authProvider': 'backend',
      'token': token?.toString(),
      'user': user,
    };
  }

  // -------------------- Firebase profile helpers --------------------

  Future<void> _saveFirebaseProfile(
    User user, {
    String? name,
    String? phone,
    String? role,
    Map<String, dynamic>? merchantData,
  }) async {
    try {
      final roleLc = (role ?? '').toLowerCase();
      final doc = _firestore.collection('users').doc(user.uid);

      final data = <String, dynamic>{
        'email': user.email,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (roleLc.isNotEmpty) 'role': roleLc,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (merchantData != null && roleLc == 'merchant') {
        data.addAll(merchantData);
      }

      await doc.set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _buildFirebaseAuthResult(
    User user, {
    String? fallbackName,
    String? fallbackPhone,
    String? fallbackRole,
    Map<String, dynamic>? merchantData,
  }) async {
    Map<String, dynamic> profile = {};
    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      if (snap.exists && snap.data() != null) {
        profile = Map<String, dynamic>.from(snap.data()!);
      }
    } catch (_) {}

    final name =
        (profile['name'] ?? fallbackName ?? user.displayName ?? '').toString();
    final phone = (profile['phone'] ?? fallbackPhone ?? '').toString();
    final role = (profile['role'] ?? fallbackRole ?? 'customer')
        .toString()
        .toLowerCase();

    final token = await user.getIdToken();

    // Log JWT so you can see it in console (not the UID)
    if (token != null && token.isNotEmpty) {
      debugPrint('[JWT] Firebase ID token (JWT): $token');
    }

    final userMap = <String, dynamic>{
      'id': user.uid,
      'firebaseUid': user.uid,
      'email': user.email ?? '',
      'phone': phone,
      'name': name,
      'role': role,
    };

    if (merchantData != null && role == 'merchant') {
      userMap.addAll(merchantData);
    }

    return {
      'authProvider': 'firebase',
      'token': token,
      'user': userMap,
    };
  }

  Future<Map<String, dynamic>?> _loginWithFirebaseEmailPassword(
    String email,
    String password,
    BuildContext context, {
    String? onFailMessage,
  }) async {
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        _toast(context, onFailMessage ?? 'login failed (no user).', //backup
            ok: false);
        return null;
      }

      _toast(context, 'Logged in successfully', ok: true);
      return _buildFirebaseAuthResult(user, fallbackRole: 'customer');
    } on FirebaseAuthException catch (e) {
      _toast(context, onFailMessage ?? (e.message ?? 'Backup login failed.'),
          ok: false);
      return null;
    } catch (_) {
      _toast(context, onFailMessage ?? 'login failed.', ok: false);
      return null;
    }
  }

  Future<void> _ensureFirebaseMirrorForBackendUser({
    required String email,
    required String password,
    Map<String, dynamic>? backendUser,
    Map<String, dynamic>? merchantData,
  }) async {
    try {
      final current = _firebaseAuth.currentUser;
      if (current != null && current.email == email) {
        await _saveFirebaseProfile(
          current,
          name: backendUser?['name']?.toString(),
          phone: backendUser?['phone']?.toString(),
          role: (backendUser?['role'] ?? backendUser?['userRole'])?.toString(),
          merchantData: merchantData,
        );
        return;
      }

      try {
        final cred = await _firebaseAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        await _saveFirebaseProfile(
          cred.user!,
          name: backendUser?['name']?.toString(),
          phone: backendUser?['phone']?.toString(),
          role: (backendUser?['role'] ?? backendUser?['userRole'])?.toString(),
          merchantData: merchantData,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          final cred = await _firebaseAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );

          await _saveFirebaseProfile(
            cred.user!,
            name: backendUser?['name']?.toString(),
            phone: backendUser?['phone']?.toString(),
            role:
                (backendUser?['role'] ?? backendUser?['userRole'])?.toString(),
            merchantData: merchantData,
          );
        }
      }
    } catch (_) {}
  }

  // -------------------- Login (Backend first, Firebase fallback for email) --------------------

  Future<Map<String, dynamic>?> loginWithIdentifier(
    String identifier,
    String password,
    BuildContext context,
  ) async {
    final trimmedId = identifier.trim();

    try {
      // ✅ Use ApiConfig for production-ready endpoint
      final res = await http
          .post(
            ApiConfig.endpoint('/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({'identifier': trimmedId, 'password': password}),
          )
          .timeout(_reqTimeoutWarm);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        String? backendMsg;
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded['message'] != null) {
            final m = decoded['message'];
            if (m is List) {
              backendMsg = m.join('\n');
            } else {
              backendMsg = m.toString();
            }
          }
        } catch (_) {}
        throw ApiException(
          message: backendMsg ?? 'Login failed. Please check your details.',
          statusCode: res.statusCode,
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _toast(context, 'Signed in');
      final normalized = _normalizeBackendAuthResponse(data);

      if (trimmedId.contains('@')) {
        final user = normalized['user'] as Map<String, dynamic>?;
        final roleLc =
            (user?['role'] ?? user?['userRole'] ?? '').toString().toLowerCase();

        Map<String, dynamic>? merchantData;
        if (roleLc == 'merchant') {
          merchantData = {
            'merchantService': user?['merchantService'],
            'businessName': user?['businessName'],
            'businessAddress': user?['businessAddress'],
          };
        }

        _ensureFirebaseMirrorForBackendUser(
          email: trimmedId,
          password: password,
          backendUser: user,
          merchantData: merchantData,
        );
      }

      return normalized;
    } on ApiException catch (e) {
      if (trimmedId.contains('@')) {
        final fb = await _loginWithFirebaseEmailPassword(
          trimmedId,
          password,
          context,
          onFailMessage: e.message,
        );
        if (fb != null) return fb;
      }
      _toast(context, e.message, ok: false);
      return null;
    } catch (e) {
      if (trimmedId.contains('@')) {
        final fb = await _loginWithFirebaseEmailPassword(
          trimmedId,
          password,
          context,
        );
        if (fb != null) return fb;
      }
      _toast(context,
          _looksLikeServerDown(e) ? 'Server unreachable.' : 'Login failed.',
          ok: false);
      return null;
    }
  }

  // -------------------- OTP --------------------

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
      _toast(context, 'OTP failed: ${e.message}', ok: false);
      return false;
    } catch (_) {
      _toast(context, 'OTP failed (server unreachable)', ok: false);
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
        _toast(context, 'No ticket returned', ok: false);
        return null;
      }

      _toast(context, 'Verified');
      return ticket;
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Verification failed (server unreachable)', ok: false);
      return null;
    }
  }

  // -------------------- Register --------------------

  Future<Map<String, dynamic>?> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    required String profilePicture,
    required String preferredVerification,
    required String verificationTicket,
    Map<String, dynamic>? merchantData,
    required BuildContext context,
  }) async {
    final normalizedRole = role.toLowerCase();

    // 1) Try backend register if ticket exists
    if (verificationTicket.trim().isNotEmpty) {
      try {
        final body = <String, dynamic>{
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'role': normalizedRole,
          'profilepicture': profilePicture,
          'preferredVerification': preferredVerification,
          'verificationTicket': verificationTicket,
          if (merchantData != null) ...merchantData,
        };

        final res = await ApiClient.post(
          '/auth/register',
          body: jsonEncode(body),
          timeout: _reqTimeoutWarm,
        );

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Account created');

        final backendAuth = _normalizeBackendAuthResponse(data);

        // mirror to Firebase
        if (email.trim().isNotEmpty) {
          await _ensureFirebaseMirrorForBackendUser(
            email: email.trim(),
            password: password,
            backendUser: backendAuth['user'] as Map<String, dynamic>?,
            merchantData: merchantData,
          );
        }

        return backendAuth;
      } on ApiException catch (e) {
        _toast(context, 'Backend signup failed: ${e.message}', ok: false);
      } catch (e) {
        _toast(context, 'Signup error: $e', ok: false);
      }
    }

    // 2) Firebase fallback
    if (email.trim().isEmpty) {
      _toast(context, 'Email required for backup sign-up.', ok: false);
      return null;
    }

    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        _toast(context, 'Backup signup failed.', ok: false);
        return null;
      }

      await _saveFirebaseProfile(
        user,
        name: name,
        phone: phone,
        role: normalizedRole,
        merchantData: merchantData,
      );

      final auth = await _buildFirebaseAuthResult(
        user,
        fallbackName: name,
        fallbackPhone: phone,
        fallbackRole: normalizedRole,
        merchantData: merchantData,
      );

      _toast(context, 'Account created (backup)', ok: true);
      return auth;
    } on FirebaseAuthException catch (e) {
      _toast(context, e.message ?? 'Backup signup failed.', ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Signup failed. Try again later.', ok: false);
      return null;
    }
  }

  // -------------------- Google Sign-In (google_sign_in 7.x) --------------------

  Future<Map<String, dynamic>?> continueWithGoogle(BuildContext context) async {
    try {
      await _ensureGoogleInit();

      if (!_google.supportsAuthenticate()) {
        _toast(context, 'Google Sign-In not supported on this platform',
            ok: false);
        return null;
      }

      final GoogleSignInAccount account = await _google.authenticate();
      if (account == null) return null;

      // Prefer server auth code for backend exchange
      GoogleSignInServerAuthorization? serverAuth;
      try {
        serverAuth =
            await account.authorizationClient.authorizeServer(_googleScopes);
      } catch (_) {}

      final serverAuthCode = serverAuth?.serverAuthCode;

      // Fallback tokens (if your backend still accepts idToken)
      String? idToken;
      try {
        final auth = account.authentication;
        idToken = auth.idToken;
      } catch (_) {}

      if ((serverAuthCode == null || serverAuthCode.isEmpty) &&
          (idToken == null || idToken.isEmpty)) {
        _toast(context, 'Could not get Google token', ok: false);
        return null;
      }

      // ✅ Use ApiConfig for production-ready endpoint
      final res = await http
          .post(
            ApiConfig.endpoint('/auth/google'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({
              if (serverAuthCode != null && serverAuthCode.isNotEmpty)
                'serverAuthCode': serverAuthCode,
              if (idToken != null && idToken.isNotEmpty) 'idToken': idToken,
              'email': account.email,
            }),
          )
          .timeout(_reqTimeoutWarm);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        String? backendMsg;
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded['message'] != null) {
            final m = decoded['message'];
            if (m is List) {
              backendMsg = m.join('\n');
            } else {
              backendMsg = m.toString();
            }
          }
        } catch (_) {}
        throw ApiException(
          message: backendMsg ?? 'Google sign-in failed.',
          statusCode: res.statusCode,
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _toast(context, 'Signed in with Google');
      return _normalizeBackendAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Google sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  // -------------------- Apple Sign-In --------------------

  Future<Map<String, dynamic>?> continueWithApple(BuildContext context) async {
    try {
      if (!Platform.isIOS) {
        _toast(context, 'Apple Sign-In is only available on iOS', ok: false);
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

      // ✅ Use ApiConfig for production-ready endpoint
      final res = await http
          .post(
            ApiConfig.endpoint('/auth/apple'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({
              'identityToken': identityToken,
              'rawNonce': rawNonce,
              if (fullName.isNotEmpty) 'fullName': fullName,
            }),
          )
          .timeout(_reqTimeoutWarm);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        String? backendMsg;
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded['message'] != null) {
            final m = decoded['message'];
            if (m is List) {
              backendMsg = m.join('\n');
            } else {
              backendMsg = m.toString();
            }
          }
        } catch (_) {}
        throw ApiException(
          message: backendMsg ?? 'Apple sign-in failed.',
          statusCode: res.statusCode,
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _toast(context, 'Signed in with Apple');
      return _normalizeBackendAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Apple sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  // -------------------- Delete Account Everywhere --------------------

  Future<DeleteAccountStatus> deleteAccountEverywhere(
      BuildContext context) async {
    final token = await _readAnyToken();

    bool backendDeleted = false;
    if (token != null && token.trim().isNotEmpty) {
      try {
        // ✅ Use ApiConfig for production-ready endpoint
        final resp = await http.delete(
          ApiConfig.endpoint('/users/me'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );
        backendDeleted = _is2xx(resp.statusCode);
      } catch (_) {
        backendDeleted = false;
      }
    } else {
      backendDeleted = true;
    }

    bool firebaseDeleted = true;
    final u = _firebaseAuth.currentUser;

    if (u != null) {
      try {
        await _firestore.collection('users').doc(u.uid).delete();
      } catch (_) {}

      try {
        await u.delete();
      } on FirebaseAuthException catch (e) {
        firebaseDeleted = false;
        if (e.code == 'requires-recent-login') {
          _toast(context, 'Please login again, then try deleting your account.',
              ok: false);
          await logout(context: context);
          return DeleteAccountStatus.requiresRecentLogin;
        }
      } catch (_) {
        firebaseDeleted = false;
      }
    }

    await logout(context: context);

    if (backendDeleted && firebaseDeleted) {
      _toast(context, 'Account deleted', ok: true);
      return DeleteAccountStatus.success;
    }

    _toast(context, 'Account delete partially completed.', ok: false);
    return DeleteAccountStatus.failed;
  }

  // -------------------- Logout --------------------

  Future<bool> logout({BuildContext? context}) async {
    String? token;
    try {
      final sp = await SharedPreferences.getInstance();
      token = sp.getString('token') ??
          sp.getString('jwt_token') ??
          sp.getString('authToken') ??
          sp.getString('jwt');
    } catch (_) {}

    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient.post(
          '/auth/logout',
          headers: {'Authorization': 'Bearer $token'},
          body: jsonEncode({}),
        );
      } catch (_) {}
    }

    // Google
    try {
      await _google.signOut();
    } catch (_) {}

    // Firebase
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}

    final ok = await _clearLocalSession();
    if (context != null) {
      _toast(context, ok ? 'Signed out' : 'Signed out (cleanup error)', ok: ok);
    }
    return ok;
  }

  Future<bool> _clearLocalSession() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in const [
        'token',
        'jwt_token',
        'authToken',
        'jwt',
        'email',
        'prefill_login_identifier',
        'prefill_login_role',
        'merchant_review_pending',
        'auth_provider',
        'merchant_service',
        'business_name',
        'business_address',
        'uid',
        'role',
        'user_role',
        'fullName',
        'name',
        'phone',
        'address',
        'profilepicture',
      ]) {
        await sp.remove(k);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------- Merchant helpers --------------------

  Future<String> getMerchantStatus(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['status']?.toString() ?? 'pending';
      }
      return 'pending';
    } catch (_) {
      return 'pending';
    }
  }

  Future<bool> updateMerchantProfile({
    required String uid,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> prewarm() => ApiConfig.ensureBackendUp();

  // -------------------- Nonce helpers --------------------

  String _randomNonce([int length = 32]) {
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
