// lib/Pages/checkout_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/Pages/address.dart';

import 'package:vero360_app/models/marketplace.model.dart';
import 'package:vero360_app/services/paychangu_service.dart';
import 'package:vero360_app/toasthelper.dart';
import 'package:vero360_app/Pages/payment_webview.dart';

// ⬇️ Address imports
import 'package:vero360_app/models/address_model.dart';
import 'package:vero360_app/services/address_service.dart';

enum PaymentMethod { mobile, card, cod }

class CheckoutPage extends StatefulWidget {
  final MarketplaceDetailModel item;
  const CheckoutPage({required this.item, Key? key}) : super(key: key);

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  // ► Brand (UI only)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft   = Color(0xFFFFE8CC);

  // ► Mobile money provider constants
  static const String _kAirtel = 'AirtelMoney';
  static const String _kMpamba = 'Mpamba';

  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  PaymentMethod _method = PaymentMethod.mobile;
  String _provider = _kAirtel;

  String? _phoneError;
  int _qty = 1;
  bool _submitting = false;

  // ⬇️ Default address state
  final _addrSvc = AddressService();
  Address? _defaultAddr;
  bool _loadingAddr = true;
  bool _loggedIn = false;

  double get _subtotal => widget.item.price * _qty;
  double get _delivery => 0;
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

  // ── Small UI helpers (no logic changes) ─────────────────────────────────
  InputDecoration _inputDecoration({String? label, String? hint, Widget? prefixIcon, String? helper, String? error}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      errorText: error,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black, width: 1), // black before active
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _brandOrange, width: 2),          // orange on focus
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

  // ── Provider helpers ─────────────────────────────────────────────────────
  String get _providerLabel => _provider == _kAirtel ? 'Airtel Money' : 'TNM Mpamba';
  String get _providerHint  => _provider == _kAirtel ? '09xxxxxxxx'   : '08xxxxxxxx';
  IconData get _providerIcon => _provider == _kAirtel
      ? Icons.phone_android_rounded
      : Icons.phone_iphone_rounded;

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

  // ── Auth + Default address bootstrap ─────────────────────────────────────
  Future<String?> _readAuthToken() async {
    final sp = await SharedPreferences.getInstance();
    for (final k in const ['token', 'jwt_token', 'jwt']) {
      final v = sp.getString(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

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
      Address? def = list.firstWhere(
        (a) => a.isDefault,
        orElse: () => list.isNotEmpty ? list.first : null as Address, // (kept as-is; UI-only pass)
      );
      setState(() {
        _loggedIn = true;
        _defaultAddr = def?.isDefault == true ? def : null; // require true default
        _loadingAddr = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loggedIn = true; // we had a token
        _defaultAddr = null;
        _loadingAddr = false;
      });
    }
  }

  Future<bool> _ensureDefaultAddress() async {
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

  // ── Common guards ────────────────────────────────────────────────────────
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
    if (!await _ensureDefaultAddress()) return;

    switch (_method) {
      case PaymentMethod.mobile:
        await _payMobile();
        break;
      case PaymentMethod.card:
        await _payCard();
        break;
      case PaymentMethod.cod:
        await _placeCOD();
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
      final resp = await PaymentsService.pay(
        amount: _total,
        currency: 'MWK',
        phoneNumber: phone,
        relatedType: 'ORDER',
        description:
            'Order for ${widget.item.name} (x$_qty) • $_providerLabel • Deliver to: ${_defaultAddr?.city ?? '-'}',
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
      final resp = await PaymentsService.pay(
        amount: _total,
        currency: 'MWK',
        phoneNumber: null,
        relatedType: 'ORDER',
        description:
            'Card payment for ${widget.item.name} (x$_qty) • Deliver to: ${_defaultAddr?.city ?? '-'}',
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

  // ── Cash on Delivery ────────────────────────────────────────────────────
  Future<void> _placeCOD() async {
    ToastHelper.showCustomToast(
      context,
      'Order placed • COD',
      isSuccess: true,
      errorMessage: 'OK',
    );
    if (mounted) Navigator.pop(context);
  }

  String _methodLabel(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.mobile: return 'Pay Now';
      case PaymentMethod.card:   return 'Pay Now';
      case PaymentMethod.cod:    return 'Place Order';
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canPay = !_submitting && _loggedIn && _defaultAddr != null;

    return Theme(
      data: Theme.of(context).copyWith(outlinedButtonTheme: _outlinedTheme),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Checkout'),
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            // ── Mini banner for trust cue ───────────────────────────────────
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
                  Expanded(child: Text('Secure checkout — review your address and payment details.')),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Item summary ────────────────────────────────────────────────
            Card(
              elevation: 6,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      item.image,
                      width: 96, height: 96, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 96, height: 96, color: Colors.grey.shade300,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _brandSoft,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _brandOrange),
                        ),
                        child: Text('MWK ${item.price.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        _qtyBtn(Icons.remove, () { if (_qty > 1) setState(() => _qty--); }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('$_qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        _qtyBtn(Icons.add, () { setState(() => _qty++); }),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 12),

            // ── Delivery Address (required) ─────────────────────────────────
            _DeliveryAddressCard(
              loading: _loadingAddr,
              loggedIn: _loggedIn,
              address: _defaultAddr,
              onManage: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
                await _initAuthAndAddress();
              },
            ),

            const SizedBox(height: 12),

            // ── Payment method selector with inline Mobile Money fields ─────
            Card(
              elevation: 6,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RadioListTile<PaymentMethod>(
                        value: PaymentMethod.mobile,
                        groupValue: _method,
                        onChanged: (v) => setState(() => _method = v!),
                        title: const Text('Mobile Money'),
                        secondary: const Icon(Icons.phone_iphone_rounded),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _method == PaymentMethod.mobile
                            ? Padding(
                                key: const ValueKey('mobile-fields'),
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: _mobileFields(),
                              )
                            : const SizedBox.shrink(key: ValueKey('mobile-empty')),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  RadioListTile<PaymentMethod>(
                    value: PaymentMethod.card,
                    groupValue: _method,
                    onChanged: (v) => setState(() => _method = v!),
                    title: const Text('Card'),
                    secondary: const Icon(Icons.credit_card_rounded),
                  ),
                  const Divider(height: 1),
                  RadioListTile<PaymentMethod>(
                    value: PaymentMethod.cod,
                    groupValue: _method,
                    onChanged: (v) => setState(() => _method = v!),
                    title: const Text('Cash on Delivery'),
                    secondary: const Icon(Icons.delivery_dining_rounded),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Summary ─────────────────────────────────────────────────────
            Card(
              elevation: 6,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(children: [
                  _rowLine('Subtotal', 'MWK ${_subtotal.toStringAsFixed(0)}'),
                  const SizedBox(height: 6),
                  _rowLine('Delivery', 'MWK ${_delivery.toStringAsFixed(0)}'),
                  const Divider(height: 18),
                  _rowLine('Total', 'MWK ${_total.toStringAsFixed(0)}', bold: true),
                ]),
              ),
            ),

            const SizedBox(height: 16),

            // ── Action button ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: _filledBtnStyle(),
                onPressed: canPay ? _onPayPressed : null,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock),
                label: Text(_submitting ? 'Processing…' : _methodLabel(_method)),
              ),
            ),
          ],
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
          icon: const Icon(Icons.arrow_drop_down),
          decoration: _inputDecoration(label: 'Provider'),
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
      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
      fontSize: bold ? 16 : 14,
    );
    return Row(
      children: [
        Expanded(child: Text(left, style: style)),
        Text(right, style: style),
      ],
    );
  }
}

// ── Delivery Address card widget (UI styling only) ─────────────────────────
class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({
    required this.loading,
    required this.loggedIn,
    required this.address,
    required this.onManage,
  });

  final bool loading;
  final bool loggedIn;
  final Address? address;
  final VoidCallback onManage;

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
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (loading)
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
                    Text(address!.description, style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ],
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onManage,
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
        Expanded(child: Text(a, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text(b, style: const TextStyle(color: Colors.black87)),
      ],
    );
  }

  static String _label(AddressType t) {
    switch (t) {
      case AddressType.home: return 'Home';
      case AddressType.work: return 'Office';
      case AddressType.business: return 'Business';
      case AddressType.other: return 'Other';
    }
  }
}
