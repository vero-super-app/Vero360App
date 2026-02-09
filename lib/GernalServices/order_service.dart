import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

/// Thrown when user must login again (safe to show to user)
class AuthRequiredException implements Exception {
  final String message;
  AuthRequiredException([this.message = 'Please sign in to continue.']);
  @override
  String toString() => message;
}

/// Thrown for any API/network issue, with a user-friendly message only.
/// (No endpoints, no status codes, no raw response bodies)
class FriendlyApiException implements Exception {
  final String message;

  /// For internal logging only (do NOT show to user)
  final String? debugMessage;
  final int? statusCode;

  FriendlyApiException(
    this.message, {
    this.debugMessage,
    this.statusCode,
  });

  @override
  String toString() => message;
}

class OrderService {
  /* --------------------- infra helpers --------------------- */

  Future<String> _token() async {
    // Use same token as rest of app (Firebase → SP)
    final t = await AuthHandler.getTokenForApi();
    if (t != null && t.trim().isNotEmpty) return t.trim();

    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'jwt_token',
      'token',
      'authToken',
      'merchant_token',
      'merchantToken',
      'jwt'
    ];
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    throw AuthRequiredException('Please sign in to continue.');
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isMerchant() async {
    // 1) Prefer explicit flags saved during login
    final prefs = await SharedPreferences.getInstance();
    final explicit =
        (prefs.getBool('is_merchant') ?? prefs.getBool('merchant')) == true;
    if (explicit) return true;

    final roleStr =
        (prefs.getString('role') ?? prefs.getString('userRole') ?? '')
            .toLowerCase();
    if (roleStr.contains('merchant')) return true;

    // 2) Fallback: inspect JWT claims
    try {
      final t = await _token();
      final p = _decodeJwtPayload(t);
      if (p != null) {
        if (p['isMerchant'] == true) return true;

        final role = (p['role'] ?? '').toString().toLowerCase();
        if (role.contains('merchant')) return true;

        final roles = p['roles'];
        if (roles is List &&
            roles.map((e) => '$e'.toLowerCase()).contains('merchant'))
          return true;

        final scope = (p['scope'] ?? '').toString().toLowerCase();
        if (scope.contains('merchant')) return true;

        final perms = p['permissions'];
        if (perms is List &&
            perms.map((e) => '$e'.toLowerCase()).contains('merchant'))
          return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, String>> _headers() async => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _token()}',
      };

  String _friendlyMessageForStatus(int code, {required String action}) {
    if (code == 401 || code == 403)
      return 'Your session has expired. Please sign in again.';
    if (code == 404) return 'We couldn’t find what you requested.';
    if (code == 408) return 'Request timed out. Please try again.';
    if (code == 409)
      return 'This request couldn’t be completed due to a conflict. Please refresh and try again.';
    if (code == 422 || code == 400)
      return 'We couldn’t $action. Please check your details and try again.';
    if (code >= 500)
      return 'We couldn’t $action right now. Please try again shortly.';
    return 'We couldn’t $action. Please try again.';
  }

  Never _bad(http.Response r,
      {required String action, Object? error, StackTrace? st}) {
    // Always log technical details internally only
    dev.log(
      '[OrderService] HTTP error',
      name: 'OrderService',
      error:
          error ?? {'status': r.statusCode, 'body': _safeBodyForLogs(r.body)},
      stackTrace: st,
    );

    if (r.statusCode == 401 || r.statusCode == 403) {
      throw AuthRequiredException(
          'Your session has expired. Please sign in again.');
    }

    throw FriendlyApiException(
      _friendlyMessageForStatus(r.statusCode, action: action),
      statusCode: r.statusCode,
      debugMessage: 'HTTP ${r.statusCode} (hidden)',
    );
  }

  String _safeBodyForLogs(String body) {
    // Avoid logging massive payloads
    if (body.length <= 1200) return body;
    return '${body.substring(0, 1200)}…(truncated)';
  }

  FriendlyApiException _networkFriendly(Object e,
      {StackTrace? st, required String action}) {
    // Internal log only
    dev.log('[OrderService] Network/Client error',
        name: 'OrderService', error: e, stackTrace: st);

    if (e is TimeoutException) {
      return FriendlyApiException('Request timed out. Please try again.',
          debugMessage: 'Timeout', statusCode: 408);
    }
    if (e is SocketException) {
      return FriendlyApiException(
          'No internet connection. Please check your network and try again.',
          debugMessage: 'SocketException');
    }
    if (e is http.ClientException) {
      return FriendlyApiException(
          'We couldn’t reach the server. Please try again.',
          debugMessage: 'ClientException');
    }
    return FriendlyApiException('We couldn’t $action. Please try again.',
        debugMessage: 'Unknown error: $e');
  }

  Future<http.Response> _retry(
    Future<http.Response> Function() run, {
    int retries = 2,
    required String action,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        final res = await run().timeout(const Duration(seconds: 45));

        // Retry on temporary gateway issues
        if ((res.statusCode == 502 ||
                res.statusCode == 503 ||
                res.statusCode == 504) &&
            attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }

        return res;
      } catch (e, st) {
        final canRetry = attempt < retries &&
            (e is TimeoutException ||
                e is SocketException ||
                e is http.ClientException);

        if (canRetry) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }

        // Throw friendly (no raw technical details)
        throw _networkFriendly(e, st: st, action: action);
      }
    }
  }

  /* --------------------- public API --------------------- */

  // Chooses the right “me” endpoint by role.
  bool _isSingleOrderMap(Map<dynamic, dynamic> m) {
    final hasId = m.containsKey('ID') || m.containsKey('id');
    final hasOrderNo =
        m.containsKey('OrderNumber') || m.containsKey('orderNumber');
    return hasId && hasOrderNo;
  }

  Future<List<OrderItem>> getMyOrders({OrderStatus? status}) async {
    await ApiConfig.readBase();
    final isMerchant = await _isMerchant();

    // Primary endpoints match your backend:
    // - customer: GET /vero/orders/me
    // - merchant: GET /vero/orders/merchant/me
    final primaryPath = isMerchant ? '/orders/merchant/me' : '/orders/me';
    final qp = status != null ? {'status': orderStatusToApi(status)} : null;

    Uri buildUri(String path) {
      final base = ApiConfig.endpoint(path);
      return qp != null ? base.replace(queryParameters: qp) : base;
    }

    var u = buildUri(primaryPath);
    final h = await _headers();

    var r =
        await _retry(() => http.get(u, headers: h), action: 'load your orders');

    // Fallback: if /me endpoint 404s, try generic /orders
    if (r.statusCode == 404) {
      final fallbackPath = '/orders';
      u = buildUri(fallbackPath);
      r = await _retry(
          () => http.get(u, headers: h), action: 'load your orders');
    }

    if (r.statusCode == 404) return [];
    if (r.statusCode != 200 && r.statusCode != 201) {
      _bad(r, action: 'load your orders');
    }

    try {
      final decoded = jsonDecode(r.body);

      // Backend may return: List, { data: List }, { data: singleOrder }, { orders: List }, or single order object
      List<dynamic> list;
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map) {
        final map = Map<dynamic, dynamic>.from(decoded);
        if (decoded['data'] is List) {
          list = decoded['data'] as List;
        } else if (decoded['data'] is Map) {
          final dataMap = Map<dynamic, dynamic>.from(decoded['data'] as Map);
          list = _isSingleOrderMap(dataMap) ? [decoded['data']] : <dynamic>[];
        } else if (decoded['orders'] is List) {
          list = decoded['orders'] as List;
        } else if (_isSingleOrderMap(map)) {
          list = [decoded];
        } else {
          list = <dynamic>[];
        }
      } else {
        list = <dynamic>[];
      }

      final all = list
          .whereType<Map>()
          .map((m) => OrderItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      // If backend ignored the filter, narrow client-side.
      if (status != null) {
        return all.where((o) => o.status == status).toList();
      }
      return all;
    } catch (e, st) {
      dev.log('[OrderService] JSON parse error',
          name: 'OrderService', error: e, stackTrace: st);
      throw FriendlyApiException(
          'We couldn’t load your orders. Please try again.');
    }
  }

  // PATCH /orders/{id}/status (works for either role if permitted server-side)
  Future<void> updateStatus(String id, OrderStatus next) async {
    if (id.trim().isEmpty) {
      throw FriendlyApiException(
          'Invalid order. Please refresh and try again.');
    }

    final u = ApiConfig.endpoint('/orders/$id/status');
    final h = await _headers();

    // keep your server's expected key casing
    final body = jsonEncode({'Status': orderStatusToApi(next)});

    final r = await _retry(() => http.patch(u, headers: h, body: body),
        action: 'update the order');
    if (r.statusCode < 200 || r.statusCode >= 300)
      _bad(r, action: 'update the order');
  }

  // Cancel, else delete as fallback.
  Future<bool> cancelOrMarkCancelled(String id) async {
    try {
      await updateStatus(id, OrderStatus.cancelled);
      return true;
    } on AuthRequiredException {
      rethrow;
    } on FriendlyApiException {
      rethrow;
    } catch (_) {
      // fallback: delete endpoint
      final u = ApiConfig.endpoint('/orders/$id');
      final h = await _headers();
      final r = await _retry(() => http.delete(u, headers: h),
          action: 'cancel the order');
      if (r.statusCode < 200 || r.statusCode >= 300)
        _bad(r, action: 'cancel the order');
      return false;
    }
  }
}
