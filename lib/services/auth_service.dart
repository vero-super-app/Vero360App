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

import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/toasthelper.dart';

class AuthService {
  static const Duration _reqTimeoutWarm = Duration(seconds: 18);

  final GoogleSignIn _google = GoogleSignIn(scopes: ['email', 'profile']);

  void _toast(BuildContext ctx, String msg, {bool ok = true}) {
    ToastHelper.showCustomToast(
      ctx,
      msg,
      isSuccess: ok,
      errorMessage: ok ? '' : msg,
    );
  }

  // ---------- Email/Phone + Password ----------
  Future<Map<String, dynamic>?> loginWithIdentifier(
    String identifier,
    String password,
    BuildContext context,
  ) async {
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
      _toast(context, 'Signed in');
      return _normalizeAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
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
      _toast(context, 'Account created');
      return _normalizeAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Something went wrong. Please try again.', ok: false);
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
      ]) {
        await sp.remove(k);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Social: Google ----------
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
      return _normalizeAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Google sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  // ---------- Social: Apple ----------
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
      return _normalizeAuthResponse(data);
    } on ApiException catch (e) {
      _toast(context, e.message, ok: false);
      return null;
    } catch (_) {
      _toast(context, 'Apple sign-in failed. Please try again.', ok: false);
      return null;
    }
  }

  // ---------- misc ----------
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
