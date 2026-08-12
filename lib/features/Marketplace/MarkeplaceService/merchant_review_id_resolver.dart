import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';

/// Resolves marketplace merchant references (Firebase UID, etc.)
/// to the numeric Nest **user** id required by `/vero/reviews`.
///
/// Important: never treat service-provider / shop record ids as user ids —
/// the reviews API requires a Nest user with `role == merchant` to **create**
/// a review. Loading reviews only needs a resolvable Nest user id.
class MerchantReviewIdResolver {
  MerchantReviewIdResolver._();

  static bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  static int? _parsePositiveInt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = int.tryParse(raw.trim());
    if (n != null && n > 0) return n;
    return null;
  }

  static bool _isMerchantRole(Map<String, dynamic> user) {
    if (RoleHelper.isMerchant(user)) return true;
    final role = (user['role'] ?? user['userRole'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return role.contains('merchant') || role == 'seller' || role == 'vendor';
  }

  /// True when Firebase session or stored API token exists.
  static Future<bool> _hasSession() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    return AuthHandler.isAuthenticated();
  }

  /// Resolve Nest user id for viewing + writing reviews.
  /// Does **not** require the seller to already be `role=merchant` (that check
  /// belongs only in [ensureMerchantEligibleForReview]).
  static Future<int> resolveMerchantId({
    required String merchantRef,
    String? serviceProviderId,
    String? sellerUserId,
    int? preResolvedBackendId,
  }) async {
    final trimmedRef = merchantRef.trim();
    final candidates = <int>[];
    final signedIn = await _hasSession();

    void addCandidate(int? id) {
      if (id == null || id <= 0) return;
      if (!candidates.contains(id)) candidates.add(id);
    }

    // 1) Firebase shop UID → Nest user id.
    if (_looksLikeFirebaseUid(trimmedRef)) {
      addCandidate(await _lookupBackendIdFromFirestore(trimmedRef));
      if (signedIn) {
        addCandidate(await _lookupUserIdByFirebaseUid(trimmedRef));
      }
    }

    // 2) Explicit Nest id from caller (orders / warm cache).
    addCandidate(preResolvedBackendId);
    addCandidate(_parsePositiveInt(trimmedRef));

    // sellerUserId may be Nest id OR Firebase UID.
    final seller = (sellerUserId ?? '').trim();
    if (_looksLikeFirebaseUid(seller)) {
      addCandidate(await _lookupBackendIdFromFirestore(seller));
      if (signedIn) {
        addCandidate(await _lookupUserIdByFirebaseUid(seller));
      }
    } else {
      addCandidate(_parsePositiveInt(seller));
    }

    // Prefer a confirmed merchant when we can (helps write path), but never
    // block resolve just because Nest still has role=customer.
    for (final id in candidates) {
      final profile = await _fetchUserProfile(id);
      if (profile != null && _isMerchantRole(profile)) return id;
    }

    if (candidates.isNotEmpty) return candidates.first;

    if (!signedIn) {
      throw const ApiException(
        message: 'Please log in to view and leave reviews.',
        requiresLogin: true,
      );
    }

    throw const ApiException(
      message:
          'Could not find this seller’s review profile. Pull to refresh or open the shop again.',
    );
  }

  /// Call before POST /reviews. Throws a clear error if Nest user isn’t merchant.
  static Future<void> ensureMerchantEligibleForReview(int merchantId) async {
    final profile = await _fetchUserProfile(merchantId);
    if (profile == null) return; // offline / 403 — let API decide
    if (_isMerchantRole(profile)) return;
    throw const ApiException(
      message:
          'This seller is not marked as a merchant on the server yet. '
          'Ask them to open their Merchant dashboard once, then try again.',
    );
  }

  static Future<Map<String, dynamic>?> _fetchUserProfile(int userId) async {
    if (userId <= 0) return null;
    try {
      if (!await _hasSession()) return null;
      final token = await AuthHandler.getTokenForApi();
      if (token == null || token.isEmpty) return null;
      await ApiConfig.init();
      final res = await http
          .get(
            ApiConfig.endpoint('/users/$userId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      if (decoded['data'] is Map) {
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _lookupBackendIdFromFirestore(String firebaseUid) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(firebaseUid);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await ref.get(const GetOptions(source: Source.cache));
        if (!doc.exists) {
          doc = await ref.get(const GetOptions(source: Source.serverAndCache));
        }
      } catch (_) {
        doc = await ref.get(const GetOptions(source: Source.serverAndCache));
      }
      if (!doc.exists) {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUid)
            .get(const GetOptions(source: Source.serverAndCache));
        if (!u.exists) return null;
        final data = u.data();
        if (data == null) return null;
        return _parsePositiveInt(data['backendUserId']?.toString()) ??
            _parsePositiveInt(data['userId']?.toString()) ??
            _parsePositiveInt(data['nestUserId']?.toString());
      }
      final data = doc.data();
      if (data == null) return null;

      return _parsePositiveInt(data['backendUserId']?.toString()) ??
          _parsePositiveInt(data['merchantUserId']?.toString()) ??
          _parsePositiveInt(data['userId']?.toString()) ??
          _parsePositiveInt(data['nestUserId']?.toString());
    } catch (_) {}
    return null;
  }

  static Future<int?> _lookupUserIdByFirebaseUid(String firebaseUid) async {
    if (firebaseUid.isEmpty) return null;
    try {
      if (!await _hasSession()) return null;
      await BackendChatService.ensureAuth();
      // Prefer validated mapping; fall back to plain lookup if validation rejects.
      final validated = await BackendChatService.getUserIdByFirebaseUidValidated(
        firebaseUid,
        quiet: true,
      );
      if (validated != null && validated > 0) return validated;
      return BackendChatService.getUserIdByFirebaseUid(firebaseUid, quiet: true);
    } catch (_) {
      return null;
    }
  }

  static Future<int> resolveCustomerId() async {
    if (!await _hasSession()) {
      throw const ApiException(
        message: 'Please log in to leave a review.',
        requiresLogin: true,
      );
    }
    try {
      await BackendChatService.ensureAuth();
      return BackendChatService.getUserId();
    } catch (_) {
      throw const ApiException(
        message:
            'Could not verify your account for reviews. Pull to refresh, or sign out and back in.',
      );
    }
  }

  /// Sellers: ensure Nest `role` is merchant so buyers can leave reviews.
  static Future<void> ensureCurrentUserNestMerchantRole({
    String? merchantService,
  }) async {
    try {
      if (!await _hasSession()) return;
      final token = await AuthHandler.getTokenForApi();
      if (token == null || token.isEmpty) return;
      await ApiConfig.init();

      final meRes = await http
          .get(
            ApiConfig.endpoint('/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (meRes.statusCode != 200) return;

      final decoded = jsonDecode(meRes.body);
      Map<String, dynamic>? me;
      if (decoded is Map && decoded['data'] is Map) {
        me = Map<String, dynamic>.from(decoded['data'] as Map);
      } else if (decoded is Map) {
        me = Map<String, dynamic>.from(decoded);
      }
      if (me != null && _isMerchantRole(me)) return;

      final body = <String, dynamic>{'role': 'merchant'};
      final svc = (merchantService ?? '').trim();
      if (svc.isNotEmpty) {
        body['merchantService'] = svc;
        body['serviceType'] = svc;
      }

      await http
          .put(
            ApiConfig.endpoint('/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
