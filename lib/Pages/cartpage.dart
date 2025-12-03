// lib/Pages/cartpage.dart
import 'dart:async';
import 'dart:convert'; // for base64 image support
import 'dart:math';
import 'dart:typed_data'; // 👈 needed for Uint8List

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/Pages/checkout_from_cart_page.dart';

import 'package:vero360_app/models/cart_model.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/toasthelper.dart';

class CartPage extends StatefulWidget {
  final CartService cartService;
  const CartPage({required this.cartService, Key? key}) : super(key: key);

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late Future<List<CartModel>> _cartFuture;
  final List<CartModel> _items = [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _cartFuture = _fetch();
  }

  Future<bool> _hasToken() async {
    final sp = await SharedPreferences.getInstance();
    final t =
        sp.getString('token') ?? sp.getString('jwt_token') ?? sp.getString('jwt');
    return t != null && t.isNotEmpty;
  }

  Future<List<CartModel>> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await _hasToken()) {
        _items.clear();
        ToastHelper.showCustomToast(
          context,
          'Please log in to view your cart.',
          isSuccess: false,
          errorMessage: 'Not logged in',
        );
        return _items;
      }

      final data = await widget.cartService.fetchCartItems();
      _items
        ..clear()
        ..addAll(data);
      return _items;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('404') ||
          msg.toLowerCase().contains('no items in cart')) {
        _items.clear();
        return _items;
      }
      _error = msg;
      ToastHelper.showCustomToast(
        context,
        'Error loading cart',
        isSuccess: false,
        errorMessage: msg,
      );
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _cartFuture = _fetch());
    await _cartFuture;
  }

  double get _subtotal =>
      _items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));

  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  Future<void> _remove(CartModel item) async {
    if (item.item <= 0) {
      ToastHelper.showCustomToast(
        context,
        'Invalid cart item id.',
        isSuccess: false,
        errorMessage: 'item <= 0',
      );
      return;
    }

    final idx = _items.indexWhere((x) => x.item == item.item);
    if (idx == -1) return;
    final backup = _items[idx];
    setState(() => _items.removeAt(idx));

    try {
      await widget.cartService.removeFromCart(item.item);
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Removed ${item.name}',
          isSuccess: true,
          errorMessage: 'OK',
        );
      }
    } catch (e) {
      setState(() => _items.insert(idx, backup));
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Failed to remove item',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }
  }

  Future<void> _changeQty(CartModel item, int newQty) async {
    newQty = max(0, min(99, newQty));
    if (newQty == item.quantity) return;
    if (newQty == 0) return _remove(item);

    if (item.item <= 0) {
      ToastHelper.showCustomToast(
        context,
        'Invalid cart item id.',
        isSuccess: false,
        errorMessage: 'item <= 0',
      );
      return;
    }

    final idx = _items.indexWhere((x) => x.item == item.item);
    if (idx == -1) return;
    final backup = _items[idx];
    setState(() => _items[idx] = backup.copyWith(quantity: newQty));

    try {
      // Server upserts on POST /cart
      await widget.cartService.addToCart(
        CartModel(
          userId: backup.userId,
          item: item.item, // int, positive
          quantity: newQty,
          name: item.name,
          image: item.image,
          price: item.price,
          description: item.description,
          comment: item.comment,
        ),
      );
    } catch (e) {
      setState(() => _items[idx] = backup);
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Failed to update quantity',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }
  }

  Future<void> _clearCart() async {
    if (_items.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('Remove all items from your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await widget.cartService.clearCart();
      setState(() => _items.clear());
      ToastHelper.showCustomToast(
        context,
        'Cart cleared',
        isSuccess: true,
        errorMessage: 'OK',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Failed to clear cart',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _proceedToCheckout() async {
    if (!await _hasToken()) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to checkout.',
        isSuccess: false,
        errorMessage: 'Not logged in',
      );
      return;
    }
    if (_items.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Your cart is empty.',
        isSuccess: false,
        errorMessage: 'Empty cart',
      );
      return;
    }

    // Pass a copy so the checkout page can mutate locally if it needs to
    final itemsForCheckout = List<CartModel>.from(_items);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutFromCartPage(items: itemsForCheckout),
      ),
    );

    // After returning from checkout, refresh in case the cart changed
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final deliveryFee = _items.isEmpty ? 0.0 : 20.0;
    final discount = 0.0;
    final total = _subtotal + deliveryFee + discount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Clear cart',
            onPressed: _items.isEmpty ? null : _clearCart,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CartModel>>(
          future: _cartFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                _items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError && _items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Error loading cart:\n${_error ?? snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }

            if (_items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Your cart is empty',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, i) => _CartItemTile(
                      item: _items[i],
                      onInc: () =>
                          _changeQty(_items[i], _items[i].quantity + 1),
                      onDec: () =>
                          _changeQty(_items[i], _items[i].quantity - 1),
                      onRemove: () => _remove(_items[i]),
                    ),
                  ),
                ),
                _CartSummary(
                  subtotal: _subtotal,
                  deliveryFee: deliveryFee,
                  discount: discount,
                  total: total,
                  loading: _loading,
                  onCheckout: _proceedToCheckout,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.onInc,
    required this.onDec,
    required this.onRemove,
  });

  final CartModel item;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onRemove;

  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  /// Debug helper so we can see what image string we're getting
  void _debugLogImage() {
    if (item.image.isEmpty) {
      // ignore: avoid_print
      print('[CartPage] image EMPTY for "${item.name}" (itemId=${item.item})');
    } else {
      final short = item.image.length > 80
          ? item.image.substring(0, 80)
          : item.image;
      // ignore: avoid_print
      print('[CartPage] image for "${item.name}" (itemId=${item.item}): $short');
    }
  }

  /// Try to decode a base64 image string.
  /// Supports both plain base64 and data URLs like "data:image/jpeg;base64,..."
  Uint8List? _decodeBase64Image(String v) {
    if (v.isEmpty) return null;

    // If it looks like a normal URL, don't even try base64
    final lower = v.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return null;
    }

    try {
      var cleaned = v.trim();

      // If it is a data URL: data:image/jpeg;base64,XXXXX
      final commaIndex = cleaned.indexOf(',');
      if (cleaned.startsWith('data:image') && commaIndex != -1) {
        cleaned = cleaned.substring(commaIndex + 1);
      }

      return base64Decode(cleaned);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _debugLogImage(); // 👈 log what we're receiving

    Widget imageWidget;

    if (item.image.isEmpty) {
      // No image at all
      imageWidget = const ColoredBox(
        color: Color(0xFFEAEAEA),
        child: Icon(Icons.image_not_supported, size: 40),
      );
    } else {
      // 1) Try base64 first (unless it's clearly a URL)
      final bytes = _decodeBase64Image(item.image);

      if (bytes != null) {
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
        );
      } else {
        // 2) Fallback: treat as normal URL (http/https/whatever)
        imageWidget = Image.network(
          item.image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0xFFEAEAEA),
            child: Icon(Icons.broken_image, size: 40),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 80,
              height: 80,
              child: imageWidget,
            ),
          ),
          const SizedBox(width: 12),

          // details
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _mwk(item.price),
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // qty controls
                  Row(
                    children: [
                      _IconBtn(icon: Icons.remove, onTap: onDec),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _IconBtn(icon: Icons.add, onTap: onInc),
                      const Spacer(),
                      IconButton(
                        onPressed: onRemove,
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.loading,
    required this.onCheckout,
  });

  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;
  final bool loading;
  final VoidCallback onCheckout;

  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          children: [
            _row('Subtotal', _mwk(subtotal)),
            _row('Delivery Fee', _mwk(deliveryFee)),
            const Divider(height: 16),
            _row('Total', _mwk(total), bold: true, green: true),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : onCheckout,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFFFF8A00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  loading ? 'Please wait…' : 'Checkout',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, bool green = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: green ? Colors.green : Colors.black87,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
