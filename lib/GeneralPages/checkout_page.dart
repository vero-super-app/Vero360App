// lib/Pages/checkout_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GeneralPages/address.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

enum DeliveryType { speed, cts, pickup }

class CheckoutPage extends StatefulWidget {
  final MarketplaceDetailModel item;
  const CheckoutPage({required this.item, Key? key}) : super(key: key);

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  // ► Brand (UI only)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFE8CC);

  // ► Delivery fees (edit as you want)
  static const double _feeSpeed = 0; // e.g. 2500
  static const double _feeCts = 0; // e.g. 1500
  static const double _feePickup = 0;

  DeliveryType _deliveryType = DeliveryType.cts;

  int _qty = 1;
  bool _submitting = false;

  // Address
  final _addrSvc = AddressService();
  Address? _defaultAddr;
  bool _loadingAddr = true;
  bool _loggedIn = false;
  String? _pickupLocation; // merchant/shop address for pickup

  // Money formatter (MWK)
  late final NumberFormat _mwkFmt =
      NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
  String _mwk(num v) => _mwkFmt.format(v);

  double get _subtotal => widget.item.price * _qty;

  double get _delivery {
    switch (_deliveryType) {
      case DeliveryType.speed:
        return _feeSpeed;
      case DeliveryType.cts:
        return _feeCts;
      case DeliveryType.pickup:
        return _feePickup;
    }
  }

  double get _total => _subtotal + _delivery;

  @override
  void initState() {
    super.initState();
    _initAuthAndAddress();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── UI helpers ──────────────────────────────────────────────────────────
  InputDecoration _inputDecoration({
    String? label,
    String? hint,
    Widget? prefixIcon,
    String? helper,
    String? error,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2, // ✅ prevent helper overflow
      errorText: error,
      errorMaxLines: 2, // ✅ prevent error overflow
      filled: true,
      fillColor: Colors.white,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }

  ButtonStyle _filledBtnStyle() => FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      );

  OutlinedButtonThemeData get _outlinedTheme => OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.black, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );

  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Delivery helpers ─────────────────────────────────────────────────────
  String _deliveryLabel(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return 'Speed';
      case DeliveryType.cts:
        return 'CTS';
      case DeliveryType.pickup:
        return 'Pickup';
    }
  }

  // ✅ Rich dropdown menu item (2 lines) — used ONLY in the dropdown menu
  Widget _deliveryMenuItem({
    required String title,
    required String subtitle,
    required String trailing,
    required IconData icon,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    final middleMaxW = (w * 0.45).clamp(120.0, 210.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _brandSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _brandOrange.withOpacity(0.25)),
            ),
            child: Icon(icon, size: 18, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: middleMaxW),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, height: 1.05),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.05),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Compact single-line selected item — used inside the closed field (fixes bottom overflow)
  Widget _deliverySelectedItem({
    required String title,
    required String trailing,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _brandSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _brandOrange.withOpacity(0.25)),
          ),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  // ── Auth + Default address bootstrap (single source: Firebase then SP) ───
  Future<String?> _readAuthToken() async => AuthHandler.getTokenForApi();

  Future<void> _initAuthAndAddress() async {
    // When pickup is selected we will show merchant address instead of user address.
    _pickupLocation = widget.item.location.trim().isEmpty
        ? widget.item.sellerBusinessName
        : widget.item.location.trim();

    setState(() {
      _loadingAddr = true;
      _defaultAddr = null;
      _loggedIn = false;
    });

    final token = await _readAuthToken();
    if (!mounted) return;

    if (token == null) {
      setState(() {
        _loggedIn = false;
        _loadingAddr = false;
      });
      return;
    }

    try {
      final list = await _addrSvc.getMyAddresses();

      Address? def;
      for (final a in list) {
        if (a.isDefault) {
          def = a;
          break;
        }
      }

      setState(() {
        _loggedIn = true;
        _defaultAddr = def;
        _loadingAddr = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _defaultAddr = null;
        _loadingAddr = false;
      });
    }
  }

  Future<bool> _ensureDefaultAddressIfNeeded() async {
    // For shop pickup we do not require a customer delivery address.
    if (_deliveryType == DeliveryType.pickup) return true;

    if (!_loggedIn) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to continue.',
        isSuccess: false,
        errorMessage: 'Auth required',
      );
      return false;
    }
    if (_defaultAddr != null) return true;

    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delivery address required'),
        content: const Text('You need to set a default address before checkout.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set address')),
        ],
      ),
    );

    if (go == true) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
      await _initAuthAndAddress();
      return _defaultAddr != null;
    }
    return false;
  }

  Future<bool> _requireLogin() async {
    final t = await _readAuthToken();
    final ok = t != null;
    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to complete checkout.',
        isSuccess: false,
        errorMessage: 'Not logged in',
      );
    }
    return ok;
  }

  // ── Pay routing (Paychangu handles card/mobile on their page) ─────────────
  Future<void> _onPayPressed() async {
    if (!await _requireLogin()) return;
    if (!await _ensureDefaultAddressIfNeeded()) return;
    await _startPayChanguPayment();
  }

  // ── Paychangu API (same flow as checkout_from_cart_page) ─────────────────
  static const String _paychanguApiUrl = 'https://api.paychangu.com/payment';
  static const String _paychanguBearer = 'Bearer SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u';

  Future<void> _startPayChanguPayment() async {
    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('email') ?? 'customer@example.com';
      final name = prefs.getString('name') ?? 'Customer';
      final phoneNumber = prefs.getString('phone') ?? '+265888000000';

      final parts = name.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : 'Customer';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';

      try {
        await InternetAddress.lookup('api.paychangu.com');
      } on SocketException catch (_) {
        throw Exception('Cannot connect to payment service. Please check your internet connection.');
      }

      final addrText = _deliveryType == DeliveryType.pickup
          ? 'Pickup'
          : 'Deliver to: ${_defaultAddr?.city ?? '-'}';
      final description =
          'Order: ${widget.item.name} (x$_qty) • Delivery: ${_deliveryLabel(_deliveryType)} • $addrText';

      final response = await http
          .post(
            Uri.parse(_paychanguApiUrl),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': _paychanguBearer,
            },
            body: json.encode({
              'tx_ref': txRef,
              'first_name': firstName,
              'last_name': lastName,
              'email': email,
              'phone_number': phoneNumber,
              'currency': 'MWK',
              'amount': _total.round().toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero 360 Payment',
                'description': description,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseJson = json.decode(response.body);
        final status = (responseJson['status'] ?? '').toString().toLowerCase();
        if (status == 'success') {
          final checkoutUrl = responseJson['data']['checkout_url'] as String;
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InAppPaymentPage(
                checkoutUrl: checkoutUrl,
                txRef: txRef,
                totalAmount: _total,
                rootContext: context,
              ),
            ),
          );
        } else {
          throw Exception(responseJson['message'] ?? 'Payment failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Network error. Please check your internet connection.',
        isSuccess: false,
        errorMessage: e.message,
      );
    } on TimeoutException {
      ToastHelper.showCustomToast(
        context,
        'Connection timeout. Please try again.',
        isSuccess: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Payment error: $e',
        isSuccess: false,
        errorMessage: 'Payment failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Image like Marketplace (http / base64 / firebase storage) ───────────
  Widget _itemImage(String raw, {double size = 96}) {
    final s = raw.trim();
    if (s.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey.shade300,
        child: const Icon(Icons.image_not_supported),
      );
    }

    // HTTP URL
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Image.network(
        s,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade300,
          child: const Icon(Icons.image_not_supported),
        ),
      );
    }

    // Firebase Storage gs://
    if (s.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(s).getDownloadURL(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Container(
              width: size,
              height: size,
              color: Colors.grey.shade200,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return Image.network(
            snap.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: Colors.grey.shade300,
              child: const Icon(Icons.image_not_supported),
            ),
          );
        },
      );
    }

    // Try Base64
    try {
      final base64Part = s.contains(',') ? s.split(',').last : s;
      if (base64Part.length > 150) {
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover);
      }
    } catch (_) {}

    // Try Firebase Storage path
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(s).getDownloadURL(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: size,
            height: size,
            color: Colors.grey.shade300,
            child: const Icon(Icons.image_not_supported),
          );
        }
        return Image.network(
          snap.data!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: Colors.grey.shade300,
            child: const Icon(Icons.image_not_supported),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    final addressOk = _deliveryType == DeliveryType.pickup || _defaultAddr != null;
    final canPay = !_submitting && _loggedIn && addressOk;

    return Theme(
      data: Theme.of(context).copyWith(outlinedButtonTheme: _outlinedTheme),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F6),
        appBar: AppBar(
          title: const Text('Checkout'),
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              // Trust banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _brandOrange.withOpacity(0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('Secure checkout — review delivery and payment details.')),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Item summary
              Card(
                elevation: 6,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _itemImage(item.image, size: 96),
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
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _brandSoft,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _brandOrange),
                              ),
                              child: Text(
                                _mwk(item.price),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _qtyBtn(Icons.remove, () {
                                  if (_qty > 1) setState(() => _qty--);
                                }),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    '$_qty',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                _qtyBtn(Icons.add, () => setState(() => _qty++)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Delivery Type dropdown
              Card(
                elevation: 6,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delivery Type',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      const SizedBox(height: 10),

                      DropdownButtonFormField<DeliveryType>(
                        value: _deliveryType,
                        isExpanded: true,

                        // ✅ THIS is what fixes the bottom overflow in the CLOSED field
                        selectedItemBuilder: (_) => [
                          _deliverySelectedItem(
                            title: 'Speed',
                            trailing: _mwk(_feeSpeed),
                            icon: Icons.flash_on_rounded,
                          ),
                          _deliverySelectedItem(
                            title: 'CTS',
                            trailing: _mwk(_feeCts),
                            icon: Icons.local_shipping_rounded,
                          ),
                          _deliverySelectedItem(
                            title: 'Pickup',
                            trailing: _mwk(_feePickup),
                            icon: Icons.storefront_rounded,
                          ),
                        ],

                        // ✅ this controls the dropdown menu item height (safe for all flutter versions)
                        itemHeight: 72,

                        decoration: _inputDecoration(
                          label: 'Choose delivery option',
                          prefixIcon: const Icon(Icons.local_shipping_rounded),
                          helper: _deliveryType == DeliveryType.pickup
                              ? 'Pickup selected — no delivery address needed'
                              : 'Delivery address is required',
                        ).copyWith(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),

                        items: [
                          DropdownMenuItem(
                            value: DeliveryType.speed,
                            child: _deliveryMenuItem(
                              title: 'Speed',
                              subtitle: 'Fast delivery',
                              trailing: _mwk(_feeSpeed),
                              icon: Icons.flash_on_rounded,
                            ),
                          ),
                          DropdownMenuItem(
                            value: DeliveryType.cts,
                            child: _deliveryMenuItem(
                              title: 'CTS',
                              subtitle: 'Standard delivery',
                              trailing: _mwk(_feeCts),
                              icon: Icons.local_shipping_rounded,
                            ),
                          ),
                          DropdownMenuItem(
                            value: DeliveryType.pickup,
                            child: _deliveryMenuItem(
                              title: 'Pickup',
                              subtitle: 'Collect at shop',
                              trailing: _mwk(_feePickup),
                              icon: Icons.storefront_rounded,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _deliveryType = v);
                        },
                      ),

                      const SizedBox(height: 12),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(
                            icon: _deliveryType == DeliveryType.pickup
                                ? Icons.storefront_rounded
                                : Icons.local_shipping_rounded,
                            text: _deliveryLabel(_deliveryType),
                          ),
                          _pill(icon: Icons.payments_rounded, text: 'Fee: ${_mwk(_delivery)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Delivery Address
              _DeliveryAddressCard(
                loading: _loadingAddr,
                loggedIn: _loggedIn,
                address: _defaultAddr,
                pickupSelected: _deliveryType == DeliveryType.pickup,
                pickupLocation: _pickupLocation,
                onManage: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
                  await _initAuthAndAddress();
                },
              ),

              const SizedBox(height: 12),

              // Order Summary + big orange Pay Now (same style as cart checkout)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, -2),
                    ),
                  ],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Summary',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _rowLine('Subtotal', _mwk(_subtotal)),
                    const SizedBox(height: 6),
                    _rowLine('Delivery', _mwk(_delivery)),
                    const SizedBox(height: 8),
                    const Divider(thickness: 1),
                    const SizedBox(height: 8),
                    _rowLine('Total', _mwk(_total), bold: true),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canPay ? _onPayPressed : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandOrange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_submitting)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            else
                              const Icon(Icons.payment, color: Colors.white),
                            const SizedBox(width: 10),
                            Text(
                              _submitting ? 'Processing...' : 'Pay Now',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Small helpers ────────────────────────────────────────────────────────
  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _rowLine(String left, String right, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      fontSize: bold ? 16 : 14,
    );
    return Row(
      children: [
        Expanded(
          child: Text(left, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Text(right, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ── Delivery Address card widget ───────────────────────────────────────────
class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({
    required this.loading,
    required this.loggedIn,
    required this.address,
    required this.onManage,
    required this.pickupSelected,
    this.pickupLocation,
  });

  final bool loading;
  final bool loggedIn;
  final Address? address;
  final VoidCallback onManage;
  final bool pickupSelected;
  final String? pickupLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery Address',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (pickupSelected)
              _line(
                'Shop pickup selected',
                (pickupLocation ?? '').trim().isEmpty
                    ? 'Pickup at merchant shop (address from listing)'
                    : pickupLocation!.trim(),
              )
            else if (loading)
              const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (!loggedIn)
              _line('Not logged in', 'Please log in to select address')
            else if (address == null)
              _line('No default address', 'Set your default delivery address')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line(_label(address!.addressType), address!.city),
                  if (address!.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      address!.description,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: pickupSelected ? null : onManage,
                icon: const Icon(Icons.location_pin),
                label: Text(address == null ? 'Set address' : 'Change'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _line(String a, String b) {
    return Row(
      children: [
        Expanded(
          child: Text(
            a,
            style: const TextStyle(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            b,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      ],
    );
  }

  static String _label(AddressType t) {
    switch (t) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Office';
      case AddressType.business:
        return 'Business';
      case AddressType.other:
        return 'Other';
    }
  }
}
