import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/config/paychangu_config.dart';

const Color _brandOrange = Color(0xFFFF8A00);
const Color _brandSoft = Color(0xFFFFF3E0);

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
      ToastHelper.showCustomToast(context, 'Cart is empty', isSuccess: false);
      return;
    }

    if (!PayChanguConfig.isConfigured) {
      print('Config check failed: PayChanguConfig.isConfigured = false');
      ToastHelper.showCustomToast(context, 'Payment config error', isSuccess: false);
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
        ToastHelper.showCustomToast(context, 'Order placed successfully!', isSuccess: true);
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

  // ... your _row, build, and image methods remain unchanged ...
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
        ToastHelper.showCustomToast(context, 'Payment check timed out', isSuccess: false);
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
    ToastHelper.showCustomToast(widget.rootContext, 'Payment Successful!', isSuccess: true);
    if (mounted) {
      Navigator.pop(context);
      Navigator.pop(widget.rootContext, true);
    }
  }

  void _handleFailure() {
    _cleanup();
    print('FAILURE HANDLER CALLED');
    ToastHelper.showCustomToast(widget.rootContext, 'Payment not completed', isSuccess: false);
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