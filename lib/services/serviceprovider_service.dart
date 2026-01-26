// lib/services/serviceprovider_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/services/api_exception.dart';

import '../models/serviceprovider_model.dart';

/// Legacy static-style service (kept for compatibility)
class ServiceProviderServicess {
  // Build a full URI from the configured base + path (handles slashes)
  static Future<Uri> _u(String path) async {
    final base = await ApiConfig.readBase(); // e.g. http://10.0.2.2:3000
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$b$p');
  }

  static Future<String?> _getToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('jwt') ?? sp.getString('token');
  }

  /// Get *my* service provider (shop) – returns null if not found.
  static Future<ServiceProvider?> fetchMine() async {
    final t = await _getToken();
    final uri = await _u('/serviceprovider/me');

    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (t != null) 'Authorization': 'Bearer $t',
      },
    );

    if (res.statusCode == 200) {
      final raw = res.body.trim();

      // 🔹 Backend sometimes returns empty body → treat as "no shop yet"
      if (raw.isEmpty) {
        debugPrint('fetchMine: 200 with empty body -> treating as no shop');
        return null;
      }

      try {
        final body = jsonDecode(raw);
        final data =
            (body is Map && body['data'] != null) ? body['data'] : body;
        if (data == null) return null;
        return ServiceProvider.fromJson(data);
      } catch (e) {
        // If backend sent HTML or some weird string, don't crash UI.
        debugPrint('fetchMine json error: $e  body: ${res.body}');
        return null;
      }
    }

    if (res.statusCode == 404) {
      // Explicit "not found" also means no shop.
      return null;
    }

    debugPrint('fetchMine failed: ${res.statusCode} ${res.body}');
    throw ApiException(
      message: 'fetchMine failed',
      statusCode: res.statusCode,
    );
  }

  static Future<ServiceProvider?> fetchByNumber(String spNumber) async {
    final uri = await _u('/serviceprovider/search/$spNumber');
    final res = await http.get(uri, headers: {'Accept': 'application/json'});

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      // If not found your backend returns a string message; guard for that.
      if (body is Map<String, dynamic> && body['id'] != null) {
        return ServiceProvider.fromJson(body);
      }
      return null;
    }

    debugPrint('fetchByNumber failed: ${res.statusCode} ${res.body}');
    throw ApiException(
      message: 'fetchByNumber failed',
      statusCode: res.statusCode,
    );
  }

  static Future<ServiceProvider> create({
    required String businessName,
    String? businessDescription,
    String? status,
    required String openingHours,
    String? logoPath, // mobile/desktop
    Uint8List? logoBytes, // web
    String? logoFileName,
  }) async {
    final t = await _getToken();
    final uri = await _u('/serviceprovider');

    final req = http.MultipartRequest('POST', uri);
    if (t != null) req.headers['Authorization'] = 'Bearer $t';
    req.headers['Accept'] = 'application/json';

    req.fields['businessName'] = businessName;
    req.fields['openingHours'] = openingHours;
    if (businessDescription != null) {
      req.fields['businessDescription'] = businessDescription;
    }
    if (status != null) req.fields['status'] = status;

    if (!kIsWeb && logoPath != null) {
      req.files.add(await http.MultipartFile.fromPath(
        'logoImage',
        logoPath,
        filename: logoFileName ?? logoPath.split('/').last,
        contentType: MediaType('image', 'jpeg'),
      ));
    } else if (kIsWeb && logoBytes != null) {
      req.files.add(http.MultipartFile.fromBytes(
        'logoImage',
        logoBytes,
        filename: logoFileName ?? 'logo.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 201 || res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body is Map && body['data'] != null ? body['data'] : body;
      return ServiceProvider.fromJson(data);
    }

    debugPrint('create failed: ${res.statusCode} ${res.body}');
    throw ApiException(
      message: 'create service provider failed',
      statusCode: res.statusCode,
    );
  }

  static Future<ServiceProvider> update(
    int id, {
    String? businessName,
    String? businessDescription,
    String? status,
    String? openingHours,
    String? logoPath,
    Uint8List? logoBytes,
    String? logoFileName,
  }) async {
    final t = await _getToken();
    final uri = await _u('/serviceprovider/$id');

    final req = http.MultipartRequest('PATCH', uri);
    if (t != null) req.headers['Authorization'] = 'Bearer $t';
    req.headers['Accept'] = 'application/json';

    if (businessName != null) req.fields['businessName'] = businessName;
    if (businessDescription != null) {
      req.fields['businessDescription'] = businessDescription;
    }
    if (status != null) req.fields['status'] = status;
    if (openingHours != null) req.fields['openingHours'] = openingHours;

    if (!kIsWeb && logoPath != null) {
      req.files.add(await http.MultipartFile.fromPath(
        'logoImage',
        logoPath,
        filename: logoFileName ?? logoPath.split('/').last,
        contentType: MediaType('image', 'jpeg'),
      ));
    } else if (kIsWeb && logoBytes != null) {
      req.files.add(http.MultipartFile.fromBytes(
        'logoImage',
        logoBytes,
        filename: logoFileName ?? 'logo.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = body is Map && body['data'] != null ? body['data'] : body;
      return ServiceProvider.fromJson(data);
    }

    debugPrint('update failed: ${res.statusCode} ${res.body}');
    throw ApiException(
      message: 'update service provider failed',
      statusCode: res.statusCode,
    );
  }

  static Future<void> deleteById(int id) async {
    final t = await _getToken();
    final uri = await _u('/serviceprovider/$id');

    final res = await http.delete(
      uri,
      headers: {
        if (t != null) 'Authorization': 'Bearer $t',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode != 200) {
      debugPrint('delete failed: ${res.statusCode} ${res.body}');
      throw ApiException(
        message: 'delete service provider failed',
        statusCode: res.statusCode,
      );
    }
  }
}

/// New instance-style wrapper used by pages (e.g. MarketplaceCrudPage)
class ServiceproviderService {
  const ServiceproviderService();

  /// Get *my* service provider (shop) – returns null if not found.
  Future<ServiceProvider?> fetchMine() {
    return ServiceProviderServicess.fetchMine();
  }

  /// Get shop data as Map for easy access in marketplace pages
  /// This is used by MarketplaceCrudPage to get merchant info
  Future<Map<String, dynamic>?> fetchMyShopAsMap() async {
    final shop = await fetchMine();
    if (shop == null) return null;

    // Convert ServiceProvider to a Map with all required fields
    return _convertServiceProviderToMap(shop);
  }

  Future<ServiceProvider?> fetchByNumber(String spNumber) {
    return ServiceProviderServicess.fetchByNumber(spNumber);
  }

  Future<ServiceProvider> create({
    required String businessName,
    String? businessDescription,
    String? status,
    required String openingHours,
    String? logoPath, // mobile/desktop
    Uint8List? logoBytes, // web
    String? logoFileName,
  }) {
    return ServiceProviderServicess.create(
      businessName: businessName,
      businessDescription: businessDescription,
      status: status,
      openingHours: openingHours,
      logoPath: logoPath,
      logoBytes: logoBytes,
      logoFileName: logoFileName,
    );
  }

  Future<ServiceProvider> update(
    int id, {
    String? businessName,
    String? businessDescription,
    String? status,
    String? openingHours,
    String? logoPath,
    Uint8List? logoBytes,
    String? logoFileName,
  }) {
    return ServiceProviderServicess.update(
      id,
      businessName: businessName,
      businessDescription: businessDescription,
      status: status,
      openingHours: openingHours,
      logoPath: logoPath,
      logoBytes: logoBytes,
      logoFileName: logoFileName,
    );
  }

  Future<void> deleteById(int id) {
    return ServiceProviderServicess.deleteById(id);
  }

  // ---------------------------------------------------------------------------
  // HELPER METHODS
  // ---------------------------------------------------------------------------

  /// Convert ServiceProvider object to Map
  Map<String, dynamic> _convertServiceProviderToMap(ServiceProvider shop) {
    return {
      'id': shop.id?.toString() ?? 'unknown',
      'businessName': shop.businessName ?? 'Unknown Business',
      'status': shop.status ?? 'active',
      'serviceType': 'marketplace', // Fixed for marketplace items
    };
  }

  /// Check if the current user has a valid shop for marketplace posting
  Future<bool> hasValidShop() async {
    try {
      final shop = await fetchMine();
      return shop != null && shop.id != null && shop.businessName != null;
    } catch (e) {
      debugPrint('Error checking shop: $e');
      return false;
    }
  }

  /// Get merchant info for wallet integration
  /// Returns: {id, businessName, serviceType: 'marketplace'}
  Future<Map<String, dynamic>?> getMerchantInfo() async {
    try {
      final shop = await fetchMine();
      if (shop == null) return null;

      return _convertServiceProviderToMap(shop);
    } catch (e) {
      debugPrint('Error getting merchant info: $e');
      return null;
    }
  }

  /// Validate merchant info for wallet payments
  bool validateMerchantInfo(Map<String, dynamic> merchantInfo) {
    return merchantInfo['id'] != null &&
        merchantInfo['id'].toString().isNotEmpty &&
        merchantInfo['id'] != 'unknown' &&
        merchantInfo['businessName'] != null &&
        merchantInfo['businessName'].toString().isNotEmpty &&
        merchantInfo['businessName'] != 'Unknown Merchant';
  }
}
