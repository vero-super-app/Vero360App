// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/password_reset_verification_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/registration_verification_service.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';

enum DeleteAccountStatus { success, requiresRecentLogin, failed }

enum PasswordResetChannel { email, phone }

enum PasswordResetOutcome {
  sent,
  otpSent,
  phoneOnlyNoRecovery,
  notFound,
  error,
  completed,
}

/// Result of [AuthService.requestPasswordReset] for UI feedback.
class PasswordResetResult {
  final bool success;
  final PasswordResetChannel? channel;
  final String? maskedDestination;
  final String message;
  final PasswordResetOutcome outcome;

  const PasswordResetResult({
    required this.success,
    this.channel,
    this.maskedDestination,
    required this.message,
    required this.outcome,
  });
}

class AuthService {
  static const String supportEmail = 'support@vero360.app';
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
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 12));
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

    final token = await AuthHandler.getFirebaseToken();

    // Avoid logging raw JWT values; they can be used to impersonate users.
    if (token != null && token.isNotEmpty && kDebugMode) {
      debugPrint('[JWT] Firebase ID token acquired');
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

  static String _firebaseEmailForIdentifier(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.contains('@')) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return '$digits@phone.vero360.app';
  }

  Future<User?> _ensureFirebaseMirrorForBackendUser({
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
        return current;
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
        return cred.user;
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
          return cred.user;
        }
        if (kDebugMode) {
          debugPrint('[Auth] Firebase mirror failed: ${e.code} ${e.message}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Firebase mirror error: $e');
    }
    return null;
  }

  // -------------------- Login (Backend first, Firebase fallback for email) --------------------

  /// When [showErrorToast] is false, errors are not shown (caller may try Firebase fallback and show one error).
  Future<Map<String, dynamic>?> loginWithIdentifier(
    String identifier,
    String password,
    BuildContext context, {
    bool showErrorToast = true,
  }) async {
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

      // Firestore requires Firebase Auth — mirror backend account before returning.
      final firebaseEmail = _firebaseEmailForIdentifier(trimmedId);
      final fbUser = await _ensureFirebaseMirrorForBackendUser(
        email: firebaseEmail,
        password: password,
        backendUser: user,
        merchantData: merchantData,
      );

      if (fbUser != null) {
        return _buildFirebaseAuthResult(
          fbUser,
          fallbackName: user?['name']?.toString(),
          fallbackPhone: user?['phone']?.toString(),
          fallbackRole: roleLc,
          merchantData: merchantData,
        );
      }

      if (showErrorToast) {
        _toast(
          context,
          'Signed in, but Firebase sync failed. Sign out and sign in again to save data.',
          ok: false,
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
      if (showErrorToast) _toast(context, e.message, ok: false);
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
      if (showErrorToast) {
        _toast(context,
            _looksLikeServerDown(e) ? 'Server unreachable.' : 'Login failed.',
            ok: false);
      }
      return null;
    }
  }

  // -------------------- Forgot password (email or phone) --------------------
  //
  // OTP is sent via the Vero API (backend SMTP, same as registration).
  // After the user enters the code + new password in-app, Firebase Auth is updated.

  static bool _looksLikeEmail(String v) =>
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(v.trim());

  static bool _looksLikePhone(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(08|09)\d{8}$').hasMatch(digits) ||
        RegExp(r'^\+265[89]\d{8}$').hasMatch(t);
  }

  static bool _isRecoverableEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return false;
    return !e.toLowerCase().endsWith('@phone.vero360.app');
  }

  static String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return '***';
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty) return '***@$domain';
    final visible = local.length <= 1 ? '*' : local[0];
    return '$visible***@$domain';
  }

  Set<String> _phoneLookupVariants(String phone) {
    final trimmed = phone.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    final variants = <String>{trimmed, digits};
    if (digits.length == 10 && digits.startsWith('0')) {
      variants.add('+265${digits.substring(1)}');
      variants.add('265${digits.substring(1)}');
    } else if (digits.length == 12 && digits.startsWith('265')) {
      variants.add('0${digits.substring(3)}');
      variants.add('+$digits');
    }
    return variants;
  }

  Future<String?> _lookupRecoverableEmailByPhone(String phone) async {
    for (final variant in _phoneLookupVariants(phone)) {
      try {
        final snap = await _firestore
            .collection('users')
            .where('phone', isEqualTo: variant)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 12));
        if (snap.docs.isEmpty) continue;
        final email = snap.docs.first.data()['email']?.toString().trim() ?? '';
        if (_isRecoverableEmail(email)) return email;
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _phoneProfileExists(String phone) async {
    for (final variant in _phoneLookupVariants(phone)) {
      try {
        final snap = await _firestore
            .collection('users')
            .where('phone', isEqualTo: variant)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 12));
        if (snap.docs.isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<String> _resolveAuthEmailForPasswordReset({
    required String channel,
    String? email,
    String? phone,
  }) async {
    if (channel == 'email' && email != null && email.trim().isNotEmpty) {
      return email.trim().toLowerCase();
    }

    if (phone == null || phone.trim().isEmpty) {
      return '';
    }

    final linkedEmail = await _lookupRecoverableEmailByPhone(phone);
    if (linkedEmail != null && linkedEmail.isNotEmpty) {
      return linkedEmail.trim().toLowerCase();
    }

    return syntheticEmailForPhone(phone).toLowerCase();
  }

  String _passwordResetApplyErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'requires-recent-login':
        return 'Please sign in again, then change your password from settings.';
      case 'user-not-found':
        return 'No Vero360 account found for this email or phone.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Failed to update password. Try again.';
    }
  }

  Future<void> _applyFirebasePasswordAfterOtp({
    required String authEmail,
    required String newPassword,
    required String verificationTicket,
    String? firebaseCustomToken,
    String? channel,
    String? email,
    String? phone,
  }) async {
    await _firebaseAuth.signOut();

    final customToken = firebaseCustomToken?.trim();
    if (customToken != null && customToken.isNotEmpty) {
      try {
        final cred = await _firebaseAuth.signInWithCustomToken(customToken);
        await cred.user?.updatePassword(newPassword);
        await _firebaseAuth.signOut();
        return;
      } on FirebaseAuthException catch (e) {
        throw ApiException(message: _passwordResetApplyErrorMessage(e));
      }
    }

    try {
      await ApiClient.post(
        '/auth/password/reset',
        body: jsonEncode({
          'verificationTicket': verificationTicket,
          'newPassword': newPassword,
          'authEmail': authEmail,
          if (channel != null) 'channel': channel,
          if (email != null && email.isNotEmpty)
            'email': email.trim().toLowerCase(),
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        }),
        timeout: _reqTimeoutWarm,
      );
      return;
    } on ApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('resetPasswordAfterOtp')
          .call({
        'authEmail': authEmail,
        'newPassword': newPassword,
        'verificationTicket': verificationTicket,
        if (channel != null) 'channel': channel,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      });
      final data = result.data;
      if (data is Map && data['success'] == true) return;
      if (data == true) return;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw const ApiException(
          message:
              'No Vero360 account found. Check your email or phone, or register first.',
        );
      }
      if (e.code != 'unavailable') {
        throw ApiException(
          message: e.message?.trim().isNotEmpty == true
              ? e.message!
              : 'Password reset failed. Try again.',
        );
      }
    }

    try {
      final cred =
          await _firebaseAuth.signInWithCustomToken(verificationTicket);
      await cred.user?.updatePassword(newPassword);
      await _firebaseAuth.signOut();
      return;
    } on FirebaseAuthException catch (_) {
      // verificationTicket is not a Firebase custom token — expected.
    }

    try {
      await _firebaseAuth.confirmPasswordReset(
        code: verificationTicket,
        newPassword: newPassword,
      );
      return;
    } on FirebaseAuthException catch (_) {
      // verificationTicket is not a Firebase oob code — expected.
    }

    throw const ApiException(
      message:
          'Could not update your password. Deploy the resetPasswordAfterOtp cloud function or contact support@vero360.app.',
    );
  }

  /// Step 1: send a 6-digit code via backend SMTP (same pipeline as registration).
  Future<PasswordResetResult> requestPasswordReset({
    required String identifier,
  }) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      return const PasswordResetResult(
        success: false,
        message: 'Enter email or phone number',
        outcome: PasswordResetOutcome.error,
      );
    }

    final service = PasswordResetVerificationService();

    if (_looksLikeEmail(trimmed)) {
      try {
        await service.requestOtp(channel: 'email', email: trimmed);
        return PasswordResetResult(
          success: true,
          channel: PasswordResetChannel.email,
          maskedDestination: _maskEmail(trimmed),
          message:
              '6-digit code sent to ${_maskEmail(trimmed)}. Enter it on the next screen with your new password.',
          outcome: PasswordResetOutcome.otpSent,
        );
      } on ApiException catch (e) {
        return PasswordResetResult(
          success: false,
          channel: PasswordResetChannel.email,
          message: PasswordResetVerificationService.friendlyError(e, forSend: true),
          outcome: PasswordResetOutcome.error,
        );
      } catch (_) {
        return const PasswordResetResult(
          success: false,
          channel: PasswordResetChannel.email,
          message: 'Could not send verification code. Try again.',
          outcome: PasswordResetOutcome.error,
        );
      }
    }

    if (!_looksLikePhone(trimmed)) {
      return const PasswordResetResult(
        success: false,
        message: 'Enter a valid email or phone number',
        outcome: PasswordResetOutcome.error,
      );
    }

    final linkedEmail = await _lookupRecoverableEmailByPhone(trimmed);
    if (linkedEmail == null) {
      final profileExists = await _phoneProfileExists(trimmed);
      if (!profileExists) {
        return const PasswordResetResult(
          success: true,
          channel: PasswordResetChannel.phone,
          message:
              'If an account exists for this number, we sent a verification code.',
          outcome: PasswordResetOutcome.otpSent,
        );
      }
      return PasswordResetResult(
        success: false,
        channel: PasswordResetChannel.phone,
        message:
            'This account was created with phone only and has no email on file. '
            'Try signing in with Google or Apple, or contact $supportEmail for help.',
        outcome: PasswordResetOutcome.phoneOnlyNoRecovery,
      );
    }

    try {
      await service.requestOtp(channel: 'phone', phone: trimmed);
      return PasswordResetResult(
        success: true,
        channel: PasswordResetChannel.phone,
        maskedDestination: _maskEmail(linkedEmail),
        message:
            '6-digit code sent via SMS. Enter it with your new password on the next screen.',
        outcome: PasswordResetOutcome.otpSent,
      );
    } on ApiException catch (e) {
      return PasswordResetResult(
        success: false,
        channel: PasswordResetChannel.phone,
        message: PasswordResetVerificationService.friendlyError(e, forSend: true),
        outcome: PasswordResetOutcome.error,
      );
    } catch (_) {
      return const PasswordResetResult(
        success: false,
        channel: PasswordResetChannel.phone,
        message: 'Could not send verification code. Try again.',
        outcome: PasswordResetOutcome.error,
      );
    }
  }

  /// Step 2: verify OTP + set a new Firebase password (in-app, no reset link email).
  Future<PasswordResetResult> completePasswordResetWithOtp({
    required String identifier,
    required String otpCode,
    required String newPassword,
    required PasswordResetVerificationResult verification,
  }) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty || otpCode.trim().length != 6) {
      return const PasswordResetResult(
        success: false,
        message: 'Enter the 6-digit verification code',
        outcome: PasswordResetOutcome.error,
      );
    }
    if (newPassword.trim().length < 6) {
      return const PasswordResetResult(
        success: false,
        message: 'Password must be at least 6 characters',
        outcome: PasswordResetOutcome.error,
      );
    }

    final channel = verification.channel;
    final email = channel == 'email' ? trimmed : null;
    final phone = channel == 'phone' ? trimmed : null;

    try {
      final authEmail = await _resolveAuthEmailForPasswordReset(
        channel: channel,
        email: email,
        phone: phone,
      );
      if (authEmail.isEmpty) {
        return const PasswordResetResult(
          success: false,
          message: 'Could not resolve account email for password reset.',
          outcome: PasswordResetOutcome.error,
        );
      }

      await _applyFirebasePasswordAfterOtp(
        authEmail: authEmail,
        newPassword: newPassword.trim(),
        verificationTicket: verification.verificationTicket,
        firebaseCustomToken: verification.firebaseCustomToken,
        channel: channel,
        email: email,
        phone: phone != null
            ? RegistrationVerificationService.formatPhoneE164(phone)
            : null,
      );

      return const PasswordResetResult(
        success: true,
        message: 'Password updated. You can sign in now.',
        outcome: PasswordResetOutcome.completed,
      );
    } on ApiException catch (e) {
      return PasswordResetResult(
        success: false,
        message: e.message,
        outcome: PasswordResetOutcome.error,
      );
    } on FirebaseAuthException catch (e) {
      return PasswordResetResult(
        success: false,
        message: _passwordResetApplyErrorMessage(e),
        outcome: PasswordResetOutcome.error,
      );
    } catch (_) {
      return const PasswordResetResult(
        success: false,
        message: 'Failed to update password. Try again.',
        outcome: PasswordResetOutcome.error,
      );
    }
  }

  // -------------------- OTP --------------------

  static String syntheticEmailForPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return '$digits@phone.vero360.app';
  }

  Future<bool> requestOtp({
    required String channel, // 'email' | 'phone'
    String? email,
    String? phone,
    required BuildContext context,
    bool showToast = true,
    String purpose = 'registration',
  }) async {
    try {
      await ApiClient.post(
        '/auth/otp/request',
        body: jsonEncode({
          'channel': channel,
          'purpose': purpose,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
        }),
        timeout: _reqTimeoutWarm,
      );
      if (showToast) {
        final msg = channel == 'email'
            ? '6-digit code sent to your email'
            : '6-digit code sent via SMS';
        _toast(context, msg);
      }
      return true;
    } on ApiException catch (e) {
      if (showToast) _toast(context, 'OTP failed: ${e.message}', ok: false);
      return false;
    } catch (_) {
      if (showToast) {
        _toast(context, 'OTP failed (server unreachable)', ok: false);
      }
      return false;
    }
  }

  Future<String?> verifyOtpGetTicket({
    required String identifier,
    required String code,
    required BuildContext context,
    bool showToast = true,
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
        if (showToast) _toast(context, 'Invalid or expired code', ok: false);
        return null;
      }

      if (showToast) _toast(context, 'Verified');
      return ticket;
    } on ApiException catch (e) {
      if (showToast) _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      if (showToast) {
        _toast(context, 'Verification failed (server unreachable)', ok: false);
      }
      return null;
    }
  }

  // -------------------- Register --------------------
  //
  // OTP is verified via the Vero API; the account is created in Firebase only
  // (Auth + Firestore). NestJS /auth/register is not used.

  String _registerFirebaseErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Account already exists. Please sign in.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Sign up failed. Try again.';
    }
  }

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
    bool allowFirebaseFallback = true,
  }) async {
    final normalizedRole = role.toLowerCase();

    if (verificationTicket.trim().isEmpty && !allowFirebaseFallback) {
      _toast(
        context,
        'Verification required before creating your account.',
        ok: false,
      );
      return null;
    }

    // Firebase Auth requires an email; phone-only signups use a synthetic address.
    final authEmail = email.trim().isNotEmpty
        ? email.trim()
        : syntheticEmailForPhone(phone);
    if (authEmail.isEmpty) {
      _toast(context, 'Email or phone number is required.', ok: false);
      return null;
    }

    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        _toast(context, 'Sign up failed.', ok: false);
        return null;
      }

      if (name.trim().isNotEmpty) {
        await user.updateDisplayName(name.trim());
      }

      await _saveFirebaseProfile(
        user,
        name: name,
        phone: phone,
        role: normalizedRole,
        merchantData: merchantData,
      );

      // Store contact email separately when auth uses a synthetic phone email.
      if (email.trim().isNotEmpty && email.trim() != authEmail) {
        try {
          await _firestore.collection('users').doc(user.uid).set(
            {'contactEmail': email.trim()},
            SetOptions(merge: true),
          );
        } catch (_) {}
      }

      if (preferredVerification.trim().isNotEmpty) {
        try {
          await _firestore.collection('users').doc(user.uid).set(
            {'preferredVerification': preferredVerification.trim()},
            SetOptions(merge: true),
          );
        } catch (_) {}
      }

      final auth = await _buildFirebaseAuthResult(
        user,
        fallbackName: name,
        fallbackPhone: phone,
        fallbackRole: normalizedRole,
        merchantData: merchantData,
      );

      _toast(context, 'Account created', ok: true);
      return auth;
    } on FirebaseAuthException catch (e) {
      _toast(context, _registerFirebaseErrorMessage(e), ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Sign up failed. Try again later.', ok: false);
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

    // Step 1: Set all driver taxis to unavailable before logout
    try {
      final driverService = DriverService();
      final driver = await driverService.getMyDriverProfile();
      if (driver != null && driver['taxis'] != null && driver['taxis'].isNotEmpty) {
        for (final taxi in driver['taxis']) {
          try {
            await driverService.setTaxiAvailability(taxi['id'], false);
          } catch (e) {
            if (kDebugMode) debugPrint('Error setting taxi unavailable: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting driver profile for logout: $e');
    }

    // Step 2: Call backend logout endpoint to clean up FCM tokens and mark driver inactive
    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient.post(
          '/auth/logout',
          headers: {'Authorization': 'Bearer $token'},
          body: jsonEncode({}),
        );
      } catch (e) {
        if (kDebugMode) debugPrint(' logout call failed: $e');
      }
    }

    // Step 3: Google sign out
    try {
      await _google.signOut();
    } catch (_) {}

    // Step 4: Firebase sign out
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}

    // Step 5: Clear notifications
    try {
      await NotificationStore.instance.clearAll();
    } catch (_) {}

    // Step 6: Clear local session
    final ok = await _clearLocalSession();
    if (context != null) {
      _toast(context, ok ? 'Signed out' : 'Signed out', ok: ok);
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
        'userId',
        'user_id',
        'messaging_firebase_uid',
        'role',
        'user_role',
        'has_driver_profile',
        'fullName',
        'name',
        'phone',
        'address',
        'profilepicture',
      ]) {
        await sp.remove(k);
      }
      resetDriverSessionCache();
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
