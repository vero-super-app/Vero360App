// lib/Pages/checkout_from_cart_page.dart
import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:paychangu_flutter/paychangu_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
  late final PayChanguConfig _config;
  bool _paying = false;

  double get _subtotal =>
      widget.items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));
  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;
  double get _total => max(0.0, _subtotal + _deliveryFee);
  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _config = PayChanguConfig(
      secretKey: 'SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u',
      isTestMode: true,
    );
    _paychangu = PayChangu(_config);
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
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : 'Customer';

    final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';
    final amountInt = _total.round();

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

    const baseUrl = 'https://api.paychangu.com';
    final uri = Uri.parse('$baseUrl/payment');

    final body = {
      'tx_ref': request.txRef,
      'first_name': request.firstName,
      'last_name': request.lastName,
      'email': request.email,
      'currency': request.currency.name,
      'amount': request.amount.toString(),
      'callback_url': request.callbackUrl,
      'return_url': request.returnUrl,
      'customization': {'title': 'Vero Payment', 'description': 'Cart checkout'},
    };

    try {
      final response = await http.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config.secretKey}',
        },
        body: json.encode(body),
      );

      print('PayChangu response: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonResp = json.decode(response.body) as Map<String, dynamic>;
        if (jsonResp['status'] == 'success') {
          final checkoutUrl = jsonResp['data']['checkout_url'] as String;
          await Navigator.of(rootContext).push(
            MaterialPageRoute(
              builder: (_) => _PaymentWebViewPage(
                checkoutUrl: checkoutUrl,
                request: request,
                paychangu: _paychangu,
                amountInt: amountInt,
                txRef: txRef,
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
    } catch (e) {
      ToastHelper.showCustomToast(
        rootContext,
        'Payment setup failed',
        isSuccess: false,
        errorMessage: e.toString(),
      );
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
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: Colors.black12.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(_mwk(it.price), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Qty: ${it.quantity}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
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
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
              child: Column(
                children: [
                  _summaryRow('Subtotal', _mwk(_subtotal)),
                  _summaryRow('Delivery Fee', _mwk(_deliveryFee)),
                  const Divider(height: 16),
                  _summaryRow('Total', _mwk(_total), bold: true, green: true),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _paying ? null : _startPayChanguPayment,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFFF8A00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(_paying ? 'Processing…' : 'Pay Now', style: const TextStyle(fontSize: 16)),
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

  Widget _summaryRow(String label, String value, {bool bold = false, bool green = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          Text(value, style: TextStyle(color: green ? Colors.green : Colors.black87, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }
}

// ──────────────────────── Payment WebView Page ────────────────────────
class _PaymentWebViewPage extends StatefulWidget {
  final String checkoutUrl;
  final PaymentRequest request;
  final PayChangu paychangu;
  final int amountInt;
  final String txRef;
  final BuildContext rootContext;

  const _PaymentWebViewPage({
    required this.checkoutUrl,
    required this.request,
    required this.paychangu,
    required this.amountInt,
    required this.txRef,
    required this.rootContext,
  });

  @override
  State<_PaymentWebViewPage> createState() => _PaymentWebViewPageState();
}

class _PaymentWebViewPageState extends State<_PaymentWebViewPage> {
  late final WebViewController controller;
  bool _isLoading = true;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        Navigator.of(context).pop();
        ToastHelper.showCustomToast(
          widget.rootContext,
          'Payment page timed out',
          isSuccess: false,
          errorMessage: 'Timeout',
        );
      }
    });

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..clearCache()
      ..setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (progress == 100 && mounted) {
              setState(() => _isLoading = false);
              _timeoutTimer?.cancel();

              // Fix React hydration + paymentDetails null bug
              controller.runJavaScript('''
                console.warn = () => {};
                console.error = (msg) => { if (String(msg).includes('418')) return; console.error(msg); };
                if (typeof window !== 'undefined' && (!window.paymentDetails || window.paymentDetails === null)) {
                  setTimeout(() => window.location.reload(), 1500);
                }
              ''');
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() => _isLoading = false);
              ToastHelper.showCustomToast(
                widget.rootContext,
                'Failed to load payment page',
                isSuccess: false,
                errorMessage: error.description,
              );
              Navigator.of(context).pop();
            }
          },
          onNavigationRequest: (request) async {
            final url = request.url;

            if (url.startsWith(widget.request.callbackUrl ?? '')) {
              final txRef = Uri.parse(url).queryParameters['tx_ref'] ?? widget.txRef;
              try {
                final verification = await widget.paychangu.verifyTransaction(txRef);
                final valid = widget.paychangu.validatePayment(
                  verification,
                  expectedTxRef: txRef,
                  expectedCurrency: 'MWK',
                  expectedAmount: widget.amountInt,
                );
                if (!mounted) return NavigationDecision.prevent;
                ToastHelper.showCustomToast(
                  widget.rootContext,
                  'Payment successful!',
                  isSuccess: true,
                  errorMessage: '',
                );
                Navigator.of(widget.rootContext).pop(true);
              } catch (e) {
                ToastHelper.showCustomToast(
                  widget.rootContext,
                  'Verification failed',
                  isSuccess: false,
                  errorMessage: e.toString(),
                );
              }
              return NavigationDecision.prevent;
            }

            if (url.startsWith(widget.request.returnUrl ?? '')) {
              ToastHelper.showCustomToast(
                widget.rootContext,
                'Payment cancelled or failed',
                isSuccess: false,
                errorMessage: 'User cancelled',
              );
              Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Payment')),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading secure payment options...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}