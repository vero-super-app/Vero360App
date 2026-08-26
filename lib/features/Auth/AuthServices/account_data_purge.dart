import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/postlatestArrivalservices.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/utils/session_local_cache.dart';

/// Permanently removes customer + merchant data for the signed-in user
/// (marketplace items, shops, wallets, carts, stories, rooms, food menus, etc.).
///
/// Call **before** deleting the Firebase Auth user so Firestore rules still allow writes.
class AccountDataPurge {
  AccountDataPurge._();

  static final _db = FirebaseFirestore.instance;

  /// Best-effort full wipe. Failures are logged; deletion flow should continue.
  /// Caps remote work so Settings delete does not hang.
  static Future<void> purgeCurrentUser({
    Duration budget = const Duration(seconds: 6),
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    final prefs = await SharedPreferences.getInstance();
    final nestId = _nestUserIdFromPrefs(prefs);
    final email = (user.email ?? prefs.getString('email') ?? '').trim();
    final token = await AuthHandler.getTokenForApi();

    if (kDebugMode) {
      debugPrint('[AccountDataPurge] starting for uid=$uid nestId=$nestId');
    }

    // Local chats / rides / hive first — new signup must not see old data.
    CartService.clearSessionCache();
    await SessionLocalCache.clearOnAccountDeletion();

    try {
      await Future.wait<void>([
        _deleteBackendUser(token),
        _deleteBackendChats(token),
        _deleteBackendVerticalListings(
          token: token,
          uid: uid,
          email: email,
        ),
        _deleteFirestoreBundle(uid: uid, nestId: nestId, email: email),
      ]).timeout(budget);
    } catch (e) {
      if (kDebugMode) debugPrint('[AccountDataPurge] timed/failed: $e');
    }

    // Slow leftovers — never block leaving the account.
    unawaited(_deleteMyLatestArrivals(token));
    unawaited(_deleteMyPromos(token));
    unawaited(_deleteStoragePrefix('merchant_stories/$uid'));
    unawaited(_deleteStoragePrefix('profiles/$uid'));
    unawaited(_deleteStoragePrefix('marketplace/$uid'));
    unawaited(_deleteStoragePrefix('food/$uid'));
    unawaited(_deleteStoragePrefix('restaurants/$uid'));
    unawaited(_deleteStoragePrefix('accommodation/$uid'));
    unawaited(_deleteStoragePrefix('homepage_adverts/$uid'));

    if (kDebugMode) debugPrint('[AccountDataPurge] finished for uid=$uid');
  }

  static Future<void> _deleteFirestoreBundle({
    required String uid,
    required int? nestId,
    required String email,
  }) async {
    final accommodationListingIds = await _collectAccommodationListingIds(uid);
    final userRef = _db.collection('users').doc(uid);
    final jobs = <Future<void>>[
      _deleteQueryDocs(
        _db.collection('marketplace_items').where('merchantId', isEqualTo: uid),
      ),
      _deleteDoc(_db.collection('marketplace_merchants').doc(uid)),
      _deleteDoc(_db.collection('food_merchants').doc(uid)),
      _deleteDoc(_db.collection('accommodation_merchants').doc(uid)),
      _deleteDoc(_db.collection('courier_merchants').doc(uid)),
      _deleteDoc(_db.collection('merchant_wallets').doc(uid)),
      _deleteDoc(_db.collection('wallets').doc(uid)),
      _deleteQueryDocs(
        _db.collection('merchant_stories').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('food_menu_items').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('latestarrivals').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db
            .collection('wallet_transactions')
            .where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('wallet_transactions').where('userId', isEqualTo: uid),
      ),
      _deleteFoodRestaurantFirestore(uid),
      _deleteAccommodationFirestore(uid, accommodationListingIds),
      _deleteSubcollection(_db.collection('backup_carts').doc(uid), 'items'),
      _deleteDoc(_db.collection('backup_carts').doc(uid)),
      _deleteSubcollection(userRef, 'followed_merchants'),
      _deleteSubcollection(userRef, 'notifications'),
      _deleteSubcollection(userRef, 'fcmTokens'),
      _deleteDoc(userRef),
      _deleteDoc(_db.collection('profiles').doc(uid)),
    ];
    if (nestId != null) {
      jobs.addAll([
        _deleteQueryDocs(
          _db
              .collection('marketplace_items')
              .where('sellerUserId', isEqualTo: nestId),
        ),
        _deleteQueryDocs(
          _db
              .collection('marketplace_items')
              .where('sellerUserId', isEqualTo: nestId.toString()),
        ),
      ]);
    }
    if (email.isNotEmpty) {
      jobs.addAll([
        _deleteSubcollection(_db.collection('backup_carts').doc(email), 'items'),
        _deleteDoc(_db.collection('backup_carts').doc(email)),
      ]);
    }
    await Future.wait(jobs);
  }

  /// Food & restaurant merchant/customer rows in Firestore.
  static Future<void> _deleteFoodRestaurantFirestore(String uid) async {
    await Future.wait([
      _deleteQueryDocs(
        _db.collection('restaurants').where('ownerUid', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('food_orders').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('food_orders').where('customerUid', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('food_reviews').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('food_reviews').where('customerUid', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('order_escrow').where('merchantUid', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('order_party_alerts').where('toUid', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('homepage_adverts').where('userId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db.collection('homepage_adverts').where('merchantId', isEqualTo: uid),
      ),
      _deleteSubcollection(
        _db.collection('merchant_followers').doc(uid),
        'followers',
      ),
      _deleteDoc(_db.collection('merchant_followers').doc(uid)),
    ]);
  }

  static Future<Set<int>> _collectAccommodationListingIds(String uid) async {
    final ids = <int>{};
    try {
      final snap = await _db
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: uid)
          .limit(200)
          .get();
      for (final d in snap.docs) {
        _takeListingId(ids, d.data()['apiAccommodationId']);
        final parts = d.id.split('_');
        if (parts.length >= 2) {
          _takeListingId(ids, parts.last);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AccountDataPurge] accommodation listing ids: $e');
      }
    }
    return ids;
  }

  static void _takeListingId(Set<int> ids, dynamic raw) {
    if (raw is num) {
      final v = raw.toInt();
      if (v > 0) ids.add(v);
      return;
    }
    final v = int.tryParse(raw?.toString() ?? '');
    if (v != null && v > 0) ids.add(v);
  }

  /// Accommodation host listings, bookings, occupancy, and live watchers.
  static Future<void> _deleteAccommodationFirestore(
    String uid,
    Set<int> listingIds,
  ) async {
    final jobs = <Future<void>>[
      _deleteQueryDocs(
        _db.collection('accommodation_rooms').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db
            .collection('accommodation_reviews')
            .where('merchantId', isEqualTo: uid),
      ),
      for (final field in [
        'merchantId',
        'hostUid',
        'userId',
        'customerUid',
        'ownerUid',
      ])
        _deleteQueryDocs(
          _db.collection('bookings').where(field, isEqualTo: uid),
        ),
      for (final id in listingIds) ...[
        _deleteOccupancyTree(id),
        _deleteWatchersTree(id),
      ],
    ];
    await Future.wait(jobs);
  }

  static Future<void> _deleteOccupancyTree(int accommodationId) async {
    if (accommodationId <= 0) return;
    final root =
        _db.collection('accommodation_occupancy').doc('$accommodationId');
    await _deleteSubcollection(root, 'nights');
    await _deleteSubcollection(root, 'stays');
    await _deleteDoc(root);
  }

  static Future<void> _deleteWatchersTree(int listingId) async {
    if (listingId <= 0) return;
    final root = _db.collection('accommodation_watchers').doc('$listingId');
    await _deleteSubcollection(root, 'viewers');
    await _deleteDoc(root);
  }

  /// Nest API listings + bookings for food/accommodation merchants.
  static Future<void> _deleteBackendVerticalListings({
    required String? token,
    required String uid,
    required String email,
  }) async {
    if (token == null || token.isEmpty) return;
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
    await Future.wait([
      _deleteBackendAccommodations(headers, uid: uid, email: email),
      _deleteBackendBookings(headers),
    ]);
  }

  static Future<void> _deleteBackendAccommodations(
    Map<String, String> headers, {
    required String uid,
    required String email,
  }) async {
    try {
      final res = await http
          .get(
            ApiConfig.endpoint('/accommodations/all'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;

      for (final item in _extractList(jsonDecode(res.body))) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        if (!_ownsAccommodation(map, uid: uid, email: email)) continue;

        final rawId = map['id'];
        final numeric = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        if (numeric == null || numeric <= 0) continue;

        try {
          await http
              .delete(
                ApiConfig.endpoint('/accommodations/$numeric'),
                headers: headers,
              )
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AccountDataPurge] backend accommodations: $e');
      }
    }
  }

  static bool _ownsAccommodation(
    Map<String, dynamic> map, {
    required String uid,
    required String email,
  }) {
    final emailLower = email.trim().toLowerCase();
    for (final k in [
      'hostMerchantUid',
      'hostUid',
      'merchantFirebaseUid',
      'merchantId',
    ]) {
      if (map[k]?.toString().trim() == uid) return true;
    }

    final owner = map['owner'];
    if (owner is Map) {
      final ownerMap = Map<String, dynamic>.from(owner);
      for (final k in ['firebaseUid', 'uid', 'merchantUid', 'userId']) {
        if (ownerMap[k]?.toString().trim() == uid) return true;
      }
      final ownerEmail =
          ownerMap['email']?.toString().trim().toLowerCase() ?? '';
      if (emailLower.isNotEmpty && ownerEmail == emailLower) return true;
    }

    final ownerEmail = map['ownerEmail']?.toString().trim().toLowerCase() ?? '';
    return emailLower.isNotEmpty && ownerEmail == emailLower;
  }

  static Future<void> _deleteBackendBookings(
    Map<String, String> headers,
  ) async {
    for (final path in ['/bookings/me', '/bookings/merchant/me']) {
      try {
        final res = await http
            .get(
              ApiConfig.endpoint(path),
              headers: headers,
            )
            .timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        for (final item in _extractList(jsonDecode(res.body))) {
          if (item is! Map) continue;
          final id =
              (item['id'] ?? item['bookingId'] ?? item['booking_id'] ?? '')
                  .toString()
                  .trim();
          if (id.isEmpty) continue;
          try {
            await http
                .delete(
                  ApiConfig.endpoint('/bookings/$id'),
                  headers: headers,
                )
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[AccountDataPurge] backend bookings: $e');
      }
    }
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;
      if (data is Map) {
        for (final key in ['items', 'results', 'bookings', 'accommodations']) {
          final v = data[key];
          if (v is List) return v;
        }
      }
      for (final key in ['items', 'results', 'bookings', 'accommodations']) {
        final v = decoded[key];
        if (v is List) return v;
      }
    }
    return const [];
  }

  /// Remove chat threads on the API so the same email/phone cannot reopen them.
  static Future<void> _deleteBackendChats(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      final listUri = Uri.parse(
        '${ApiConfig.prod}/vero/api/v1/chats?page=1&pageSize=100',
      );
      final res = await http.get(
        listUri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final raw = <dynamic>[];
      if (decoded is List) {
        raw.addAll(decoded);
      } else if (decoded is Map) {
        final data = decoded['data'];
        if (data is List) {
          raw.addAll(data);
        } else if (data is Map) {
          for (final key in ['items', 'chats', 'threads', 'results']) {
            final v = data[key];
            if (v is List) {
              raw.addAll(v);
              break;
            }
          }
        }
        if (raw.isEmpty) {
          for (final key in ['items', 'chats', 'threads', 'results']) {
            final v = decoded[key];
            if (v is List) {
              raw.addAll(v);
              break;
            }
          }
        }
      }

      await Future.wait(
        raw.map((item) async {
          if (item is! Map) return;
          final id = (item['id'] ?? item['chatId'] ?? '').toString().trim();
          if (id.isEmpty) return;
          try {
            await http
                .delete(
                  Uri.parse('${ApiConfig.prod}/vero/api/v1/chats/$id'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Accept': 'application/json',
                  },
                )
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      if (kDebugMode) debugPrint('[AccountDataPurge] chats: $e');
    }
  }

  static int? _nestUserIdFromPrefs(SharedPreferences prefs) {
    final i = prefs.getInt('userId') ?? prefs.getInt('user_id');
    if (i != null && i > 0) return i;
    final s = (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    return int.tryParse(s);
  }

  static Future<void> _deleteBackendUser(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await http
          .delete(
            ApiConfig.endpoint('/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) debugPrint('[AccountDataPurge] backend DELETE /users/me: $e');
    }
  }

  static Future<void> _deleteMyLatestArrivals(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      final svc = LatestArrivalsServicess();
      final mine = await svc.fetchMine();
      for (final item in mine) {
        if (item.id <= 0) continue;
        try {
          await svc.delete(item.id);
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AccountDataPurge] latest arrivals: $e');
    }
  }

  static Future<void> _deleteMyPromos(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      final svc = PromoService();
      final mine = await svc.fetchMyPromos();
      for (final p in mine) {
        try {
          await svc.deletePromo(p.id);
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AccountDataPurge] promos: $e');
    }
  }

  static Future<void> _deleteDoc(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.delete();
    } catch (_) {}
  }

  static Future<void> _deleteQueryDocs(Query<Map<String, dynamic>> query) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      do {
        snap = await query.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      } while (snap.docs.length >= 400);
    } catch (e) {
      if (kDebugMode) debugPrint('[AccountDataPurge] query delete: $e');
    }
  }

  static Future<void> _deleteSubcollection(
    DocumentReference<Map<String, dynamic>> parent,
    String name,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      do {
        snap = await parent.collection(name).limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      } while (snap.docs.length >= 400);
    } catch (_) {}
  }

  static Future<void> _deleteStoragePrefix(String prefix) async {
    try {
      final root = FirebaseStorage.instance.ref(prefix);
      final listed = await root.listAll();
      for (final item in listed.items) {
        try {
          await item.delete();
        } catch (_) {}
      }
      for (final prefixRef in listed.prefixes) {
        await _deleteStoragePrefix(prefixRef.fullPath);
      }
    } catch (_) {}
  }
}
