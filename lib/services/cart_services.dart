// lib/services/cart_services.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_config.dart';
import 'package:vero360_app/services/api_exception.dart';

import '../models/cart_model.dart';

const _kFirstTimeout = Duration(seconds: 60);

class CartService {
  static bool _warmedUp = false;

  // Keep signature for compatibility (we ignore the params).
  CartService(String unused, {required String apiPrefix});

  Future<String?> _getToken() async {
    final p = await SharedPreferences.getInstance();
    for (final k in const ['token', 'jwt_token', 'jwt']) {
      final v = p.getString(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<void> warmup() async {
    if (_warmedUp) return;
    try {
      await ApiConfig.ensureBackendUp(timeout: _kFirstTimeout);
      _warmedUp = true;
    } catch (_) {
      // ignore warmup failures; real requests will handle errors via ApiClient
    }
  }

  Map<String, String> _headers({String? token}) => {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Connection': 'close',
        'User-Agent': 'Vero360App/Cart/1.0',
      };

  /// POST /cart (server identifies user from Bearer token)
  Future<void> addToCart(CartModel cartItem) async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to add items to cart.',
      );
    }

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
      }),
      timeout: _kFirstTimeout,
    );
  }

  /// GET /cart  (returns current user's cart; 404 => empty)
  Future<List<CartModel>> fetchCartItems() async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to view your cart.',
      );
    }

    final res = await ApiClient.get(
      '/cart',
      headers: _headers(token: token),
      timeout: _kFirstTimeout,
      allowedStatusCodes: {200, 404},
    );

    if (res.statusCode == 404) {
      // Your backend: 404 == "no items"
      return <CartModel>[];
    }

    final decoded = jsonDecode(res.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List ? decoded['data'] : <dynamic>[]);

    return list.map<CartModel>((e) => CartModel.fromJson(e)).toList();
  }

  /// DELETE /cart/:itemId
  Future<void> removeFromCart(int itemId) async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to modify your cart.',
      );
    }

    await ApiClient.delete(
      '/cart/$itemId',
      headers: _headers(token: token),
      timeout: _kFirstTimeout,
    );
  }

  /// DELETE /cart (clear everything, if backend supports it)
  Future<void> clearCart() async {
    await warmup();
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'You need to be signed in to clear your cart.',
      );
    }

    await ApiClient.delete(
      '/cart',
      headers: _headers(token: token),
      timeout: _kFirstTimeout,
    );
  }
}
  