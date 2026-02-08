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

  Widget _itemImage(String? raw, {double size = 64}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return _placeholder(size);

    if (s.startsWith('http')) {
      return Image.network(s, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(size));
    }

    if (s.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(s).getDownloadURL(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return _loading(size);
          return snap.hasData
              ? Image.network(snap.data!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(size))
              : _placeholder(size);
        },
      );
    }

    try {
      final base64 = s.contains(',') ? s.split(',').last : s;
      if (base64.length > 100) {
        return Image.memory(base64Decode(base64), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(size));
      }
    } catch (_) {}

    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(s).getDownloadURL(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _loading(size);
        return snap.hasData
            ? Image.network(snap.data!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(size))
            : _placeholder(size);
      },
    );
  }

  Widget _placeholder(double size) => Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );

  Widget _loading(double size) => Container(
        width: size,
        height: size,
        color: Colors.grey[100],
        alignment: Alignment.center,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );

  Future<void> _startPayChanguPayment() async {
    if (widget.items.isEmpty) {
      ToastHelper.showCustomToast(context, 'Your cart is empty.', isSuccess: false, errorMessage: "Please add items to your cart before proceeding to payment.");
      return;
    }

    if (!PayChanguConfig.isConfigured) {
      ToastHelper.showCustomToast(context, 'Payment not configured correctly', isSuccess: false, errorMessage: "Payment gateway is not properly configured. Please contact support.");
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

      try {
        await InternetAddress.lookup('api.paychangu.com');
      } on SocketException {
        throw Exception('Cannot reach payment server. Check your connection.');
      }

      final body = PayChanguConfig.buildPaymentBody(
        txRef: txRef,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        amount: _total.toInt().toString(),
      );

      final response = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (![200, 201].contains(response.statusCode)) {
        throw Exception('Payment gateway error: ${response.statusCode}');
      }

      final jsonResponse = json.decode(response.body);
      final status = (jsonResponse['status'] ?? '').toString().toLowerCase();

      if (status != 'success') {
        throw Exception(jsonResponse['message'] ?? 'Failed to start payment');
      }

      final checkoutUrl = jsonResponse['data']?['checkout_url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('No checkout URL received');
      }

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
        // Payment succeeded → clear cart, show confirmation, etc.
        ToastHelper.showCustomToast(context, 'Order placed successfully!', isSuccess: true, errorMessage: 'your order has been placed successfully');
      }
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(context, 'Network error', isSuccess: false, errorMessage: e.message);
    } on TimeoutException {
      ToastHelper.showCustomToast(context, 'Request timed out', isSuccess: false, errorMessage: 'The payment request took too long. Please check your connection and try again.');
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Payment failed', isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _paying = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
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
                Expanded(child: Text('Secure checkout — review your details before paying.')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Order Items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final item = widget.items[i];
                      return Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: _itemImage(item.image, size: 64),
                            ),
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
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_mwk(item.price)} × ${item.quantity}',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _mwk(item.price * item.quantity),
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, -4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Order Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _row('Subtotal', _mwk(_subtotal)),
                _row('Delivery Fee', _mwk(_deliveryFee)),
                const Divider(height: 32),
                _row('Total', _mwk(_total), bold: true, green: true),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _paying || widget.items.isEmpty ? null : _startPayChanguPayment,
                    icon: _paying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          )
                        : const Icon(Icons.payment),
                    label: Text(
                      _paying ? 'Processing...' : 'Pay MWK ${_mwk(_total)}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
}

// ───────────────────────────────────────────────
// Payment WebView – fully deep-link driven
// ───────────────────────────────────────────────

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
    _initWebView();
    _startPolling();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _isLoading = p < 100),
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            if (request.url.startsWith('vero360://payment-complete')) {
              final uri = Uri.parse(request.url);
              final status = uri.queryParameters['status']?.toLowerCase() ?? 'unknown';
              final tx = uri.queryParameters['tx_ref'];

              if (tx == widget.txRef) {
                if (status.contains('success') || status == 'successful') {
                  _handleSuccess();
                } else {
                  _handleFailure();
                }
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
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _verifyStatus());

    // Safety: stop polling after 10 minutes
    Timer(const Duration(minutes: 10), () {
      if (mounted && _pollTimer?.isActive == true) {
        _pollTimer?.cancel();
        if (mounted) {
          ToastHelper.showCustomToast(context, 'Payment check timed out', isSuccess: false, errorMessage: "Unable to verify payment status. Please check your orders.");
          Navigator.pop(context);
        }
      }
    });
  }

  Future<void> _verifyStatus() async {
    try {
      final res = await http.get(
        PayChanguConfig.verifyUri(widget.txRef),
        headers: PayChanguConfig.authHeaders,
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final status = (data['data']?['status'] as String?)?.toLowerCase() ?? '';

        if (status.contains('success')) {
          _handleSuccess();
        } else if (['failed', 'cancelled', 'expired'].contains(status)) {
          _handleFailure();
        }
      }
    } catch (_) {
      // silent - keep polling
    }
  }

  void _handleSuccess() {
    _cleanup();
    ToastHelper.showCustomToast(widget.rootContext, 'Payment Successful!', isSuccess: true, errorMessage: 'payment is successful');
    if (mounted) {
      Navigator.pop(context);
      Navigator.pop(widget.rootContext, true);
    }
  }

  void _handleFailure() {
    _cleanup();
    ToastHelper.showCustomToast(widget.rootContext, 'Payment not completed', isSuccess: false, errorMessage: '');
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