import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

/// Device + Firebase token metadata sent to the backend so pm2 logs can
/// distinguish clock skew vs expired handshake vs wrong token type.
class AuthDiagnostics {
  AuthDiagnostics._();

  /// Keep in sync with pubspec `version:` (used when package_info is unavailable).
  static const String appVersion = '1.1.5+10009';

  static Map<String, dynamic>? peekJwtClaims(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final json = utf8.decode(base64Decode(payload));
      final map = jsonDecode(json);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> buildHeaders({
    String? token,
  }) async {
    final now = DateTime.now().toUtc();
    final user = FirebaseAuth.instance.currentUser;
    final claims = peekJwtClaims(token);

    String platform = 'unknown';
    String osVersion = 'unknown';
    String deviceModel = 'unknown';
    try {
      if (!kIsWeb) {
        platform = Platform.operatingSystem;
        osVersion = Platform.operatingSystemVersion;
        deviceModel = Platform.localHostname;
      } else {
        platform = 'web';
      }
    } catch (_) {}

    final exp = claims?['exp'];
    final iat = claims?['iat'];
    final uid = user?.uid ??
        claims?['user_id']?.toString() ??
        claims?['sub']?.toString();

    return {
      'X-Vero-Client-Time': now.toIso8601String(),
      'X-Vero-Client-Epoch-Ms': '${now.millisecondsSinceEpoch}',
      'X-Vero-Platform': platform,
      'X-Vero-Os-Version': osVersion.length > 120
          ? osVersion.substring(0, 120)
          : osVersion,
      'X-Vero-App-Version': appVersion,
      'X-Vero-Device-Model': deviceModel.length > 120
          ? deviceModel.substring(0, 120)
          : deviceModel,
      if (uid != null && uid.isNotEmpty) 'X-Vero-Firebase-Uid': uid,
      if (exp != null) 'X-Vero-Token-Exp': '$exp',
      if (iat != null) 'X-Vero-Token-Iat': '$iat',
      if (token != null) 'X-Vero-Token-Len': '${token.length}',
    };
  }

  /// Query params for Socket.IO (extra headers are unreliable on some mobiles).
  static Future<Map<String, dynamic>> buildSocketQuery({
    required String token,
  }) async {
    final h = await buildHeaders(token: token);
    return {
      'token': token,
      for (final e in h.entries) e.key.toLowerCase(): e.value,
    };
  }

  /// POST diagnostics when auth fails (works without a valid session).
  static Future<void> reportFailure({
    required String reason,
    String channel = 'http',
    String? lastError,
    String? idToken,
  }) async {
    try {
      final token =
          idToken ?? await AuthHandler.getFirebaseTokenForApi();
      final headers = await buildHeaders(token: token);
      final user = FirebaseAuth.instance.currentUser;
      await http
          .post(
            ApiConfig.endpoint('/auth/client-diagnostics'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              ...headers,
            },
            body: jsonEncode({
              'channel': channel,
              'reason': reason,
              'lastError': lastError,
              if (token != null && token.isNotEmpty) 'idToken': token,
              'platform': headers['X-Vero-Platform'],
              'osVersion': headers['X-Vero-Os-Version'],
              'appVersion': headers['X-Vero-App-Version'],
              'deviceModel': headers['X-Vero-Device-Model'],
              'clientTimeIso': headers['X-Vero-Client-Time'],
              'clientEpochMs': int.tryParse(
                headers['X-Vero-Client-Epoch-Ms'] ?? '',
              ),
              'firebaseUid': user?.uid,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthDiagnostics] report failed: $e');
      }
    }
  }
}
