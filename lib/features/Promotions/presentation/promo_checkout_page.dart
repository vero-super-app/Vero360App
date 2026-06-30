import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class PromoCheckoutPage extends StatefulWidget {
  const PromoCheckoutPage({super.key, required this.promo});

  final PromoModel promo;

  @override
  State<PromoCheckoutPage> createState() => _PromoCheckoutPageState();
}

class _PromoCheckoutPageState extends State<PromoCheckoutPage> {
  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _svc = PromoService();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _prefillContact();
  }

  Future<void> _prefillContact() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text =
          (prefs.getString('fullName') ?? prefs.getString('name') ?? '').trim();
      _phoneCtrl.text = (prefs.getString('phone') ?? '').trim();
      _emailCtrl.text = (prefs.getString('email') ?? '').trim();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidMwLocalPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^0[89]\d{8}$').hasMatch(digits);
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 &&
        (digits.startsWith('0') || digits.startsWith('265'))) {
      final rest =
          digits.startsWith('265') ? digits.substring(3) : digits.substring(1);
      return '+265$rest';
    }
    return raw.trim().isEmpty ? '+265888000000' : (raw.startsWith('+') ? raw : '+$raw');
  }

  Future<bool> _ensureLoggedIn() async {
    if (await AuthHandler.isAuthenticated()) return true;
    if (!mounted) return false;
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log in required'),
        content: const Text(
          'Sign in to claim this promotion and complete checkout.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _orange),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
    if (goLogin != true || !mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    return AuthHandler.isAuthenticated();
  }

  Future<void> _claimFreePromo() async {
    if (!await _ensureLoggedIn()) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await _svc.subscribe(widget.promo.id, 0);
      if (!mounted) return;
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isSuccess: false,
        errorMessage: 'Could not claim promotion',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _payNow() async {
    if (!await _ensureLoggedIn()) return;
    if (!_formKey.currentState!.validate()) return;

    final amount = widget.promo.displayPrice;
    if (amount <= 0) {
      await _claimFreePromo();
      return;
    }

    setState(() => _submitting = true);
    try {
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      final parts = name.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : 'Customer';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      try {
        await InternetAddress.lookup('api.paychangu.com');
      } on SocketException {
        throw Exception(
          'Cannot connect to payment service. Check your internet connection.',
        );
      }

      final txRef = 'vero-promo-${widget.promo.id}-${DateTime.now().millisecondsSinceEpoch}';
      final response = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode({
              'tx_ref': txRef,
              'first_name': firstName,
              'last_name': lastName,
              'email': email,
              'phone_number': phone,
              'currency': 'MWK',
              'amount': amount.round().toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero 360 Promotion',
                'description': widget.promo.title,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final status = (responseJson['status'] ?? '').toString().toLowerCase();
      if (status != 'success') {
        throw Exception(responseJson['message'] ?? 'Payment failed');
      }

      final checkoutUrl = responseJson['data']['checkout_url'] as String;
      if (!mounted) return;

      final promo = widget.promo;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InAppPaymentPage(
            checkoutUrl: checkoutUrl,
            txRef: txRef,
            totalAmount: amount,
            rootContext: context,
            popOnlyOnSuccess: true,
            onSuccessNavigate: (root) async {
              try {
                await _svc.subscribe(promo.id, amount);
              } catch (_) {}
              if (!root.mounted) return;
              ToastHelper.showCustomToast(
                root,
                'Promotion activated!',
                isSuccess: true,
                errorMessage: '',
              );
              Navigator.of(root).pop();
            },
          ),
        ),
      );
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Network error. Check your connection.',
        isSuccess: false,
        errorMessage: e.message,
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isSuccess: false,
        errorMessage: 'Payment failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promotion claimed'),
        content: Text(
          'You have successfully claimed "${widget.promo.title}". '
          'Check your notifications for details.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: _orange),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final promo = widget.promo;
    final imageUrl = promo.resolvedImageUrl;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Promotion checkout',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFECEEF2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null)
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ResilientCachedNetworkImage(
                          url: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            promo.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: _ink,
                            ),
                          ),
                          if ((promo.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              promo.description!.trim(),
                              style: const TextStyle(
                                color: _muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            promo.formattedPrice,
                            style: const TextStyle(
                              color: _orange,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Your details',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'We use this for payment and promotion delivery.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _nameCtrl,
                label: 'Full name',
                icon: PhosphorIconsBold.user,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _field(
                controller: _phoneCtrl,
                label: 'Phone number',
                icon: PhosphorIconsBold.phone,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!_isValidMwLocalPhone(v)) {
                    return 'Enter a valid Malawi number (09…)';
                  }
                  return null;
                },
              ),
              _field(
                controller: _emailCtrl,
                label: 'Email',
                icon: PhosphorIconsBold.envelope,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _payNow,
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          promo.isFree
                              ? PhosphorIconsBold.gift
                              : PhosphorIconsBold.creditCard,
                        ),
                  label: Text(
                    _submitting
                        ? 'Please wait…'
                        : (promo.isFree ? 'Claim for free' : 'Pay & claim offer'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    PhosphorIconsBold.shieldCheck,
                    size: 16,
                    color: _muted.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Secure checkout via PayChangu • Mobile money & card',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: _muted),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFECEEF2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _orange, width: 1.5),
          ),
        ),
      ),
    );
  }
}
