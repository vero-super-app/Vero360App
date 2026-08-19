// lib/services/cart_services.dart
//
// ✅ Full correct CartService for your NestJS routes:
//
//   POST   /vero/cart/add
//   GET    /vero/cart/me
//   DELETE /vero/cart/:itemId
//   DELETE /vero/cart
//
// ✅ Offline-first + resilient:
// - Always writes to Firestore immediately (so "Added to cart" is real)
// - Background sync to backend
// - Fetch prefers backend, falls back to Firestore
// - Never clears Firestore just because backend returns 404
// - Uses ONE Firestore schema everywhere:
//     backup_carts/{userKey}/items/{itemId_merchantId}
//   userKey = FirebaseAuth.uid ?? SharedPreferences.email
//

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

import '../CartModel/cart_model.dart';

const _kApiTimeout = Duration(seconds: 10);
const _kApiTimeoutFast = Duration(seconds: 4);
const _kWarmupTimeout = Duration(milliseconds: 900);
const _kWarmupCooldown = Duration(seconds: 45);

class CartService {
  // Keep this EXACT signature (you use it everywhere)
  CartService(String unused, {required String apiPrefix})
      : _apiPrefix = apiPrefix;

  final String
      _apiPrefix; // kept for compatibility; ApiConfig already applies /vero

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Warmup throttling (fast + avoids spamming)
  static bool _warmedUp = false;
  static bool _warmupInFlight = false;
  static DateTime? _lastWarmupAttempt;

  /// Doc ids (`itemId_merchantId`) removed locally but may still appear in an
  /// in-flight fetch / stale Firestore rewrite. Prevents deleted items "sticking".
  /// Static so every CartService instance shares the same tombstones.
  static final Set<String> _pendingDeletedKeys = <String>{};
  static int _cartEpoch = 0;

  /// Last known cart for instant UI (shared across CartService instances).
  static List<CartModel> _memoryCache = <CartModel>[];

  /// Owner of [_memoryCache] — discard if account switches on the same device.
  static String? _memoryCacheUid;

  /// Wipe in-memory cart so a new account never inherits the previous cart.
  static void clearSessionCache() {
    _memoryCache = <CartModel>[];
    _pendingDeletedKeys.clear();
    _cartEpoch++;
    _memoryCacheUid = null;
    _warmedUp = false;
    _lastWarmupAttempt = null;
  }

  static void _ensureCacheMatchesCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_memoryCacheUid == null) return;
    if (uid == null || uid != _memoryCacheUid) {
      clearSessionCache();
    }
  }

  /// Instant snapshot — no I/O. May be empty on cold start.
  List<CartModel> get cachedItems {
    _ensureCacheMatchesCurrentUser();
    return List<CartModel>.unmodifiable(_withoutPendingDeletes(_memoryCache));
  }

  void _setMemoryCache(List<CartModel> items) {
    _memoryCache = List<CartModel>.from(_withoutPendingDeletes(items));
    _memoryCacheUid = FirebaseAuth.instance.currentUser?.uid;
  }

  // ---------------------------------------------------------------------------
  // AUTH + HEADERS (single source: Firebase then SP, same as rest of app)
  // ---------------------------------------------------------------------------

  Future<String?> _getToken() async => AuthHandler.getTokenForApi();

  Future<String?> _getEmail() async {
    final p = await SharedPreferences.getInstance();
    final email = p.getString('email');
    if (email != null && email.isNotEmpty) return email;
    return null;
  }

  Map<String, String> _headers({required String token}) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Connection': 'close',
        'User-Agent': 'Vero360App/Cart/1.0',
      };

  Future<void> warmup() async {
    if (_warmedUp) return;

    final now = DateTime.now();
    if (_lastWarmupAttempt != null &&
        now.difference(_lastWarmupAttempt!) < _kWarmupCooldown) {
      return;
    }

    if (_warmupInFlight) return;
    _warmupInFlight = true;
    _lastWarmupAttempt = now;

    try {
      await ApiConfig.ensureBackendUp(timeout: _kWarmupTimeout);
      _warmedUp = true;
    } catch (_) {
      // ignore; we operate offline if needed
    } finally {
      _warmupInFlight = false;
    }
  }

  bool _looksLikeAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden') ||
        (msg.contains('jwt') && msg.contains('expired'));
  }

  bool _looksLikePassengerHtmlOrDown(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('phusion passenger') ||
        msg.contains('web application could not be started') ||
        msg.contains("we're sorry, but something went wrong") ||
        msg.contains('<!doctype html') ||
        msg.contains('<html') ||
        msg.contains('500') ||
        msg.contains('502') ||
        msg.contains('503') ||
        msg.contains('504') ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('timed out') ||
        msg.contains('we couldn’t process your request') ||
        msg.contains("we couldn't process your request") ||
        msg.contains('unexpected error');
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE OFFLINE BACKUP (ONE schema everywhere)
  // backup_carts/{userKey}/items/{itemId_merchantId}
  // userKey = FirebaseAuth.uid ?? email
  // ---------------------------------------------------------------------------

  Future<String?> _userKey() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) return uid;

    final email = await _getEmail();
    if (email != null && email.isNotEmpty) return email;

    return null;
  }

  String _docIdFor(CartModel item) => item.firestoreDocId;

  String _key(int itemId, String merchantId) => '${itemId}_$merchantId';

  List<CartModel> _withoutPendingDeletes(List<CartModel> items) {
    if (_pendingDeletedKeys.isEmpty) return items;
    return items
        .where((e) => !_pendingDeletedKeys.contains(_docIdFor(e)))
        .toList();
  }

  void _rememberDelete(int itemId, String? merchantId) {
    _cartEpoch++;
    final mid = (merchantId ?? '').trim();
    if (mid.isNotEmpty) {
      _pendingDeletedKeys.add(_key(itemId, mid));
    } else {
      // Mark any known key that starts with this item id once we see lists.
      _pendingDeletedKeys.add('${itemId}_');
    }
    _memoryCache = _withoutPendingDeletes(_memoryCache);
  }

  /// Call before optimistic UI remove so an in-flight fetch cannot resurrect the row.
  void noteLocalDelete(int itemId, {String? merchantId}) {
    _rememberDelete(itemId, merchantId);
  }

  Map<String, dynamic> _fsMap(CartModel item, {required bool pendingSync}) {
    return <String, dynamic>{
      'itemId': item.item,
      'name': item.name,
      'image': item.image,
      'price': item.price,
      'quantity': item.quantity,
      'description': item.description,
      'comment': item.comment,
      'merchantId': item.merchantId,
      'merchantName': item.merchantName,
      'serviceType': item.serviceType,
      'updatedAt': FieldValue.serverTimestamp(),
      'pendingSync': pendingSync,
      if (item.availableStock != null) 'availableStock': item.availableStock,
      if (item.availableStock != null) 'stockQuantity': item.availableStock,
      if (item.restaurantId != null && item.restaurantId!.trim().isNotEmpty)
        'restaurantId': item.restaurantId!.trim(),
      if (item.variant != null && item.variant!.trim().isNotEmpty)
        'variant': item.variant!.trim(),
      if (item.notes != null && item.notes!.trim().isNotEmpty)
        'notes': item.notes!.trim(),
      if (item.addOns.isNotEmpty) 'addOns': item.addOns,
      if (item.location != null && item.location!.trim().isNotEmpty)
        'location': item.location!.trim(),
    };
  }

  void _upsertMemory(CartModel item) {
    final next = List<CartModel>.from(_memoryCache);
    final i = next.indexWhere((e) =>
        e.item == item.item &&
        e.merchantId == item.merchantId &&
        e.lineConfigKey == item.lineConfigKey);
    if (i >= 0) {
      next[i] = item;
    } else {
      next.insert(0, item);
    }
    _setMemoryCache(next);
  }

  Future<void> _writeCartItemToFirestore(CartModel item,
      {required bool pendingSync}) async {
    final userKey = await _userKey();
    if (userKey == null || userKey.isEmpty) {
      throw const ApiException(
          message:
              'No user session found (missing uid/email). Please log in again.');
    }

    final doc = _firestore
        .collection('backup_carts')
        .doc(userKey)
        .collection('items')
        .doc(_docIdFor(item));

    // Firestore set() waits for the server when online — use a hard cap so a
    // bad network cannot stall "Add to cart" forever.
    await doc
        .set(_fsMap(item, pendingSync: pendingSync), SetOptions(merge: true))
        .timeout(const Duration(seconds: 4));
  }

  Future<void> _upsertCartItemInFirestore(CartModel item,
      {required bool pendingSync}) async {
    _upsertMemory(item);
    await _writeCartItemToFirestore(item, pendingSync: pendingSync);
  }

  Future<void> _persistAddInBackground(String token, CartModel cartItem) async {
    try {
      await _writeCartItemToFirestore(cartItem, pendingSync: true);
    } catch (_) {
      // Memory already updated; sync may still succeed.
    }
    unawaited(_syncAddToCart(token, cartItem));
  }

  Future<void> _markSynced(CartModel item) async {
    try {
      final userKey = await _userKey();
      if (userKey == null || userKey.isEmpty) return;

      final doc = _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items')
          .doc(_docIdFor(item));

      await doc.set(
          {'pendingSync': false, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _removeFromFirestoreByKey(int itemId, String merchantId) async {
    try {
      final userKey = await _userKey();
      if (userKey == null || userKey.isEmpty) return;

      final col = _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items');

      // Canonical doc id.
      await col.doc('${itemId}_$merchantId').delete();

      // Also wipe any legacy / mismatched docs for this item id.
      try {
        final snap = await col.where('itemId', isEqualTo: itemId).get();
        if (snap.docs.isEmpty) return;
        final batch = _firestore.batch();
        for (final d in snap.docs) {
          final mid = (d.data()['merchantId'] ?? '').toString();
          if (mid.isEmpty || mid == merchantId) {
            batch.delete(d.reference);
          }
        }
        await batch.commit();
      } catch (_) {
        // Query may need an index — canonical delete above is enough.
      }
    } catch (_) {}
  }

  Future<void> _clearCartInFirestore() async {
    try {
      final userKey = await _userKey();
      if (userKey == null || userKey.isEmpty) return;

      final col = _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items');

      final snap = await col.get();
      if (snap.docs.isEmpty) return;
      // Firestore batches max ~500.
      var batch = _firestore.batch();
      var n = 0;
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        n++;
        if (n >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          n = 0;
        }
      }
      if (n > 0) await batch.commit();
    } catch (_) {}
  }

  Future<void> _saveCartListToFirestore(List<CartModel> items) async {
    final epochAtStart = _cartEpoch;
    try {
      final userKey = await _userKey();
      if (userKey == null || userKey.isEmpty) return;

      // A delete/clear happened while this save was queued — do not resurrect.
      if (epochAtStart != _cartEpoch) return;

      final filtered = _withoutPendingDeletes(items);
      if (epochAtStart != _cartEpoch) return;

      _setMemoryCache(filtered);

      final col = _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items');

      final existing = await col.get();
      if (epochAtStart != _cartEpoch) return;

      final wantedIds = filtered.map(_docIdFor).toSet();
      final batch = _firestore.batch();

      for (final doc in existing.docs) {
        if (!wantedIds.contains(doc.id) ||
            _pendingDeletedKeys.contains(doc.id)) {
          batch.delete(doc.reference);
        }
      }

      for (final it in filtered) {
        final docRef = col.doc(_docIdFor(it));
        batch.set(
          docRef,
          _fsMap(it, pendingSync: false),
          SetOptions(merge: true),
        );
      }

      await batch.commit();
    } catch (_) {}
  }

  Future<List<CartModel>> _loadCartFromFirestore() async {
    try {
      final userKey = await _userKey();
      if (userKey == null || userKey.isEmpty) return [];

      final col = _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items');

      // Prefer local Firestore cache for first paint — server can catch up later.
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await col.get(const GetOptions(source: Source.cache));
        if (snapshot.docs.isEmpty) {
          snapshot = await col.get();
        }
      } catch (_) {
        snapshot = await col.get();
      }

      int safeInt(Object? v, {int def = 0}) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse('${v ?? ''}') ?? def;
      }

      double safeDouble(Object? v, {double def = 0}) {
        if (v is double) return v;
        if (v is num) return v.toDouble();
        return double.tryParse('${v ?? ''}') ?? def;
      }

      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        return CartModel(
          userId: userKey,
          item: safeInt(data['itemId'] ?? data['item']),
          quantity: safeInt(data['quantity'], def: 1),
          name: (data['name'] ?? '').toString(),
          image: (data['image'] ?? '').toString(),
          price: safeDouble(data['price']),
          description: (data['description'] ?? '').toString(),
          comment: (data['comment'] ?? '').toString(),
          merchantId: (data['merchantId'] ?? '').toString(),
          merchantName: (data['merchantName'] ?? '').toString(),
          serviceType: (data['serviceType'] ?? 'marketplace').toString(),
          availableStock: data['availableStock'] == null &&
                  data['stockQuantity'] == null
              ? null
              : safeInt(data['availableStock'] ?? data['stockQuantity']),
          restaurantId: (data['restaurantId'] ?? '').toString().trim().isEmpty
              ? null
              : (data['restaurantId'] ?? '').toString().trim(),
          variant: (data['variant'] ?? '').toString().trim().isEmpty
              ? null
              : (data['variant'] ?? '').toString().trim(),
          notes: (data['notes'] ?? '').toString().trim().isEmpty
              ? null
              : (data['notes'] ?? '').toString().trim(),
          addOns: CartModel.parseAddOnNames(data['addOns'] ?? data['addons']),
          location: (data['location'] ?? '').toString().trim().isEmpty
              ? null
              : (data['location'] ?? '').toString().trim(),
        );
      }).toList();

      items.sort((a, b) => b.item.compareTo(a.item));
      final filtered = _withoutPendingDeletes(items);
      _setMemoryCache(filtered);
      return filtered;
    } catch (_) {
      return _withoutPendingDeletes(_memoryCache);
    }
  }

  // ---------------------------------------------------------------------------
  // API PAYLOAD (small => avoids 413)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _smallCartPayload(CartModel cartItem) {
    return <String, dynamic>{
      'item': cartItem.item,
      'quantity': cartItem.quantity,
      'merchantId': cartItem.merchantId,
      'serviceType': cartItem.serviceType,
      if (cartItem.comment != null && cartItem.comment!.trim().isNotEmpty)
        'comment': cartItem.comment!.trim(),
      if (cartItem.restaurantId != null &&
          cartItem.restaurantId!.trim().isNotEmpty)
        'restaurantId': cartItem.restaurantId!.trim(),
      if (cartItem.variant != null && cartItem.variant!.trim().isNotEmpty)
        'variant': cartItem.variant!.trim(),
      if (cartItem.notes != null && cartItem.notes!.trim().isNotEmpty)
        'notes': cartItem.notes!.trim(),
      if (cartItem.addOns.isNotEmpty) 'addOns': cartItem.addOns,
      if (cartItem.location != null && cartItem.location!.trim().isNotEmpty)
        'location': cartItem.location!.trim(),
    };
  }

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Offline-first + instant UI:
  /// - updates in-memory cart immediately (returns fast)
  /// - persists Firestore + backend sync in the background
  Future<void> addToCart(CartModel cartItem) async {
    // Never block add on a health ping (up to ~900ms).
    unawaited(warmup());

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
          message: 'You need to be signed in to add items to cart.');
    }

    // Re-adding clears any delete tombstone for this line.
    _pendingDeletedKeys.remove(_docIdFor(cartItem));
    _pendingDeletedKeys.remove('${cartItem.item}_');
    _cartEpoch++;

    // Instant local success — cart page can open this right away.
    _upsertMemory(cartItem);

    // Persist + API sync without stalling the UI (Firestore waits on network).
    unawaited(_persistAddInBackground(token, cartItem));
  }

  Future<void> _syncAddToCart(String token, CartModel cartItem) async {
    final body = jsonEncode(_smallCartPayload(cartItem));

    try {
      // ignore: avoid_print
      print('CART POST try=/cart/add bytes=${utf8.encode(body).length}');

      await ApiClient.post(
        '/cart/add', // ✅ matches NestJS @Post('add')
        headers: _headers(token: token),
        body: body,
        timeout: _kApiTimeout,
      );

      // ✅ mark synced locally
      await _markSynced(cartItem);
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) return;
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    } catch (_) {
      return;
    }
  }

  /// Instant local cart (Firestore backup). Safe to call before network.
  Future<List<CartModel>> loadLocalCart() => _loadCartFromFirestore();

  /// Fetch:
  /// - loads Firestore backup in parallel with auth token
  /// - tries backend GET /cart/me (warmup is non-blocking)
  /// - falls back to Firestore if backend is down or returns HTML
  /// - NEVER clears Firestore on 404 (route mismatch / server issues)
  Future<List<CartModel>> fetchCartItems() async {
    // Don't block the cart UI on a health-check ping.
    unawaited(warmup());

    final tokenFuture = _getToken();
    final localFuture = _loadCartFromFirestore();

    final local = await localFuture;
    final token = await tokenFuture;
    if (token == null || token.isEmpty) {
      final filtered = _withoutPendingDeletes(local);
      if (filtered.isNotEmpty) {
        _setMemoryCache(filtered);
        return filtered;
      }
      throw const ApiException(
          message: 'You need to be signed in to view your cart.');
    }

    // When we already have a local cart, fail fast instead of waiting 10s.
    final timeout =
        local.isNotEmpty || _memoryCache.isNotEmpty ? _kApiTimeoutFast : _kApiTimeout;

    try {
      final res = await ApiClient.get(
        '/cart/me', // ✅ matches NestJS @Get('me')
        headers: _headers(token: token),
        timeout: timeout,
        allowedStatusCodes: {200, 404},
      );

      if (res.statusCode == 404) {
        // ✅ do NOT wipe local cart — return backup
        final filtered = _withoutPendingDeletes(local);
        _setMemoryCache(filtered);
        return filtered;
      }

      final bodyTrim = res.body.trimLeft().toLowerCase();
      if (bodyTrim.startsWith('<!doctype html') ||
          bodyTrim.startsWith('<html')) {
        // passenger/hosting html => treat as down
        final filtered = _withoutPendingDeletes(local);
        _setMemoryCache(filtered);
        return filtered;
      }

      final decoded = jsonDecode(res.body);

      // Support: List OR {data: List}
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      final items = <CartModel>[];
      for (final e in list) {
        if (e is Map) {
          items.add(CartModel.fromJson(Map<String, dynamic>.from(e)));
        }
      }

      final filtered = _withoutPendingDeletes(items);

      // Drop tombstones only once the server no longer returns those items.
      if (_pendingDeletedKeys.isNotEmpty) {
        final serverIds = items.map(_docIdFor).toSet();
        _pendingDeletedKeys.removeWhere(
          (k) => !k.endsWith('_') && !serverIds.contains(k),
        );
        _pendingDeletedKeys.removeWhere((k) {
          if (!k.endsWith('_')) return false;
          final idPart = k.substring(0, k.length - 1);
          final id = int.tryParse(idPart);
          if (id == null) return true;
          return !items.any((e) => e.item == id);
        });
      }

      _setMemoryCache(filtered);
      // Persist in background so UI can return immediately.
      unawaited(_saveCartListToFirestore(filtered));
      return filtered;
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) {
        throw const ApiException(
            message: 'Session expired. Please log in again.');
      }
      final filtered = _withoutPendingDeletes(local);
      _setMemoryCache(filtered);
      return filtered;
    } catch (_) {
      final filtered = _withoutPendingDeletes(local);
      _setMemoryCache(filtered);
      return filtered;
    }
  }

  /// Remove:
  /// - removes from Firestore immediately
  /// - then hits backend DELETE /cart/:itemId
  ///
  /// IMPORTANT: if you can have same itemId across different merchants,
  /// pass merchantId from UI to remove the correct local doc.
  Future<void> removeFromCart(int itemId, {String? merchantId}) async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
          message: 'You need to be signed in to modify your cart.');
    }

    _rememberDelete(itemId, merchantId);

    if (merchantId != null && merchantId.isNotEmpty) {
      await _removeFromFirestoreByKey(itemId, merchantId);
    } else {
      // Fallback: if merchantId unknown, do a best-effort scan delete
      // (avoid heavy queries — but this is still safe).
      try {
        final userKey = await _userKey();
        if (userKey != null && userKey.isNotEmpty) {
          final col = _firestore
              .collection('backup_carts')
              .doc(userKey)
              .collection('items');
          final snap = await col.get();
          final batch = _firestore.batch();
          var any = false;
          for (final d in snap.docs) {
            final data = d.data();
            final raw = data['itemId'] ?? data['item'];
            final id = raw is num
                ? raw.toInt()
                : int.tryParse('${raw ?? ''}') ?? -1;
            if (id == itemId || d.id.startsWith('${itemId}_')) {
              batch.delete(d.reference);
              any = true;
            }
          }
          if (any) await batch.commit();
        }
      } catch (_) {}
    }

    try {
      await ApiClient.delete(
        '/cart/$itemId', // ✅ matches NestJS @Delete(':itemId')
        headers: _headers(token: token),
        timeout: _kApiTimeout,
      );
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) {
        throw const ApiException(
            message: 'Session expired. Please log in again.');
      }
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    } catch (e) {
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    }
  }

  /// Clear:
  /// - clears Firestore immediately
  /// - then hits backend DELETE /cart
  Future<void> clearCart() async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
          message: 'You need to be signed in to clear your cart.');
    }

    _cartEpoch++;
    _pendingDeletedKeys.clear();
    _memoryCache = <CartModel>[];

    await _clearCartInFirestore();

    try {
      await ApiClient.delete(
        '/cart', // ✅ matches NestJS @Delete()
        headers: _headers(token: token),
        timeout: _kApiTimeout,
      );
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) {
        throw const ApiException(
            message: 'Session expired. Please log in again.');
      }
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    } catch (e) {
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    }
  }
}
