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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/api_exception.dart';
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

  // ---------- Backend normaliser ----------

  Map<String, dynamic> _normalizeBackendAuthResponse(
      Map<String, dynamic> data) {
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
      final doc = _firestore.collection('users').doc(user.uid);
      final data = <String, dynamic>{
        'email': user.email,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (role != null && role.trim().isNotEmpty)
          'role': role.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Add merchant data if available - FIXED LINE 504
      if (merchantData != null && role == 'merchant') {
        // Convert all values to strings to match Map<String, String> type
        data.addAll(merchantData.map((key, value) => MapEntry(key, value.toString())));
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

    final name = (profile['name'] ?? fallbackName ?? user.displayName ?? '')
        .toString();
    final phone = (profile['phone'] ?? fallbackPhone ?? '').toString();
    final role = (profile['role'] ?? fallbackRole ?? 'customer')
        .toString()
        .toLowerCase();

    final token = await user.getIdToken();

    final userMap = <String, dynamic>{
      'id': user.uid,
      'firebaseUid': user.uid,
      'email': user.email ?? '',
      'phone': phone,
      'name': name,
      'role': role,
    };
    
    // Add merchant data if available
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
        _toast(
          context,
          onFailMessage ?? 'Backup login failed (no user).',
          ok: false,
        );
        return null;
      }

      _toast(context, 'Signed in (backup account)', ok: true);
      return await _buildFirebaseAuthResult(user, fallbackRole: 'customer');
    } on FirebaseAuthException catch (e) {
      _toast(
        context,
        onFailMessage ?? (e.message ?? 'Backup login failed.'),
        ok: false,
      );
      return null;
    } catch (_) {
      _toast(
        context,
        onFailMessage ?? 'Backup login failed.',
        ok: false,
      );
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
          if (backendUser?['role'] == 'merchant' && merchantData != null) {
            // FIXED LINE 910 - added null safety
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
        } else {
          // ignore other firebase errors here
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
        // Extract merchant data if available
        Map<String, dynamic>? merchantData;
        final user = normalized['user'] as Map<String, dynamic>?;
        if (user?['role'] == 'merchant') {
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

      _toast(
        context,
        'Something went wrong. Please try again.',
        ok: false,
      );
      return null;
    }
  }

  // ---------- OTP (register flow) ----------

  /// NOTE: If Nest is down, this will now still return `true` so the UI
  /// can continue and we'll rely on Firebase-only registration.
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
      // Backend responded with an error (rate-limit, etc.)
      _toast(
        context,
        'OTP failed: ${e.message}. You can still continue — we will create a backup account.',
        ok: false,
      );
      return true; // allow flow to continue
    } catch (e) {
      // Network/server completely down
      _toast(
        context,
        'Server not reachable for OTP. You can still continue — we will create a backup account.',
        ok: false,
      );
      return true; // allow flow to continue
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
      // When this fails (server down), we'll fall back to Firebase only.
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
    Map<String, dynamic>? merchantData, // Add merchant data parameter
    required BuildContext context,
  }) async {
    final normalizedRole = role.toLowerCase();

    // Prepare merchant data for Firebase if merchant
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
        final body = {
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'role': normalizedRole,
          'profilepicture': profilePicture,
          'preferredVerification': preferredVerification,
          'verificationTicket': verificationTicket,
        };
        
        // Add merchant data to request if available
        if (merchantData != null && normalizedRole == 'merchant') {
          // FIXED: Convert all values to strings
          body.addAll(merchantData.map((key, value) => MapEntry(key, value.toString())));
        }

        final res = await ApiClient.post(
          '/auth/register',
          body: jsonEncode(body),
          timeout: _reqTimeoutWarm,
        );

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Account created');

        final backendAuth = _normalizeBackendAuthResponse(data);

        // Mirror this user into Firebase as backup (best-effort)
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
        // fall through to Firebase backup
      } catch (e) {
        if (_looksLikeServerDown(e)) {
          _toast(
            context,
            'Server unavailable. Creating backup account.',
            ok: false,
          );
        } else {
          _toast(
            context,
            'Signup error: $e. Trying backup account.',
            ok: false,
          );
        }
        // fall through to Firebase backup
      }
    }

    // 2) Fallback: pure Firebase registration (NO OTP required here)
    if (email.trim().isEmpty) {
      _toast(
        context,
        'Email is required for backup sign-up.',
        ok: false,
      );
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

      // Create merchant profile in service-specific collection if merchant
      if (normalizedRole == 'merchant' && firebaseMerchantData != null) {
        final serviceKey = firebaseMerchantData['merchantService']?.toString() ?? '';
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
          await _firestore
              .collection(collectionName)
              .doc(user.uid)
              .set(merchantProfile);
        }
      }

      final auth = await _normalizeFirebaseUser(
        user,
        name: name,
        phone: phone,
        role: normalizedRole,
        merchantData: firebaseMerchantData,
      );

      _toast(
        context,
        'Account created (backup)',
        ok: true,
      );
      return auth;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Already exists in Firebase → sign in instead
        try {
          final cred = await _firebaseAuth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
          final user = cred.user;
          if (user == null) {
            _toast(
              context,
              'Backup account exists but could not sign in.',
              ok: false,
            );
            return null;
          }

          // Update existing user with merchant data if needed
          if (normalizedRole == 'merchant' && firebaseMerchantData != null) {
            await _saveFirebaseProfile(
              user,
              name: name,
              phone: phone,
              role: normalizedRole,
              merchantData: firebaseMerchantData,
            );
            
            // Also update/create merchant profile in service-specific collection
            final serviceKey = firebaseMerchantData['merchantService']?.toString() ?? '';
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
              await _firestore
                  .collection(collectionName)
                  .doc(user.uid)
                  .set(merchantProfile, SetOptions(merge: true));
            }
          }

          final auth = await _buildFirebaseAuthResult(
            user,
            fallbackName: name,
            fallbackPhone: phone,
            fallbackRole: normalizedRole,
            merchantData: firebaseMerchantData,
          );

          _toast(
            context,
            'Signed in to existing backup account',
            ok: true,
          );
          return auth;
        } catch (e2) {
          _toast(
            context,
            e2.toString(),
            ok: false,
          );
          return null;
        }
      }

      _toast(
        context,
        e.message ?? 'Backup signup failed.',
        ok: false,
      );
      return null;
    } catch (_) {
      _toast(
        context,
        'Signup failed. Please try again later.',
        ok: false,
      );
      return null;
    }
  }

  // ---------- Logout ----------

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

    try {
      await _google.signOut();
    } catch (_) {}
    try {
      await _google.disconnect();
    } catch (_) {}

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
        'prefill_login_identifier',
        'prefill_login_role',
        'merchant_review_pending',
        'auth_provider',
        'merchant_service',
        'business_name',
        'business_address',
        'uid',
      ]) {
        await sp.remove(k);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Social: Google (unchanged backend flow) ----------

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

  // ---------- Social: Apple (unchanged backend flow) ----------

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

  /// Get merchant status from Firebase
  Future<String> getMerchantStatus(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['status'] ?? 'pending';
      }
      return 'pending';
    } catch (e) {
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
      
      if (userData?['role'] == 'merchant' && userData?['merchantService'] != null) {
        final serviceKey = userData?['merchantService']?.toString() ?? '';
        if (serviceKey.isNotEmpty) {
          final collectionName = '${serviceKey}_merchants';
          
          await _firestore
              .collection(collectionName)
              .doc(uid)
              .update({
                ...updates,
                'updatedAt': FieldValue.serverTimestamp(),
              });
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Optional: call once at app start to pre-warm backend.
  static Future<void> prewarm() => ApiConfig.ensureBackendUp();
}