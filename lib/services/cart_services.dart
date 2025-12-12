// lib/services/cart_services.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/api_exception.dart';

import '../models/cart_model.dart';

const _kFirstTimeout = Duration(seconds: 60);

class CartService {
  static bool _warmedUp = false;

  CartService(String unused, {required String apiPrefix});

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  bool _looksLikeServiceUnavailable(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('service is temporarily unavailable') ||
        msg.contains('503') ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable');
  }

  Future<void> warmup() async {
    if (_warmedUp) return;
    try {
      await ApiConfig.ensureBackendUp(timeout: _kFirstTimeout);
      _warmedUp = true;
    } catch (_) {}
  }

  Map<String, String> _headers({String? token}) => {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Connection': 'close',
        'User-Agent': 'Vero360App/Cart/1.0',
      };

  // ---------------------------------------------------------------------------
  // FIRESTORE BACKUP HELPERS - UPDATED WITH MERCHANT FIELDS
  // Schema: backup_carts/{userEmail}/items/{itemId}
  // ---------------------------------------------------------------------------

  Future<void> _saveCartListToFirestore(List<CartModel> items) async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      final col =
          _firestore.collection('backup_carts').doc(userId).collection('items');

      final batch = _firestore.batch();

      final existing = await col.get();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }

      for (final it in items) {
        final docRef = col.doc(it.item.toString());
        batch.set(docRef, {
          'itemId': it.item,
          'name': it.name,
          'image': it.image,
          'price': it.price,
          'quantity': it.quantity,
          'description': it.description,
          'comment': it.comment,
          // NEW: Merchant fields for wallet integration
          'merchantId': it.merchantId,
          'merchantName': it.merchantName,
          'serviceType': it.serviceType,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (_) {
      // never crash UI because of backup issues
    }
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

        final rawItemId = data['itemId'] ?? data['item'];
        final itemId = rawItemId is num
            ? rawItemId.toInt()
            : int.tryParse(rawItemId.toString()) ?? 0;

        final rawQty = data['quantity'];
        final quantity = rawQty is num
            ? rawQty.toInt()
            : int.tryParse(rawQty.toString()) ?? 1;

        final rawPrice = data['price'];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice.toString()) ?? 0.0;

        return CartModel(
          userId: userId,
          item: itemId,
          quantity: quantity,
          name: (data['name'] ?? '').toString(),
          image: (data['image'] ?? '').toString(),
          price: price,
          description: (data['description'] ?? '').toString(),
          comment: (data['comment'] ?? '').toString(),
          // NEW: Load merchant fields from Firestore
          merchantId: (data['merchantId'] ?? '').toString(),
          merchantName: (data['merchantName'] ?? '').toString(),
          serviceType: (data['serviceType'] ?? 'marketplace').toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _upsertCartItemInFirestore(CartModel item) async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      final doc = _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .doc(item.item.toString());

      await doc.set({
        'itemId': item.item,
        'name': item.name,
        'image': item.image,
        'price': item.price,
        'quantity': item.quantity,
        'description': item.description,
        'comment': item.comment,
        // NEW: Merchant fields for wallet integration
        'merchantId': item.merchantId,
        'merchantName': item.merchantName,
        'serviceType': item.serviceType,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _removeFromFirestore(int itemId) async {
    try {
      final userId = await _getUserEmail();
      if (userId == null || userId.isEmpty) return;

      final doc = _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .doc(itemId.toString());

      await doc.delete();
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

  // ---------------------------------------------------------------------------
  // API + FIREBASE BACKUP METHODS - UPDATED WITH MERCHANT FIELDS
  // ---------------------------------------------------------------------------

  /// POST /cart (server identifies user from Bearer token)
  /// If backend is unavailable, we still upsert into Firestore and return OK.
  Future<void> addToCart(CartModel cartItem) async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to add items to cart.',
      );
    }

    try {
      // UPDATED: Include merchant fields in API request
      await ApiClient.post(
        '/cart',
        headers: _headers(token: token),
        body: jsonEncode({
          'item': cartItem.item,
          'quantity': cartItem.quantity,
          'image': cartItem.image,
          'name': cartItem.name,
          'price': cartItem.price,
          'description': cartItem.description,
          // NEW: Merchant fields for wallet integration
          'merchantId': cartItem.merchantId,
          'merchantName': cartItem.merchantName,
          'serviceType': cartItem.serviceType,
          if (cartItem.comment != null) 'comment': cartItem.comment,
        }),
        timeout: _kFirstTimeout,
      );

      // Mirror to Firebase when API works (now includes merchant fields)
      await _upsertCartItemInFirestore(cartItem);
    } on ApiException catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        // Backend down → save to Firebase only (offline backup with merchant fields)
        await _upsertCartItemInFirestore(cartItem);
        return;
      }
      rethrow;
    } catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        await _upsertCartItemInFirestore(cartItem);
        return;
      }
      rethrow;
    }
  }

  /// GET /cart (returns current user's cart; 404 => empty)
  /// Falls back to Firebase backup if server is unavailable.
  Future<List<CartModel>> fetchCartItems() async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to view your cart.',
      );
    }

    try {
      final res = await ApiClient.get(
        '/cart',
        headers: _headers(token: token),
        timeout: _kFirstTimeout,
        allowedStatusCodes: {200, 404},
      );

      if (res.statusCode == 404) {
        // Backend says "no items" => clear backup as well
        await _clearCartInFirestore();
        return <CartModel>[];
      }

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      // UPDATED: CartModel.fromJson now handles merchant fields automatically
      final items =
          list.map<CartModel>((e) => CartModel.fromJson(e)).toList();

      // Keep Firebase backup synced (now includes merchant fields)
      await _saveCartListToFirestore(items);
      return items;
    } on ApiException catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        // Use last known Firebase backup (now includes merchant fields)
        return await _loadCartFromFirestore();
      }
      rethrow;
    } catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        return await _loadCartFromFirestore();
      }
      rethrow;
    }
  }

  /// DELETE /cart/:itemId
  /// If backend is unavailable, we still remove from Firebase backup.
  Future<void> removeFromCart(int itemId) async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to modify your cart.',
      );
    }

    try {
      await ApiClient.delete(
        '/cart/$itemId',
        headers: _headers(token: token),
        timeout: _kFirstTimeout,
      );

      await _removeFromFirestore(itemId);
    } on ApiException catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        await _removeFromFirestore(itemId);
        return;
      }
      rethrow;
    } catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        await _removeFromFirestore(itemId);
        return;
      }
      rethrow;
    }
  }

  /// DELETE /cart (clear everything, if backend supports it)
  /// If backend is unavailable, we still clear the Firebase backup.
  Future<void> clearCart() async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to clear your cart.',
      );
    }

    try {
      await ApiClient.delete(
        '/cart',
        headers: _headers(token: token),
        timeout: _kFirstTimeout,
      );

      await _clearCartInFirestore();
    } on ApiException catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        await _clearCartInFirestore();
        return;
      }
      rethrow;
    } catch (e) {
      if (_looksLikeServiceUnavailable(e)) {
        await _clearCartInFirestore();
        return;
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // NEW HELPER METHODS FOR MERCHANT WALLET INTEGRATION
  // ---------------------------------------------------------------------------

  /// Helper to validate cart items have merchant info for wallet payments
  Future<bool> validateCartForCheckout() async {
    try {
      final items = await fetchCartItems();
      if (items.isEmpty) return false;

      // Check if all items have valid merchant information
      for (final item in items) {
        if (!item.hasValidMerchant) {
          print('Cart validation failed: Item "${item.name}" missing valid merchant info');
          return false;
        }
      }

      // Check for duplicate items from same merchant
      final itemKeys = <String>{};
      for (final item in items) {
        final key = '${item.item}_${item.merchantId}';
        if (itemKeys.contains(key)) {
          print('Cart validation failed: Duplicate item $key');
          return false;
        }
        itemKeys.add(key);
      }

      return true;
    } catch (e) {
      print('Cart validation error: $e');
      return false;
    }
  }

  /// Helper to get cart total for checkout
  Future<double> getCartTotal() async {
    try {
      final items = await fetchCartItems();
      return items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
    } catch (e) {
      return 0.0;
    }
  }

  /// Helper to group items by merchant for wallet payments
  Future<Map<String, List<CartModel>>> getItemsByMerchant() async {
    try {
      final items = await fetchCartItems();
      final Map<String, List<CartModel>> merchantGroups = {};

      for (final item in items) {
        final merchantKey = '${item.merchantId}_${item.serviceType}';
        if (!merchantGroups.containsKey(merchantKey)) {
          merchantGroups[merchantKey] = [];
        }
        merchantGroups[merchantKey]!.add(item);
      }

      return merchantGroups;
    } catch (e) {
      return {};
    }
  }
}