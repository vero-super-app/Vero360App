// lib/services/promo_service.dart  (your file name may differ)
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

class PromoModel {
  final int id;
  final int merchantId;
  final int? serviceProviderId;
  final String title;
  final String? description;
  final double? price;
  final String? image;
  final bool isActive;
  final DateTime? freeTrialEndsAt;
  final DateTime? subscribedAt;
  final DateTime createdAt;

  PromoModel({
    required this.id,
    required this.merchantId,
    required this.title,
    required this.isActive,
    required this.createdAt,
    this.serviceProviderId,
    this.description,
    this.price,
    this.image,
    this.freeTrialEndsAt,
    this.subscribedAt,
  });

  double get displayPrice => price ?? 0;

  bool get isFree => displayPrice <= 0;

  String get formattedPrice =>
      isFree ? 'Free' : 'MWK ${displayPrice.toStringAsFixed(0)}';

  bool get hasFreeTrial =>
      freeTrialEndsAt != null && freeTrialEndsAt!.isAfter(DateTime.now());

  String? get resolvedImageUrl {
    final raw = image?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final root = ApiConfig.prod.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$root$raw';
    return '$root/$raw';
  }

  factory PromoModel.fromJson(Map<String, dynamic> j) => PromoModel(
        id: (j['id'] as num?)?.toInt() ?? 0,
        merchantId: (j['merchantId'] as num?)?.toInt() ?? 0,
        serviceProviderId: (j['serviceProviderId'] as num?)?.toInt(),
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString(),
        price: j['price'] == null ? null : (j['price'] as num).toDouble(),
        image: j['image']?.toString(),
        isActive: j['isActive'] != false,
        freeTrialEndsAt: j['freeTrialEndsAt'] == null
            ? null
            : DateTime.tryParse(j['freeTrialEndsAt'].toString()),
        subscribedAt: j['subscribedAt'] == null
            ? null
            : DateTime.tryParse(j['subscribedAt'].toString()),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toCreateJson() => {
        'title': title,
        'description': description,
        'price': price,
        'image': image,
      };
}

class PromoService {
  Future<String> _token() async {
    final firebase = await AuthHandler.getTokenForApi();
    if (firebase != null && firebase.isNotEmpty) return firebase;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token') ?? '';
  }

  List<PromoModel> _parsePromoList(dynamic body, {bool publicActiveList = false}) {
    final raw = body is List
        ? body
        : (body is Map && body['data'] is List)
            ? body['data'] as List
            : const [];
    return raw
        .whereType<Map>()
        .map((e) => PromoModel.fromJson(Map<String, dynamic>.from(e)))
        .where((p) {
          if (p.id <= 0 || p.title.trim().isEmpty) return false;
          if (publicActiveList) return true;
          return p.isActive;
        })
        .toList();
  }

  /// Public: active promotions (no auth). GET /vero/promos
  Future<List<PromoModel>> fetchActivePromos() async {
    await ApiConfig.readBase();
    final url = ApiConfig.endpoint('promos');
    final r = await http.get(
      url,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    final body = _decode(r, where: 'GET /promos');
    return _parsePromoList(body, publicActiveList: true);
  }

  Map<String, String> _auth(String t, {Map<String, String>? extra}) => {
        'Authorization': 'Bearer $t',
        'Accept': 'application/json',
        if (extra != null) ...extra,
      };

  String _friendlyError(String body) {
    try {
      final parsed = json.decode(body);
      if (parsed is Map) {
        final m = parsed['message'] ?? parsed['error'];
        if (m is List && m.isNotEmpty) return m.first.toString();
        if (m is String) return m;
      }
      if (parsed is List && parsed.isNotEmpty) {
        return parsed.first.toString();
      }
    } catch (_) {}
    return 'Request failed. Please try again.';
  }

  dynamic _decode(http.Response r, {required String where}) {
    // `where` is for debugging only, not exposed to user
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(_friendlyError(r.body));
    }
    return r.body.isEmpty ? {} : json.decode(r.body);
  }

  // === uploads (auth) ===
  Future<String> uploadImageBytes(
    Uint8List bytes, {
    String filename = 'promo.jpg',
    String mime = 'image/jpeg',
  }) async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('uploads');

    final parts = mime.split('/');
    final contentType = parts.length == 2
        ? MediaType(parts[0], parts[1])
        : MediaType('image', 'jpeg');

    final req = http.MultipartRequest('POST', url)
      ..headers.addAll(_auth(t))
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    final body = _decode(resp, where: 'POST /uploads');
    final imageUrl = (body is Map ? body['url']?.toString() : null);
    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Upload succeeded but no image URL was returned.');
    }
    return imageUrl;
  }

  Future<String> uploadImageFile(
    File f, {
    String filename = 'promo.jpg',
  }) async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('uploads');

    final req = http.MultipartRequest('POST', url)
      ..headers.addAll(_auth(t))
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        f.path,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    final body = _decode(resp, where: 'POST /uploads');
    final imageUrl = (body is Map ? body['url']?.toString() : null);
    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Upload succeeded but no image URL was returned.');
    }
    return imageUrl;
  }

  // === secured promo endpoints ===
  Future<List<PromoModel>> fetchMyPromos() async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('promos/me');
    final r = await http.get(url, headers: _auth(t));
    final body = _decode(r, where: 'GET /promos/me');
    return _parsePromoList(body);
  }

  Future<PromoModel> createPromo(PromoModel p) async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('promos');
    final r = await http.post(
      url,
      headers: _auth(t, extra: {'Content-Type': 'application/json'}),
      body: jsonEncode(p.toCreateJson()),
    );
    final body = _decode(r, where: 'POST /promos');
    return PromoModel.fromJson(Map<String, dynamic>.from(body));
  }

  Future<void> subscribe(int promoId, double amountPaid) async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('promos/$promoId/subscribe');
    final r = await http.patch(
      url,
      headers: _auth(t, extra: {'Content-Type': 'application/json'}),
      body: jsonEncode({'amountPaid': amountPaid}),
    );
    _decode(r, where: 'PATCH /promos/$promoId/subscribe');
  }

  Future<void> deactivate(int promoId) async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('promos/$promoId/deactivate');
    final r = await http.patch(url, headers: _auth(t));
    _decode(r, where: 'PATCH /promos/$promoId/deactivate');
  }

  Future<void> deletePromo(int promoId) async {
    await ApiConfig.readBase();
    final t = await _token();
    final url = ApiConfig.endpoint('promos/$promoId');
    final r = await http.delete(url, headers: _auth(t));
    _decode(r, where: 'DELETE /promos/$promoId');
  }
}
