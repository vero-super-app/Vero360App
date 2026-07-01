import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
          .timeout(const Duration(seconds: 12));

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
    info.businessName ??= _trimmed(
      item['merchantName'] ?? item['sellerBusinessName'] ?? item['businessName'],
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
    info.businessName ??= _trimmed(
      user['businessName'] ?? user['fullName'] ?? user['name'] ?? user['displayName'],
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

    info.businessName ??= _trimmed(
      m['businessName'] ?? m['merchantName'] ?? m['name'],
    );
    info.description ??= _trimmed(
      m['businessDescription'] ?? m['description'] ?? m['about'],
    );
    info.status ??= _trimmed(m['status'] ?? m['verificationStatus']);
    info.openingHours ??= _trimmed(m['openingHours']);

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
      final uDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!uDoc.exists) return;
      _applyBackendUserProfile(info, uDoc.data() ?? <String, dynamic>{});
    } catch (_) {}
  }

  static void _applyServiceProvider(MerchantSellerInfo info, ServiceProvider sp) {
    final name = sp.businessName.trim();
    if (name.isNotEmpty) info.businessName ??= name;

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
  }) async {
    var merchantRef = (merchantId ?? '').trim();
    var sellerUid = sellerUserId?.trim();

    final info = MerchantSellerInfo(
      businessName: sellerBusinessName,
      openingHours: sellerOpeningHours,
      status: sellerStatus,
      description: sellerBusinessDescription,
      rating: sellerRating,
      logoUrl: sellerLogoUrl,
      serviceProviderId: serviceProviderId?.trim(),
      merchantRef: merchantRef,
      sellerUserId: sellerUid,
    );

    // Promo API: numeric merchantId → find Firebase UID via marketplace items.
    if (backendUserIdHint != null && backendUserIdHint > 0) {
      final bridge = await lookupViaMarketplaceItems(backendUserIdHint);
      if (bridge != null) {
        merchantRef = bridge.firebaseUid;
        sellerUid ??= bridge.firebaseUid;
        info.merchantRef = bridge.firebaseUid;
        info.sellerUserId ??= bridge.firebaseUid;
        _applyMarketplaceItemData(info, bridge.item);
      }

      final merchantDoc = await lookupMerchantDocByBackendId(backendUserIdHint);
      if (merchantDoc != null) {
        merchantRef = merchantDoc.docId;
        sellerUid ??= merchantDoc.docId;
        _applyFirestoreMerchantData(info, merchantDoc.docId, merchantDoc.data);
      }

      final userProfile = await fetchBackendUserProfile(backendUserIdHint);
      if (userProfile != null) {
        _applyBackendUserProfile(info, userProfile);
        final uid = info.merchantRef.trim();
        if (_looksLikeFirebaseUid(uid)) {
          merchantRef = uid;
          sellerUid ??= uid;
        }
      }

      if (merchantRef.isEmpty) {
        merchantRef = backendUserIdHint.toString();
        sellerUid ??= backendUserIdHint.toString();
      }
      info.merchantRef = info.merchantRef.isNotEmpty ? info.merchantRef : merchantRef;
    }

    if (merchantRef.isEmpty &&
        backendUserIdHint != null &&
        backendUserIdHint > 0) {
      merchantRef = backendUserIdHint.toString();
      sellerUid ??= backendUserIdHint.toString();
      info.merchantRef = merchantRef;
    }

    final merchantUid = merchantRef.trim();
    if (merchantUid.isNotEmpty && _looksLikeFirebaseUid(merchantUid)) {
      try {
        final mDoc = await FirebaseFirestore.instance
            .collection('marketplace_merchants')
            .doc(merchantUid)
            .get();
        if (mDoc.exists) {
          _applyFirestoreMerchantData(
            info,
            mDoc.id,
            mDoc.data() ?? <String, dynamic>{},
          );
        }
      } catch (_) {}

      await _applyFirestoreUserData(info, merchantUid);
    }

    await _enrichFromServiceProvider(info, [
      info.serviceProviderId ?? '',
      serviceProviderId ?? '',
      if (backendUserIdHint != null && backendUserIdHint > 0)
        backendUserIdHint.toString(),
      merchantRef,
      sellerUid ?? '',
    ]);

    final reviewsId = backendMerchantIdForReviews ??
        backendUserIdHint ??
        info.backendMerchantId ??
        0;

    await _loadReviews(
      info,
      reviewsMerchantId: reviewsId,
      merchantRef: _looksLikeFirebaseUid(info.merchantRef)
          ? info.merchantRef
          : merchantRef,
      serviceProviderId: info.serviceProviderId ?? serviceProviderId,
      sellerUserId: info.sellerUserId ?? sellerUid,
    );

    return info;
  }
}
