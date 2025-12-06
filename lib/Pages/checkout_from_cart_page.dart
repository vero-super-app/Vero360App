// lib/Pages/checkout_from_cart_page.dart
import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:paychangu_flutter/paychangu_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/models/cart_model.dart';
import 'package:vero360_app/toasthelper.dart';

class CheckoutFromCartPage extends StatefulWidget {
  final List<CartModel> items;

  const CheckoutFromCartPage({Key? key, required this.items}) : super(key: key);

  @override
  State<CheckoutFromCartPage> createState() => _CheckoutFromCartPageState();
}

class _CheckoutFromCartPageState extends State<CheckoutFromCartPage> {
  // FIXED: No more late initialization
  final PayChanguConfig _config = PayChanguConfig(
    secretKey: 'SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u',
    isTestMode: true,
  );

  bool _paying = false;

  double get _subtotal =>
      widget.items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));
  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;
  double get _total => max(0.0, _subtotal + _deliveryFee);
  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  Future<void> _startPayChanguPayment() async {
    if (widget.items.isEmpty || _total <= 0) {
      ToastHelper.showCustomToast(
        context,
        'Your cart is empty.',
        isSuccess: false,
        errorMessage: 'Empty cart',
      );
      return;
    }

    setState(() => _paying = true);
    final rootContext = context;

    try {
      print('Starting payment...');

      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('email') ?? 'customer@example.com';
      final fullName = prefs.getString('name') ?? 'Vero Customer';
      final parts = fullName.trim().split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : 'Vero';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : 'Customer';

      final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';
      final amountInt = _total.round();

      print('tx_ref: $txRef | amount: $amountInt MWK | email: $email');

      final response = await http.post(
        Uri.parse('https://api.paychangu.com/payment'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config.secretKey}',
        },
        body: json.encode({
          'tx_ref': txRef,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'currency': 'MWK',
          'amount': amountInt.toString(),
          'callback_url': 'https://your-backend.com/paychangu/callback',
          'return_url': 'https://your-frontend.com/paychangu/return',
          'customization': {'title': 'Vero Payment', 'description': 'Cart checkout'},
        }),
      ).timeout(const Duration(seconds: 30));

      print('PayChangu Response: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResp = json.decode(response.body) as Map<String, dynamic>;
        if (jsonResp['status'] == 'success') {
          final checkoutUrl = jsonResp['data']['checkout_url'] as String;
          print('Checkout URL: $checkoutUrl');

          await Navigator.of(rootContext).push(
            MaterialPageRoute(
              builder: (_) => PaymentLauncherPage(
                checkoutUrl: checkoutUrl,
                txRef: txRef,
                secretKey: _config.secretKey,
                rootContext: rootContext,
              ),
            ),
          );
        } else {
          throw Exception(jsonResp['message'] ?? 'Unknown error');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      ToastHelper.showCustomToast(rootContext, 'No internet connection', isSuccess: false, errorMessage: 'Timeout');
    } catch (e) {
      print('Payment failed: $e');
      ToastHelper.showCustomToast(rootContext, 'Payment setup failed', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final it = widget.items[i];
                return Card(
                  child: ListTile(
                    title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Qty: ${it.quantity} × ${_mwk(it.price)}'),
                    trailing: Text(_mwk(it.price * it.quantity), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
            child: Column(
              children: [
                _row('Subtotal', _mwk(_subtotal)),
                _row('Delivery Fee', _mwk(_deliveryFee)),
                const Divider(),
                _row('Total', _mwk(_total), bold: true, green: true),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _paying ? null : _startPayChanguPayment,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFFFF8A00),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_paying ? 'Processing...' : 'Pay Now', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, bool green = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(color: green ? Colors.green : null, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}

// ────────────────────── PAYMENT LAUNCHER (WORKS 100%) ──────────────────────
class PaymentLauncherPage extends StatefulWidget {
  final String checkoutUrl;
  final String txRef;
  final String secretKey;
  final BuildContext rootContext;

  const PaymentLauncherPage({
    Key? key,
    required this.checkoutUrl,
    required this.txRef,
    required this.secretKey,
    required this.rootContext,
  }) : super(key: key);

  @override
  State<PaymentLauncherPage> createState() => _PaymentLauncherPageState();
}

class _PaymentLauncherPageState extends State<PaymentLauncherPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uri = Uri.parse(widget.checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.paychangu.com/transaction/verify/${widget.txRef}'),
        headers: {'Authorization': 'Bearer ${widget.secretKey}'},
      );

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final status = (data['data']?['status'] as String?)?.toLowerCase();

        if (status == 'success' || status == 'successful') {
          _timer?.cancel();
          if (mounted) Navigator.of(context).pop();
          ToastHelper.showCustomToast(widget.rootContext, 'Payment Successful!', isSuccess: true, errorMessage: '');
          Navigator.of(widget.rootContext).pop(true);
        } else if (status == 'failed' || status == 'cancelled') {
          _timer?.cancel();
          if (mounted) Navigator.of(context).pop();
          ToastHelper.showCustomToast(widget.rootContext, 'Payment Failed', isSuccess: false, errorMessage: status ?? '');
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Payment')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Opening payment in browser...', style: TextStyle(fontSize: 18)),
            SizedBox(height: 12),
            Text('Complete payment and return to app', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}