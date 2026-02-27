import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';

// Merchant dashboards
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_dashboard.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/oauth_buttons.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/firebaseAuth.dart';

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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthService _firebaseAuthService = FirebaseAuthService();
  final AuthService _authService = AuthService();

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

  // -------------------- Merchant dashboard selection --------------------

  Widget _getMerchantDashboard(String serviceKey, String email) {
    switch (serviceKey) {
      case 'marketplace':
        return MarketplaceMerchantDashboard(
          email: email,
          onBackToHomeTab: () {},
        );
      case 'food':
        return FoodMerchantDashboard(email: email);
      case 'taxi':
        return DriverDashboard();
      case 'accommodation':
        return AccommodationMerchantDashboard(email: email);
      case 'courier':
        return CourierMerchantDashboard(email: email);
      default:
        return MarketplaceMerchantDashboard(
          email: email,
          onBackToHomeTab: () {},
        );
    }
  }

  // -------------------- Handle auth result --------------------

  Future<void> _handleAuthResult(Map<String, dynamic>? result) async {
    if (result == null) return;

    final prefs = await SharedPreferences.getInstance();

    final authProvider =
        (result['authProvider'] ?? 'firebase').toString().toLowerCase();
    await prefs.setString('auth_provider', authProvider);

    final token = result['token']?.toString();
    if (token == null || token.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'No token received from $authProvider login',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    await prefs.setString('token', token);
    await prefs.setString('jwt_token', token);

    Map<String, dynamic> user = {};
    final rawUser = result['user'];
    if (rawUser is Map<String, dynamic>) {
      user = Map<String, dynamic>.from(rawUser);
    }

    final displayId = user['email']?.toString() ??
        user['phone']?.toString() ??
        _identifier.text.trim();
    await prefs.setString('email', displayId);

    // Persist name and phone so other screens (e.g. airport pickup, profile) can auto-fill
    final nameVal = (user['name'] ?? user['fullName'] ?? user['displayName'] ?? '').toString().trim();
    if (nameVal.isNotEmpty) {
      await prefs.setString('fullName', nameVal);
      await prefs.setString('name', nameVal);
    }
    final phoneVal = (user['phone'] ?? user['phoneNumber'] ?? user['mobile'] ?? '').toString().trim();
    if (phoneVal.isNotEmpty) {
      await prefs.setString('phone', phoneVal);
    }

    final role =
        (user['role'] ?? user['userRole'] ?? 'customer').toString().toLowerCase();
    await prefs.setString('role', role);

    final uid = user['uid']?.toString() ??
        user['id']?.toString() ??
        user['firebaseUid']?.toString();
    if (uid != null && uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }

    // Backend chat expects numeric userId in SharedPreferences
    final rawId = user['id'] ?? user['userId'];
    if (rawId != null) {
      final numericId = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (numericId != null) {
        await prefs.setInt('userId', numericId);
      }
    }
    if (prefs.getInt('userId') == null && uid != null) {
      final numericId = int.tryParse(uid);
      if (numericId != null) await prefs.setInt('userId', numericId);
    }

    if (role == 'merchant') {
      String? merchantService = user['merchantService']?.toString() ??
          user['serviceType']?.toString() ??
          user['merchant_service']?.toString();

      if (merchantService == null || merchantService.isEmpty) {
        if (uid != null) {
          merchantService = await _fetchMerchantServiceFromFirebase(uid);
        }
      }

      if (merchantService != null && merchantService.isNotEmpty) {
        await prefs.setString('merchant_service', merchantService);
      }

      final businessName = user['businessName']?.toString();
      if (businessName != null && businessName.isNotEmpty) {
        await prefs.setString('business_name', businessName);
      }

      final businessAddress = user['businessAddress']?.toString();
      if (businessAddress != null && businessAddress.isNotEmpty) {
        await prefs.setString('business_address', businessAddress);
      }
    }

    if (!mounted) return;

    if (role == 'merchant') {
      final merchantService = prefs.getString('merchant_service');

      if (merchantService != null && merchantService.isNotEmpty) {
        final merchantDashboard =
            _getMerchantDashboard(merchantService, displayId);

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => merchantDashboard),
          (route) => route.isFirst,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MarketplaceMerchantDashboard(
              email: displayId,
              onBackToHomeTab: () {},
            ),
          ),
          (route) => route.isFirst,
        );
      }
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => Bottomnavbar(email: displayId),
        ),
        (route) => route.isFirst,
      );
    }
  }

  // -------------------- Firebase profile helpers --------------------

  Future<String?> _fetchMerchantServiceFromFirebase(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        return userData?['merchantService']?.toString() ??
            userData?['merchant_service']?.toString() ??
            userData?['serviceType']?.toString();
      }

      final services = ['marketplace', 'food', 'taxi', 'accommodation', 'courier'];
      for (final service in services) {
        final collectionName =
            service == 'marketplace' ? 'marketplace_merchants' : '${service}_merchants';

        final merchantDoc =
            await _firestore.collection(collectionName).doc(uid).get();
        if (merchantDoc.exists) {
          return service;
        }
      }
    } catch (e) {
      print('Error fetching merchant service from Firebase: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> _buildResultFromUser(User user) async {
    Map<String, dynamic> profile = {};
    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      if (snap.exists && snap.data() != null) {
        profile = Map<String, dynamic>.from(snap.data()!);
      }
    } catch (e) {
      print('Failed to load Firebase profile: $e');
    }

    // Ensure at least a basic profile exists
    if (profile.isEmpty) {
      profile = {
        'email': user.email,
        'name': user.displayName,
        'phone': '',
        'role': 'customer',
      };
      try {
        await _firestore.collection('users').doc(user.uid).set({
          ...profile,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    final role =
        (profile['role'] ?? 'customer').toString().toLowerCase();
    final token = await user.getIdToken();

    return <String, dynamic>{
      'authProvider': 'firebase',
      'token': token,
      'user': <String, dynamic>{
        'uid': user.uid,
        'firebaseUid': user.uid,
        'email': user.email ?? _identifier.text.trim(),
        'phone': profile['phone']?.toString() ?? '',
        'name': profile['name']?.toString() ?? (user.displayName ?? ''),
        'role': role,
        'merchantService': profile['merchantService'],
        'businessName': profile['businessName'],
        'businessAddress': profile['businessAddress'],
      },
    };
  }

  // -------------------- Email/phone + password submit --------------------

  static bool _looksLikeEmail(String v) =>
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(v);

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final identifier = _identifier.text.trim();
    final password = _password.text.trim();

    setState(() => _loading = true);
    try {
      // Phone or backend-first: use AuthService (backend + Firebase fallback for email)
      if (!_looksLikeEmail(identifier)) {
        final result = await _authService.loginWithIdentifier(
          identifier,
          password,
          context,
        );
        if (result != null && mounted) await _handleAuthResult(result);
        return;
      }

      // Email: try Firebase first
      final cred = await _auth.signInWithEmailAndPassword(
        email: identifier,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        ToastHelper.showCustomToast(
          context,
          'Login failed (no user).',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      final result = await _buildResultFromUser(user);
      ToastHelper.showCustomToast(
        context,
        'Logged in successfully',
        isSuccess: true,
        errorMessage: '',
      );
      await _handleAuthResult(result);
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found for this email.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-email':
          msg = 'Incorrect email or password.';
          break;
        case 'user-disabled':
          msg = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts. Try again later.';
          break;
        case 'operation-not-allowed':
          msg = 'Email/password sign-in is not enabled.';
          break;
        default:
          msg = e.message?.trim().isNotEmpty == true
              ? e.message!
              : 'Incorrect email or password.';
      }
      ToastHelper.showCustomToast(
        context,
        msg,
        isSuccess: false,
        errorMessage: '',
      );
    } catch (e) {
      final String msg = e.toString().contains('credential') ||
              e.toString().contains('incorrect') ||
              e.toString().contains('invalid')
          ? 'Incorrect email or password.'
          : 'Login failed. Please try again.';
      ToastHelper.showCustomToast(
        context,
        msg,
        isSuccess: false,
        errorMessage: '',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- Forgot password (email or phone) --------------------

  static bool _looksLikePhone(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(08|09)\d{8}$').hasMatch(digits) ||
        RegExp(r'^\+265[89]\d{8}$').hasMatch(t);
  }

  Future<void> _showForgotPasswordDialog() async {
    if (!mounted) return;
    final identifier = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ForgotPasswordDialog(
        initialValue: _identifier.text.trim(),
        looksLikeEmail: _looksLikeEmail,
        looksLikePhone: _looksLikePhone,
      ),
    );
    if (identifier == null || identifier.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _authService.requestPasswordReset(
        identifier: identifier,
        context: context,
      );
    });
  }

  // -------------------- Social sign-in via Firebase (no platform lock) --------------------

  Future<void> _google() async {
    setState(() => _socialLoading = true);
    try {
      final user = await _firebaseAuthService.signInWithGoogle();
      if (user == null) {
        ToastHelper.showCustomToast(
          context,
          'Google sign-in cancelled or failed.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      final result = await _buildResultFromUser(user);
      ToastHelper.showCustomToast(
        context,
        'Signed in with Google',
        isSuccess: true,
        errorMessage: '',
      );
      await _handleAuthResult(result);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Google sign-in failed.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _apple() async {
    setState(() => _socialLoading = true);
    try {
      final user = await _firebaseAuthService.signInWithApple();
      if (user == null) {
        ToastHelper.showCustomToast(
          context,
          'Apple sign-in cancelled or not supported on this device.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      final result = await _buildResultFromUser(user);
      ToastHelper.showCustomToast(
        context,
        'Signed in with Apple',
        isSuccess: true,
        errorMessage: '',
      );
      await _handleAuthResult(result);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Apple sign-in failed.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  // -------------------- UI helpers --------------------

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
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.brandOrange, width: 1.2),
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
              begin: Alignment(0, -1),
              end: Alignment(0, 1),
              colors: [Color(0xFFEFF6FF), Colors.white],
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.eco,
                            size: 42,
                            color: AppColors.brandOrange,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        color: AppColors.title,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
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
                                label: 'Email or phone number',
                                hint: 'you@example.com or +265...',
                                icon: Icons.person_outline,
                              ),
                              validator: (v) {
                                final val = v?.trim() ?? '';
                                if (val.isEmpty) return 'Email or phone is required';
                                final isEmail = RegExp(
                                  r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$',
                                ).hasMatch(val);
                                final isPhone = RegExp(r'^\+?[\d\s\-]{8,}$').hasMatch(val.replaceAll(' ', ''));
                                if (!isEmail && !isPhone) {
                                  return 'Enter a valid email or phone number';
                                }
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
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Password is required';
                                }
                                if (v.length < 6) {
                                  return 'Must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loading ? null : _showForgotPasswordDialog,
                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: AppColors.brandOrange,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandOrange,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  _loading ? 'Signing in…' : 'Sign in',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: AppColors.body,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OAuthButtonsRow(
                      onGoogle: _socialLoading ? null : _google,
                      onApple: _socialLoading ? null : _apple,
                      iconOnly: true,
                    ),

                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account?",
                          style: TextStyle(
                            color: AppColors.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  );
                                },
                          child: const Text(
                            'Create one',
                            style: TextStyle(
                              color: AppColors.brandOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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

/// Self-contained dialog so controller and form key are disposed with the dialog.
/// Pops with the identifier string on submit; no async or parent context used inside.
class _ForgotPasswordDialog extends StatefulWidget {
  final String initialValue;
  final bool Function(String) looksLikeEmail;
  final bool Function(String) looksLikePhone;

  const _ForgotPasswordDialog({
    required this.initialValue,
    required this.looksLikeEmail,
    required this.looksLikePhone,
  });

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final identifier = _controller.text.trim();
    Navigator.of(context).pop(identifier);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot password'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email or phone number',
            hintText: 'you@example.com or 09xxxxxxxx',
          ),
          validator: (v) {
            final val = v?.trim() ?? '';
            if (val.isEmpty) return 'Email or phone is required';
            if (widget.looksLikeEmail(val)) return null;
            if (widget.looksLikePhone(val)) return null;
            return 'Enter a valid email or phone number';
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandOrange),
          child: const Text('Send code / reset link'),
        ),
      ],
    );
  }
}