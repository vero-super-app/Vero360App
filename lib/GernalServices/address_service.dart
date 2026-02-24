// lib/services/address_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

class AuthRequiredException implements Exception {
  final String message;
  AuthRequiredException([this.message = 'Authentication required']);
  @override
  String toString() => message;
}

class AddressService {
  // ---------- Simple in-memory cache for address list ----------
  List<Address>? _cachedAddresses;
  DateTime? _addressesFetchedAt;
  static const Duration _addressesCacheTtl = Duration(minutes: 5);

  void _clearAddressesCache() {
    _cachedAddresses = null;
    _addressesFetchedAt = null;
  }

  // ---------- Core helpers (Firebase auth for NestJS FirebaseAuthGuard) ----------

  /// Uses Firebase ID token so backend FirebaseAuthGuard can verify the user.
  Future<String> _getTokenOrThrow() async {
    final token = await AuthHandler.getFirebaseToken();
    if (token == null || token.isEmpty) {
      throw AuthRequiredException('No Auth token Found. Please log in.');
    }
    return token;
  }

  Future<Map<String, String>> _authHeaders() async {
    // Ensure ApiConfig loads persisted base URL before any endpoint() calls.
    await ApiConfig.init();
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

  dynamic _decodeJsonBody(http.Response r, {required String endpointName}) {
    try {
      return jsonDecode(r.body);
    } catch (_) {
      final snippet = r.body.length > 220 ? '${r.body.substring(0, 220)}...' : r.body;
      throw Exception(
        '$endpointName returned non-JSON response (${r.statusCode}). Body: $snippet',
      );
    }
  }

  List<Map<String, dynamic>> _extractPredictions(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }

    if (data is! Map) return <Map<String, dynamic>>[];

    final directPredictions = data['predictions'];
    if (directPredictions is List) {
      return directPredictions.whereType<Map<String, dynamic>>().toList();
    }

    final nestedData = data['data'];
    if (nestedData is List) {
      return nestedData.whereType<Map<String, dynamic>>().toList();
    }
    if (nestedData is Map && nestedData['predictions'] is List) {
      return (nestedData['predictions'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    final results = data['results'];
    if (results is List) {
      return results.whereType<Map<String, dynamic>>().toList();
    }

    return <Map<String, dynamic>>[];
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

  // GET /vero/addresses/me (Firebase auth)
  Future<List<Address>> getMyAddresses({
    bool forceRefresh = false,
    bool allowCache = true,
  }) async {
    // Return cached value when allowed and still fresh
    if (!forceRefresh &&
        allowCache &&
        _cachedAddresses != null &&
        _addressesFetchedAt != null) {
      final age = DateTime.now().difference(_addressesFetchedAt!);
      if (age <= _addressesCacheTtl) {
        return _cachedAddresses!;
      }
    }

    final h = await _authHeaders();
    final u = ApiConfig.endpoint('addresses/me');

    final r = await _sendWithRetry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _handleBad(r);

    final decoded = jsonDecode(r.body);
    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : <dynamic>[];

    final parsed = list
        .whereType<Map<String, dynamic>>()
        .map<Address>((m) => Address.fromJson(m))
        .toList();

    // Cache a defensive copy
    _cachedAddresses = List<Address>.from(parsed);
    _addressesFetchedAt = DateTime.now();

    return parsed;
  }

  Future<List<Map<String, dynamic>>> placesAutocomplete(String q,
      {String? sessionToken}) async {
    final h = await _authHeaders();
    final u = ApiConfig.endpoint('addresses/places/autocomplete')
        .replace(queryParameters: {
      'q': q,
      // Compatibility with handlers that expect Google's original key name.
      'input': q,
      if (sessionToken != null) 'st': sessionToken,
      if (sessionToken != null) 'sessionToken': sessionToken,
    });

    final r = await _sendWithRetry(() => http.get(u, headers: h));
    if (r.statusCode != 200) _handleBad(r);
    final data = _decodeJsonBody(r, endpointName: 'places autocomplete');
    final preds = _extractPredictions(data);

    if (preds.isNotEmpty) return preds;

    if (data is Map) {
      final status = (data['status'] ?? data['error'] ?? '').toString();
      final message = (data['message'] ?? '').toString();
      if (status.isNotEmpty || message.isNotEmpty) {
        throw Exception('Autocomplete failed: $status ${message.trim()}'.trim());
      }
    }

    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>?> placeDetails(String placeId,
      {String? sessionToken}) async {
    final h = await _authHeaders();
    final directPath = ApiConfig.endpoint('addresses/places/details/$placeId')
        .replace(queryParameters: {
      if (sessionToken != null) 'st': sessionToken,
      if (sessionToken != null) 'sessionToken': sessionToken,
    });

    http.Response r = await _sendWithRetry(() => http.get(directPath, headers: h));

    // Compatibility fallback when backend expects query parameter instead of path segment.
    if (r.statusCode == 404) {
      final queryPath = ApiConfig.endpoint('addresses/places/details').replace(
        queryParameters: {
          'placeId': placeId,
          if (sessionToken != null) 'st': sessionToken,
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );
      r = await _sendWithRetry(() => http.get(queryPath, headers: h));
    }

    if (r.statusCode != 200) _handleBad(r);
    final data = _decodeJsonBody(r, endpointName: 'place details');

    if (data is Map<String, dynamic>) {
      if (data['result'] is Map<String, dynamic>) {
        return data['result'] as Map<String, dynamic>;
      }
      if (data['data'] is Map<String, dynamic>) {
        final nested = data['data'] as Map<String, dynamic>;
        if (nested['result'] is Map<String, dynamic>) {
          return nested['result'] as Map<String, dynamic>;
        }
        return nested;
      }
      return data;
    }

    throw Exception('Place details returned invalid response shape');
  }

  // POST /vero/addresses (Firebase auth)
  Future<Address> createAddress(AddressPayload payload) async {
    final h = await _authHeaders();
    final u = ApiConfig.endpoint('addresses');

    final r = await _sendWithRetry(
      () => http.post(u, headers: h, body: jsonEncode(payload.toJson())),
    );

    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);

    if (r.body.isEmpty) {
      // Some APIs return 204; refetch list and return last
      final all =
          await getMyAddresses(forceRefresh: true, allowCache: false);
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

  // PUT /vero/addresses/:id (Firebase auth)
  Future<Address> updateAddress(String id, AddressPayload payload) async {
    final h = await _authHeaders();
    final u = ApiConfig.endpoint('addresses/$id');

    final r = await _sendWithRetry(
      () => http.put(u, headers: h, body: jsonEncode(payload.toJson())),
    );

    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);

    if (r.body.isEmpty) {
      // Gracefully handle 204: re-fetch the updated list and find the record
      final all =
          await getMyAddresses(forceRefresh: true, allowCache: false);
      return all.firstWhere((a) => a.id == id, orElse: () {
        // If not found just return a minimal model
        return Address(
          id: id,
          addressType: payload.addressType,
          city: payload.city,
          description: payload.description,
          isDefault: payload.isDefault == true,
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

  // DELETE /vero/addresses/:id (Firebase auth)
  Future<void> deleteAddress(String id) async {
    final h = await _authHeaders();
    final u = ApiConfig.endpoint('addresses/$id');

    final r = await _sendWithRetry(() => http.delete(u, headers: h));
    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);
    _clearAddressesCache();
  }

  /// POST /vero/addresses/:id/default (Firebase auth)
  Future<void> setDefaultAddress(String id) async {
    final h = await _authHeaders();
    final u = ApiConfig.endpoint('addresses/$id/default');

    final r = await _sendWithRetry(() => http.post(u, headers: h));
    if (r.statusCode < 200 || r.statusCode >= 300) _handleBad(r);
    _clearAddressesCache();
  }
}
