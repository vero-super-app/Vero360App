// lib/Pages/checkout_from_cart_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:paychangu_flutter/paychangu_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

    // Initialize WebView for Android if needed (adjust based on webview_flutter version)
    if (Platform.isAndroid) {
      WebViewPlatform.instance = SurfaceAndroidWebView();
    }

    // ⚠️ IMPORTANT:
    // Use your real PayChangu secret key here.
    // In production: set isTestMode: false and use a live key.
    _paychangu = PayChangu(
      PayChanguConfig(
        secretKey: 'SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u', // TODO: replace
        isTestMode: true,
      ),
    );
  }

  void _handlePayChanguError(
    BuildContext rootContext, {
    required String message,
    dynamic error,
  }) {
    final details = error?.toString() ?? '';
    // ignore: avoid_print
    print('[PayChangu] onError: $details');

    ToastHelper.showCustomToast(
      rootContext,
      message,
      isSuccess: false,
      errorMessage: details,
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

    // Pull basic user info from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? 'customer@example.com';
    final fullName = prefs.getString('name') ?? 'Vero Customer';

    final parts = fullName.trim().split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : 'Vero';
    final lastName =
        parts.length > 1 ? parts.sublist(1).join(' ') : 'Customer';

    // Generate a txRef. In production, you usually generate this in backend.
    final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';
    final amountInt = _total.round(); // PayChangu expects an int for MWK.

    final request = PaymentRequest(
      txRef: txRef,
      firstName: firstName,
      lastName: lastName,
      email: email,
      currency: Currency.MWK,
      amount: amountInt,
      // TODO: Replace with your real callback / return URLs
      callbackUrl: 'https://your-backend.com/paychangu/callback',
      returnUrl: 'https://your-frontend.com/paychangu/return',
    );

    // Manual payment initiation to bypass SDK bug with status 201
    final baseUrl = _paychangu.config.isTestMode
        ? 'https://test-api.paychangu.com'
        : 'https://api.paychangu.com';
    final uri = Uri.parse('$baseUrl/payment');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_paychangu.config.secretKey}',
    };
    final body = {
      'tx_ref': request.txRef,
      'first_name': request.firstName,
      'last_name': request.lastName,
      'email': request.email,
      'currency': request.currency.name,
      'amount': request.amount.toString(),
      'callback_url': request.callbackUrl,
      'return_url': request.returnUrl,
      // Optional: 'customization': {'title': 'Your Title', 'description': 'Your Description'},
    };

    try {
      final response = await http.post(uri, headers: headers, body: json.encode(body));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResp = json.decode(response.body) as Map<String, dynamic>;

        if (jsonResp['status'] == 'success') {
          final checkoutUrl = jsonResp['data']['checkout_url'] as String;

          // Launch WebView with checkout URL
          await Navigator.of(rootContext).push(
            MaterialPageRoute(
              builder: (innerContext) {
                final controller = WebViewController()
                  ..setJavaScriptMode(JavaScriptMode.unrestricted)
                  ..setNavigationDelegate(
                    NavigationDelegate(
                      onNavigationRequest: (NavigationRequest navReq) async {
                        if (navReq.url.startsWith(request.callbackUrl)) {
                          // Success redirect
                          final uri = Uri.parse(navReq.url);
                          final respTxRef = uri.queryParameters['tx_ref'] ?? txRef;

                          try {
                            // Verify transaction using SDK.
                            final verification =
                                await _paychangu.verifyTransaction(respTxRef);

                            final isValid = _paychangu.validatePayment(
                              verification,
                              expectedTxRef: respTxRef,
                              expectedCurrency: 'MWK',
                              expectedAmount: amountInt,
                            );

                            if (!mounted) return NavigationDecision.prevent;

                            if (isValid) {
                              ToastHelper.showCustomToast(
                                rootContext,
                                'Payment successful!',
                                isSuccess: true,
                                errorMessage: '',
                              );

                              // Close WebView and checkout page
                              Navigator.of(innerContext).pop();
                              Navigator.of(rootContext).pop(true);
                            } else {
                              _handlePayChanguError(
                                rootContext,
                                message:
                                    'Payment validation failed. Please contact support.',
                                error: 'Validation failed for tx_ref: $respTxRef',
                              );
                              Navigator.of(innerContext).pop();
                            }
                          } catch (e) {
                            if (!mounted) return NavigationDecision.prevent;
                            _handlePayChanguError(
                              rootContext,
                              message: 'Could not verify payment. Please try again.',
                              error: e,
                            );
                            Navigator.of(innerContext).pop();
                          }

                          return NavigationDecision.prevent;
                        } else if (navReq.url.startsWith(request.returnUrl)) {
                          // Failure or cancel redirect
                          final uri = Uri.parse(navReq.url);
                          final respTxRef = uri.queryParameters['tx_ref'] ?? txRef;
                          final status = uri.queryParameters['status'];

                          _handlePayChanguError(
                            rootContext,
                            message: 'Payment ${status ?? 'failed or cancelled'}.',
                            error: 'tx_ref: $respTxRef',
                          );
                          Navigator.of(innerContext).pop();

                          return NavigationDecision.prevent;
                        }
                        return NavigationDecision.navigate;
                      },
                    ),
                  )
                  ..loadRequest(Uri.parse(checkoutUrl));

                return Scaffold(
                  appBar: AppBar(title: const Text('Complete Payment')),
                  body: WebViewWidget(controller: controller),
                );
              },
            ),
          );
        } else {
          throw Exception('Initiation failed: ${jsonResp['message']}');
        }
      } else {
        throw Exception('Initiation failed with status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _handlePayChanguError(
        rootContext,
        message: 'Payment initiation failed. Please try again.',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
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

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    bool green = false,
  }) {
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