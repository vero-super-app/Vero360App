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
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

enum DeliveryType { speed, cts, ankolo, smart, pickup }

class CheckoutPage extends StatefulWidget {
  final MarketplaceDetailModel item;
  final int? promoSubscribeId;

  const CheckoutPage({
    required this.item,
    this.promoSubscribeId,
    super.key,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  // ► Brand (UI only)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _brandSoft = Color(0xFFFFE8CC);
  static const Color _pageBg = Color(0xFFF4F6FA);

  DeliveryType _deliveryType = DeliveryType.speed;

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

  String _formatMoney(num v) {
    if (v != v.roundToDouble()) {
      return 'MWK ${v.toStringAsFixed(2)}';
    }
    return _mwk(v);
  }

  double get _subtotal => widget.item.price * _qty;

  double get _total => _subtotal;

  bool get _isPromotion =>
      widget.item.serviceType == 'promotion' || widget.promoSubscribeId != null;

  @override
  void initState() {
    super.initState();
    // Defer so auth and context are ready (avoids "address not loaded until re-navigate")
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAuthAndAddressWithRetry();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── UI helpers ──────────────────────────────────────────────────────────
  OutlinedButtonThemeData get _outlinedTheme => OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.black, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );

  // ── Delivery helpers ─────────────────────────────────────────────────────
  String _deliveryLabel(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return 'Speed';
      case DeliveryType.cts:
        return 'CTS';
      case DeliveryType.ankolo:
        return 'Ankolo';
      case DeliveryType.smart:
        return 'Smart';
      case DeliveryType.pickup:
        return 'Pickup';
    }
  }

  String _deliverySubtitle(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return 'Fast delivery';
      case DeliveryType.cts:
        return 'Standard';
      case DeliveryType.ankolo:
        return 'Online tracking';
      case DeliveryType.smart:
        return 'Online tracking';
      case DeliveryType.pickup:
        return 'Collect at shop';
    }
  }

  IconData _deliveryIcon(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return Icons.bolt_rounded;
      case DeliveryType.cts:
        return Icons.local_shipping_rounded;
      case DeliveryType.ankolo:
        return Icons.local_shipping_outlined;
      case DeliveryType.smart:
        return Icons.electric_moped_rounded;
      case DeliveryType.pickup:
        return Icons.storefront_rounded;
    }
  }

  Widget _section({required String title, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: _brandNavy,
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _stepsHeader() {
    Widget step(String label, bool active) {
      return Expanded(
        child: Column(
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: active ? _brandOrange : Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: active ? _brandNavy : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        step('Order', true),
        const SizedBox(width: 8),
        step('Delivery', true),
        const SizedBox(width: 8),
        step('Pay', false),
      ],
    );
  }

  Widget _courierTile(DeliveryType type) {
    final selected = _deliveryType == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _deliveryType = type),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(
            color: selected ? _brandSoft : const Color(0xFFF8F9FC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _brandOrange
                  : Colors.black.withValues(alpha: 0.08),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _deliveryIcon(type),
                    size: 18,
                    color: selected ? _brandOrange : _brandNavy,
                  ),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: _brandOrange),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _deliveryLabel(type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: _brandNavy,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _deliverySubtitle(type),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _courierGrid() {
    const options = DeliveryType.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 64;
        const gap = 8.0;
        final cols = maxW < 340 ? 2 : 3;
        final tileW = ((maxW - gap * (cols - 1)) / cols).clamp(96.0, 200.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in options)
              SizedBox(width: tileW, child: _courierTile(d)),
          ],
        );
      },
    );
  }

  // ── Auth + Default address bootstrap (single source: Firebase then SP) ───
  Future<String?> _readAuthToken() async => AuthHandler.getTokenForApi();

  /// Initial load: run after first frame, then retry once if auth wasn't ready.
  Future<void> _loadAuthAndAddressWithRetry() async {
    await _initAuthAndAddress();
    if (!mounted) return;
    // If we still have no address and not logged in, auth may have been initializing — retry once.
    if (!_loggedIn && _defaultAddr == null && !_loadingAddr) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      await _initAuthAndAddress();
    }
  }

  Future<void> _initAuthAndAddress({bool forceRefresh = false}) async {
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
      final list = await _addrSvc.getMyAddresses(forceRefresh: forceRefresh);

      Address? def;
      for (final a in list) {
        if (a.isDefault) {
          def = a;
          break;
        }
      }

      if (!mounted) return;
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
      await _initAuthAndAddress(forceRefresh: true);
      return _defaultAddr != null;
    }
    return false;
  }

  Future<bool> _requireLogin() async {
    final t = await _readAuthToken();
    final ok = t != null;
    if (!ok) {
      // When user tries to pay while not logged in, give a clearer message,
      // especially for shop pickup.
      final msg = _deliveryType == DeliveryType.pickup
          ? 'Please log in to use shop pickup.'
          : 'Please log in to complete checkout.';
      ToastHelper.showCustomToast(
        context,
        msg,
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
              'amount': _total == _total.roundToDouble()
                  ? _total.round().toString()
                  : _total.toStringAsFixed(2),
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
          // Pass merchant credit so wallet is credited on payment success (same as cart checkout)
          final mid = (widget.item.merchantId ?? '').trim();
          final mname = (widget.item.merchantName ?? '').trim();
          final hasMerchant = mid.isNotEmpty && mid != 'unknown' &&
              mname.isNotEmpty && mname != 'Unknown Merchant';
          final listForCredit = hasMerchant
              ? <CartModel>[
                  CartModel(
                    userId: '',
                    item: widget.item.id,
                    quantity: _qty,
                    image: widget.item.image,
                    name: widget.item.name,
                    price: widget.item.price,
                    description: widget.item.description,
                    merchantId: mid,
                    merchantName: mname,
                    serviceType: _isPromotion ? 'promotion' : 'marketplace',
                  ),
                ]
              : null;
          final promoId = widget.promoSubscribeId;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InAppPaymentPage(
                checkoutUrl: checkoutUrl,
                txRef: txRef,
                totalAmount: _total,
                rootContext: context,
                cartItemsForMerchantCredit: listForCredit,
                shippingAddress: _deliveryType == DeliveryType.pickup ? null : _defaultAddr,
                deliveryType: _deliveryType,
                popOnlyOnSuccess: promoId != null,
                onSuccessNavigate: promoId != null
                    ? (root) async {
                        try {
                          await PromoService()
                              .subscribe(promoId, _total.toDouble());
                        } catch (_) {}
                        if (!root.mounted) return;
                        ToastHelper.showCustomToast(
                          root,
                          'Promotion activated!',
                          isSuccess: true,
                          errorMessage: '',
                        );
                        Navigator.of(root).pop();
                      }
                    : null,
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
    final addressOk =
        _deliveryType == DeliveryType.pickup || _defaultAddr != null;
    final canPay = !_submitting && addressOk;

    return Theme(
      data: Theme.of(context).copyWith(outlinedButtonTheme: _outlinedTheme),
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          centerTitle: false,
          titleSpacing: 0,
          title: const Text(
            'Checkout',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.4,
              color: Colors.white,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _stepsHeader(),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.black.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 18,
                            color: _brandNavy.withValues(alpha: 0.7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Secure checkout · PayChangu protected',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section(
                    title: 'Your order',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _itemImage(item.image, size: 88),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: _brandNavy,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatMoney(item.price),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: _brandOrange,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _qtyBtn(Icons.remove_rounded, () {
                                    if (_qty > 1) setState(() => _qty--);
                                  }),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    child: Text(
                                      '$_qty',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: _brandNavy,
                                      ),
                                    ),
                                  ),
                                  _qtyBtn(Icons.add_rounded,
                                      () => setState(() => _qty++)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Courier',
                    subtitle: _deliveryType == DeliveryType.pickup
                        ? 'Pickup selected — no delivery address needed'
                        : 'Choose how you want your order delivered',
                    child: _courierGrid(),
                  ),
                  const SizedBox(height: 12),
                  _DeliveryAddressCard(
                    loading: _loadingAddr,
                    loggedIn: _loggedIn,
                    address: _defaultAddr,
                    pickupSelected: _deliveryType == DeliveryType.pickup,
                    pickupLocation: _pickupLocation,
                    onManage: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AddressPage()),
                      );
                      await _initAuthAndAddress(forceRefresh: true);
                    },
                  ),
                  const SizedBox(height: 12),
                  _section(
                    title: 'Summary',
                    child: Column(
                      children: [
                        _rowLine('Subtotal', _formatMoney(_subtotal)),
                        const SizedBox(height: 10),
                        _rowLine(
                          'Delivery',
                          _deliveryType == DeliveryType.pickup
                              ? 'Pickup'
                              : _deliveryLabel(_deliveryType),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(
                              height: 1, color: Colors.grey.shade200),
                        ),
                        _rowLine('Total', _formatMoney(_total), bold: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _stickyPayBar(canPay: canPay),
          ],
        ),
      ),
    );
  }

  Widget _stickyPayBar({required bool canPay}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatMoney(_total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _brandNavy,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: canPay ? _onPayPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                disabledBackgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _submitting
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
                      'Pay Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Small helpers ────────────────────────────────────────────────────────
  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FA),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: _brandNavy),
      ),
    );
  }

  Widget _rowLine(String left, String right, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      fontSize: bold ? 16 : 14,
      color: bold ? _brandNavy : Colors.grey.shade800,
    );
    return Row(
      children: [
        Expanded(
          child: Text(left,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Text(right,
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Delivery address',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF16284C),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (!pickupSelected)
                TextButton.icon(
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF8A00),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                  label: Text(
                    address == null ? 'Set' : 'Change',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (pickupSelected)
            _addrBox(
              Icons.storefront_rounded,
              'Shop pickup',
              (pickupLocation ?? '').trim().isEmpty
                  ? 'Pickup at merchant shop'
                  : pickupLocation!.trim(),
            )
          else if (loading)
            const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!loggedIn)
            _addrBox(Icons.lock_outline_rounded, 'Not logged in',
                'Please log in to select address')
          else if (address == null)
            _addrBox(Icons.location_off_outlined, 'No default address',
                'Set your default delivery address')
          else
            _addrBox(
              Icons.place_rounded,
              _label(address!.addressType),
              [
                address!.city,
                if (address!.description.isNotEmpty) address!.description,
              ].join(' · '),
            ),
        ],
      ),
    );
  }

  static Widget _addrBox(IconData icon, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF16284C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF16284C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
