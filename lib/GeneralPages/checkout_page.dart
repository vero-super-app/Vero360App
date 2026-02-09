// lib/Pages/checkout_page.dart
import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/GeneralPages/address.dart';
import 'package:vero360_app/GeneralPages/payment_webview.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/GernalServices/paychangu_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

enum PaymentMethod { mobile, card }
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

  // ► Mobile money provider constants
  static const String _kAirtel = 'AirtelMoney';
  static const String _kMpamba = 'Mpamba';

  // ► Delivery fees (edit as you want)
  static const double _feeSpeed = 0; // e.g. 2500
  static const double _feeCts = 0; // e.g. 1500
  static const double _feePickup = 0;

  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  PaymentMethod _method = PaymentMethod.mobile;
  String _provider = _kAirtel;

  DeliveryType _deliveryType = DeliveryType.cts;

  String? _phoneError;
  int _qty = 1;
  bool _submitting = false;

  // Address
  final _addrSvc = AddressService();
  Address? _defaultAddr;
  bool _loadingAddr = true;
  bool _loggedIn = false;

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
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
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

  // ── Provider helpers ─────────────────────────────────────────────────────
  String get _providerLabel => _provider == _kAirtel ? 'Airtel Money' : 'TNM Mpamba';
  String get _providerHint => _provider == _kAirtel ? '09xxxxxxxx' : '08xxxxxxxx';
  IconData get _providerIcon =>
      _provider == _kAirtel ? Icons.phone_android_rounded : Icons.phone_iphone_rounded;

  String? _validatePhoneForSelectedProvider(String raw) {
    final p = raw.replaceAll(RegExp(r'\D'), '');
    if (p.length != 10) return 'Phone must be exactly 10 digits';
    if (_provider == _kAirtel && !PaymentsService.validateAirtel(p)) {
      return 'Airtel numbers must start with 09…';
    }
    if (_provider == _kMpamba && !PaymentsService.validateMpamba(p)) {
      return 'Mpamba numbers must start with 08…';
    }
    return null;
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

  // ── Pay routing ─────────────────────────────────────────────────────────
  Future<void> _onPayPressed() async {
    if (!await _requireLogin()) return;
    if (!await _ensureDefaultAddressIfNeeded()) return;

    switch (_method) {
      case PaymentMethod.mobile:
        await _payMobile();
        break;
      case PaymentMethod.card:
        await _payCard();
        break;
    }
  }

  // ── Mobile Money flow ───────────────────────────────────────────────────
  Future<void> _payMobile() async {
    final err = _validatePhoneForSelectedProvider(_phoneCtrl.text);
    if (err != null) {
      setState(() => _phoneError = err);
      ToastHelper.showCustomToast(context, err, isSuccess: false, errorMessage: 'Invalid phone');
      return;
    }
    setState(() => _phoneError = null);

    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    setState(() => _submitting = true);

    try {
      final addrText = _deliveryType == DeliveryType.pickup
          ? 'Pickup'
          : 'Deliver to: ${_defaultAddr?.city ?? '-'}';

      final resp = await PaymentsService.pay(
        amount: _total,
        currency: 'MWK',
        phoneNumber: phone,
        relatedType: 'ORDER',
        description:
            'Order: ${widget.item.name} (x$_qty) • Delivery: ${_deliveryLabel(_deliveryType)} • $addrText • $_providerLabel',
      );

      if (resp.checkoutUrl != null && resp.checkoutUrl!.isNotEmpty) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PaymentWebView(checkoutUrl: resp.checkoutUrl!)),
        );
      } else {
        ToastHelper.showCustomToast(
          context,
          resp.message ?? resp.status ?? 'Payment initiated',
          isSuccess: true,
          errorMessage: 'OK',
        );
      }
      if (mounted) Navigator.pop(context);
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

  // ── Card flow ───────────────────────────────────────────────────────────
  Future<void> _payCard() async {
    setState(() => _submitting = true);
    try {
      final addrText = _deliveryType == DeliveryType.pickup
          ? 'Pickup'
          : 'Deliver to: ${_defaultAddr?.city ?? '-'}';

      final resp = await PaymentsService.pay(
        amount: _total,
        currency: 'MWK',
        phoneNumber: null,
        relatedType: 'ORDER',
        description:
            'Card payment: ${widget.item.name} (x$_qty) • Delivery: ${_deliveryLabel(_deliveryType)} • $addrText',
      );

      if (resp.checkoutUrl != null && resp.checkoutUrl!.isNotEmpty) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PaymentWebView(checkoutUrl: resp.checkoutUrl!)),
        );
      } else {
        ToastHelper.showCustomToast(
          context,
          resp.message ?? resp.status ?? 'Card payment started',
          isSuccess: true,
          errorMessage: 'OK',
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Card payment error: $e',
        isSuccess: false,
        errorMessage: 'Card payment failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _methodLabel(PaymentMethod m) => 'Pay Now';

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
                onManage: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
                  await _initAuthAndAddress();
                },
              ),

              const SizedBox(height: 12),

              // Payment method
              Card(
                elevation: 6,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    RadioListTile<PaymentMethod>(
                      value: PaymentMethod.mobile,
                      groupValue: _method,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _method = v);
                      },
                      title: const Text('Mobile Money'),
                      secondary: const Icon(Icons.phone_iphone_rounded),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _method == PaymentMethod.mobile
                          ? Padding(
                              key: const ValueKey('mobile-fields'),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: _mobileFields(),
                            )
                          : const SizedBox.shrink(key: ValueKey('mobile-empty')),
                    ),
                    const Divider(height: 1),
                    RadioListTile<PaymentMethod>(
                      value: PaymentMethod.card,
                      groupValue: _method,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _method = v);
                      },
                      title: const Text('Card'),
                      secondary: const Icon(Icons.credit_card_rounded),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

            

              // Summary
              Card(
                elevation: 6,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      _rowLine('Subtotal', _mwk(_subtotal)),
                      const SizedBox(height: 6),
                      _rowLine('Delivery', _mwk(_delivery)),
                      const Divider(height: 18),
                      _rowLine('Total', _mwk(_total), bold: true),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: canPay ? _onPayPressed : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock),
                  label: Text(_submitting ? 'Processing…' : _methodLabel(_method)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Inline Mobile Money fields ───────────────────────────────────────────
  Widget _mobileFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _provider,
          isExpanded: true,
          decoration: _inputDecoration(label: 'Provider').copyWith(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          items: const [
            DropdownMenuItem(value: _kAirtel, child: Text('Airtel Money')),
            DropdownMenuItem(value: _kMpamba, child: Text('TNM Mpamba')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _provider = v;
              _phoneError = null;
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
          decoration: _inputDecoration(
            label: 'Phone number ($_providerLabel)',
            hint: _providerHint,
            prefixIcon: Icon(_providerIcon),
            helper: '10 digits only',
            error: _phoneError,
          ),
        ),
      ],
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
  });

  final bool loading;
  final bool loggedIn;
  final Address? address;
  final VoidCallback onManage;
  final bool pickupSelected;

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
              _line('Pickup selected', 'No address needed')
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
