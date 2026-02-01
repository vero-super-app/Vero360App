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

import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

import '../CartModel/cart_model.dart';

const _kApiTimeout = Duration(seconds: 10);
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

  // ---------------------------------------------------------------------------
  // AUTH + HEADERS
  // ---------------------------------------------------------------------------

  Future<String?> _getToken() async {
    final p = await SharedPreferences.getInstance();
    for (final k in const ['token', 'jwt_token', 'jwt']) {
      final v = p.getString(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

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

  String _docIdFor(CartModel item) => '${item.item}_${item.merchantId}';

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
    };
  }

  Future<void> _upsertCartItemInFirestore(CartModel item,
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

    await doc.set(
        _fsMap(item, pendingSync: pendingSync), SetOptions(merge: true));
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

      await _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items')
          .doc('${itemId}_$merchantId')
          .delete();
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
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<void> _saveCartListToFirestore(List<CartModel> items) async {
    try {
      final userKey = await _userKey();
      if (userKey == null || userKey.isEmpty) return;

      final col = _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items');

      // delete anything not in wanted
      final existing = await col.get();
      final wantedIds = items.map((e) => _docIdFor(e)).toSet();
      final batch = _firestore.batch();

      for (final doc in existing.docs) {
        if (!wantedIds.contains(doc.id)) batch.delete(doc.reference);
      }

      for (final it in items) {
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

      final snapshot = await _firestore
          .collection('backup_carts')
          .doc(userKey)
          .collection('items')
          .orderBy('updatedAt', descending: true)
          .get();

      int _int(Object? v, {int def = 0}) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse('${v ?? ''}') ?? def;
      }

      double _double(Object? v, {double def = 0}) {
        if (v is num) return v.toDouble();
        return double.tryParse('${v ?? ''}') ?? def;
      }

      return snapshot.docs.map((d) {
        final data = d.data();
        return CartModel(
          userId: userKey,
          item: _int(data['itemId'] ?? data['item']),
          quantity: _int(data['quantity'], def: 1),
          name: (data['name'] ?? '').toString(),
          image: (data['image'] ?? '').toString(),
          price: _double(data['price']),
          description: (data['description'] ?? '').toString(),
          comment: data['comment'] == null ? null : data['comment'].toString(),
          merchantId: (data['merchantId'] ?? '').toString(),
          merchantName: (data['merchantName'] ?? '').toString(),
          serviceType: (data['serviceType'] ?? 'marketplace').toString(),
        );
      }).toList();
    } catch (_) {
      return [];
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
    };
  }

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Offline-first:
  /// - writes to Firestore immediately (so UI is truthful)
  /// - syncs to backend in background
  Future<void> addToCart(CartModel cartItem) async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
          message: 'You need to be signed in to add items to cart.');
    }

    // ✅ must succeed
    await _upsertCartItemInFirestore(cartItem, pendingSync: true);

    // ✅ background sync
    unawaited(_syncAddToCart(token, cartItem));
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

  /// Fetch:
  /// - tries backend GET /cart/me
  /// - falls back to Firestore if backend is down or returns HTML
  /// - NEVER clears Firestore on 404 (route mismatch / server issues)
  Future<List<CartModel>> fetchCartItems() async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
          message: 'You need to be signed in to view your cart.');
    }

    final local = await _loadCartFromFirestore();

    try {
      final res = await ApiClient.get(
        '/cart/me', // ✅ matches NestJS @Get('me')
        headers: _headers(token: token),
        timeout: _kApiTimeout,
        allowedStatusCodes: {200, 404},
      );

      if (res.statusCode == 404) {
        // ✅ do NOT wipe local cart — return backup
        return local;
      }

      final bodyTrim = res.body.trimLeft().toLowerCase();
      if (bodyTrim.startsWith('<!doctype html') ||
          bodyTrim.startsWith('<html')) {
        // passenger/hosting html => treat as down
        return local;
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

      await _saveCartListToFirestore(items);
      return items;
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) {
        throw const ApiException(
            message: 'Session expired. Please log in again.');
      }
      return local;
    } catch (_) {
      return local;
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
          final snap = await col.where('itemId', isEqualTo: itemId).get();
          final batch = _firestore.batch();
          for (final d in snap.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
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
