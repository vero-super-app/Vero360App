// lib/services/cart_services.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_config.dart';

import '../models/cart_model.dart';

const _kFirstTimeout = Duration(seconds: 60);
const _kRetryTimeout = Duration(seconds: 30);

class CartService {
  static bool _warmedUp = false;

  CartService(String s, {required String apiPrefix});

 Future<String?> _getToken() async {
  final p = await SharedPreferences.getInstance();
  for (final k in const ['token', 'jwt_token', 'jwt']) {
    final v = p.getString(k);
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}


  Future<Uri> _uri(String path, {Map<String, String>? query}) async {
    final base = await ApiConfig.prod; 
    final origin = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalized = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse('$origin$normalized');
    return query == null ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  Map<String, String> _headers({String? token}) => {
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Connection': 'close',
        'User-Agent': 'Vero360App/Cart/1.0',
      };

  Future<http.Response> _withRetry(
    Future<http.Response> Function() run, {
    int retries = 3,
    List<Duration>? timeouts,
  }) async {
    Object? lastErr;
    for (var attempt = 0; attempt <= retries; attempt++) {
      final timeout = (timeouts != null && attempt < timeouts.length)
          ? timeouts[attempt]
          : _kRetryTimeout;
      try {
        final res = await run().timeout(timeout);
        return res;
      } on SocketException catch (e) {
        lastErr = e;
      } on http.ClientException catch (e) {
        lastErr = e;
      } on TimeoutException catch (e) {
        lastErr = e;
      }
      await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
    throw Exception('Network error after retries: $lastErr');
  }

  // ---------- Warmup ----------
  Future<void> warmup() async {
    if (_warmedUp) return;
    try {
      final h = await _uri('/healthz');
      final r = await http.get(h, headers: _headers()).timeout(_kFirstTimeout);
      // print('WARMUP /healthz => ${r.statusCode}');
      _warmedUp = true;
      return;
    } catch (_) {}
    try {
      final m = await _uri('/marketplace');
      final r = await http.get(m, headers: _headers()).timeout(_kFirstTimeout);
      // print('WARMUP /marketplace => ${r.statusCode}');
      _warmedUp = true;
    } catch (_) {}
  }

  // ---------- API ----------
  /// POST /cart  (server identifies user from Bearer token)
  Future<void> addToCart(CartModel cartItem) async {
    await warmup();
    final token = await _getToken();
    if (token == null) throw Exception('User not logged in');

    final uri = await _uri('/cart');

    final res = await _withRetry(
      () => http.post(
        uri,
        headers: _headers(token: token),
        body: jsonEncode({
          'item': cartItem.item,
          'quantity': cartItem.quantity,
          'image': cartItem.image,
          'name': cartItem.name,
          'price': cartItem.price,
          'description': cartItem.description,
      
        }),
      ),
      timeouts: const [_kFirstTimeout, _kRetryTimeout, _kRetryTimeout, _kRetryTimeout],
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to add to cart (${res.statusCode}): ${res.body}');
    }
  }

  /// GET /cart  (returns current user's cart; 404 => empty)
  Future<List<CartModel>> fetchCartItems() async {
    await warmup();
    final token = await _getToken();
    if (token == null) throw Exception('User not logged in');

    final uri = await _uri('/cart');

    final res = await _withRetry(
      () => http.get(uri, headers: _headers(token: token)),
      timeouts: const [_kFirstTimeout, _kRetryTimeout, _kRetryTimeout, _kRetryTimeout],
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List ? decoded['data'] : <dynamic>[]);
      return list.map<CartModel>((e) => CartModel.fromJson(e)).toList();
    }

    // Your backend returns 404 "No items in cart"
    if (res.statusCode == 404) return <CartModel>[];

    throw Exception('Failed to fetch cart (${res.statusCode}): ${res.body}');
  }

  /// DELETE /cart/:itemId
  Future<void> removeFromCart(int itemId) async {
    await warmup();
    final token = await _getToken();
    if (token == null) throw Exception('User not logged in');

    final uri = await _uri('/cart/$itemId');

    final res = await _withRetry(
      () => http.delete(uri, headers: _headers(token: token)),
      timeouts: const [_kFirstTimeout, _kRetryTimeout, _kRetryTimeout, _kRetryTimeout],
    );

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to remove item (${res.statusCode}): ${res.body}');
    }
  }

  /// DELETE /cart (if supported); if not, remove items one-by-one on the UI side
  Future<void> clearCart() async {
    await warmup();
    final token = await _getToken();
    if (token == null) throw Exception('User not logged in');

    final uri = await _uri('/cart');

    final res = await _withRetry(
      () => http.delete(uri, headers: _headers(token: token)),
      timeouts: const [_kFirstTimeout, _kRetryTimeout, _kRetryTimeout, _kRetryTimeout],
    );

    if (res.statusCode != 200 && res.statusCode != 204) {
      // If your backend doesn’t support DELETE /cart, surface a clean error.
      throw Exception('Clear cart not supported (${res.statusCode}): ${res.body}');
    }
  }
}
