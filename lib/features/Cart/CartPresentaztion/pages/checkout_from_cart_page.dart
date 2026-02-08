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
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFF3E0);

  bool _paying = false;

  late final NumberFormat _mwkFmt = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'MWK ',
    decimalDigits: 0,
  );

  String _mwk(num v) => _mwkFmt.format(v);

  double get _subtotal => widget.items.fold(
        0.0,
        (sum, item) => sum + (item.price * item.quantity),
      );

  double get _deliveryFee => widget.items.isEmpty ? 0.0 : 20.0;

  double get _total => max(0.0, _subtotal + _deliveryFee);

  Widget _itemImage(String raw, {double size = 64}) {
    final s = raw.trim();
    if (s.isEmpty) {
      return _placeholderImage(size);
    }

    // HTTP/HTTPS
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Image.network(
        s,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(size),
      );
    }

    // gs:// Firebase Storage reference
    if (s.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(s).getDownloadURL(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _loadingPlaceholder(size);
          }
          if (!snap.hasData || snap.hasError) {
            return _placeholderImage(size);
          }
          return Image.network(
            snap.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholderImage(size),
          );
        },
      );
    }

    // Base64 attempt
    try {
      final base64Part = s.contains(',') ? s.split(',').last : s;
      if (base64Part.length > 100) { // reasonable threshold
        final bytes = base64Decode(base64Part);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholderImage(size),
        );
      }
    } catch (_) {}

    // Plain Firebase Storage path
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(s).getDownloadURL(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _loadingPlaceholder(size);
        }
        if (!snap.hasData || snap.hasError) {
          return _placeholderImage(size);
        }
        return Image.network(
          snap.data!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholderImage(size),
        );
      },
    );
  }

  Widget _placeholderImage(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }

  Widget _loadingPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _startPayChanguPayment() async {
    if (widget.items.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Your cart is empty.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    if (!PayChanguConfig.isConfigured) {
      ToastHelper.showCustomToast(
        context,
        'Payment service not properly configured',
        isSuccess: false,
        errorMessage: 'Please check your PayChanguConfig settings.',
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

      // Optional quick connectivity check
      try {
        await InternetAddress.lookup('api.paychangu.com');
      } on SocketException {
        throw Exception('Cannot reach payment server. Check your internet.');
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

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseJson = json.decode(response.body);
        final status = (responseJson['status'] ?? '').toString().toLowerCase();

        if (status == 'success') {
          final checkoutUrl = responseJson['data']['checkout_url'] as String?;

          if (checkoutUrl == null || checkoutUrl.isEmpty) {
            throw Exception('No checkout URL received from gateway');
          }

          if (!mounted) return;

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InAppPaymentPage(
                checkoutUrl: checkoutUrl,
                txRef: txRef,
                totalAmount: _total,
                rootContext: context,
              ),
            ),
          );
        } else {
          throw Exception(responseJson['message'] ?? 'Payment initiation failed');
        }
      } else {
        throw Exception('Server responded with status ${response.statusCode}');
      }
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Network error',
        isSuccess: false,
        errorMessage: e.message,
      );
    } on TimeoutException {
      ToastHelper.showCustomToast(
        context,
        'Request timed out',
        isSuccess: false,
        errorMessage: 'The payment request took too long. Please try again.',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Could not start payment',
        isSuccess: false,
        errorMessage: e.toString(),
      );
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
                Expanded(
                  child: Text('Secure checkout — review your details before paying.'),
                ),
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
                  const Text(
                    'Order Items',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
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
                              child: _itemImage(item.image ?? '', size: 64),
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
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
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
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
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
//  Payment WebView Page
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
          onProgress: (progress) => setState(() => _isLoading = progress < 100),
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            if (request.url.startsWith('vero360://')) {
              final uri = Uri.parse(request.url);
              final status = uri.queryParameters['status']?.toLowerCase() ?? 'unknown';

              if (status.contains('success')) {
                _handleSuccess();
              } else {
                _handleFailure();
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
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _verifyPaymentStatus();
    });
  }

  Future<void> _verifyPaymentStatus() async {
    try {
      final response = await http.get(
        PayChanguConfig.verifyUri(widget.txRef),
        headers: PayChanguConfig.authHeaders,
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final status = (jsonData['data']?['status'] as String?)?.toLowerCase() ?? '';

        if (status == 'successful' || status == 'success') {
          _handleSuccess();
        } else if (status == 'failed' || status == 'cancelled' || status == 'expired') {
          _handleFailure();
        }
      }
    } catch (_) {
      // silent fail - continue polling
    }
  }

  void _handleSuccess() {
    _cleanup();
    ToastHelper.showCustomToast(
      widget.rootContext,
      'Payment completed successfully!',
      isSuccess: true,
      errorMessage: '',
    );
    if (mounted) {
      Navigator.pop(context);
      Navigator.pop(widget.rootContext, true);
    }
  }

  void _handleFailure() {
    _cleanup();
    ToastHelper.showCustomToast(
      widget.rootContext,
      'Payment was not completed',
      isSuccess: false,
      errorMessage: 'Please try again or choose a different payment method.',
    );
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
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A00)),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Loading secure payment page...',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}