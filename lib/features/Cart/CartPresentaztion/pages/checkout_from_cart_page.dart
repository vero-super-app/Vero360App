import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/config/paychangu_config.dart';

const Color _brandOrange = Color(0xFFFF8A00);

class CheckoutFromCartPage extends StatefulWidget {
  final List<CartModel> items;
  const CheckoutFromCartPage({super.key, required this.items});

  @override
  State<CheckoutFromCartPage> createState() => _CheckoutFromCartPageState();
}

class _CheckoutFromCartPageState extends State<CheckoutFromCartPage> {
  bool _paying = false;

  late final NumberFormat _mwkFmt = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'MWK ',
    decimalDigits: 0,
  );

  String _mwk(num v) => _mwkFmt.format(v);

  double get _subtotal => widget.items.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;

  double get _total => max(0.0, _subtotal + _deliveryFee);

  // Image rendering remains unchanged (omitted here for brevity - keep your version)

  Future<void> _startPayChanguPayment() async {
    print('============================================================');
    print('!!! PAY BUTTON PRESSED - STARTING PAYMENT FLOW !!!');
    print('Time: ${DateTime.now().toIso8601String()}');
    print('Cart items: ${widget.items.length}');
    print('Total: $_total MWK');
    print('Paying state before: $_paying');
    print('============================================================');

    if (widget.items.isEmpty) {
      print('Cart empty - aborting');
      ToastHelper.showCustomToast(context, 'Cart is empty', isSuccess: false, errorMessage: 'Cart is empty');
      return;
    }

    if (!PayChanguConfig.isConfigured) {
      print('Config check failed: PayChanguConfig.isConfigured = false');
      ToastHelper.showCustomToast(context, 'Payment config error', isSuccess: false, errorMessage: 'Payment config error');
      return;
    }

    print('Config check passed');

    setState(() => _paying = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('email') ?? 'customer@example.com';
      final name = prefs.getString('name') ?? 'Customer';
      final phone = prefs.getString('phone') ?? '+265888000000';

      final parts = name.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : 'Customer';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final txRef = 'vero-${DateTime.now().millisecondsSinceEpoch}';
      print('Generated txRef: $txRef');

      // DNS check
      try {
        await InternetAddress.lookup('api.paychangu.com');
        print('DNS check OK');
      } on SocketException catch (e) {
        print('DNS failed: $e');
        throw Exception('Cannot reach PayChangu');
      }

      final body = PayChanguConfig.buildPaymentBody(
        txRef: txRef,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        amount: _total.toInt().toString(),
      );

      // CRITICAL LOG - what is ACTUALLY sent
      print('CALLBACK URL TO BE SENT: ${PayChanguConfig.callbackUrl}');
      print('RETURN URL TO BE SENT: ${PayChanguConfig.returnUrl}');
      print('Authorization header: ${PayChanguConfig.authHeaders['Authorization']}');

      final response = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));

      print('RESPONSE STATUS: ${response.statusCode}');
      print('RESPONSE BODY (first 500 chars): ${response.body.substring(0, response.body.length.clamp(0, 500))}');

      if (![200, 201].contains(response.statusCode)) {
        throw Exception('Gateway error: ${response.statusCode}');
      }

      final jsonResponse = json.decode(response.body);
      final status = (jsonResponse['status'] ?? '').toString().toLowerCase();

      if (status != 'success') {
        throw Exception(jsonResponse['message'] ?? 'Init failed');
      }

      final checkoutUrl = jsonResponse['data']?['checkout_url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('No checkout URL');
      }

      print('Launching WebView with: $checkoutUrl');

      if (!mounted) return;

      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => InAppPaymentPage(
            checkoutUrl: checkoutUrl,
            txRef: txRef,
            totalAmount: _total,
            rootContext: context,
          ),
        ),
      );

      if (success == true && mounted) {
        print('Payment flow returned SUCCESS from WebView');
        ToastHelper.showCustomToast(context, 'Order placed successfully!', isSuccess: true, errorMessage: 'Order placed successfully!');
      } else if (success == false && mounted) {
        print('Payment flow returned FAILURE from WebView');
      }
    } catch (e, stack) {
      print('PAYMENT CRASH: $e');
      print('Stack trace: $stack');
      ToastHelper.showCustomToast(context, 'Payment failed', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) {
        setState(() => _paying = false);
      }
      print('Payment attempt finished');
    }
  }

  Widget _itemRow(CartModel item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: item.image.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      item.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                    ),
                  )
                : const Icon(Icons.shopping_bag_outlined),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'x${item.quantity} • ${_mwk(item.price)}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _mwk(item.price * item.quantity),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      fontSize: bold ? 16 : 14,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 8),
        Text(value, style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: widget.items.length,
                itemBuilder: (_, i) => _itemRow(widget.items[i]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _summaryRow('Subtotal', _mwk(_subtotal)),
                  const SizedBox(height: 4),
                  _summaryRow('Delivery', _mwk(_deliveryFee)),
                  const Divider(height: 18),
                  _summaryRow('Total', _mwk(_total), bold: true),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _paying ? null : _startPayChanguPayment,
                      icon: _paying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock),
                      label: Text(_paying ? 'Processing…' : 'Pay Now'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// InAppPaymentPage - with detailed deep link logging (keep your current version or use this enhanced one)

class InAppPaymentPage extends StatefulWidget {
  final String checkoutUrl;
  final String txRef;
  final double totalAmount;
  final BuildContext rootContext;

  const InAppPaymentPage({
    super.key,
    required this.checkoutUrl,
    required this.txRef,
    required this.totalAmount,
    required this.rootContext,
  });

  @override
  State<InAppPaymentPage> createState() => _InAppPaymentPageState();
}

class _InAppPaymentPageState extends State<InAppPaymentPage> {
  late WebViewController _controller;
  Timer? _pollTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    print('InAppPaymentPage initState - loading URL: ${widget.checkoutUrl}');
    _initWebView();
    _startPolling();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            print('WebView progress: $p%');
            setState(() => _isLoading = p < 100);
          },
          onPageStarted: (url) {
            print('PAGE STARTED: $url');
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            print('PAGE FINISHED: $url');
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            print('WEB ERROR: ${error.description} - ${error.errorCode}');
            setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            print('NAVIGATION REQUEST: ${request.url}');
            if (request.url.startsWith('vero360://payment-complete')) {
              print('!!! DEEP LINK CAUGHT !!!');
              print('Full URL: ${request.url}');

              final uri = Uri.parse(request.url);
              final status = uri.queryParameters['status']?.toLowerCase() ?? 'unknown';
              final tx = uri.queryParameters['tx_ref'] ?? 'missing';

              print('Parsed → tx_ref: $tx | status: $status');

              if (tx == widget.txRef) {
                if (status.contains('success') || status == 'successful') {
                  print('DEEP LINK → SUCCESS DETECTED');
                  _handleSuccess();
                } else {
                  print('DEEP LINK → FAILURE / CANCEL DETECTED');
                  _handleFailure();
                }
              } else {
                print('TX MISMATCH! Expected ${widget.txRef}, got $tx');
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _startPolling() {
    print('Starting polling for txRef: ${widget.txRef}');
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _verifyStatus());

    Timer(const Duration(minutes: 10), () {
      if (mounted && _pollTimer?.isActive == true) {
        print('Polling timeout after 10 min');
        _pollTimer?.cancel();
        ToastHelper.showCustomToast(context, 'Payment check timed out', isSuccess: false, errorMessage: 'Payment check timed out');
        Navigator.pop(context);
      }
    });
  }

  Future<void> _verifyStatus() async {
    print('Polling verify for ${widget.txRef}');
    try {
      final res = await http.get(
        PayChanguConfig.verifyUri(widget.txRef),
        headers: PayChanguConfig.authHeaders,
      );

      print('Verify status: ${res.statusCode} | body: ${res.body.substring(0, res.body.length.clamp(0, 300))}...');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final status = (data['data']?['status'] as String?)?.toLowerCase() ?? '';

        if (status.contains('success')) {
          print('POLL → SUCCESS');
          _handleSuccess();
        } else if (['failed', 'cancelled', 'expired'].contains(status)) {
          print('POLL → FAILURE');
          _handleFailure();
        }
      }
    } catch (e) {
      print('Poll error: $e');
    }
  }

  void _handleSuccess() {
    _cleanup();
    print('SUCCESS HANDLER CALLED');
    ToastHelper.showCustomToast(widget.rootContext, 'Payment Successful!', isSuccess: true, errorMessage: 'Payment Successful!');
    if (mounted) {
      Navigator.pop(context);
      Navigator.pop(widget.rootContext, true);
    }
  }

  void _handleFailure() {
    _cleanup();
    print('FAILURE HANDLER CALLED');
    ToastHelper.showCustomToast(widget.rootContext, 'Payment not completed', isSuccess: false, errorMessage: 'Payment not completed');
    if (mounted) Navigator.pop(context);
  }

  void _cleanup() {
    _pollTimer?.cancel();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A00))),
                  SizedBox(height: 24),
                  Text('Loading secure payment page...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}