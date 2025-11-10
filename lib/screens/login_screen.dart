import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/merchantbottomnavbar.dart';
import 'package:vero360_app/screens/register_screen.dart';
import 'package:vero360_app/services/auth_service.dart';
import 'package:vero360_app/toasthelper.dart';
import 'package:vero360_app/widget/oauth_buttons.dart';


class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const fieldFill = Color(0xFFF7F7F9);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _socialLoading = false;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _handleAuthResult(Map<String, dynamic>? result) async {
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();

    final token = result['token']?.toString();
    if (token == null || token.isEmpty) {
      ToastHelper.showCustomToast(context, 'No token received', isSuccess: false, errorMessage: '');
      return;
    }
    await prefs.setString('token', token);
    await prefs.setString('jwt_token', token);

    final user = Map<String, dynamic>.from(result['user'] ?? {});
    final displayId = user['email']?.toString()
        ?? user['phone']?.toString()
        ?? _identifier.text.trim();
    await prefs.setString('email', displayId);

    final role = (user['role'] ?? user['userRole'] ?? '').toString().toLowerCase();
    if (!mounted) return;
    if (role == 'merchant') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MerchantBottomnavbar(email: displayId)),
        (_) => false,
      );
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => Bottomnavbar(email: displayId)),
      (_) => false,
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final result = await AuthService().loginWithIdentifier(
        _identifier.text.trim(),
        _password.text.trim(),
        context,
      );
      await _handleAuthResult(result);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _socialLoading = true);
    try {
      final resp = await AuthService().continueWithGoogle(context);
      await _handleAuthResult(resp);
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _apple() async {
    // We allow the button to show everywhere, but only iOS actually runs the flow.
    if (!Platform.isIOS) return;
    setState(() => _socialLoading = true);
    try {
      final resp = await AuthService().continueWithApple(context);
      await _handleAuthResult(resp);
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? trailing,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: trailing,
      filled: true,
      fillColor: AppColors.fieldFill,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.brandOrange, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, -1), end: Alignment(0, 1),
              colors: [Color(0xFFEFF6FF), Colors.white],
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white,
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo_mark.png',
                          width: 72, height: 72, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                            const Icon(Icons.eco, size: 42, color: AppColors.brandOrange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Welcome back',
                      style: TextStyle(color: AppColors.title, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),

                    // Logo-only socials (always visible)
                    OAuthButtonsRow(
                      onGoogle: _socialLoading ? null : _google,
                      onApple:  _socialLoading ? null : _apple,
                    ),
                    const SizedBox(height: 18),

                    // Form card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _identifier,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: _fieldDecoration(
                                label: 'Email or Phone',
                                hint: 'you@example.com or +2659XXXXXXXX',
                                icon: Icons.person_outline,
                              ),
                              validator: (v) {
                                final val = v?.trim() ?? '';
                                if (val.isEmpty) return 'Email or phone is required';
                                final isEmail = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(val);
                                final digits = val.replaceAll(RegExp(r'\D'), '');
                                final isLocal = RegExp(r'^(08|09)\d{8}$').hasMatch(digits);
                                final isE164  = RegExp(r'^\+265[89]\d{8}$').hasMatch(val);
                                if (!isEmail && !isLocal && !isE164) return 'Use email or phone (08/09… or +265…)';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: _fieldDecoration(
                                label: 'Password',
                                hint: '••••••••',
                                icon: Icons.lock_outline,
                                trailing: IconButton(
                                  tooltip: _obscure ? 'Show' : 'Hide',
                                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Password is required';
                                if (v.length < 6) return 'Must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity, height: 50,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandOrange,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: Text(_loading ? 'Signing in…' : 'Sign in',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account?", style: TextStyle(color: AppColors.body, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: _loading ? null : () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                          },
                          child: const Text('Create one',
                            style: TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
