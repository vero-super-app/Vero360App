// lib/Pages/checkout_from_cart_page.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:paychangu_flutter/paychangu_flutter.dart';

import 'package:vero360_app/models/cart_model.dart';
import 'package:vero360_app/toasthelper.dart';

class CheckoutFromCartPage extends StatefulWidget {
  final List<CartModel> items;

  const CheckoutFromCartPage({Key? key, required this.items}) : super(key: key);

  @override
  State<CheckoutFromCartPage> createState() => _CheckoutFromCartPageState();
}

class _CheckoutFromCartPageState extends State<CheckoutFromCartPage> {
  late final PayChangu _paychangu;
  bool _paying = false;

  // --- basic pricing (tweak if you have your own logic) ---
  double get _subtotal =>
      widget.items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));

  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;
  double get _total => max(0.0, _subtotal + _deliveryFee);

  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();

    _paychangu = PayChangu(
      PayChanguConfig(
        secretKey: 'SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u', // TODO: your real key
        isTestMode: true,
      ),
    );
  }

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

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? 'customer@example.com';
    final fullName = prefs.getString('name') ?? 'Vero Customer';

    final parts = fullName.trim().split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : 'Vero';
    final lastName =
        parts.length > 1 ? parts.sublist(1).join(' ') : 'Customer';

    final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';
    final amountInt = _total.round(); // PayChangu expects an int (MWK)

    final request = PaymentRequest(
      txRef: txRef,
      firstName: firstName,
      lastName: lastName,
      email: email,
      currency: Currency.MWK,
      amount: amountInt,
      callbackUrl: 'https://your-backend.com/paychangu/callback',
      returnUrl: 'https://your-frontend.com/paychangu/return',
    );

    await Navigator.of(rootContext).push(
      MaterialPageRoute(
        builder: (innerContext) {
          return Scaffold(
            appBar: AppBar(title: const Text('Complete Payment')),
            body: _paychangu.launchPayment(
              request: request,
              onSuccess: (response) async {
                final ref = response['tx_ref']?.toString() ?? txRef;

                try {
                  final verification =
                      await _paychangu.verifyTransaction(ref);

                  final isValid = _paychangu.validatePayment(
                    verification,
                    expectedTxRef: ref,
                    expectedCurrency: 'MWK',
                    expectedAmount: amountInt,
                  );

                  if (!mounted) return;

                  if (isValid) {
                    ToastHelper.showCustomToast(
                      rootContext,
                      'Payment successful!',
                      isSuccess: true,
                      errorMessage: '',
                    );

                    // Close PayChangu webview
                    Navigator.of(innerContext).pop();

                    // Close checkout → CartPage will refresh
                    Navigator.of(rootContext).pop(true);
                  } else {
                    ToastHelper.showCustomToast(
                      rootContext,
                      'Payment validation failed. Please contact support.',
                      isSuccess: false,
                      errorMessage: 'Validation failed',
                    );
                    Navigator.of(innerContext).pop();
                  }
                } catch (e) {
                  if (!mounted) return;
                  ToastHelper.showCustomToast(
                    rootContext,
                    'Could not verify payment. Please try again.',
                    isSuccess: false,
                    errorMessage: e.toString(),
                  );
                  Navigator.of(innerContext).pop();
                }
              },

              // 👇 IMPORTANT: soften this handler
              onError: (error) {
                if (!mounted) return;

                // Workaround: the SDK sometimes throws even when the
                // response body is "status: success" (HTTP 201).
                final detailsStr = error.details?.toString() ?? '';

                if (detailsStr.contains('"status":"success"') &&
                    detailsStr.contains('"checkout_url"')) {
                  // This is a "soft error" – session actually created.
                  // We just log and DO NOT close the WebView.
                  debugPrint(
                      '[PayChangu] Soft error (201 with success payload) – ignoring.');
                  return;
                }

                ToastHelper.showCustomToast(
                  rootContext,
                  'Payment failed. Please try again.',
                  isSuccess: false,
                  errorMessage: error.message ?? error.toString(),
                );
                Navigator.of(innerContext).pop();
              },

              onCancel: () {
                if (!mounted) return;
                ToastHelper.showCustomToast(
                  rootContext,
                  'Payment cancelled.',
                  isSuccess: false,
                  errorMessage: 'User cancelled',
                );
                Navigator.of(innerContext).pop();
              },
            ),
          );
        },
      ),
    );

    if (mounted) setState(() => _paying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final it = widget.items[i];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _mwk(it.price),
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty: ${it.quantity}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Column(
                children: [
                  _summaryRow('Subtotal', _mwk(_subtotal)),
                  _summaryRow('Delivery Fee', _mwk(_deliveryFee)),
                  const Divider(height: 16),
                  _summaryRow('Total', _mwk(_total),
                      bold: true, green: true),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _paying ? null : _startPayChanguPayment,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFFF8A00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _paying ? 'Processing…' : 'Pay Now',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
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
