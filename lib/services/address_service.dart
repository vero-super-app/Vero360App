// lib/services/address_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/models/address_model.dart';
import 'package:vero360_app/config/api_config.dart';

class AuthRequiredException implements Exception {
  final String message;
  AuthRequiredException([this.message = 'Authentication required']);
  @override
  String toString() => message;
}

class AddressService {
  // ---------- Core helpers ----------

  Future<String> _readBase() => ApiConfig.readBase();

  Future<String> _getTokenOrThrow() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw AuthRequiredException('No auth token found.');
    }
    return token;
  }

  Future<Map<String, String>> _authHeaders() async {
    final t = await _getTokenOrThrow();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $t',
    };
  }

  Never _handleBad(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw AuthRequiredException('Unauthorized or session expired');
    }
    throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  /// Render cold starts can exceed 20s. Use 60s + retry with small backoff.
  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() fn, {
    int retries = 2,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        final res = await fn().timeout(const Duration(seconds: 60));
        // retry on 502/503/504 (cold start)
        if ((res.statusCode == 502 ||
                res.statusCode == 503 ||
                res.statusCode == 504) &&
            attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        return res;
      } on TimeoutException {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        rethrow;
      } on SocketException catch (e) {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        throw Exception('Network error: $e');
      } on http.ClientException catch (e) {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        throw Exception('HTTP client error: $e');
      }
    }
  }

  // ---------- API methods ----------

  // GET /addresses/me
  Future<List<Address>> getMyAddresses() async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses/me');

    final r = await _sendWithRetry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _handleBad(r);

    final decoded = jsonDecode(r.body);
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : <dynamic>[];

    return list
        .whereType<Map<String, dynamic>>()
        .map<Address>((m) => Address.fromJson(m))
        .toList();
  }

  // lib/services/address_service.dart  (add two helpers)
  Future<List<Map<String, dynamic>>> placesAutocomplete(String q,
      {String? sessionToken}) async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses/places/autocomplete')
        .replace(queryParameters: {
      'q': q,
      if (sessionToken != null) 'st': sessionToken,
    });

    final r = await _sendWithRetry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _handleBad(r);
    final data = jsonDecode(r.body);
    final List preds = (data['predictions'] ?? []) as List;
    return preds.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> placeDetails(String placeId,
      {String? sessionToken}) async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses/places/details/$placeId')
        .replace(queryParameters: {
      if (sessionToken != null) 'st': sessionToken,
    });

    final r = await _sendWithRetry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _handleBad(r);
    final data = jsonDecode(r.body);
    return (data['result'] ?? data) as Map<String, dynamic>?;
  }

  // POST /addresses
  Future<Address> createAddress(AddressPayload payload) async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses');

    final r = await _sendWithRetry(
      () => http.post(u, headers: h, body: jsonEncode(payload.toJson())),
    );

    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);

    if (r.body.isEmpty) {
      // Some APIs return 204; refetch list and return last
      final all = await getMyAddresses();
      return all.isNotEmpty
          ? all.last
          : throw Exception('Create succeeded but no body/list empty');
    }

    final d = jsonDecode(r.body);
    final map = (d is Map<String, dynamic>)
        ? d
        : (d is Map && d['data'] is Map)
            ? d['data'] as Map<String, dynamic>
            : <String, dynamic>{};
    return Address.fromJson(map);
  }

  // PUT /addresses/:id
  Future<Address> updateAddress(String id, AddressPayload payload) async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses/$id');

    final r = await _sendWithRetry(
      () => http.put(u, headers: h, body: jsonEncode(payload.toJson())),
    );

    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);

    if (r.body.isEmpty) {
      // Gracefully handle 204: re-fetch the updated list and find the record
      final all = await getMyAddresses();
      return all.firstWhere((a) => a.id == id, orElse: () {
        // If not found just return a minimal model
        return Address(
          id: id,
          addressType: payload.addressType,
          city: payload.city,
          description: payload.description ?? '',
          isDefault: payload.isDefault ?? false,
        );
      });
    }

    final d = jsonDecode(r.body);
    final map = (d is Map<String, dynamic>)
        ? d
        : (d is Map && d['data'] is Map)
            ? d['data'] as Map<String, dynamic>
            : <String, dynamic>{};
    return Address.fromJson(map);
  }

  // DELETE /addresses/:id
  Future<void> deleteAddress(String id) async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses/$id');

    final r = await _sendWithRetry(() => http.delete(u, headers: h));
    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);
  }

  /// Mark one address as default. If your backend has
  /// `POST /addresses/:id/default` use that instead.
  Future<void> setDefaultAddress(String id) async {
    final base = await _readBase();
    final h = await _authHeaders();
    final u = Uri.parse('$base/addresses/$id/default');

    final r = await _sendWithRetry(() => http.post(u, headers: h));
    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);
  }
}
