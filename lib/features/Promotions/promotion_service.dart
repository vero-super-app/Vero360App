// lib/services/promo_service.dart  (your file name may differ)
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_seller_loader.dart';

/// Promo date labels without `initializeDateFormatting` (avoids LocaleDataException).
class PromoDateFormat {
  PromoDateFormat._();

  static const _months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String dayMonth(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day} ${_months[local.month - 1]}';
  }

  static String dayMonthYearTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '${local.day} ${_months[local.month - 1]} ${local.year}, $h12:$minute $ampm';
  }

  static String periodRange(DateTime start, DateTime? end) {
    final startLabel = dayMonth(start);
    if (end == null) return startLabel;
    final endLabel = dayMonth(end);
    if (startLabel == endLabel) return startLabel;
    return '$startLabel – $endLabel';
  }
}

class PromoModel {
  final int id;
  final int merchantId;
  final int? serviceProviderId;
  final String? merchantFirebaseUid;
  final String? merchantBusinessName;
  final String title;
  final String? description;
  final double? price;
  final String? image;
  final bool isActive;
  final DateTime? freeTrialEndsAt;
  final DateTime? subscribedAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;

  PromoModel({
    required this.id,
    required this.merchantId,
    required this.title,
    required this.isActive,
    required this.createdAt,
    this.serviceProviderId,
    this.merchantFirebaseUid,
    this.merchantBusinessName,
    this.description,
    this.price,
    this.image,
    this.freeTrialEndsAt,
    this.subscribedAt,
    this.startsAt,
    this.endsAt,
  });

  double get displayPrice => price ?? 0;

  bool get isFree => displayPrice <= 0;

  static final NumberFormat _mwkFmt = NumberFormat('#,##0', 'en');

  String get formattedPrice {
    final p = displayPrice;
    if (p <= 0) return 'MWK 0';
    if (p == p.roundToDouble()) {
      return 'MWK ${_mwkFmt.format(p.round())}';
    }
    return 'MWK ${p.toStringAsFixed(2)}';
  }

  MarketplaceDetailModel toCheckoutItem({PromoMerchantInfo? merchant}) {
    final m = merchant;
    return MarketplaceDetailModel(
      id: id,
      name: title,
      image: resolvedImageUrl ?? '',
      price: displayPrice,
      description: (description ?? '').trim().isNotEmpty
          ? description!.trim()
          : 'Vero360 promotion',
      location: 'Promotion',
      serviceType: 'promotion',
      merchantId: m?.merchantRef ?? merchantId.toString(),
      merchantName: m?.displayName ?? 'Merchant',
      sellerBusinessName: m?.businessName,
      sellerStatus: m?.status,
      sellerBusinessDescription: m?.description,
      sellerRating: m?.rating,
      sellerLogoUrl: m?.logoUrl,
      serviceProviderId:
          m?.serviceProviderId ?? serviceProviderId?.toString(),
      sellerUserId: m?.sellerUserId ?? merchantId.toString(),
    );
  }

  bool get hasFreeTrial =>
      freeTrialEndsAt != null && freeTrialEndsAt!.isAfter(DateTime.now());

  DateTime get promoStart => startsAt ?? createdAt;

  DateTime? get promoEnd => endsAt ?? freeTrialEndsAt;

  String get formattedPromoStart =>
      PromoDateFormat.dayMonthYearTime(promoStart);

  String get formattedPromoEnd {
    final end = promoEnd;
    if (end == null) return '—';
    return PromoDateFormat.dayMonthYearTime(end);
  }

  /// e.g. "2 January – 10 January"
  String get formattedPromoPeriodRange =>
      PromoDateFormat.periodRange(promoStart, promoEnd);

  static String toApiIso(DateTime dt) => dt.toUtc().toIso8601String();

  String? get resolvedImageUrl {
    final raw = image?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final root = ApiConfig.prod.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$root$raw';
    return '$root/$raw';
  }

  factory PromoModel.fromJson(Map<String, dynamic> j) {
    final merchant = j['merchant'] is Map
        ? Map<String, dynamic>.from(j['merchant'] as Map)
        : null;

    var merchantId = 0;
    String? firebaseUid;
    final rawMerchantId = j['merchantId'];
    final merchantIdAsUid = _parseFirebaseUid(rawMerchantId);
    if (merchantIdAsUid != null) {
      firebaseUid = merchantIdAsUid;
    } else {
      merchantId = _parseMerchantId(rawMerchantId) ?? 0;
    }

    if (merchantId <= 0 && merchant != null) {
      merchantId = _parseMerchantId(
            merchant['id'] ?? merchant['userId'] ?? merchant['merchantId'],
          ) ??
          0;
    }

    firebaseUid ??= _parseFirebaseUid(
      j['merchantFirebaseUid'] ??
          j['merchantUid'] ??
          j['sellerUserId'] ??
          merchant?['firebaseUid'] ??
          merchant?['uid'] ??
          merchant?['merchantUid'] ??
          merchant?['sellerUserId'],
    );

    final merchantName = (j['merchantName'] ??
            j['merchantBusinessName'] ??
            merchant?['businessName'] ??
            merchant?['merchantName'] ??
            merchant?['name'])
        ?.toString()
        .trim();

    var serviceProviderId = _parseMerchantId(
      j['serviceProviderId'] ?? merchant?['serviceProviderId'],
    );

    return PromoModel(
        id: (j['id'] as num?)?.toInt() ?? 0,
        merchantId: merchantId,
        serviceProviderId: serviceProviderId,
        merchantFirebaseUid: firebaseUid,
        merchantBusinessName:
            (merchantName != null && merchantName.isNotEmpty) ? merchantName : null,
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString(),
        price: _parsePrice(j),
        image: j['image']?.toString(),
        isActive: j['isActive'] != false,
        freeTrialEndsAt: _parseDate(
          j['freeTrialEndsAt'] ?? j['freeTrialEndAt'],
        ),
        subscribedAt: _parseDate(j['subscribedAt']),
        startsAt: _parseDate(
          j['startsAt'] ??
              j['startDate'] ??
              j['startAt'] ??
              j['validFrom'] ??
              j['promoStart'],
        ),
        endsAt: _parseDate(
          j['endsAt'] ??
              j['endDate'] ??
              j['endAt'] ??
              j['validTo'] ??
              j['expiresAt'] ??
              j['promoEnd'],
        ),
        createdAt: _parseDate(j['createdAt']) ?? DateTime.now(),
      );
  }

  static int? _parseMerchantId(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  static String? _parseFirebaseUid(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(s)) return s;
    return null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static double? _parsePrice(Map<String, dynamic> j) {
    dynamic v = j['price'] ??
        j['amount'] ??
        j['promoPrice'] ??
        j['cost'] ??
        j['salePrice'];
    if (v == null && j['pricing'] is Map) {
      final pricing = Map<String, dynamic>.from(j['pricing'] as Map);
      v = pricing['price'] ?? pricing['amount'];
    }
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final cleaned = v.toString().replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Map<String, dynamic> toCreateJson() {
    final map = <String, dynamic>{
      'title': title.trim(),
      'price': price ?? 0,
    };
    final desc = description?.trim();
    if (desc != null && desc.isNotEmpty) map['description'] = desc;
    final img = image?.trim();
    if (img != null && img.isNotEmpty) map['image'] = img;
    if (startsAt != null) map['startDate'] = toApiIso(startsAt!);
    if (endsAt != null) map['endDate'] = toApiIso(endsAt!);
    return map;
  }
}

class PromoMerchantInfo {
  final String displayName;
  final String? businessName;
  final String? status;
  final String? description;
  final String? logoUrl;
  final double? rating;
  final int reviewCount;
  final String merchantRef;
  final int backendMerchantId;
  final String? serviceProviderId;
  final String? sellerUserId;
  final List<MerchantReview> recentReviews;

  const PromoMerchantInfo({
    required this.displayName,
    required this.merchantRef,
    required this.backendMerchantId,
    this.businessName,
    this.status,
    this.description,
    this.logoUrl,
    this.rating,
    this.reviewCount = 0,
    this.serviceProviderId,
    this.sellerUserId,
    this.recentReviews = const [],
  });
}

class PromoService {
  static Future<PromoMerchantInfo> resolvePromoMerchant(PromoModel promo) async {
    final seller = await MerchantSellerLoader.load(
      merchantId: promo.merchantFirebaseUid,
      serviceProviderId: promo.serviceProviderId?.toString(),
      sellerBusinessName: promo.merchantBusinessName,
      backendUserIdHint: promo.merchantId > 0 ? promo.merchantId : null,
      backendMerchantIdForReviews:
          promo.merchantId > 0 ? promo.merchantId : null,
    );

    final merchantRef = RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(seller.merchantRef.trim())
        ? seller.merchantRef.trim()
        : (promo.merchantFirebaseUid?.trim().isNotEmpty == true
            ? promo.merchantFirebaseUid!.trim()
            : (seller.serviceProviderId?.trim().isNotEmpty == true
                ? seller.serviceProviderId!.trim()
                : promo.merchantId.toString()));

    return PromoMerchantInfo(
      displayName: seller.displayName,
      businessName: seller.businessName,
      status: seller.status,
      description: seller.description,
      logoUrl: seller.logoUrl,
      rating: seller.rating,
      reviewCount: seller.reviewCount,
      merchantRef: merchantRef,
      backendMerchantId: seller.backendMerchantId ?? promo.merchantId,
      serviceProviderId: seller.serviceProviderId ?? promo.serviceProviderId?.toString(),
      sellerUserId: seller.sellerUserId ??
          (RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(merchantRef)
              ? merchantRef
              : promo.merchantId.toString()),
      recentReviews: seller.recentReviews,
    );
  }
  Future<String> _token() async {
    final firebase = await AuthHandler.getTokenForApi();
    if (firebase != null && firebase.isNotEmpty) return firebase;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token') ?? '';
  }

  Map<String, dynamic> _unwrapPromoMap(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map) return Map<String, dynamic>.from(body);
    return const {};
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
    return PromoModel.fromJson(_unwrapPromoMap(body));
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
