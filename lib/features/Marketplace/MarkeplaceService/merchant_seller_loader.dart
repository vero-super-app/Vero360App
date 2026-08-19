import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/serviceprovider_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/serviceprovider_model.dart';

/// Seller profile + reviews bundle (same data path as marketplace product details).
class MerchantSellerInfo {
  String? businessName;
  String? openingHours;
  String? status;
  String? description;
  String? logoUrl;
  String? serviceProviderId;
  double? rating;
  int reviewCount;
  int? backendMerchantId;
  String merchantRef;
  String? sellerUserId;
  List<MerchantReview> recentReviews;

  MerchantSellerInfo({
    this.businessName,
    this.openingHours,
    this.status,
    this.description,
    this.logoUrl,
    this.serviceProviderId,
    this.rating,
    this.reviewCount = 0,
    this.backendMerchantId,
    this.merchantRef = '',
    this.sellerUserId,
    this.recentReviews = const [],
  });

  String get displayName {
    final name = (businessName ?? '').trim();
    return name.isNotEmpty ? name : 'Merchant';
  }
}

class MerchantSellerLoader {
  MerchantSellerLoader._();

  static const String _kHoursPrefsPrefix = 'merchant_opening_hours_v1_';
  static const String _kDaysPrefsPrefix = 'merchant_opening_days_v1_';
  static const String _kNamePrefsPrefix = 'merchant_business_name_v1_';

  /// Instant OPEN/CLOSED: merchantId → openingHours (e.g. `08:00–17:00`).
  static final Map<String, String> _openingHoursByMerchantId = {};
  /// merchantId → weekday ints (1=Mon … 7=Sun). Empty/missing = every day.
  static final Map<String, List<int>> _openingDaysByMerchantId = {};
  static final Map<String, String> _businessNameByMerchantId = {};

  static void clearSessionCaches() {
    _openingHoursByMerchantId.clear();
    _openingDaysByMerchantId.clear();
    _businessNameByMerchantId.clear();
  }

  static String? peekOpeningHours(String? merchantId) {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return null;
    final h = _openingHoursByMerchantId[id];
    return (h == null || h.isEmpty) ? null : h;
  }

  static List<int>? peekOpeningDays(String? merchantId) {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return null;
    return _openingDaysByMerchantId[id];
  }

  static void cacheOpeningHours(String? merchantId, String? hours) {
    final id = (merchantId ?? '').trim();
    final h = (hours ?? '').trim();
    if (id.isEmpty || h.isEmpty) return;
    _openingHoursByMerchantId[id] = h;
    // Disk cache so next cold open is instant.
    SharedPreferences.getInstance().then((p) {
      p.setString('$_kHoursPrefsPrefix$id', h);
    }).catchError((_) {});
  }

  static void cacheOpeningDays(String? merchantId, List<int>? days) {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty || days == null) return;
    final cleaned = days.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    if (cleaned.isEmpty) return;
    _openingDaysByMerchantId[id] = cleaned;
    SharedPreferences.getInstance().then((p) {
      p.setString('$_kDaysPrefsPrefix$id', cleaned.join(','));
    }).catchError((_) {});
  }

  static String? peekBusinessName(String? merchantId) {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return null;
    final n = _businessNameByMerchantId[id];
    return (n == null || n.trim().isEmpty) ? null : n.trim();
  }

  static void cacheBusinessName(String? merchantId, String? name) {
    final id = (merchantId ?? '').trim();
    final n = (name ?? '').trim();
    if (id.isEmpty || n.isEmpty || _isWeakSellerName(n)) return;
    _businessNameByMerchantId[id] = n;
    SharedPreferences.getInstance().then((p) {
      p.setString('$_kNamePrefsPrefix$id', n);
    }).catchError((_) {});
  }

  static Future<String?> peekBusinessNamePersisted(String? merchantId) async {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return null;
    final mem = peekBusinessName(id);
    if (mem != null) return mem;
    try {
      final p = await SharedPreferences.getInstance();
      final n = (p.getString('$_kNamePrefsPrefix$id') ?? '').trim();
      if (n.isEmpty || _isWeakSellerName(n)) return null;
      _businessNameByMerchantId[id] = n;
      return n;
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>?> peekOpeningDaysPersisted(String? merchantId) async {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return null;
    final mem = peekOpeningDays(id);
    if (mem != null && mem.isNotEmpty) return mem;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = (p.getString('$_kDaysPrefsPrefix$id') ?? '').trim();
      if (raw.isEmpty) return null;
      final days = <int>[];
      for (final part in raw.split(',')) {
        final n = int.tryParse(part.trim());
        if (n != null && n >= 1 && n <= 7) days.add(n);
      }
      if (days.isEmpty) return null;
      days.sort();
      _openingDaysByMerchantId[id] = days;
      return days;
    } catch (_) {
      return null;
    }
  }

  /// Fresh hours + days from Firestore (cache-first, then server).
  /// Use on product details so OPEN/CLOSED updates immediately after merchant saves.
  static Future<({String? hours, List<int> days})> prefetchShopSchedule(
    String? merchantId, {
    List<String?> extraIds = const [],
  }) async {
    final candidates = <String>{
      if ((merchantId ?? '').trim().isNotEmpty) merchantId!.trim(),
      for (final e in extraIds)
        if ((e ?? '').trim().isNotEmpty) e!.trim(),
    };

    String? hours;
    List<int> days = const [];

    for (final id in candidates) {
      hours ??= peekOpeningHours(id);
      days = peekOpeningDays(id) ?? days;
    }

    for (final id in candidates) {
      hours ??= await peekOpeningHoursPersisted(id);
      if (days.isEmpty) {
        days = await peekOpeningDaysPersisted(id) ?? days;
      }
    }

    for (final id in candidates) {
      if (!_looksLikeFirebaseUid(id)) continue;
      final h = await _fetchOpeningHoursDoc(id, preferServer: true);
      if (h != null && h.isNotEmpty) hours = h;
      final d = peekOpeningDays(id);
      if (d != null && d.isNotEmpty) days = d;
      if (hours != null && hours.isNotEmpty) break;
    }

    return (hours: hours, days: days);
  }

  static Future<String?> peekOpeningHoursPersisted(String? merchantId) async {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return null;
    final mem = peekOpeningHours(id);
    if (mem != null) return mem;
    try {
      final p = await SharedPreferences.getInstance();
      final h = (p.getString('$_kHoursPrefsPrefix$id') ?? '').trim();
      if (h.isEmpty) return null;
      _openingHoursByMerchantId[id] = h;
      return h;
    } catch (_) {
      return null;
    }
  }

  /// Cache-first Firestore read for shop hours only (fast status chip).
  /// Tries [merchantId] and any extra candidate ids (sellerUserId, etc.).
  static Future<String?> prefetchOpeningHours(
    String? merchantId, {
    List<String?> extraIds = const [],
  }) async {
    final candidates = <String>{
      if ((merchantId ?? '').trim().isNotEmpty) merchantId!.trim(),
      for (final e in extraIds)
        if ((e ?? '').trim().isNotEmpty) e!.trim(),
    };

    for (final id in candidates) {
      final mem = peekOpeningHours(id);
      if (mem != null) return mem;
    }

    for (final id in candidates) {
      final disk = await peekOpeningHoursPersisted(id);
      if (disk != null) return disk;
    }

    for (final id in candidates) {
      if (!_looksLikeFirebaseUid(id)) continue;
      final h = await _fetchOpeningHoursDoc(id);
      if (h != null) return h;
    }
    return null;
  }

  static Future<String?> _fetchOpeningHoursDoc(
    String id, {
    bool preferServer = false,
  }) async {
    Future<String?> fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) async {
      if (!doc.exists) return null;
      final data = doc.data();
      final h = _trimmed(data?['openingHours']);
      if (h != null) {
        cacheOpeningHours(id, h);
      }
      final daysRaw = data?['openingDays'];
      if (daysRaw is List) {
        final days = <int>[];
        for (final e in daysRaw) {
          final n = e is int ? e : int.tryParse('$e');
          if (n != null && n >= 1 && n <= 7) days.add(n);
        }
        if (days.isNotEmpty) cacheOpeningDays(id, days);
      }
      return h;
    }

    if (!preferServer) {
      try {
        final cacheDoc = await FirebaseFirestore.instance
            .collection('marketplace_merchants')
            .doc(id)
            .get(const GetOptions(source: Source.cache));
        final fromCache = await fromDoc(cacheDoc);
        if (fromCache != null) return fromCache;
      } catch (_) {}
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(id)
          .get(const GetOptions(source: Source.serverAndCache));
      return await fromDoc(doc);
    } catch (_) {
      return peekOpeningHours(id);
    }
  }

  static bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  static int? _parsePositiveInt(dynamic raw) {
    if (raw == null) return null;
    final n = raw is int ? raw : int.tryParse(raw.toString().trim());
    if (n != null && n > 0) return n;
    return null;
  }

  static String? _trimmed(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static bool _isWeakSellerName(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return true;
    final n = v.toLowerCase();
    if (v.contains('@')) return true;
    if (n == 'merchant' ||
        n == 'user' ||
        n == 'unknown' ||
        n == 'unknown merchant' ||
        n == 'contact' ||
        n == 'seller') {
      return true;
    }
    return false;
  }

  static String? _shopNameFromMap(Map<dynamic, dynamic> data) {
    for (final key in [
      'businessName',
      'shopName',
      'storeName',
      'companyName',
    ]) {
      final v = _trimmed(data[key]);
      if (v != null && !_isWeakSellerName(v)) return v;
    }
    final merchantName = _trimmed(data['merchantName']);
    if (merchantName == null || _isWeakSellerName(merchantName)) return null;
    final personal = _trimmed(
      data['fullName'] ?? data['displayName'] ?? data['name'],
    );
    if (personal != null &&
        merchantName.toLowerCase() == personal.toLowerCase()) {
      return null;
    }
    return merchantName;
  }

  static void _setShopName(
    MerchantSellerInfo info,
    String? name, {
    bool strong = false,
  }) {
    final v = _trimmed(name);
    if (v == null || _isWeakSellerName(v)) return;
    if (strong || _isWeakSellerName(info.businessName)) {
      info.businessName = v;
    }
    cacheBusinessName(info.merchantRef, info.businessName);
    cacheBusinessName(info.sellerUserId, info.businessName);
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> _docCacheFirst(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        unawaited(ref.get(const GetOptions(source: Source.serverAndCache)));
        return cached;
      }
    } catch (_) {}
    return ref.get(const GetOptions(source: Source.serverAndCache));
  }

  /// Promo API returns numeric `merchantId`; Firestore shops use Firebase UID doc ids.
  static Future<({String firebaseUid, Map<String, dynamic> item})?>
      lookupViaMarketplaceItems(int backendId) async {
    if (backendId <= 0) return null;

    const fields = ['sellerUserId', 'merchantBackendId', 'ownerId', 'userId'];
    for (final field in fields) {
      for (final value in [backendId, backendId.toString()]) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('marketplace_items')
              .where(field, isEqualTo: value)
              .limit(1)
              .get();
          if (snap.docs.isEmpty) continue;
          final data = snap.docs.first.data();
          final mid = _trimmed(data['merchantId']);
          if (mid != null && _looksLikeFirebaseUid(mid)) {
            return (firebaseUid: mid, item: data);
          }
        } catch (e) {
          debugPrint('[MerchantSellerLoader] items bridge ($field): $e');
        }
      }
    }
    return null;
  }

  /// Finds `marketplace_merchants` doc from numeric backend user / merchant id.
  static Future<({String docId, Map<String, dynamic> data})?>
      lookupMerchantDocByBackendId(int backendId) async {
    if (backendId <= 0) return null;

    const fields = [
      'backendUserId',
      'userId',
      'merchantUserId',
      'merchantId',
      'ownerId',
      'sellerUserId',
    ];

    for (final field in fields) {
      for (final value in [backendId, backendId.toString()]) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('marketplace_merchants')
              .where(field, isEqualTo: value)
              .limit(1)
              .get();
          if (snap.docs.isEmpty) continue;
          final doc = snap.docs.first;
          return (docId: doc.id, data: doc.data());
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> fetchBackendUserProfile(int userId) async {
    if (userId <= 0) return null;
    try {
      final token = await AuthHandler.getTokenForApi();
      if (token == null || token.isEmpty) return null;

      await ApiConfig.readBase();
      final res = await http
          .get(
            ApiConfig.endpoint('/users/$userId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['data'] is Map) {
        return Map<String, dynamic>.from(map['data'] as Map);
      }
      return map;
    } catch (e) {
      debugPrint('[MerchantSellerLoader] user profile: $e');
      return null;
    }
  }

  static void _applyMarketplaceItemData(
    MerchantSellerInfo info,
    Map<String, dynamic> item,
  ) {
    info.businessName ??= _shopNameFromMap(item);
    _setShopName(
      info,
      item['sellerBusinessName'] ?? item['businessName'],
      strong: true,
    );
    info.description ??= _trimmed(item['sellerBusinessDescription']);
    info.status ??= _trimmed(item['sellerStatus']);
    info.openingHours ??= _trimmed(item['sellerOpeningHours']);
    info.logoUrl ??= _trimmed(item['sellerLogoUrl'] ?? item['merchantLogoUrl']);
    info.serviceProviderId ??= _trimmed(item['serviceProviderId']);

    final mid = _trimmed(item['merchantId']);
    if (mid != null && _looksLikeFirebaseUid(mid)) {
      info.merchantRef = mid;
      info.sellerUserId ??= _trimmed(item['sellerUserId']) ?? mid;
    }

    final rating = item['sellerRating'];
    if (info.rating == null && rating is num) {
      info.rating = rating.toDouble();
    }
  }

  static void _applyBackendUserProfile(
    MerchantSellerInfo info,
    Map<String, dynamic> user,
  ) {
    _setShopName(
      info,
      user['businessName'] ??
          user['shopName'] ??
          user['companyName'] ??
          user['storeName'],
      strong: true,
    );
    info.description ??= _trimmed(
      user['businessDescription'] ?? user['description'] ?? user['bio'],
    );
    info.status ??= _trimmed(user['status'] ?? user['verificationStatus']);
    info.logoUrl ??= _trimmed(
      user['profilepicture'] ??
          user['profilePicture'] ??
          user['photoUrl'] ??
          user['photoURL'],
    );

    final phone = _trimmed(user['phone'] ?? user['phoneNumber']);
    if (phone != null) info.serviceProviderId ??= phone;

    for (final key in ['firebaseUid', 'firebase_uid', 'uid']) {
      final uid = _trimmed(user[key]);
      if (uid != null && _looksLikeFirebaseUid(uid)) {
        info.merchantRef = uid;
        info.sellerUserId ??= uid;
        break;
      }
    }

    final userId = _parsePositiveInt(user['id'] ?? user['userId']);
    if (userId != null) {
      info.sellerUserId ??= userId.toString();
    }
  }

  static void _applyFirestoreMerchantData(
    MerchantSellerInfo info,
    String docId,
    Map<String, dynamic> m,
  ) {
    info.merchantRef = docId;
    info.sellerUserId ??= docId;

    _setShopName(
      info,
      m['businessName'] ?? m['shopName'] ?? m['storeName'] ?? m['companyName'],
      strong: true,
    );
    if (_isWeakSellerName(info.businessName)) {
      _setShopName(info, m['merchantName']);
    }
    info.description ??= _trimmed(
      m['businessDescription'] ?? m['description'] ?? m['about'],
    );
    info.status ??= _trimmed(m['status'] ?? m['verificationStatus']);
    info.openingHours ??= _trimmed(m['openingHours']);
    if (info.openingHours != null) {
      cacheOpeningHours(docId, info.openingHours);
    }

    info.serviceProviderId ??= _trimmed(
      m['serviceProviderId'] ??
          m['serviceProviderNumber'] ??
          m['phone'] ??
          m['phoneNumber'],
    );

    info.logoUrl ??= _trimmed(
      m['profilePicture'] ?? m['profilepicture'] ?? m['logoUrl'] ?? m['logourl'],
    );

    final rating = m['rating'];
    if (info.rating == null && rating is num) {
      info.rating = rating.toDouble();
    }

    final spRecordId =
        _parsePositiveInt(m['serviceProviderRecordId'] ?? m['shopId']);
    for (final key in [
      'backendUserId',
      'userId',
      'merchantUserId',
      'ownerId',
    ]) {
      final backendId = _parsePositiveInt(m[key]);
      if (backendId != null) {
        info.backendMerchantId ??= backendId;
        break;
      }
    }
    if (spRecordId != null) info.backendMerchantId ??= spRecordId;
  }

  static Future<void> _applyFirestoreUserData(
    MerchantSellerInfo info,
    String uid,
  ) async {
    try {
      final uDoc = await _docCacheFirst(
        FirebaseFirestore.instance.collection('users').doc(uid),
      );
      if (!uDoc.exists) return;
      _applyBackendUserProfile(info, uDoc.data() ?? <String, dynamic>{});
    } catch (_) {}
  }

  static void _applyServiceProvider(MerchantSellerInfo info, ServiceProvider sp) {
    final name = sp.businessName.trim();
    if (name.isNotEmpty) _setShopName(info, name, strong: true);

    final desc = (sp.businessDescription ?? '').trim();
    if (desc.isNotEmpty) info.description ??= desc;

    final st = (sp.status ?? '').trim();
    if (st.isNotEmpty) info.status ??= st;

    final hours = (sp.openingHours ?? '').trim();
    if (hours.isNotEmpty) info.openingHours ??= hours;

    final logo = (sp.logoUrl ?? '').trim();
    if (logo.isNotEmpty) info.logoUrl ??= logo;

    if (sp.serviceProviderId.trim().isNotEmpty) {
      info.serviceProviderId = sp.serviceProviderId;
    }
    if (sp.id != null && sp.id! > 0) {
      info.backendMerchantId = sp.id;
    }
    if (info.rating == null && sp.rating != null) {
      info.rating = sp.rating;
    }
  }

  static Future<void> _enrichFromServiceProvider(
    MerchantSellerInfo info,
    List<String> searchKeys,
  ) async {
    final seen = <String>{};
    for (final raw in searchKeys) {
      final key = raw.trim();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      if (_looksLikeFirebaseUid(key)) continue;

      try {
        if (RegExp(r'^\d+$').hasMatch(key)) {
          final byId = await ServiceProviderServicess.fetchById(int.parse(key));
          if (byId != null) {
            _applyServiceProvider(info, byId);
            return;
          }
        }
      } catch (_) {}

      try {
        final sp = await ServiceProviderServicess.fetchByNumber(key);
        if (sp != null) {
          _applyServiceProvider(info, sp);
          return;
        }
      } catch (_) {}
    }
  }

  static Future<void> _loadReviews(
    MerchantSellerInfo info, {
    required int reviewsMerchantId,
    String? merchantRef,
    String? serviceProviderId,
    String? sellerUserId,
  }) async {
    try {
      int backendId = reviewsMerchantId;

      if (reviewsMerchantId <= 0) {
        final ref = (merchantRef ?? '').trim();
        if (ref.isEmpty) return;
        backendId = await MerchantReviewIdResolver.resolveMerchantId(
          merchantRef: ref,
          serviceProviderId: serviceProviderId,
          sellerUserId: sellerUserId,
          preResolvedBackendId: info.backendMerchantId,
        );
      }

      info.backendMerchantId = backendId;

      const reviewService = MerchantReviewService();
      final cached = MerchantReviewService.peekCache(backendId);
      if (cached != null) {
        if (cached.summary.count > 0 || cached.summary.average > 0) {
          info.rating = cached.summary.average;
        }
        info.reviewCount = cached.summary.count;
        info.recentReviews = cached.reviews.take(3).toList();
      }

      final bundle = await reviewService.loadMerchantReviewsBundle(backendId);
      if (bundle.summary.count > 0 || bundle.summary.average > 0) {
        info.rating = bundle.summary.average;
      }
      info.reviewCount = bundle.summary.count;
      info.recentReviews = bundle.reviews.take(3).toList();
    } catch (e) {
      debugPrint('[MerchantSellerLoader] reviews: $e');
    }
  }

  static Future<MerchantSellerInfo> load({
    String? merchantId,
    String? sellerUserId,
    String? serviceProviderId,
    String? sellerBusinessName,
    String? sellerOpeningHours,
    String? sellerStatus,
    String? sellerBusinessDescription,
    double? sellerRating,
    String? sellerLogoUrl,
    int? backendUserIdHint,
    int? backendMerchantIdForReviews,
    void Function(MerchantSellerInfo snapshot)? onUpdate,
  }) async {
    var merchantRef = (merchantId ?? '').trim();
    var sellerUid = sellerUserId?.trim();

    final seededName = !_isWeakSellerName(sellerBusinessName)
        ? sellerBusinessName!.trim()
        : (peekBusinessName(merchantRef) ?? peekBusinessName(sellerUid));

    final info = MerchantSellerInfo(
      businessName: seededName,
      openingHours: sellerOpeningHours,
      status: sellerStatus,
      description: sellerBusinessDescription,
      rating: sellerRating,
      logoUrl: sellerLogoUrl,
      serviceProviderId: serviceProviderId?.trim(),
      merchantRef: merchantRef,
      sellerUserId: sellerUid,
      backendMerchantId: backendUserIdHint,
    );

    void ping() {
      final cb = onUpdate;
      if (cb == null) return;
      scheduleMicrotask(() => cb(info));
    }

    info.openingHours ??=
        peekOpeningHours(merchantRef) ?? peekOpeningHours(sellerUid);
    if ((sellerOpeningHours ?? '').trim().isNotEmpty) {
      cacheOpeningHours(merchantRef, sellerOpeningHours);
      cacheOpeningHours(sellerUid, sellerOpeningHours);
    }
    if (!_isWeakSellerName(info.businessName)) {
      cacheBusinessName(merchantRef, info.businessName);
      cacheBusinessName(sellerUid, info.businessName);
    }

    final reviewsId = backendMerchantIdForReviews ??
        backendUserIdHint ??
        info.backendMerchantId ??
        0;
    if (reviewsId > 0) {
      final cachedReviews = MerchantReviewService.peekCache(reviewsId);
      if (cachedReviews != null) {
        info.backendMerchantId = reviewsId;
        if (cachedReviews.summary.count > 0 ||
            cachedReviews.summary.average > 0) {
          info.rating = cachedReviews.summary.average;
        }
        info.reviewCount = cachedReviews.summary.count;
        info.recentReviews = cachedReviews.reviews.take(3).toList();
      }
    }
    ping();

    bool isUid(String? value) {
      final v = (value ?? '').trim();
      return v.isNotEmpty && _looksLikeFirebaseUid(v);
    }

    Future<void> loadFirestoreShop(String uid) async {
      if (uid.isEmpty || !_looksLikeFirebaseUid(uid)) return;
      try {
        final mDoc = await _docCacheFirst(
          FirebaseFirestore.instance
              .collection('marketplace_merchants')
              .doc(uid),
        );
        if (mDoc.exists) {
          _applyFirestoreMerchantData(
            info,
            mDoc.id,
            mDoc.data() ?? <String, dynamic>{},
          );
          merchantRef = mDoc.id;
          sellerUid ??= mDoc.id;
          ping();
        }
      } catch (_) {}
      await _applyFirestoreUserData(info, uid);
      ping();
    }

    // Fast path: Firebase UID shops — don't wait on numeric API bridges.
    final shopUid = isUid(merchantRef)
        ? merchantRef
        : (isUid(sellerUid) ? sellerUid!.trim() : '');
    if (shopUid.isNotEmpty) {
      await loadFirestoreShop(shopUid);
    }

    final reviewsF = _loadReviews(
      info,
      reviewsMerchantId: reviewsId,
      merchantRef: isUid(info.merchantRef) ? info.merchantRef : merchantRef,
      serviceProviderId: info.serviceProviderId ?? serviceProviderId,
      sellerUserId: info.sellerUserId ?? sellerUid,
    );

    final extraF = () async {
      final needsUid = !isUid(info.merchantRef) && !isUid(sellerUid);
      if (needsUid && backendUserIdHint != null && backendUserIdHint > 0) {
        try {
          final merchantDoc =
              await lookupMerchantDocByBackendId(backendUserIdHint);
          if (merchantDoc != null) {
            merchantRef = merchantDoc.docId;
            sellerUid ??= merchantDoc.docId;
            _applyFirestoreMerchantData(
              info,
              merchantDoc.docId,
              merchantDoc.data,
            );
            ping();
            if (_looksLikeFirebaseUid(merchantDoc.docId)) {
              await loadFirestoreShop(merchantDoc.docId);
            }
          }
        } catch (_) {}
        try {
          final userProfile = await fetchBackendUserProfile(backendUserIdHint);
          if (userProfile != null) {
            _applyBackendUserProfile(info, userProfile);
            ping();
            final uid = info.merchantRef.trim();
            if (_looksLikeFirebaseUid(uid)) {
              merchantRef = uid;
              sellerUid ??= uid;
              await loadFirestoreShop(uid);
            }
          }
        } catch (_) {}
      }

      await _enrichFromServiceProvider(info, [
        info.serviceProviderId ?? '',
        serviceProviderId ?? '',
        if (backendUserIdHint != null && backendUserIdHint > 0)
          backendUserIdHint.toString(),
      ]);
      ping();
    }();

    await Future.wait([reviewsF, extraF]);
    ping();

    if ((info.openingHours ?? '').trim().isNotEmpty) {
      cacheOpeningHours(info.merchantRef, info.openingHours);
      cacheOpeningHours(info.sellerUserId, info.openingHours);
      cacheOpeningHours(merchantId, info.openingHours);
    }
    if (!_isWeakSellerName(info.businessName)) {
      cacheBusinessName(info.merchantRef, info.businessName);
      cacheBusinessName(info.sellerUserId, info.businessName);
      cacheBusinessName(merchantId, info.businessName);
    }

    return info;
  }
}
