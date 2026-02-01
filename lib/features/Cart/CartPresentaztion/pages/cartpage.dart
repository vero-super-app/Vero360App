// lib/Pages/cartpage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // ✅ ADD (commas formatter)

import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/utils/toasthelper.dart';

// ✅ ONE global formatter (commas)
// If you want decimals, change decimalDigits: 2
final NumberFormat _mwkFmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
String mwk(num n) => _mwkFmt.format(n);

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

  // Firebase services
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _cartFuture = _fetch();
  }

  /// Check if user has a valid session
  Future<bool> _hasSession() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString('token') ??
        sp.getString('jwt_token') ??
        sp.getString('jwt');
    final email = sp.getString('email');
    final uid = _auth.currentUser?.uid;
    return (t != null && t.isNotEmpty) ||
        (email != null && email.isNotEmpty) ||
        (uid != null && uid.isNotEmpty);
  }

  /// Get current user ID for Firestore
  Future<String?> _getCurrentUserId() async {
    final user = _auth.currentUser;
    if (user != null) return user.uid;

    final sp = await SharedPreferences.getInstance();
    final email = sp.getString('email');
    return email;
  }

  // -------- FIREBASE BACKUP HELPERS (UPDATED) --------

  Future<void> _saveCartToFirestore(List<CartModel> items) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null || userId.isEmpty) return;

      final col = _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items');

      final batch = _firestore.batch();

      // Clear existing
      final existing = await col.get();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }

      // Write fresh with merchant info
      for (final item in items) {
        final docRef = col.doc('${item.item}_${item.merchantId}');
        batch.set(docRef, {
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
        });
      }

      await batch.commit();
    } catch (e) {
      // ignore
    }
  }

  Future<List<CartModel>> _loadCartFromFirestore() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null || userId.isEmpty) return [];

      final snapshot = await _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .orderBy('updatedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();

        final rawItemId = data['itemId'] ?? data['item'];
        final itemId = rawItemId is num
            ? rawItemId.toInt()
            : int.tryParse(rawItemId.toString()) ?? 0;

        final rawQty = data['quantity'];
        final quantity =
            rawQty is num ? rawQty.toInt() : int.tryParse(rawQty.toString()) ?? 1;

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
      final userId = await _getCurrentUserId();
      if (userId == null || userId.isEmpty) return;

      final doc = _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .doc('${item.item}_${item.merchantId}');

      await doc.set({
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
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _removeFromFirestore(CartModel item) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null || userId.isEmpty) return;

      final doc = _firestore
          .collection('backup_carts')
          .doc(userId)
          .collection('items')
          .doc('${item.item}_${item.merchantId}');
      await doc.delete();
    } catch (_) {}
  }

  // -------- MAIN FETCH (UPDATED FOR MERCHANT INFO) --------
  Future<List<CartModel>> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!await _hasSession()) {
        _items.clear();
        ToastHelper.showCustomToast(
          context,
          'Please log in to view your cart.',
          isSuccess: false,
          errorMessage: 'Not logged in',
        );
        return _items;
      }

      try {
        // 1) Try main backend (NestJS)
        final data = await widget.cartService.fetchCartItems();

        // Validate merchant info
        final validatedItems =
            data.where((item) => item.hasValidMerchant).toList();

        _items
          ..clear()
          ..addAll(validatedItems);

        // 2) Mirror to Firebase backup
        await _saveCartToFirestore(_items);

        return _items;
      } catch (_) {
        // Fallback to Firebase backup
        final backup = await _loadCartFromFirestore();
        _items
          ..clear()
          ..addAll(backup);

        ToastHelper.showCustomToast(
          context,
          backup.isEmpty
              ? 'Unable to load cart. Please check your connection.'
              : 'Showing your last saved cart from backup.',
          isSuccess: backup.isNotEmpty,
          errorMessage: backup.isEmpty ? 'No backup available' : '',
        );
        return _items;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------- CART OPERATIONS (UPDATED) --------

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

    final idx = _items.indexWhere(
        (x) => x.item == item.item && x.merchantId == item.merchantId);
    if (idx == -1) return;

    final backup = _items[idx];
    setState(() => _items.removeAt(idx));

    try {
      await widget.cartService.removeFromCart(item.item);
      await _removeFromFirestore(backup);

      ToastHelper.showCustomToast(
        context,
        'Removed ${item.name}',
        isSuccess: true,
        errorMessage: 'OK',
      );
    } catch (e) {
      setState(() => _items.insert(idx, backup));
      ToastHelper.showCustomToast(
        context,
        'Failed to remove item',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _changeQty(CartModel item, int newQty) async {
    newQty = max(1, min(99, newQty));
    if (newQty == item.quantity) return;

    final idx = _items.indexWhere(
        (x) => x.item == item.item && x.merchantId == item.merchantId);
    if (idx == -1) return;

    final old = _items[idx];
    final updated = old.copyWith(quantity: newQty);

    setState(() => _items[idx] = updated);

    try {
      await widget.cartService.addToCart(updated);
      await _upsertCartItemInFirestore(updated);
    } catch (e) {
      setState(() => _items[idx] = old);
      ToastHelper.showCustomToast(
        context,
        'Failed to update quantity',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  // -------- CHECKOUT VALIDATION --------
  Future<void> _proceedToCheckout() async {
    if (!await _hasSession()) {
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

    final invalidItems = _items.where((item) => !item.hasValidMerchant).toList();
    if (invalidItems.isNotEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Some items are missing merchant information. Please remove them.',
        isSuccess: false,
        errorMessage: 'Invalid merchant info',
      );
      return;
    }

    final itemKeys = <String>{};
    final duplicates = <CartModel>[];

    for (final item in _items) {
      final key = '${item.item}_${item.merchantId}';
      if (itemKeys.contains(key)) duplicates.add(item);
      itemKeys.add(key);
    }

    if (duplicates.isNotEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Duplicate items found. Please update your cart.',
        isSuccess: false,
        errorMessage: 'Duplicate items',
      );
      return;
    }

    final itemsForCheckout = List<CartModel>.from(_items);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutFromCartPage(items: itemsForCheckout),
      ),
    );

    if (mounted) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _cartFuture = _fetch());
    await _cartFuture;
  }

  // Helper to calculate totals
  double get _subtotal =>
      _items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));

  // Helper to group items by merchant (for display)
  Map<String, List<CartModel>> get _itemsByMerchant {
    final Map<String, List<CartModel>> groups = {};
    for (final item in _items) {
      if (!groups.containsKey(item.merchantId)) {
        groups[item.merchantId] = [];
      }
      groups[item.merchantId]!.add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final deliveryFee = _items.isEmpty ? 0.0 : 20.0;
    final discount = 0.0;
    final total = _subtotal + deliveryFee + discount;

    final merchantGroups = _itemsByMerchant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh cart',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
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

            if (_items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Your cart is empty',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                if (merchantGroups.length > 1)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.store, size: 20, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Items from ${merchantGroups.length} merchants',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final merchantId in merchantGroups.keys)
                        _MerchantGroupSection(
                          merchantName:
                              merchantGroups[merchantId]!.first.merchantName,
                          items: merchantGroups[merchantId]!,
                          onInc: (item) =>
                              _changeQty(item, item.quantity + 1),
                          onDec: (item) =>
                              _changeQty(item, item.quantity - 1),
                          onRemove: _remove,
                        ),
                    ],
                  ),
                ),
                _CartSummary(
                  subtotal: _subtotal,
                  deliveryFee: deliveryFee,
                  discount: discount,
                  total: total,
                  loading: _loading,
                  merchantCount: merchantGroups.length,
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

// Merchant Group Section Widget
class _MerchantGroupSection extends StatelessWidget {
  final String merchantName;
  final List<CartModel> items;
  final Function(CartModel) onInc;
  final Function(CartModel) onDec;
  final Function(CartModel) onRemove;

  const _MerchantGroupSection({
    required this.merchantName,
    required this.items,
    required this.onInc,
    required this.onDec,
    required this.onRemove,
  });

  double get merchantTotal =>
      items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Merchant Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.store, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  merchantName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              // ✅ COMMAS
              Text(
                mwk(merchantTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),

        ...items.map((item) => _CartItemTile(
              item: item,
              onInc: () => onInc(item),
              onDec: () => onDec(item),
              onRemove: () => onRemove(item),
            )),

        const SizedBox(height: 8),
      ],
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

  void _debugLogImage() {
    if (item.image.isEmpty) {
      // ignore
    }
  }

  Uint8List? _decodeBase64Image(String v) {
    if (v.isEmpty) return null;
    final lower = v.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return null;

    try {
      var cleaned = v.trim().replaceAll(RegExp(r'\s+'), '');
      final commaIndex = cleaned.indexOf(',');
      if (cleaned.startsWith('data:image') && commaIndex != -1) {
        cleaned = cleaned.substring(commaIndex + 1);
      }
      final mod = cleaned.length % 4;
      if (mod != 0) cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
      final bytes = base64Decode(cleaned);
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder() {
    return const ColoredBox(
      color: Color(0xFFEAEAEA),
      child: Icon(Icons.image_not_supported, size: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    _debugLogImage();

    Widget imageWidget;
    if (item.image.isEmpty) {
      imageWidget = _placeholder();
    } else {
      final lower = item.image.toLowerCase();
      final isUrl = lower.startsWith('http://') || lower.startsWith('https://');

      if (isUrl) {
        imageWidget = Image.network(
          item.image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } else {
        final bytes = _decodeBase64Image(item.image);
        imageWidget = bytes != null
            ? Image.memory(bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder())
            : _placeholder();
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 80,
              height: 80,
              child: imageWidget,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                // ✅ COMMAS
                Text(
                  mwk(item.price),
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
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
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Merchant: ${item.merchantName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
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
      color: Colors.black.withValues(alpha: 0.05),
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
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;
  final bool loading;
  final int merchantCount;
  final VoidCallback onCheckout;

  const _CartSummary({
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.loading,
    required this.merchantCount,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          children: [
            if (merchantCount > 1)
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.orange[800]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Payment will be split between $merchantCount merchants',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ✅ COMMAS everywhere
            _row('Subtotal', mwk(subtotal)),
            _row('Delivery Fee', mwk(deliveryFee)),
            const Divider(height: 16),
            _row('Total', mwk(total), bold: true, green: true),
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
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Checkout',
                        style: TextStyle(fontSize: 16),
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
