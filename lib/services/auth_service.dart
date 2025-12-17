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
import 'package:http/http.dart' as http; // ✅ REQUIRED (you use http.delete)
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/toasthelper.dart';

/// ✅ Must be TOP-LEVEL (not inside class / not inside method)
enum DeleteAccountStatus { success, requiresRecentLogin, failed }

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

  bool _looksLikeServerDown(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('service unavailable') ||
        msg.contains('service is temporarily unavailable') ||
        msg.contains('503') ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('timed out');
  }

  bool _is2xx(int code) => code >= 200 && code < 300;

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

  // ---------- Backend normaliser ----------

  Map<String, dynamic> _normalizeBackendAuthResponse(Map<String, dynamic> data) {
    final token = data['access_token'] ?? data['token'] ?? data['jwt'];

    final rawUser = data['user'] ?? data;
    Map<String, dynamic> user;
    if (rawUser is Map<String, dynamic>) {
      user = Map<String, dynamic>.from(rawUser);
    } else {
      user = {'raw': rawUser};
    }

    final role =
        (user['role'] ?? user['userRole'] ?? 'customer').toString().toLowerCase();
    user['role'] = role;

    return {
      'authProvider': 'backend',
      'token': token?.toString(),
      'user': user,
    };
  }

  Map<String, dynamic> _normalizeAuthResponse(Map<String, dynamic> data) =>
      _normalizeBackendAuthResponse(data);

  // ---------- Firebase helpers ----------

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

      // Add merchant data if available
      if (merchantData != null && roleLc == 'merchant') {
        data.addAll(
          merchantData.map((k, v) => MapEntry(k, v.toString())),
        );
      }

      await doc.set(data, SetOptions(merge: true));
    } catch (_) {
      // never block auth on profile write
    }
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
    final role =
        (profile['role'] ?? fallbackRole ?? 'customer').toString().toLowerCase();

    final token = await user.getIdToken();

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

  Future<Map<String, dynamic>> _normalizeFirebaseUser(
    User user, {
    String? name,
    String? phone,
    String? role,
    Map<String, dynamic>? merchantData,
  }) async {
    await _saveFirebaseProfile(
      user,
      name: name,
      phone: phone,
      role: role,
      merchantData: merchantData,
    );
    return _buildFirebaseAuthResult(
      user,
      fallbackName: name,
      fallbackPhone: phone,
      fallbackRole: role,
      merchantData: merchantData,
    );
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
        _toast(context, onFailMessage ?? 'Backup login failed (no user).',
            ok: false);
        return null;
      }

      _toast(context, 'Signed in (backup account)', ok: true);
      return await _buildFirebaseAuthResult(user, fallbackRole: 'customer');
    } on FirebaseAuthException catch (e) {
      _toast(context, onFailMessage ?? (e.message ?? 'Backup login failed.'),
          ok: false);
      return null;
    } catch (_) {
      _toast(context, onFailMessage ?? 'Backup login failed.', ok: false);
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
            role: (backendUser?['role'] ?? backendUser?['userRole'])?.toString(),
            merchantData: merchantData,
          );

          // Create merchant profile in service-specific collection if merchant
          final roleLc = (backendUser?['role'] ?? backendUser?['userRole'] ?? '')
              .toString()
              .toLowerCase();

          if (roleLc == 'merchant' && merchantData != null) {
            final serviceKey = merchantData['merchantService']?.toString() ?? '';
            if (serviceKey.isNotEmpty) {
              final merchantProfile = {
                'uid': cred.user!.uid,
                'email': email,
                'name': backendUser?['name']?.toString() ?? '',
                'phone': backendUser?['phone']?.toString() ?? '',
                ...merchantData,
                'status': 'pending',
                'isActive': false,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
                'rating': 0.0,
                'totalRatings': 0,
                'completedOrders': 0,
              };

              final collectionName = '${serviceKey}_merchants';
              await _firestore
                  .collection(collectionName)
                  .doc(cred.user!.uid)
                  .set(merchantProfile);
            }
          }
        }
      }
    } catch (_) {
      // ignore
    }
  }

  // ---------- Email/Phone + Password login (backend + Firebase fallback) ----------

  Future<Map<String, dynamic>?> loginWithIdentifier(
    String identifier,
    String password,
    BuildContext context,
  ) async {
    final trimmedId = identifier.trim();

    // 1) Try NestJS backend first
    try {
      final res = await ApiClient.post(
        '/auth/login',
        body: jsonEncode({
          'identifier': trimmedId,
          'password': password,
        }),
        timeout: _reqTimeoutWarm,
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _toast(context, 'Signed in');
      final normalized = _normalizeBackendAuthResponse(data);

      // Best-effort: mirror to Firebase if email login
      if (trimmedId.contains('@')) {
        Map<String, dynamic>? merchantData;
        final user = normalized['user'] as Map<String, dynamic>?;
        final roleLc = (user?['role'] ?? user?['userRole'] ?? '')
            .toString()
            .toLowerCase();

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
      // Backend rejected. If identifier is email, still try Firebase backup.
      if (trimmedId.contains('@')) {
        final fbResult = await _loginWithFirebaseEmailPassword(
          trimmedId,
          password,
          context,
          onFailMessage: e.message,
        );
        if (fbResult != null) return fbResult;
      }

      _toast(context, e.message, ok: false);
      return null;
    } catch (e) {
      // Network/server down → prefer Firebase backup for email logins
      if (trimmedId.contains('@')) {
        final fbResult = await _loginWithFirebaseEmailPassword(
          trimmedId,
          password,
          context,
        );
        if (fbResult != null) return fbResult;
      }

      _toast(context, 'Something went wrong. Please try again.', ok: false);
      return null;
    }
  }

  // ---------- OTP (register flow) ----------

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
      _toast(
        context,
        'OTP failed: ${e.message}. You can still continue — we will create a backup account.',
        ok: false,
      );
      return true;
    } catch (e) {
      _toast(
        context,
        'Server not reachable for OTP. You can still continue — we will create a backup account.',
        ok: false,
      );
      return true;
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
      _toast(
        context,
        'Could not verify code (server issue). We can still create a backup account.',
        ok: false,
      );
      return null;
    }
  }

  // ---------- Register (backend first, Firebase fallback) ----------

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

    Map<String, dynamic>? firebaseMerchantData;
    if (normalizedRole == 'merchant' && merchantData != null) {
      firebaseMerchantData = {
        'merchantService': merchantData['merchantService'],
        'businessName': merchantData['businessName'],
        'businessAddress': merchantData['businessAddress'],
        'status': 'pending',
        'isActive': false,
      };
    }

    // 1) Try backend registration if we have a ticket
    if (verificationTicket.isNotEmpty) {
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
        };

        if (merchantData != null && normalizedRole == 'merchant') {
          body.addAll(merchantData.map((k, v) => MapEntry(k, v.toString())));
        }

        final res = await ApiClient.post(
          '/auth/register',
          body: jsonEncode(body),
          timeout: _reqTimeoutWarm,
        );

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Account created');

        final backendAuth = _normalizeBackendAuthResponse(data);

        if (email.trim().isNotEmpty) {
          await _ensureFirebaseMirrorForBackendUser(
            email: email.trim(),
            password: password,
            backendUser: backendAuth['user'] as Map<String, dynamic>?,
            merchantData: firebaseMerchantData,
          );
        }

        return backendAuth;
      } on ApiException catch (e) {
        _toast(
          context,
          'Backend signup failed: ${e.message}. Using backup account.',
          ok: false,
        );
      } catch (e) {
        if (_looksLikeServerDown(e)) {
          _toast(context, 'Server unavailable. Creating backup account.',
              ok: false);
        } else {
          _toast(context, 'Signup error: $e. Trying backup account.', ok: false);
        }
      }
    }

    // 2) Fallback: pure Firebase registration
    if (email.trim().isEmpty) {
      _toast(context, 'Email is required for backup sign-up.', ok: false);
      return null;
    }

    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        _toast(context, 'Backup signup failed (no user).', ok: false);
        return null;
      }

      if (normalizedRole == 'merchant' && firebaseMerchantData != null) {
        final serviceKey =
            firebaseMerchantData['merchantService']?.toString() ?? '';
        if (serviceKey.isNotEmpty) {
          final merchantProfile = {
            'uid': user.uid,
            'email': email,
            'name': name,
            'phone': phone,
            ...firebaseMerchantData,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'rating': 0.0,
            'totalRatings': 0,
            'completedOrders': 0,
          };

          final collectionName = '${serviceKey}_merchants';
          await _firestore.collection(collectionName).doc(user.uid).set(
                merchantProfile,
              );
        }
      }

      final auth = await _normalizeFirebaseUser(
        user,
        name: name,
        phone: phone,
        role: normalizedRole,
        merchantData: firebaseMerchantData,
      );

      _toast(context, 'Account created (backup)', ok: true);
      return auth;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          final cred = await _firebaseAuth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
          final user = cred.user;
          if (user == null) {
            _toast(context, 'Backup account exists but could not sign in.',
                ok: false);
            return null;
          }

          if (normalizedRole == 'merchant' && firebaseMerchantData != null) {
            await _saveFirebaseProfile(
              user,
              name: name,
              phone: phone,
              role: normalizedRole,
              merchantData: firebaseMerchantData,
            );

            final serviceKey =
                firebaseMerchantData['merchantService']?.toString() ?? '';
            if (serviceKey.isNotEmpty) {
              final merchantProfile = {
                'uid': user.uid,
                'email': email,
                'name': name,
                'phone': phone,
                ...firebaseMerchantData,
                'updatedAt': FieldValue.serverTimestamp(),
              };

              final collectionName = '${serviceKey}_merchants';
              await _firestore.collection(collectionName).doc(user.uid).set(
                    merchantProfile,
                    SetOptions(merge: true),
                  );
            }
          }

          final auth = await _buildFirebaseAuthResult(
            user,
            fallbackName: name,
            fallbackPhone: phone,
            fallbackRole: normalizedRole,
            merchantData: firebaseMerchantData,
          );

          _toast(context, 'Signed in to existing backup account', ok: true);
          return auth;
        } catch (e2) {
          _toast(context, e2.toString(), ok: false);
          return null;
        }
      }

      _toast(context, e.message ?? 'Backup signup failed.', ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Signup failed. Please try again later.', ok: false);
      return null;
    }
  }

  // ---------- DELETE ACCOUNT EVERYWHERE (Backend + Firebase + Local cleanup) ----------

  Future<DeleteAccountStatus> deleteAccountEverywhere(
      BuildContext context) async {
    final token = await _readAnyToken();

    // 1) Delete on Nest backend (best-effort)
    bool backendDeleted = false;
    if (token != null && token.trim().isNotEmpty) {
      try {
        final base = await ApiConfig.readBase();
        final resp = await http.delete(
          Uri.parse('$base/users/me'),
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
      // no backend token => user might be Firebase-only backup account
      backendDeleted = true;
    }

    // 2) Delete Firebase user + Firestore docs (best-effort)
    bool firebaseDeleted = true;
    final u = _firebaseAuth.currentUser;

    if (u != null) {
      // delete firestore docs first
      try {
        final userDoc = await _firestore.collection('users').doc(u.uid).get();
        final data = userDoc.data() ?? {};
        final serviceKey = (data['merchantService'] ?? '').toString();

        await _firestore.collection('users').doc(u.uid).delete();

        if (serviceKey.trim().isNotEmpty) {
          final collectionName = '${serviceKey}_merchants';
          await _firestore.collection(collectionName).doc(u.uid).delete();
        }
      } catch (_) {}

      try {
        await u.delete(); // may require recent login
      } on FirebaseAuthException catch (e) {
        firebaseDeleted = false;

        if (e.code == 'requires-recent-login') {
          _toast(
            context,
            'Please login again, then try deleting your account.',
            ok: false,
          );

          // still sign out everywhere
          await logout(context: context);
          return DeleteAccountStatus.requiresRecentLogin;
        }
      } catch (_) {
        firebaseDeleted = false;
      }
    }

    // 3) Cleanup: sign out everywhere + clear local
    await logout(context: context);

    if (backendDeleted && firebaseDeleted) {
      _toast(context, 'Account deleted', ok: true);
      return DeleteAccountStatus.success;
    }

    _toast(
      context,
      'Account delete partially completed. If this persists, contact support.',
      ok: false,
    );
    return DeleteAccountStatus.failed;
  }

  // ---------- Logout ----------

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
      } catch (_) {
        // ignore logout errors
      }
    }

    // google
    try {
      await _google.signOut();
    } catch (_) {}
    try {
      await _google.disconnect();
    } catch (_) {}

    // firebase
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

  // ---------- Social: Google ----------

  Future<Map<String, dynamic>?> continueWithGoogle(BuildContext context) async {
    try {
      final acct = await _google.signIn();
      if (acct == null) return null; // cancelled

      final auth = await acct.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        _toast(context, 'No Google ID token', ok: false);
        return null;
      }

      final res = await ApiClient.post(
        '/auth/google',
        body: jsonEncode({'idToken': idToken}),
        timeout: _reqTimeoutWarm,
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _toast(context, 'Signed in with Google');
      return _normalizeBackendAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Google sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  // ---------- Social: Apple ----------

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

  /// Get merchant status from Firebase
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

  /// Update merchant profile
  Future<bool> updateMerchantProfile({
    required String uid,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Also update service-specific collection if merchant
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data();

      final roleLc = (userData?['role'] ?? '').toString().toLowerCase();
      final serviceKey = (userData?['merchantService'] ?? '').toString();

      if (roleLc == 'merchant' && serviceKey.isNotEmpty) {
        final collectionName = '${serviceKey}_merchants';
        await _firestore.collection(collectionName).doc(uid).update({
          ...updates,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Optional: call once at app start to pre-warm backend.
  static Future<void> prewarm() => ApiConfig.ensureBackendUp();
}
