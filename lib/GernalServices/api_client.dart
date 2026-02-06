import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class ApiClient {
  static const Duration _defaultTimeout = Duration(seconds: 20);

  // ---------- Public helpers ----------

  static Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
    Set<int>? allowedStatusCodes,
  }) {
    return _request(
      method: 'GET',
      path: path,
      headers: headers,
      timeout: timeout,
      allowedStatusCodes: allowedStatusCodes,
    );
  }

  static Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    Set<int>? allowedStatusCodes,
  }) {
    return _request(
      method: 'POST',
      path: path,
      headers: headers,
      body: body,
      timeout: timeout,
      allowedStatusCodes: allowedStatusCodes,
    );
  }

  static Future<http.Response> put(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    Set<int>? allowedStatusCodes,
  }) {
    return _request(
      method: 'PUT',
      path: path,
      headers: headers,
      body: body,
      timeout: timeout,
      allowedStatusCodes: allowedStatusCodes,
    );
  }

  static Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    Set<int>? allowedStatusCodes,
  }) {
    return _request(
      method: 'DELETE',
      path: path,
      headers: headers,
      body: body,
      timeout: timeout,
      allowedStatusCodes: allowedStatusCodes,
    );
  }

  /// PATCH helper
  static Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    Set<int>? allowedStatusCodes,
  }) {
    return _request(
      method: 'PATCH',
      path: path,
      headers: headers,
      body: body,
      timeout: timeout,
      allowedStatusCodes: allowedStatusCodes,
    );
  }

  // ---------- Core request + error handling ----------

  static Future<http.Response> _request({
    required String method,
    required String path,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    Set<int>? allowedStatusCodes,
  }) async {
    // Ensure backend is reachable
    final backendOk = await ApiConfig.ensureBackendUp();
    if (!backendOk) {
      throw const ApiException(
        message: 'Please check your internet connection and try again.',
      );
    }

    final uri = ApiConfig.endpoint(path);
    final allHeaders = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    };

    // 🔐 Auto‑attach Firebase ID token (JWT) if logged in and no Authorization provided
    try {
      final hasAuthHeader =
          allHeaders.keys.any((k) => k.toLowerCase() == 'authorization');
      if (!hasAuthHeader) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final rawToken = await user.getIdToken();
          final token = rawToken?.trim();
          if (token != null && token.isNotEmpty) {
            allHeaders['Authorization'] = 'Bearer $token';
            if (kDebugMode) {
              debugPrint('[JWT] Firebase ID token length: ${token.length}');
              debugPrint('[JWT] jwt_token: $token');
            }
          }
        }
      }
    } catch (_) {
      // If token fetch fails, just send request without auth
    }

    try {
      Future<http.Response> future;
      switch (lineUpper(method)) {
        case 'GET':
          future = http.get(uri, headers: allHeaders);
          break;
        case 'POST':
          future = http.post(uri, headers: allHeaders, body: body);
          break;
        case 'PUT':
          future = http.put(uri, headers: allHeaders, body: body);
          break;
        case 'DELETE':
          future = http.delete(uri, headers: allHeaders, body: body);
          break;
        case 'PATCH':
          future = http.patch(uri, headers: allHeaders, body: body);
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }

      final res = await future.timeout(timeout ?? _defaultTimeout);

      final allowed = allowedStatusCodes?.contains(res.statusCode) ?? false;
      if ((res.statusCode >= 200 && res.statusCode < 300) || allowed) {
        return res;
      }

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

      if (kDebugMode) {
        debugPrint('API $method ${uri.path} -> ${res.statusCode} ${res.body}');
      }

      final userMsg = backendMsg ??
          'We couldn’t process your request. Please check your details and try again.';

      throw ApiException(
        message: userMsg,
        statusCode: res.statusCode,
        backendMessage: backendMsg,
      );
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('API $method ${uri.path} -> timeout');
      }
      throw const ApiException(
        message:
            'Request timed out. Please check your connection and try again.',
      );
    } on http.ClientException catch (e) {
      if (kDebugMode) {
        debugPrint('API $method ${uri.path} -> network error: $e');
      }
      throw const ApiException(
        message: 'Network error. Please check your connection and try again.',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('API $method ${uri.path} -> unexpected error: $e');
      }
      throw const ApiException(
        message: 'Something went wrong. Please try again.',
      );
    }
  }

  static String lineUpper(String s) => s.toUpperCase();
}