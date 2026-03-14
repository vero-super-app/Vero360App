import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/config/paychangu_config.dart';

class RideCompletionScreen extends StatefulWidget {
  final Ride ride;
  final VoidCallback onDone;

  const RideCompletionScreen({
    super.key,
    required this.ride,
    required this.onDone,
  });

  @override
  State<RideCompletionScreen> createState() => _RideCompletionScreenState();
}

class _RideCompletionScreenState extends State<RideCompletionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isProcessingPayment = false;
  static const Color primaryColor = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double get _totalFare => widget.ride.actualFare ?? widget.ride.estimatedFare;
  double get _distance => widget.ride.actualDistance ?? widget.ride.estimatedDistance;
  double get _baseFare => _totalFare * 0.2;
  double get _distanceFare => _totalFare * 0.8;
  String get _driverName => widget.ride.driver?.fullName ?? 'Driver';
  double get _driverRating => widget.ride.driver?.rating ?? 0.0;
  int get _durationMins {
    final s = widget.ride.startTime;
    final e = widget.ride.endTime;
    if (s != null && e != null) return e.difference(s).inMinutes;
    return 0;
  }

  Future<void> _handleProceedToPayment() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to pay'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final navigator = Navigator.of(context);
    final scaffold = ScaffoldMessenger.of(context);
    final onDone = widget.onDone;
    final ride = widget.ride;
    final totalFare = _totalFare;
    final distanceStr = _distance.toStringAsFixed(1);

    setState(() => _isProcessingPayment = true);

    try {
      await InternetAddress.lookup('api.paychangu.com');
    } on SocketException catch (_) {
      if (mounted) setState(() => _isProcessingPayment = false);
      scaffold.showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please check and try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final txRef = 'ride_${ride.id}_${const Uuid().v4()}';
      final nameParts = (user.displayName ?? 'Passenger').split(' ');
      final firstName = nameParts.first;
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      final response = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode({
              'tx_ref': txRef,
              'first_name': firstName,
              'last_name': lastName,
              'email': user.email ?? '',
              'phone_number': user.phoneNumber ?? '',
              'currency': 'MWK',
              'amount': totalFare.round().toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero Ride Payment',
                'description': 'Ride #${ride.id} • $distanceStr km',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseJson = json.decode(response.body) as Map<String, dynamic>;
        final status = (responseJson['status'] ?? '').toString().toLowerCase();

        if (status == 'success') {
          final checkoutUrl = responseJson['data']['checkout_url'] as String;

          final paymentResult = await navigator.push<bool>(
            MaterialPageRoute(
              builder: (_) => _RidePaymentWebView(
                checkoutUrl: checkoutUrl,
                txRef: txRef,
              ),
            ),
          );

          if (paymentResult == true) {
            await _creditDriverWallet(ride);
            onDone();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                scaffold.showSnackBar(
                  const SnackBar(
                    content: Text('Payment successful!'),
                    backgroundColor: Colors.green,
                  ),
                );
                navigator.pop();
              } catch (_) {}
            });
          } else {
            if (mounted) setState(() => _isProcessingPayment = false);
            scaffold.showSnackBar(
              const SnackBar(
                content: Text('Payment was not completed. You can try again.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          throw Exception(responseJson['message'] ?? 'Payment initiation failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RidePayment] Error: $e');
      if (mounted) setState(() => _isProcessingPayment = false);
      try {
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _creditDriverWallet(Ride ride) async {
    final driverId = ride.driverId;
    if (driverId == null) return;

    try {
      final driverWalletId = driverId.toString();
      final driverName = ride.driver?.fullName ?? 'Driver $driverId';

      await FirebaseWalletService.getOrCreateWallet(
        merchantId: driverWalletId,
        merchantName: driverName,
      );

      final totalFare = ride.actualFare ?? ride.estimatedFare;
      final serviceFee = totalFare * FirebaseWalletService.serviceFeeRate;
      final driverEarnings = totalFare - serviceFee;

      await FirebaseWalletService.creditWallet(
        merchantId: driverWalletId,
        amount: driverEarnings,
        description:
            'Ride #${ride.id} earnings (${(ride.actualDistance ?? ride.estimatedDistance).toStringAsFixed(1)} km)',
        reference: 'ride_${ride.id}',
        type: 'ride_earnings',
      );

      if (serviceFee > 0) {
        await FirebaseWalletService.getOrCreateWallet(
          merchantId: FirebaseWalletService.superAdminUserId,
          merchantName: FirebaseWalletService.superAdminDisplayName,
        );
        await FirebaseWalletService.creditWallet(
          merchantId: FirebaseWalletService.superAdminUserId,
          amount: serviceFee,
          description:
              'Service fee from ride #${ride.id}',
          reference: 'ride_fee_${ride.id}',
          type: 'service_fee',
        );
      }

      if (kDebugMode) {
        debugPrint(
            '[RidePayment] Driver $driverWalletId credited MK${driverEarnings.toStringAsFixed(0)} '
            '(fee MK${serviceFee.toStringAsFixed(0)})');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RidePayment] Failed to credit driver wallet: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScaleTransition(
        scale: _scaleAnimation,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),

                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                    border: Border.all(
                      color: const Color(0xFF4CAF50),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 60,
                    color: Color(0xFF4CAF50),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Ride Complete!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Thanks to $_driverName',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.star_rounded, size: 16, color: Colors.amber[600]),
                    Text(
                      _driverRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Trip Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          if (_durationMins > 0)
                            Text(
                              '$_durationMins mins',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildDetailRow(
                        label: 'Distance',
                        value: '${_distance.toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 12),

                      Container(height: 1, color: Colors.grey[300]),
                      const SizedBox(height: 16),

                      Text(
                        'Fare Breakdown',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildFareRow(
                        label: 'Base Fare',
                        value: 'MK${_baseFare.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 8),

                      _buildFareRow(
                        label:
                            'Distance (${_distance.toStringAsFixed(1)} km)',
                        value: 'MK${_distanceFare.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 12),

                      Container(height: 1, color: Colors.grey[300]),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Fare',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'MK${_totalFare.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Payment method info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.security, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Secure payment via Airtel Money, TNM Mpamba, or card',
                          style: TextStyle(
                              fontSize: 13, color: Colors.blue[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isProcessingPayment ? null : _handleProceedToPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isProcessingPayment
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.payment, color: Colors.white),
                    label: Text(
                      _isProcessingPayment
                          ? 'Initiating Payment...'
                          : 'Pay MK${_totalFare.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isProcessingPayment
                        ? null
                        : () {
                            final nav = Navigator.of(context);
                            widget.onDone();
                            nav.pop();
                          },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Pay Later',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      ],
    );
  }

  Widget _buildFareRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      ],
    );
  }
}

/// In-app WebView that loads the PayChangu checkout page and polls
/// for payment completion. Returns `true` on success, `false`/null on failure.
class _RidePaymentWebView extends StatefulWidget {
  final String checkoutUrl;
  final String txRef;

  const _RidePaymentWebView({
    required this.checkoutUrl,
    required this.txRef,
  });

  @override
  State<_RidePaymentWebView> createState() => _RidePaymentWebViewState();
}

class _RidePaymentWebViewState extends State<_RidePaymentWebView> {
  late final WebViewController _controller;
  late final NavigatorState _navigator;
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _resultHandled = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final url = req.url.toLowerCase();
            final uri = Uri.tryParse(req.url);

            if (uri?.scheme == 'vero360' && uri?.host == 'payment-complete') {
              final s = (uri!.queryParameters['status'] ?? '').toLowerCase();
              _handleResult(s != 'failed' && s != 'cancelled');
              return NavigationDecision.prevent;
            }

            if (url.contains('/vero/payments/callback') ||
                url.contains('/vero/payments/return')) {
              final s = (uri?.queryParameters['status'] ?? '').toLowerCase();
              _handleResult(s != 'failed' && s != 'cancelled');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onProgress: (p) {
            if (mounted) setState(() => _isLoading = p < 100);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
            final lower = url.toLowerCase();
            if (lower.contains('/vero/payments/callback') ||
                lower.contains('/vero/payments/return')) {
              final uri = Uri.tryParse(url);
              final s = (uri?.queryParameters['status'] ?? '').toLowerCase();
              _handleResult(s != 'failed' && s != 'cancelled');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollPaymentStatus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.of(context);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollPaymentStatus() async {
    if (!mounted || _resultHandled) return;
    try {
      final response = await http.get(
        PayChanguConfig.verifyUri(widget.txRef),
        headers: PayChanguConfig.authHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final dataNode = data['data'] is Map
            ? data['data'] as Map<String, dynamic>
            : <String, dynamic>{};
        final status = (dataNode['status'] ??
                dataNode['payment_status'] ??
                '')
            .toString()
            .toLowerCase();

        if ({'successful', 'success', 'paid', 'completed'}.contains(status)) {
          _handleResult(true);
        } else if (status == 'failed' || status == 'cancelled') {
          _handleResult(false);
        }
      }
    } catch (_) {}
  }

  void _handleResult(bool success) {
    if (_resultHandled) return;
    _resultHandled = true;
    _pollTimer?.cancel();
    try {
      _navigator.pop(success);
    } catch (e) {
      if (kDebugMode) debugPrint('[RidePaymentWebView] pop error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: const Color(0xFFFF8A00),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _handleResult(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
