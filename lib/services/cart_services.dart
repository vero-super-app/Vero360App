// lib/services/cart_services.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/api_exception.dart';

import '../models/cart_model.dart';

const _kApiTimeout = Duration(seconds: 10);
const _kWarmupTimeout = Duration(milliseconds: 900);
const _kWarmupCooldown = Duration(seconds: 45);

class CartService {
  // Keep this EXACT signature (you use it everywhere)
  CartService(String unused, {required String apiPrefix}) : _apiPrefix = apiPrefix;

  final String _apiPrefix; // kept for compatibility; ApiConfig already applies /vero

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Warmup throttling (fast + avoids spamming)
  static bool _warmedUp = false;
  static bool _warmupInFlight = false;
  static DateTime? _lastWarmupAttempt;

  // Cache the working POST endpoint once discovered
  static String? _workingPostCartEndpoint;

  // ---------------------------------------------------------------------------
  // BASIC HELPERS
  // ---------------------------------------------------------------------------

  Future<String?> _getToken() async {
    final p = await SharedPreferences.getInstance();
    for (final k in const ['token', 'jwt_token', 'jwt']) {
      final v = p.getString(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<String?> _getUserEmail() async {
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

  bool _looksLikeNotFound(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('404') ||
        msg.contains('not found') ||
        msg.contains('cannot post');
  }

  // ---------------------------------------------------------------------------
  // MINIMAL PAYLOAD (fix 413 forever)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _smallCartPayload(CartModel cartItem) {
    return <String, dynamic>{
      'item': cartItem.item,
      'quantity': cartItem.quantity,
      'merchantId': cartItem.merchantId,
      'serviceType': cartItem.serviceType,
    };
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE BACKUP HELPERS
  // Schema: backup_carts/{userEmail}/items/{itemId}
  // ---------------------------------------------------------------------------

  Future<void> _upsertCartItemInFirestore(CartModel item) async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      final doc = _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .doc(item.item.toString());

      await doc.set(
        {
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
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _removeFromFirestore(int itemId) async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      await _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .doc(itemId.toString())
          .delete();
    } catch (_) {}
  }

  Future<void> _clearCartInFirestore() async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      final col =
          _firestore.collection('backup_carts').doc(userId).collection('items');

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
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      final col =
          _firestore.collection('backup_carts').doc(userId).collection('items');

      final existing = await col.get();
      final wantedIds = items.map((e) => e.item.toString()).toSet();
      final batch = _firestore.batch();

      for (final doc in existing.docs) {
        if (!wantedIds.contains(doc.id)) batch.delete(doc.reference);
      }

      for (final it in items) {
        final docRef = col.doc(it.item.toString());
        batch.set(
          docRef,
          {
            'itemId': it.item,
            'name': it.name,
            'image': it.image,
            'price': it.price,
            'quantity': it.quantity,
            'description': it.description,
            'comment': it.comment,
            'merchantId': it.merchantId,
            'merchantName': it.merchantName,
            'serviceType': it.serviceType,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
    } catch (_) {}
  }

  Future<List<CartModel>> _loadCartFromFirestore() async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return [];

      final snapshot = await _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .get();

      return snapshot.docs.map((d) {
        final data = d.data();

        int _int(Object? v, {int def = 0}) {
          if (v is int) return v;
          if (v is num) return v.toInt();
          return int.tryParse('${v ?? ''}') ?? def;
        }

        double _double(Object? v, {double def = 0}) {
          if (v is num) return v.toDouble();
          return double.tryParse('${v ?? ''}') ?? def;
        }

        return CartModel(
          userId: userId,
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
  // CART API + OFFLINE MODE
  // ---------------------------------------------------------------------------

  Future<void> addToCart(CartModel cartItem) async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'You need to be signed in to add items to cart.');
    }

    // offline-first: save immediately
    await _upsertCartItemInFirestore(cartItem);

    // background sync
    unawaited(_syncAddToCart(token, cartItem));
  }

  Future<void> _syncAddToCart(String token, CartModel cartItem) async {
    final payload = _smallCartPayload(cartItem);
    final body = jsonEncode(payload);

    // If we already discovered working endpoint, use it
    final candidates = <String>[
      if (_workingPostCartEndpoint != null) _workingPostCartEndpoint!,
      '/cart',
      '/carts',
      '/cart/add',
      '/cart-items',
      '/cart/item',
    ].toSet().toList();

    for (final ep in candidates) {
      try {
        // ignore: avoid_print
        print('CART POST try=$ep bytes=${utf8.encode(body).length}');

        await ApiClient.post(
          ep, // ApiConfig will prefix /vero automatically
          headers: _headers(token: token),
          body: body,
          timeout: _kApiTimeout,
        );

        // ✅ success — remember it
        _workingPostCartEndpoint = ep;
        return;
      } on ApiException catch (e) {
        if (_looksLikeAuthError(e)) return;
        if (_looksLikePassengerHtmlOrDown(e)) return;

        // Not found => try next candidate
        if (_looksLikeNotFound(e)) continue;

        // Other errors: stop (don’t spam)
        return;
      } catch (e) {
        if (_looksLikePassengerHtmlOrDown(e)) return;
        // unknown error: stop
        return;
      }
    }
  }

  Future<List<CartModel>> fetchCartItems() async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'You need to be signed in to view your cart.');
    }

    final local = await _loadCartFromFirestore();

    try {
      final res = await ApiClient.get(
        '/cart',
        headers: _headers(token: token),
        timeout: _kApiTimeout,
        allowedStatusCodes: {200, 404},
      );

      if (res.statusCode == 404) {
        await _clearCartInFirestore();
        return <CartModel>[];
      }

      final bodyTrim = res.body.trimLeft().toLowerCase();
      if (bodyTrim.startsWith('<!doctype html') || bodyTrim.startsWith('<html')) {
        return local;
      }

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List ? decoded['data'] : <dynamic>[]);

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
        throw const ApiException(message: 'Session expired. Please log in again.');
      }
      return local;
    } catch (_) {
      return local;
    }
  }

  Future<void> removeFromCart(int itemId) async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'You need to be signed in to modify your cart.');
    }

    await _removeFromFirestore(itemId);

    try {
      await ApiClient.delete(
        '/cart/$itemId',
        headers: _headers(token: token),
        timeout: _kApiTimeout,
      );
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) {
        throw const ApiException(message: 'Session expired. Please log in again.');
      }
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    } catch (e) {
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    }
  }

  Future<void> clearCart() async {
    await warmup();

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'You need to be signed in to clear your cart.');
    }

    await _clearCartInFirestore();

    try {
      await ApiClient.delete(
        '/cart',
        headers: _headers(token: token),
        timeout: _kApiTimeout,
      );
    } on ApiException catch (e) {
      if (_looksLikeAuthError(e)) {
        throw const ApiException(message: 'Session expired. Please log in again.');
      }
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    } catch (e) {
      if (_looksLikePassengerHtmlOrDown(e)) return;
      return;
    }
  }
}
