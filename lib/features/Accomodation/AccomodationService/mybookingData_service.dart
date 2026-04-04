import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

class AuthRequiredException implements Exception {
  final String message;
  AuthRequiredException([this.message = 'Authentication required']);
  @override
  String toString() => message;
}

class MyBookingService {
  /* --------------------- infra helpers --------------------- */

  Future<Uri> _uri(String path, [Map<String, String>? queryParameters]) async {
    await ApiConfig.init();
    final p = path.startsWith('/') ? path : '/$path';
    var u = ApiConfig.endpoint(p);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      u = u.replace(
        queryParameters: {
          ...u.queryParameters,
          ...queryParameters,
        },
      );
    }
    return u;
  }

  Future<String> _token() async {
    final firebase = await AuthHandler.getTokenForApi();
    if (firebase != null && firebase.trim().isNotEmpty) {
      return firebase.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'jwt_token',
      'token',
      'authToken',
      'merchant_token',
      'merchantToken'
    ];
    for (final k in keys) {
      final t = prefs.getString(k);
      if (t != null && t.isNotEmpty) return t;
    }
    throw AuthRequiredException('No auth token found');
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isMerchant() async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool('is_merchant') ?? prefs.getBool('merchant')) == true) {
      return true;
    }
    final roleStr =
        (prefs.getString('role') ?? prefs.getString('userRole') ?? '')
            .toLowerCase();
    if (roleStr.contains('merchant')) return true;

    try {
      final t = await _token();
      final p = _decodeJwtPayload(t);
      if (p != null) {
        if (p['isMerchant'] == true) return true;
        final role = (p['role'] ?? '').toString().toLowerCase();
        if (role.contains('merchant')) return true;
        final roles = p['roles'];
        if (roles is List &&
            roles.map((e) => '$e'.toLowerCase()).contains('merchant')) {
          return true;
        }
        final scope = (p['scope'] ?? '').toString().toLowerCase();
        if (scope.contains('merchant')) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, String>> _headers() async => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _token()}',
      };

  Never _bad(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw AuthRequiredException('Unauthorized or session expired');
    }
    throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  Future<http.Response> _retry(Future<http.Response> Function() run,
      {int retries = 2}) async {
    int attempt = 0;
    while (true) {
      try {
        final res = await run().timeout(const Duration(seconds: 45));
        if ((res.statusCode == 502 ||
                res.statusCode == 503 ||
                res.statusCode == 504) &&
            attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        return res;
      } on TimeoutException {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      } on SocketException {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  /* --------------------- public API --------------------- */

  // Chooses the right “me” endpoint by role.
  // Customer:  GET /bookings/me
  // Merchant:  GET /bookings/merchant/me   (mirror of your orders pattern)
  Future<List<BookingItem>> getMyBookings({BookingStatus? status}) async {
    final isMerchant = await _isMerchant();
    final path = isMerchant ? '/bookings/merchant/me' : '/bookings/me';

    final qp = status != null ? {'status': bookingStatusToApi(status)} : null;
    final u = await _uri(path, qp);
    final h = await _headers();

    final r = await _retry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _bad(r);

    final decoded = jsonDecode(r.body);
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : (decoded is Map ? [decoded] : <dynamic>[]);

    var all = list
        .whereType<Map<String, dynamic>>()
        .map(BookingItem.fromJson)
        .toList();

    // Guests: only paid / settled stays (createBooking runs before PayChangu; unpaid rows stay hidden).
    if (!isMerchant) {
      all = all.where((b) => b.includeInGuestMyBookings).toList();
    }

    if (status != null) {
      return all.where((b) => b.status == status).toList();
    }
    return all;
  }

  /// Stays the user **booked as a guest** (`GET /vero/bookings/me`), even when they are
  /// also a merchant (merchant list uses `/bookings/merchant/me` elsewhere).
  Future<List<BookingItem>> getGuestStaysForDiscoverOverlay() async {
    final u = await _uri('/bookings/me');
    final h = await _headers();

    final r = await _retry(() => http.get(u, headers: h));
    if (r.statusCode != 200) {
      if (r.statusCode == 404) return [];
      _bad(r);
    }

    final decoded = jsonDecode(r.body);
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : (decoded is Map ? [decoded] : <dynamic>[]);

    return list
        .whereType<Map<String, dynamic>>()
        .map(BookingItem.fromJson)
        .where((b) => b.includeInGuestMyBookings)
        .toList();
  }

  /// Incoming stays for **this user as host** (`GET /vero/bookings/merchant/me`).
  /// Use from the accommodation merchant dashboard — do not rely on [_isMerchant] prefs/JWT,
  /// or hosts may incorrectly hit `/bookings/me` and see an empty list.
  Future<List<BookingItem>> getMerchantIncomingBookings({BookingStatus? status}) async {
    final qp = status != null ? {'status': bookingStatusToApi(status)} : null;
    final u = await _uri('/bookings/merchant/me', qp);
    final h = await _headers();

    final r = await _retry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _bad(r);

    final decoded = jsonDecode(r.body);
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : (decoded is Map ? [decoded] : <dynamic>[]);

    var all = list
        .whereType<Map<String, dynamic>>()
        .map(BookingItem.fromJson)
        .toList();

    if (status != null) {
      return all.where((b) => b.status == status).toList();
    }
    return all;
  }

  // Create, update, delete remain the same — role is typically enforced by the server.
  Future<BookingItem> createBooking(BookingCreatePayload payload,
      {String? overridePath}) async {
    final u = await _uri(overridePath ?? '/bookings');
    final h = await _headers();
    final r = await _retry(
        () => http.post(u, headers: h, body: jsonEncode(payload.toJson())));
    if (r.statusCode < 200 || r.statusCode >= 300) _bad(r);

    final d = jsonDecode(r.body);
    final map = (d is Map<String, dynamic>)
        ? d
        : (d is Map && d['data'] is Map)
            ? d['data'] as Map<String, dynamic>
            : <String, dynamic>{};
    return BookingItem.fromJson(map);
  }

  Future<void> updateStatus(String id, BookingStatus next) async {
    final u = await _uri('/bookings/$id/status');
    final h = await _headers();
    final body = jsonEncode({'status': bookingStatusToApi(next)});
    final r = await _retry(() => http.patch(u, headers: h, body: body));
    if (r.statusCode < 200 || r.statusCode >= 300) _bad(r);
  }

  /// `DELETE /vero/bookings/:id` — server may return 204 No Content.
  Future<void> deleteBooking(String id) async {
    final u = await _uri('/bookings/$id');
    final h = await _headers();
    final r = await _retry(() => http.delete(u, headers: h));
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _bad(r);
  }

  Future<bool> cancelOrDelete(String id) async {
    try {
      await updateStatus(id, BookingStatus.cancelled);
      return true;
    } catch (_) {
      await deleteBooking(id);
      return false;
    }
  }
}
