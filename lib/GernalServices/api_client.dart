import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;

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

  // ✅ NEW: PATCH helper
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
    // 🔐 ensure backend (primary or backup) is reachable
    final ok = await ApiConfig.ensureBackendUp();
    if (!ok) {
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

    try {
      Future<http.Response> future;

      switch (method) {
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

      final isExplicitlyAllowed = allowedStatusCodes != null &&
          allowedStatusCodes.contains(res.statusCode);

      if ((res.statusCode >= 200 && res.statusCode < 300) ||
          isExplicitlyAllowed) {
        return res;
      }

      // Try to extract backend message safely
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
      } catch (_) {
        // ignore JSON errors
      }

      if (kDebugMode) {
        debugPrint(
          'API $method ${uri.path} -> ${res.statusCode} ${res.body}',
        );
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
}
