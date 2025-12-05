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

  // If you already calculate delivery elsewhere, you can pass it in instead.
  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;
  double get _total => max(0.0, _subtotal + _deliveryFee);

  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();

    // ⚠️ IMPORTANT:
    // Put your real PayChangu secret key here.
    // In production set isTestMode: false and use live key.
    _paychangu = PayChangu(
      PayChanguConfig(
        secretKey: 'sk_test_xxx_replace_me', // TODO: put your key
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

    // Pull some basic user info from SharedPreferences.
    // You already save 'email' in your auth flow.
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? 'customer@example.com';
    final fullName = prefs.getString('name') ?? 'Vero Customer';

    final parts = fullName.trim().split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : 'Vero';
    final lastName =
        parts.length > 1 ? parts.sublist(1).join(' ') : 'Customer';

    // Generate a txRef. In production you usually create this in your backend.
    final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';

    final amountInt = _total.round(); // PayChangu expects an int in MWK.

    final request = PaymentRequest(
      txRef: txRef,
      firstName: firstName,
      lastName: lastName,
      email: email,
      currency: Currency.MWK,
      amount: amountInt,
      // TODO: Replace these with your real callback / return URLs
      callbackUrl: 'https://your-backend.com/paychangu/callback',
      returnUrl: 'https://your-frontend.com/paychangu/return',
    );

    // Push a new route with the PayChangu WebView.
    await Navigator.of(rootContext).push(
      MaterialPageRoute(
        builder: (innerContext) {
          return Scaffold(
            appBar: AppBar(title: const Text('Complete Payment')),
            body: _paychangu.launchPayment(
              request: request,
              onSuccess: (response) async {
                // response['tx_ref'] should equal txRef
                final ref = response['tx_ref']?.toString() ?? txRef;

                try {
                  // Verify transaction using SDK.
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
                    // ✅ Payment ok. In production, you ALSO confirm this from your backend
                    // before marking order as paid.
                    ToastHelper.showCustomToast(
                      rootContext,
                      'Payment successful!',
                      isSuccess: true,
                      errorMessage: '',
                    );

                    // Close the PayChangu WebView
                    Navigator.of(innerContext).pop();

                    // Close the checkout page and send a "true" back to CartPage
                    // (CartPage already refreshes after returning).
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
              onError: (error) {
                if (!mounted) return;
                ToastHelper.showCustomToast(
                  rootContext,
                  'Payment failed. Please try again.',
                  isSuccess: false,
                  errorMessage: error.toString(),
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

          // --- Summary + Pay button ---
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
                        _paying ? 'Processing…' : 'Pay with PayChangu',
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
