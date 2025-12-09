import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:io'; // Add this import

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _paying = false;

  double get _subtotal =>
      widget.items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;
  double get _total => max(0.0, _subtotal + _deliveryFee);
  String _mwk(num n) => 'MWK ${n.toStringAsFixed(2)}';

  Future<void> _startPayChanguPayment() async {
    if (widget.items.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Your cart is empty.',
        isSuccess: false,
        errorMessage: 'Empty cart',
      );
      return;
    }

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

      // First, test if we can resolve the hostname
      try {
        final lookup = await InternetAddress.lookup('api.paychangu.com');
        print('DNS lookup successful: ${lookup.first.address}');
      } on SocketException catch (e) {
        print('DNS lookup failed: $e');
        throw Exception('Cannot connect to payment service. Please check your internet connection.');
      }

      // PayChangu API call
      final response = await http.post(
        Uri.parse('https://api.paychangu.com/payment'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u',
        },
        body: json.encode({
          'tx_ref': txRef,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'phone_number': phone,
          'currency': 'MWK',
          'amount': _total.round().toString(),
          'payment_methods': ['card', 'mobile_money', 'bank'],
          'callback_url': 'https://webhook.site/your-webhook',
          'return_url': 'https://your-app.com/payment-success',
          'customization': {
            'title': 'Vero 360 Payment',
            'description': 'Order checkout',
          },
        }),
      ).timeout(const Duration(seconds: 30));

      print('API Response: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseJson = json.decode(response.body);
        
        if (responseJson['status'] == 'success' || responseJson['status'] == 'Success') {
          final checkoutUrl = responseJson['data']['checkout_url'] as String;
          print('Opening checkout URL: $checkoutUrl');

          if (!mounted) return;
          
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InAppPaymentPage(
              checkoutUrl: checkoutUrl,
              txRef: txRef,
              totalAmount: _total,
              rootContext: context,
            ),
          ));
        } else {
          throw Exception(responseJson['message'] ?? 'Payment failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } on SocketException catch (e) {
      print('Network Error: $e');
      ToastHelper.showCustomToast(
        context,
        'Network error. Please check your internet connection.',
        isSuccess: false,
        errorMessage: e.message,
      );
    } on TimeoutException catch (e) {
      print('Timeout Error: $e');
      ToastHelper.showCustomToast(
        context,
        'Connection timeout. Please try again.',
        isSuccess: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
      print('Payment Error: $e');
      ToastHelper.showCustomToast(
        context,
        'Payment initialization failed',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Trust banner (same as main)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _brandSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _brandOrange.withValues(alpha: 0.35)),
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

            // Items summary with thumbnails
            Card(
              elevation: 6,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your Items',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),
                    ListView.separated(
                      itemCount: widget.items.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => const Divider(height: 14),
                      itemBuilder: (_, i) {
                        final it = widget.items[i];
                        final lineTotal = it.price * it.quantity;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 64, height: 64,
                                child: (it.image.isNotEmpty)
                                    ? Image.network(
                                        it.image,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const _ImgFallback(),
                                      )
                                    : const _ImgFallback(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_mwk(it.price)}  •  Qty: ${it.quantity}',
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                            child: const Icon(Icons.shopping_bag, color: Colors.grey),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text('Quantity: ${item.quantity}'),
                          trailing: Text(
                            _mwk(item.price * item.quantity),
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, -2),
                ),
              ],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _row('Subtotal', _mwk(_subtotal)),
                _row('Delivery Fee', _mwk(_deliveryFee)),
                const SizedBox(height: 8),
                const Divider(thickness: 1),
                const SizedBox(height: 8),
                _row('Total', _mwk(_total), bold: true, green: true),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _paying || widget.items.isEmpty ? null : _startPayChanguPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_paying)
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          const Icon(Icons.payment, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          _paying ? 'Processing...' : 'Pay Now',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: green ? const Color(0xFF2E7D32) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────── SIMPLIFIED IN-APP PAYMENT PAGE ──────────────────────
class InAppPaymentPage extends StatefulWidget {
  final String checkoutUrl;
  final String txRef;
  final double totalAmount;
  final BuildContext rootContext;

  const InAppPaymentPage({
    Key? key,
    required this.checkoutUrl,
    required this.txRef,
    required this.totalAmount,
    required this.rootContext,
  }) : super(key: key);

  @override
  State<InAppPaymentPage> createState() => _InAppPaymentPageState();
}

class _InAppPaymentPageState extends State<InAppPaymentPage> {
  late final WebViewController _controller;
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    print('Opening PayChangu URL: ${widget.checkoutUrl}');
    _initializeWebView();
    _startStatusPolling();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (int progress) {
          setState(() {
            _isLoading = progress < 100;
          });
        },
        onPageStarted: (String url) {
          setState(() {
            _isLoading = true;
            _hasError = false;
          });
        },
        onPageFinished: (String url) {
          setState(() => _isLoading = false);
        },
        onWebResourceError: (WebResourceError error) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _startStatusPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (timer) async {
      await _checkPaymentStatus();
    });
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.paychangu.com/transaction/verify/${widget.txRef}'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = (data['data']?['status'] as String?)?.toLowerCase();
        
        if (status == 'successful' || status == 'success') {
          _handlePaymentSuccess();
        } else if (status == 'failed' || status == 'cancelled') {
          _handlePaymentFailure();
        }
      }
    } catch (e) {
      // Silently fail for polling
    }
  }

  void _handlePaymentSuccess() {
    _pollTimer?.cancel();
    ToastHelper.showCustomToast(
      widget.rootContext,
      'Payment Successful!',
      isSuccess: true,
      errorMessage: '',
    );
    if (mounted) {
      Navigator.of(context).pop();
      Navigator.of(widget.rootContext).pop(true);
    }
  }

  void _handlePaymentFailure() {
    _pollTimer?.cancel();
    ToastHelper.showCustomToast(
      widget.rootContext,
      'Payment Failed or Cancelled',
      isSuccess: false,
      errorMessage: 'Payment was not completed',
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: const Color(0xFFFF8A00),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Cancel Payment?'),
                content: const Text('Are you sure you want to cancel this payment?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Continue Payment'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _handlePaymentFailure();
                    },
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A00)),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Loading payment gateway...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}