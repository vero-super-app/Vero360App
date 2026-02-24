import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GeneralPages/address.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum DeliveryType { speed, cts, pickup }

class CheckoutFromCartPage extends StatefulWidget {
  final List<CartModel> items;
  const CheckoutFromCartPage({super.key, required this.items});

  @override
  State<CheckoutFromCartPage> createState() => _CheckoutFromCartPageState();
}

class _CheckoutFromCartPageState extends State<CheckoutFromCartPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFF3E0);

  static const double _feeSpeed = 0;
  static const double _feeCts = 0;
  static const double _feePickup = 0;

  bool _paying = false;
  DeliveryType _deliveryType = DeliveryType.cts;

  final _addrSvc = AddressService();
  Address? _defaultAddr;
  bool _loadingAddr = true;
  bool _loggedIn = false;

  late final NumberFormat _mwkFmt =
      NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
  String _mwk(num v) => _mwkFmt.format(v);

  double get _subtotal =>
      widget.items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  double get _delivery {
    switch (_deliveryType) {
      case DeliveryType.speed:
        return _feeSpeed;
      case DeliveryType.cts:
        return _feeCts;
      case DeliveryType.pickup:
        return _feePickup;
    }
  }

  double get _total => max(0.0, _subtotal + _delivery);

  String _deliveryLabel(DeliveryType d) {
    switch (d) {
      case DeliveryType.speed:
        return 'Speed';
      case DeliveryType.cts:
        return 'CTS';
      case DeliveryType.pickup:
        return 'Pickup';
    }
  }

  @override
  void initState() {
    super.initState();
    _initAuthAndAddress();
  }

  Future<String?> _readAuthToken() async => AuthHandler.getTokenForApi();

  Future<void> _initAuthAndAddress() async {
    setState(() {
      _loadingAddr = true;
      _defaultAddr = null;
      _loggedIn = false;
    });
    final token = await _readAuthToken();
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _loggedIn = false;
        _loadingAddr = false;
      });
      return;
    }
    try {
      final list = await _addrSvc.getMyAddresses();
      Address? def;
      for (final a in list) {
        if (a.isDefault) {
          def = a;
          break;
        }
      }
      setState(() {
        _loggedIn = true;
        _defaultAddr = def;
        _loadingAddr = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _defaultAddr = null;
        _loadingAddr = false;
      });
    }
  }

  Future<bool> _ensureDefaultAddressIfNeeded() async {
    if (_deliveryType == DeliveryType.pickup) return true;
    if (!_loggedIn) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to continue.',
        isSuccess: false,
        errorMessage: 'Auth required',
      );
      return false;
    }
    if (_defaultAddr != null) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delivery address required'),
        content: const Text('You need to set a default address before checkout.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set address')),
        ],
      ),
    );
    if (go == true) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
      await _initAuthAndAddress();
      return _defaultAddr != null;
    }
    return false;
  }

  // ✅ Same image logic as CheckoutPage (http / base64 / gs:// / firebase storage path)
  Widget _itemImage(String raw, {double size = 64}) {
    final s = raw.trim();
    if (s.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    // HTTP URL
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Image.network(
        s,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      );
    }

    // Firebase Storage gs://
    if (s.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(s).getDownloadURL(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return Container(
              width: size,
              height: size,
              color: Colors.grey.shade100,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return Image.network(
            snap.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              color: Colors.grey.shade200,
              child: const Icon(Icons.image_not_supported, color: Colors.grey),
            ),
          );
        },
      );
    }

    // Try Base64
    try {
      final base64Part = s.contains(',') ? s.split(',').last : s;
      if (base64Part.length > 150) {
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover);
      }
    } catch (_) {}

    // Try Firebase Storage path
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(s).getDownloadURL(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: size,
            height: size,
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        }
        return Image.network(
          snap.data!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          ),
        );
      },
    );
  }

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
    if (!await _ensureDefaultAddressIfNeeded()) return;

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

      // DNS test
      try {
        await InternetAddress.lookup('api.paychangu.com');
      } on SocketException catch (_) {
        throw Exception(
            'Cannot connect to payment service. Please check your internet connection.');
      }

      final response = await http
          .post(
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
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero 360 Payment',
                'description': 'Cart order • Delivery: ${_deliveryLabel(_deliveryType)} • ${_deliveryType == DeliveryType.pickup ? "Pickup" : "Deliver to: ${_defaultAddr?.city ?? "-"}"}',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseJson = json.decode(response.body);

        final status = (responseJson['status'] ?? '').toString().toLowerCase();
        if (status == 'success') {
          final checkoutUrl = responseJson['data']['checkout_url'] as String;

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
      ToastHelper.showCustomToast(
        context,
        'Network error. Please check your internet connection.',
        isSuccess: false,
        errorMessage: e.message,
      );
    } on TimeoutException {
      ToastHelper.showCustomToast(
        context,
        'Connection timeout. Please try again.',
        isSuccess: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
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
                Expanded(child: Text('Secure checkout — review your address and payment details.')),
              ],
            ),
          ),
          const SizedBox(height: 12),

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
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: _itemImage(it.image, size: 64),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_mwk(it.price)}  •  Qty: ${it.quantity}',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _mwk(it.price * it.quantity),
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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

          const SizedBox(height: 12),

          // Delivery Type
          Card(
            elevation: 6,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivery Type',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<DeliveryType>(
                    initialValue: _deliveryType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Choose delivery option',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: DeliveryType.speed, child: Text('Speed')),
                      DropdownMenuItem(value: DeliveryType.cts, child: Text('CTS')),
                      DropdownMenuItem(value: DeliveryType.pickup, child: Text('Pickup')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _deliveryType = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_deliveryLabel(_deliveryType)} • Fee: ${_mwk(_delivery)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Delivery Address
          _DeliveryAddressCard(
            loading: _loadingAddr,
            loggedIn: _loggedIn,
            address: _defaultAddr,
            pickupSelected: _deliveryType == DeliveryType.pickup,
            pickupLocation: 'Pickup at merchant(s)',
            onManage: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressPage()));
              await _initAuthAndAddress();
            },
          ),

          const SizedBox(height: 12),

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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _row('Subtotal', _mwk(_subtotal)),
                _row('Delivery', _mwk(_delivery)),
                const SizedBox(height: 8),
                const Divider(thickness: 1),
                const SizedBox(height: 8),
                _row('Total', _mwk(_total), bold: true, green: true),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_paying || widget.items.isEmpty || !(_deliveryType == DeliveryType.pickup || _defaultAddr != null))
                        ? null
                        : _startPayChanguPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandOrange,
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
                          const SizedBox(
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
}

// ── Delivery Address card (same pattern as checkout_page) ─────────
class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({
    required this.loading,
    required this.loggedIn,
    required this.address,
    required this.onManage,
    required this.pickupSelected,
    this.pickupLocation,
  });

  final bool loading;
  final bool loggedIn;
  final Address? address;
  final VoidCallback onManage;
  final bool pickupSelected;
  final String? pickupLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery Address',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (pickupSelected)
              _line(
                'Pickup selected',
                (pickupLocation ?? '').trim().isEmpty
                    ? 'Pickup at merchant(s)'
                    : pickupLocation!.trim(),
              )
            else if (loading)
              const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (!loggedIn)
              _line('Not logged in', 'Please log in to select address')
            else if (address == null)
              _line('No default address', 'Set your default delivery address')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line(_label(address!.addressType), address!.city),
                  if (address!.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      address!.description,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: pickupSelected ? null : onManage,
                icon: const Icon(Icons.location_pin),
                label: Text(address == null ? 'Set address' : 'Change'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _line(String a, String b) {
    return Row(
      children: [
        Expanded(
          child: Text(
            a,
            style: const TextStyle(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            b,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      ],
    );
  }

  static String _label(AddressType t) {
    switch (t) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Office';
      case AddressType.business:
        return 'Business';
      case AddressType.other:
        return 'Other';
    }
  }
}

// ────────────────────── IN-APP PAYMENT PAGE ──────────────────────
class InAppPaymentPage extends StatefulWidget {
  final String checkoutUrl;
  final String txRef;
  final double totalAmount;
  final BuildContext rootContext;
  /// When set, this is a digital product purchase: show product-specific messages and go back to homepage after payment.
  final String? digitalProductName;

  const InAppPaymentPage({
    super.key,
    required this.checkoutUrl,
    required this.txRef,
    required this.totalAmount,
    required this.rootContext,
    this.digitalProductName,
  });

  @override
  State<InAppPaymentPage> createState() => _InAppPaymentPageState();
}

class _InAppPaymentPageState extends State<InAppPaymentPage> {
  late final WebViewController _controller;
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _resultHandled = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _startStatusPolling();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.navigate;

          final isPaymentCompleteDeepLink =
              uri.scheme == 'vero360' && uri.host == 'payment-complete';
          if (isPaymentCompleteDeepLink) {
            final status = (uri.queryParameters['status'] ?? '').toLowerCase();
            if (status == 'failed' || status == 'cancelled') {
              _handlePaymentFailure();
            } else {
              _handlePaymentSuccess();
            }
            return NavigationDecision.prevent;
          }

          final isBackendReturnUrl = request.url.startsWith(PayChanguConfig.returnUrl);
          if (isBackendReturnUrl) {
            final status = (uri.queryParameters['status'] ?? '').toLowerCase();
            if (status == 'failed' || status == 'cancelled') {
              _handlePaymentFailure();
            } else if (status.isNotEmpty) {
              _handlePaymentSuccess();
            }
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
        onProgress: (int progress) => setState(() => _isLoading = progress < 100),
        onPageStarted: (String url) => setState(() => _isLoading = true),
        onPageFinished: (String url) => setState(() => _isLoading = false),
        onWebResourceError: (_) => setState(() => _isLoading = false),
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
    } catch (_) {}
  }

  void _handlePaymentSuccess() {
    if (_resultHandled) return;
    _resultHandled = true;
    _pollTimer?.cancel();
    final isDigital = widget.digitalProductName != null && widget.digitalProductName!.isNotEmpty;
    final productName = widget.digitalProductName ?? 'your order';

    ToastHelper.showCustomToast(
      widget.rootContext,
      isDigital ? 'Payment successful!' : 'Payment Successful!',
      isSuccess: true,
      errorMessage: '',
    );

    if (isDigital) {
      // Digital purchase: thank-you message (email not sent from app)
      final message =
          'Thank you for purchasing $productName on Vero. Contact support if you need instructions.';
      if (mounted) {
        Navigator.of(context).pop(); // close webview
        if (!widget.rootContext.mounted) return;
        showDialog(
          context: widget.rootContext,
          builder: (ctx) => AlertDialog(
            title: const Text('Purchase successful'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(widget.rootContext).pop(); // back to homepage (pops DigitalProductDetailPage)
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      if (mounted) {
        Navigator.of(context).pop(); // close webview
        Navigator.of(widget.rootContext).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OrdersPage()),
          (_) => false,
        );
      }
    }
  }

  void _handlePaymentFailure() {
    if (_resultHandled) return;
    _resultHandled = true;
    _pollTimer?.cancel();
    final isDigital = widget.digitalProductName != null && widget.digitalProductName!.isNotEmpty;

    if (isDigital) {
      // Digital purchase: failure message (email not sent from app)
      final message =
          'Payment was not successful. Contact support if you need help or a refund.';
      ToastHelper.showCustomToast(
        widget.rootContext,
        'Payment failed',
        isSuccess: false,
        errorMessage: 'Payment was not completed',
      );
      if (mounted) {
        Navigator.of(context).pop(); // close webview
        if (!widget.rootContext.mounted) return;
        showDialog(
          context: widget.rootContext,
          builder: (ctx) => AlertDialog(
            title: const Text('Payment failed'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(widget.rootContext).pop(); // back to homepage
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      ToastHelper.showCustomToast(
        widget.rootContext,
        'Payment Failed or Cancelled',
        isSuccess: false,
        errorMessage: 'Payment was not completed',
      );
      if (mounted) Navigator.of(context).pop();
    }
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
