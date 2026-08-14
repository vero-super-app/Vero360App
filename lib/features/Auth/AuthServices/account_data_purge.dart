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

    if (kDebugMode) debugPrint('[AccountDataPurge] finished for uid=$uid');
  }

  static Future<void> _deleteFirestoreBundle({
    required String uid,
    required int? nestId,
    required String email,
  }) async {
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
        _db.collection('accommodation_rooms').where('merchantId', isEqualTo: uid),
      ),
      _deleteQueryDocs(
        _db
            .collection('accommodation_reviews')
            .where('merchantId', isEqualTo: uid),
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
