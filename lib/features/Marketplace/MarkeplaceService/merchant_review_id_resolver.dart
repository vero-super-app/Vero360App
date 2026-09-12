import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';

/// Resolves marketplace merchant references (Firebase UID, serviceProviderId, sellerUserId, etc.)
/// to the numeric Nest **user** id required by `/vero/reviews`.
class MerchantReviewIdResolver {
  MerchantReviewIdResolver._();

  /// Fast in-memory cache of resolved references (Firebase UID, phone, etc. -> backend user id).
  static final Map<String, int> _cache = {};

  static bool _looksLikeFirebaseUid(String value) {
    final v = value.trim();
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(v);
  }

  static int? _parsePositiveInt(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    final n = int.tryParse(str);
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

  static void _remember(int id, List<String?> keys) {
    if (id <= 0) return;
    for (final k in keys) {
      final s = (k ?? '').trim();
      if (s.isNotEmpty && s.toLowerCase() != 'unknown') {
        _cache[s] = id;
      }
    }
  }

  static void clearCache() => _cache.clear();

  /// Call before POST /reviews. Throws a clear error if Nest user isn’t merchant.
  static Future<void> ensureMerchantEligibleForReview(int merchantId) async {
    if (merchantId <= 0) {
      throw const ApiException(
        message: 'Could not find this seller’s account for reviews.',
      );
    }
    final profile = await _fetchUserProfile(merchantId);
    if (profile == null) {
      // Profile missing or unreachable — still try create; API is source of truth.
      return;
    }
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
          .timeout(const Duration(seconds: 6));
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

  static int? _extractBackendId(Map<String, dynamic>? data) {
    if (data == null) return null;
    // Only Nest *user* ids — never shopId / serviceProviderRecordId / doc id
    // (those caused POST /reviews → 404 Merchant not found).
    return _parsePositiveInt(data['backendUserId']) ??
        _parsePositiveInt(data['nestUserId']) ??
        _parsePositiveInt(data['merchantBackendId']) ??
        _parsePositiveInt(data['merchantUserId']) ??
        _parsePositiveInt(data['userId']) ??
        _parsePositiveInt(data['ownerId']);
  }

  /// True when Nest will accept this id as a reviewable merchant.
  static Future<bool> _isReviewableMerchantId(int merchantId) async {
    if (merchantId <= 0) return false;
    final profile = await _fetchUserProfile(merchantId);
    if (profile == null) return false;
    return _isMerchantRole(profile);
  }

  /// Resolve Nest user id for viewing + writing reviews.
  static Future<int> resolveMerchantId({
    required String merchantRef,
    String? serviceProviderId,
    String? sellerUserId,
    int? preResolvedBackendId,
  }) async {
    final trimmedRef = merchantRef.trim();
    final trimmedSeller = (sellerUserId ?? '').trim();
    final trimmedSp = (serviceProviderId ?? '').trim();

    // 0) Check in-memory cache first (re-verify — stale SP/shop ids caused 404s).
    for (final key in [trimmedRef, trimmedSeller, trimmedSp]) {
      if (key.isNotEmpty && _cache.containsKey(key)) {
        final cached = _cache[key];
        if (cached != null && cached > 0) {
          if (await _isReviewableMerchantId(cached)) return cached;
          _cache.remove(key);
        }
      }
    }

    final candidates = <int>[];

    void addCandidate(int? id) {
      if (id == null || id <= 0) return;
      if (!candidates.contains(id)) candidates.add(id);
    }

    final uidCandidates = <String>{};
    for (final raw in [trimmedRef, trimmedSeller, trimmedSp]) {
      if (raw.isNotEmpty &&
          raw.toLowerCase() != 'unknown' &&
          _looksLikeFirebaseUid(raw)) {
        uidCandidates.add(raw);
      }
    }

    // 1) Validated Nest user id from Firebase UID (most reliable for /reviews).
    for (final uid in uidCandidates) {
      try {
        if (await _hasSession()) {
          await BackendChatService.ensureAuth();
          final validated =
              await BackendChatService.getUserIdByFirebaseUidValidated(
            uid,
            quiet: true,
          );
          addCandidate(validated);
        }
      } catch (_) {}
      final raw = await _lookupUserIdByFirebaseUid(uid);
      addCandidate(raw);
    }

    // 2) Firestore merchant/user docs (Nest user fields only).
    for (final uid in uidCandidates) {
      final id = await _lookupBackendIdFromFirestore(uid);
      addCandidate(id);
    }

    // 3) Chat peer / product owner Nest id.
    addCandidate(preResolvedBackendId);
    addCandidate(_parsePositiveInt(trimmedRef));
    if (!_looksLikeFirebaseUid(trimmedSeller)) {
      addCandidate(_parsePositiveInt(trimmedSeller));
    }
    if (!_looksLikeFirebaseUid(trimmedSp)) {
      addCandidate(_parsePositiveInt(trimmedSp));
    }

    // 4) marketplace_items.merchantBackendId
    for (final ref in [trimmedRef, trimmedSeller, trimmedSp]) {
      if (ref.isNotEmpty && ref.toLowerCase() != 'unknown') {
        final itemId = await _lookupBackendIdFromItems(ref);
        addCandidate(itemId);
      }
    }

    // 5) Own account (merchant viewing self)
    final currentFbUser = FirebaseAuth.instance.currentUser;
    if (currentFbUser != null) {
      final currentUid = currentFbUser.uid.trim();
      if (currentUid == trimmedRef ||
          currentUid == trimmedSeller ||
          currentUid == trimmedSp) {
        addCandidate(await _getOwnBackendUserId());
      }
    }

    if (candidates.isEmpty) {
      throw ApiException(
        message:
            'Could not find this seller’s account for reviews. '
            'Open their shop once, then try rating again.',
      );
    }

    // Prefer an id Nest recognizes as a merchant role.
    var sawNonMerchantUser = false;
    for (final id in candidates) {
      final profile = await _fetchUserProfile(id);
      if (profile == null) continue;
      if (_isMerchantRole(profile)) {
        _remember(id, [trimmedRef, trimmedSeller, trimmedSp]);
        return id;
      }
      sawNonMerchantUser = true;
    }

    if (sawNonMerchantUser) {
      throw const ApiException(
        message:
            'This seller is not marked as a merchant on the server yet. '
            'Ask them to open their Merchant dashboard once, then try again.',
      );
    }

    // Profiles unreachable (offline) — try first candidate; API will validate.
    final fallback = candidates.first;
    _remember(fallback, [trimmedRef, trimmedSeller, trimmedSp]);
    return fallback;
  }

  static Future<int?> _lookupBackendIdFromFirestore(String firebaseUid) async {
    if (firebaseUid.trim().isEmpty) return null;
    final uid = firebaseUid.trim();

    // 1) Direct doc lookup in marketplace_merchants
    try {
      final mRef = FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .doc(uid);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await mRef.get(const GetOptions(source: Source.cache));
        if (!doc.exists) {
          doc = await mRef.get(const GetOptions(source: Source.serverAndCache));
        }
      } catch (_) {
        doc = await mRef.get(const GetOptions(source: Source.serverAndCache));
      }
      if (doc.exists && doc.data() != null) {
        final id = _extractBackendId(doc.data());
        if (id != null) return id;
      }
    } catch (_) {}

    // 2) Direct doc lookup in users
    try {
      final uRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      DocumentSnapshot<Map<String, dynamic>> uDoc;
      try {
        uDoc = await uRef.get(const GetOptions(source: Source.cache));
        if (!uDoc.exists) {
          uDoc = await uRef.get(const GetOptions(source: Source.serverAndCache));
        }
      } catch (_) {
        uDoc = await uRef.get(const GetOptions(source: Source.serverAndCache));
      }
      if (uDoc.exists && uDoc.data() != null) {
        final id = _extractBackendId(uDoc.data());
        if (id != null) return id;
      }
    } catch (_) {}

    // 3) Query marketplace_merchants by firebaseUid / uid / ownerId
    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .where('firebaseUid', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      if (qSnap.docs.isNotEmpty) {
        final id = _extractBackendId(qSnap.docs.first.data());
        if (id != null) return id;
      }
    } catch (_) {}

    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('marketplace_merchants')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      if (qSnap.docs.isNotEmpty) {
        final id = _extractBackendId(qSnap.docs.first.data());
        if (id != null) return id;
      }
    } catch (_) {}

    // 4) Query users collection by firebaseUid / uid
    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('firebaseUid', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      if (qSnap.docs.isNotEmpty) {
        final id = _extractBackendId(qSnap.docs.first.data());
        if (id != null) return id;
      }
    } catch (_) {}

    try {
      final qSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      if (qSnap.docs.isNotEmpty) {
        final id = _extractBackendId(qSnap.docs.first.data());
        if (id != null) return id;
      }
    } catch (_) {}

    // 5) Try restaurants doc
    try {
      final rDoc = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      if (rDoc.exists && rDoc.data() != null) {
        final id = _extractBackendId(rDoc.data());
        if (id != null) return id;
      }
    } catch (_) {}

    return null;
  }

  static Future<int?> _lookupUserIdByFirebaseUid(String firebaseUid) async {
    if (firebaseUid.trim().isEmpty) return null;
    final uid = firebaseUid.trim();

    // 1) Via BackendChatService if authenticated
    try {
      if (await _hasSession()) {
        await BackendChatService.ensureAuth();
        final validated =
            await BackendChatService.getUserIdByFirebaseUidValidated(
          uid,
          quiet: true,
        );
        if (validated != null && validated > 0) return validated;
        final raw = await BackendChatService.getUserIdByFirebaseUid(
          uid,
          quiet: true,
        );
        if (raw != null && raw > 0) return raw;
      }
    } catch (_) {}

    // 2) Direct API call to /users with query param (works even without full chat auth)
    try {
      final token = await AuthHandler.getTokenForApi();
      await ApiConfig.init();
      final headers = <String, String>{
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final attempts = [
        ApiConfig.endpoint('/users').replace(queryParameters: {'firebaseUid': uid}),
        ApiConfig.endpoint('/users').replace(queryParameters: {'uid': uid}),
      ];

      for (final uri in attempts) {
        try {
          final res = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 5),
          );
          if (res.statusCode != 200) continue;
          final decoded = jsonDecode(res.body);
          if (decoded is! Map) continue;
          final data = decoded['data'] ?? decoded;
          if (data is List && data.isNotEmpty) {
            for (final u in data) {
              if (u is Map) {
                final id = _parsePositiveInt(u['id'] ?? u['userId']);
                if (id != null) return id;
              }
            }
          } else if (data is Map) {
            final id = _parsePositiveInt(data['id'] ?? data['userId']);
            if (id != null) return id;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return null;
  }

  static Future<int?> _lookupBackendIdFromItems(String ref) async {
    final target = ref.trim();
    if (target.isEmpty) return null;

    try {
      final queries = [
        FirebaseFirestore.instance
            .collection('marketplace_items')
            .where('merchantId', isEqualTo: target)
            .limit(3),
        FirebaseFirestore.instance
            .collection('marketplace_items')
            .where('sellerUserId', isEqualTo: target)
            .limit(3),
      ];

      for (final q in queries) {
        try {
          final snap =
              await q.get(const GetOptions(source: Source.serverAndCache));
          for (final doc in snap.docs) {
            final data = doc.data();
            final id = _extractBackendId(data);
            if (id != null) return id;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return null;
  }

  static Future<int?> _getOwnBackendUserId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getInt('userId') ?? sp.getInt('user_id');
      if (id != null && id > 0) return id;
      if (await _hasSession()) {
        await BackendChatService.ensureAuth();
        final chatUserId = await BackendChatService.getUserId();
        if (chatUserId > 0) return chatUserId;
      }
    } catch (_) {}
    return null;
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
