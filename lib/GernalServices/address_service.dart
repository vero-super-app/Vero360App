// lib/services/address_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  // ---------- Shared cache (survives across AddressService instances / pages) ----------
  static List<Address>? _cachedAddresses;
  static DateTime? _addressesFetchedAt;
  static const Duration _addressesCacheTtl = Duration(minutes: 5);
  static const String _diskCacheKey = 'vero_addresses_me_cache_v1';
  static bool _diskHydrated = false;

  void _clearAddressesCache() {
    _cachedAddresses = null;
    _addressesFetchedAt = null;
    unawaited(_clearDiskCache());
  }

  /// Sync peek of in-memory default address (instant first paint on checkout).
  static Address? peekDefaultAddress() {
    final list = _cachedAddresses;
    if (list == null || list.isEmpty) return null;
    return _pickDefault(list);
  }

  /// Sync peek of full in-memory list.
  static List<Address>? peekCachedAddresses() {
    final list = _cachedAddresses;
    if (list == null) return null;
    return List<Address>.from(list);
  }

  static Address? _pickDefault(List<Address> list) {
    for (final a in list) {
      if (a.isDefault) return a;
    }
    return list.isNotEmpty ? list.first : null;
  }

  Future<void> _persistDiskCache(List<Address> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'fetchedAt': DateTime.now().toIso8601String(),
        'addresses': list.map((a) => a.toJson()).toList(),
      });
      await prefs.setString(_diskCacheKey, payload);
    } catch (_) {}
  }

  Future<void> _clearDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_diskCacheKey);
      _diskHydrated = false;
    } catch (_) {}
  }

  /// Load addresses from disk into memory (no network). Safe to call often.
  Future<List<Address>> hydrateFromDisk() async {
    if (_cachedAddresses != null && _cachedAddresses!.isNotEmpty) {
      return List<Address>.from(_cachedAddresses!);
    }
    if (_diskHydrated && _cachedAddresses != null) {
      return List<Address>.from(_cachedAddresses!);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskCacheKey);
      _diskHydrated = true;
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final listRaw = decoded['addresses'];
      if (listRaw is! List) return const [];
      final parsed = listRaw
          .whereType<Map>()
          .map((m) => Address.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _cachedAddresses = parsed;
      final fetchedAtRaw = decoded['fetchedAt']?.toString();
      _addressesFetchedAt =
          fetchedAtRaw != null ? DateTime.tryParse(fetchedAtRaw) : null;
      return List<Address>.from(parsed);
    } catch (_) {
      _diskHydrated = true;
      return const [];
    }
  }

  /// Fast default for checkout: memory → disk → null (never waits on API).
  Future<Address?> getCachedDefaultAddress() async {
    final mem = peekDefaultAddress();
    if (mem != null) return mem;
    final disk = await hydrateFromDisk();
    return _pickDefault(disk);
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
    // Avoid leaking response bodies or sensitive debug info to UI.
    throw Exception('Request failed. Please try again.');
  }

  dynamic _decodeJsonBody(http.Response r, {required String endpointName}) {
    try {
      return jsonDecode(r.body);
    } catch (_) {
      // Avoid leaking raw body content to UI.
      throw Exception('Unexpected server response. Please try again.');
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
      } on SocketException {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        throw Exception('No internet connection. Please check your network and try again.');
      } on http.ClientException {
        if (attempt < retries) {
          attempt++;
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        throw Exception('Could not reach the server. Please try again.');
      }
    }
  }

  // ---------- API methods ----------

  // GET /vero/addresses/me (Firebase auth)
  Future<List<Address>> getMyAddresses({
    bool forceRefresh = false,
    bool allowCache = true,
  }) async {
    // Return shared memory cache when allowed and still fresh
    if (!forceRefresh &&
        allowCache &&
        _cachedAddresses != null &&
        _addressesFetchedAt != null) {
      final age = DateTime.now().difference(_addressesFetchedAt!);
      if (age <= _addressesCacheTtl) {
        return List<Address>.from(_cachedAddresses!);
      }
    }

    // Stale/empty memory: try disk before network so callers can paint faster
    // when they call hydrateFromDisk separately; still fetch network below.
    if (!forceRefresh && allowCache && _cachedAddresses == null) {
      final disk = await hydrateFromDisk();
      if (disk.isNotEmpty &&
          _addressesFetchedAt != null &&
          DateTime.now().difference(_addressesFetchedAt!) <=
              _addressesCacheTtl) {
        return disk;
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

    // Shared memory + disk cache
    _cachedAddresses = List<Address>.from(parsed);
    _addressesFetchedAt = DateTime.now();
    unawaited(_persistDiskCache(parsed));

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
        // Avoid leaking backend message/status to UI.
        throw Exception('Address autocomplete failed. Please try again.');
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
