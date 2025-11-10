// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/toasthelper.dart';

class AuthService {
  final _client = http.Client();

  // ---- timeouts / backoff tuned for Render Free cold-start ----
  static const Duration _perWakeTryTimeout = Duration(seconds: 6);
  static const List<int> _wakeBackoffSecs = [0, 1, 2, 3, 5, 8, 13, 21]; // ~53s total
  static const Duration _reqTimeoutWarm = Duration(seconds: 18);
  static const Duration _reqTimeoutCold = Duration(seconds: 35);

  Map<String, String> _headers([String? token]) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  void _toast(BuildContext ctx, String msg, {bool ok = true}) {
    ToastHelper.showCustomToast(ctx, msg, isSuccess: ok, errorMessage: ok ? '' : msg);
  }

  // ---------- helpers: host & wake ----------
  Uri _rootHost() {
    final prefixed = Uri.parse(ApiConfig.prodBase); // e.g. https://.../vero
    return Uri(
      scheme: prefixed.scheme,
      host: prefixed.host,
      port: prefixed.hasPort ? prefixed.port : null,
    );
  }

  Future<bool> _hasInternet() async {
    try {
      final res = await InternetAddress.lookup('one.one.one.one').timeout(const Duration(seconds: 2));
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pingOnce(Uri url) async {
    try {
      final r = await _client.get(url).timeout(_perWakeTryTimeout);
      return r.statusCode >= 200 && r.statusCode < 500; // host is up
    } catch (_) {
      return false;
    }
  }

  /// Repeatedly ping /healthz (fallback /) with backoff to wake the dyno.
  Future<bool> _wakeServerIfAsleep() async {
    if (!await _hasInternet()) return false;

    final root = _rootHost();
    final healthz = root.replace(path: '/healthz');
    final slash = root.replace(path: '/');

    for (final delay in _wakeBackoffSecs) {
      if (delay > 0) await Future<void>.delayed(Duration(seconds: delay));
      // Race two quick pings
      final ok = await Future.any<bool>([
        _pingOnce(healthz),
        _pingOnce(slash),
      ]).catchError((_) => false);
      if (ok == true) return true;
    }
    return false;
  }

  /// POST JSON with cold-start awareness: wake, try warm timeout, then retry with cold timeout.
  Future<http.Response> _postJson(String path, Map<String, dynamic> body, {String? token}) async {
    // Best-effort wake before real call
    await _wakeServerIfAsleep();

    final url = ApiConfig.endpoint(path);
    try {
      return await _client
          .post(url, headers: _headers(token), body: jsonEncode(body))
          .timeout(_reqTimeoutWarm);
    } on TimeoutException catch (_) {
      // Try one more wake + longer call
      await _wakeServerIfAsleep();
      return await _client
          .post(url, headers: _headers(token), body: jsonEncode(body))
          .timeout(_reqTimeoutCold);
    } on SocketException catch (_) {
      // DNS/handshake hiccup: wake then retry once longer
      await _wakeServerIfAsleep();
      return await _client
          .post(url, headers: _headers(token), body: jsonEncode(body))
          .timeout(_reqTimeoutCold);
    }
  }

  // ---------- Email/Phone + Password ----------
  Future<Map<String, dynamic>?> loginWithIdentifier(
    String identifier,
    String password,
    BuildContext context,
  ) async {
    try {
      final res = await _postJson('/auth/login', {
        'identifier': identifier,
        'password': password,
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Signed in');
        return _normalizeAuthResponse(data);
      }
      final err = _extractError(res);
      _toast(context, err, ok: false);
      return null;
    } on TimeoutException {
      _toast(context, 'Network timeout. The server may be cold-starting — try again.', ok: false);
      return null;
    } on SocketException catch (e) {
      _toast(context, 'Network error: ${e.osError?.message ?? e.message}', ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Network error: $e', ok: false);
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
      final res = await _postJson('/auth/otp/request', {
        'channel': channel,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _toast(context, 'Verification code sent');
        return true;
      }
      final err = _extractError(res);
      _toast(context, err, ok: false);
      return false;
    } on TimeoutException {
      _toast(context, 'Network timeout. Please retry — server might be waking.', ok: false);
      return false;
    } catch (e) {
      _toast(context, 'Network error: $e', ok: false);
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
      final res = await _postJson('/auth/otp/verify', {
        'channel': channel,
        if (channel == 'email') 'email': identifier,
        if (channel == 'phone') 'phone': identifier,
        'code': code,
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final ticket = data['ticket']?.toString();
        if (ticket == null || ticket.isEmpty) {
          _toast(context, 'No ticket in response', ok: false);
          return null;
        }
        _toast(context, 'Verified');
        return ticket;
      }
      final err = _extractError(res);
      _toast(context, err, ok: false);
      return null;
    } on TimeoutException {
      _toast(context, 'Network timeout. Please retry — server might be waking.', ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Network error: $e', ok: false);
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
      final res = await _postJson('/auth/register', {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'profilepicture': profilePicture,
        'preferredVerification': preferredVerification,
        'verificationTicket': verificationTicket,
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Account created');
        return _normalizeAuthResponse(data);
      }
      final err = _extractError(res);
      _toast(context, err, ok: false);
      return null;
    } on TimeoutException {
      _toast(context, 'Network timeout. Please retry — server might be waking.', ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Network error: $e', ok: false);
      return null;
    }
  }

  // ---------- Logout ----------
  Future<bool> logout({BuildContext? context}) async {
    String? token;
    try {
      final sp = await SharedPreferences.getInstance();
      token = sp.getString('token') ?? sp.getString('jwt_token') ?? sp.getString('jwt');
    } catch (_) {}

    if (token != null && token.isNotEmpty) {
      try { await _postJson('/auth/logout', {}, token: token); } catch (_) {}
    }

    try { await _google.signOut(); } catch (_) {}
    try { await _google.disconnect(); } catch (_) {}

    final ok = await _clearLocalSession();
    if (context != null) _toast(context, ok ? 'Signed out' : 'Signed out (local cleanup error)', ok: ok);
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
  final GoogleSignIn _google = GoogleSignIn(scopes: ['email', 'profile']);

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

      final res = await _postJson('/auth/google', {'idToken': idToken});

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Signed in with Google');
        return _normalizeAuthResponse(data);
      }
      final err = _extractError(res);
      _toast(context, err, ok: false);
      return null;
    } on TimeoutException {
      _toast(context, 'Network timeout. Please retry — server might be waking.', ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Google sign-in failed: $e', ok: false);
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
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
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

      final res = await _postJson('/auth/apple', {
        'identityToken': identityToken,
        'rawNonce': rawNonce,
        if (fullName.isNotEmpty) 'fullName': fullName,
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _toast(context, 'Signed in with Apple');
        return _normalizeAuthResponse(data);
      }
      final err = _extractError(res);
      _toast(context, err, ok: false);
      return null;
    } on TimeoutException {
      _toast(context, 'Network timeout. Please retry — server might be waking.', ok: false);
      return null;
    } catch (e) {
      _toast(context, 'Apple sign-in failed: $e', ok: false);
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

  String _extractError(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] != null) {
        final m = body['message'];
        if (m is String) return m;
        if (m is List && m.isNotEmpty) return m.first.toString();
      }
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  String _randomNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(length, (_) => charset[rand.nextInt(charset.length)]).join();
  }

  String _sha256of(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Optional: call once at app start to pre-warm the backend.
  static Future<void> prewarm() => AuthService()._wakeServerIfAsleep();
}
