import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/features/ride_share/presentation/pages/driver_dashboard.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/GernalServices/api_client.dart';

// Merchant dashboards
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vero360_app/features/Auth/AuthPresenter/oauth_buttons.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/firebaseAuth.dart';

class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const fieldFill = Color(0xFFF7F7F9);
}

enum UserRole { customer, merchant }

// Merchant service types
class MerchantService {
  final String key;
  final String name;
  final IconData icon;

  const MerchantService({
    required this.key,
    required this.name,
    required this.icon,
  });
}

// List of merchant services
const List<MerchantService> kMerchantServices = [
  MerchantService(
    key: 'marketplace',
    name: 'Marketplace',
    icon: Icons.store_rounded,
  ),
  MerchantService(
    key: 'taxi',
    name: 'Vero Ride/Taxi',
    icon: Icons.local_taxi_rounded,
  ),
  MerchantService(
    key: 'food',
    name: 'Food & Restaurants',
    icon: Icons.restaurant_rounded,
  ),
  MerchantService(
    key: 'accommodation',
    name: 'Accommodation',
    icon: Icons.hotel_rounded,
  ),
  // MerchantService(
  //   key: 'courier',
  //   name: 'Vero Courier',
  //   icon: Icons.local_shipping_rounded,
  // ),
  // MerchantService(
  //   key: 'vero_bike',
  //   name: 'Vero Bike',
  //   icon: Icons.pedal_bike_rounded,
  // ),
  // MerchantService(
  //   key: 'airport_pickup',
  //   name: 'Airport Pickup',
  //   icon: Icons.flight_takeoff_rounded,
  // ),
];

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthService _firebaseAuthService = FirebaseAuthService();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _businessName = TextEditingController();
  final _businessAddress = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _agree = false;

  UserRole _role = UserRole.customer;
  MerchantService? _selectedMerchantService;

  bool _registering = false;
  bool _socialLoading = false;

  Timer? _dummyTimer;

  @override
  void dispose() {
    _dummyTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _businessName.dispose();
    _businessAddress.dispose();
    super.dispose();
  }

  // ---------- validators ----------

  String? _validateName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Name is required' : null;

  String? _validateBusinessName(String? v) {
    if (_role == UserRole.merchant && (v == null || v.trim().isEmpty)) {
      return 'Business name is required';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(s);
    return ok ? null : 'Enter a valid email';
  }

  String? _validatePhone(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Mobile number is required';
    final digits = s.replaceAll(RegExp(r'\D'), '');
    final isLocal = RegExp(r'^(08|09)\d{8}$').hasMatch(digits);
    final isE164 = RegExp(r'^\+265[89]\d{8}$').hasMatch(s);
    if (!isLocal && !isE164) {
      return 'Use 08/09xxxxxxxx or +2659xxxxxxxx';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Must be at least 8 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != _password.text) return 'Passwords do not match';
    return null;
  }

  String? _validateMerchantService(MerchantService? v) {
    if (_role == UserRole.merchant && v == null) {
      return 'Please select a service you provide';
    }
    return null;
  }

  // ---------- Shared handler for auth result ----------

  Future<void> _handleAuthResult(Map<String, dynamic>? resp) async {
    if (resp == null) return;

    final prefs = await SharedPreferences.getInstance();

    final authProvider =
        (resp['authProvider'] ?? 'firebase').toString().toLowerCase();
    await prefs.setString('auth_provider', authProvider);

    final token = resp['token']?.toString();
    if (token == null || token.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'No token received from $authProvider signup',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    await prefs.setString('token', token);
    await prefs.setString('jwt_token', token);

    Map<String, dynamic> user = {};
    final rawUser = resp['user'];
    if (rawUser is Map<String, dynamic>) {
      user = Map<String, dynamic>.from(rawUser);
    }

    final displayId = user['email']?.toString() ??
        user['phone']?.toString() ??
        _email.text.trim();
    if (displayId.isNotEmpty) {
      await prefs.setString('email', displayId);
    }

    final merchantService = user['merchantService']?.toString() ??
        user['serviceType']?.toString() ??
        _selectedMerchantService?.key;
    if (merchantService != null && merchantService.isNotEmpty) {
      await prefs.setString('merchant_service', merchantService);

      if (_role == UserRole.merchant) {
        await prefs.setString('business_name', _businessName.text.trim());
        await prefs.setString('business_address', _businessAddress.text.trim());
      }
    }

    final role =
        (user['role'] ?? user['userRole'] ?? '').toString().toLowerCase();
    await prefs.setString('role', role);

    final uid = user['uid']?.toString() ?? user['firebaseUid']?.toString();
    if (uid != null && uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }

    if (!mounted) return;

    if (role == 'merchant') {
      final serviceKey = merchantService ?? _selectedMerchantService?.key;

      if (serviceKey != null) {
        final merchantDashboard =
            _getMerchantDashboard(serviceKey, displayId);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => merchantDashboard),
          (_) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MarketplaceMerchantDashboard(
              email: displayId,
              onBackToHomeTab: () {},
            ),
          ),
          (_) => false,
        );
      }
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => Bottomnavbar(email: displayId),
        ),
        (_) => false,
      );
    }
  }

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
      // case 'courier':
      //   return CourierMerchantDashboard(email: email);
    }
    return MarketplaceMerchantDashboard(
      email: email,
      onBackToHomeTab: () {},
    );
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

    if (profile.isEmpty) {
      profile = {
        'email': user.email,
        'name': user.displayName ?? _name.text.trim(),
        'phone': _phone.text.trim(),
        'role': _role == UserRole.merchant ? 'merchant' : 'customer',
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
      'authProvider': 'firebase_only',
      'token': token,
      'user': <String, dynamic>{
        'uid': user.uid,
        'firebaseUid': user.uid,
        'email': user.email ?? _email.text.trim(),
        'name': profile['name']?.toString() ?? _name.text.trim(),
        'phone': profile['phone']?.toString() ?? _phone.text.trim(),
        'role': role,
        'merchantService':
            _role == UserRole.merchant ? _selectedMerchantService?.key : null,
        'businessName':
            _role == UserRole.merchant ? _businessName.text.trim() : null,
        'businessAddress':
            _role == UserRole.merchant ? _businessAddress.text.trim() : null,
      },
    };
  }

  /// Syncs the chosen role (and merchant data) to the backend so the API user
  /// is created/updated as merchant. Uses PUT /users/me (backend uses Put, not Patch).
  Future<void> _syncProfileToBackend(User user) async {
    final role = _role == UserRole.merchant ? 'merchant' : 'customer';
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'role': role,
    };
    if (_role == UserRole.merchant) {
      body['merchantService'] = _selectedMerchantService?.key;
      body['businessName'] = _businessName.text.trim();
      body['businessAddress'] = _businessAddress.text.trim();
    }

    // Ensure backend gets the new user's token (persist so ApiClient uses it).
    final token = await user.getIdToken(true);
    if (token != null && token.isNotEmpty) {
      await AuthHandler.persistTokenToSp(token);
    }

    try {
      await ApiClient.put(
        '/users/me',
        body: jsonEncode(body),
        timeout: const Duration(seconds: 10),
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] Backend profile synced via PUT /users/me (role: $role)');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] PUT /users/me failed. Ensure UpdateUserDto allows role (and merchant fields). Error: $e');
      }
    }
  }

  // ---------- Firebase-only registration ----------

  Future<void> _registerWithFirebaseOnly() async {
    if (!_agree) {
      ToastHelper.showCustomToast(
        context,
        'Please agree to the Terms & Privacy',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    if (_role == UserRole.merchant) {
      final serviceErr = _validateMerchantService(_selectedMerchantService);
      if (serviceErr != null) {
        ToastHelper.showCustomToast(
          context,
          serviceErr,
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      final businessNameErr = _validateBusinessName(_businessName.text);
      if (businessNameErr != null) {
        ToastHelper.showCustomToast(
          context,
          businessNameErr,
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _registering = true);
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = userCredential.user;
      if (user == null) throw Exception('Firebase user creation failed');

      final role = _role == UserRole.merchant ? 'merchant' : 'customer';

      final userData = <String, dynamic>{
        'uid': user.uid,
        'email': _email.text.trim(),
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'authProvider': 'firebase_only',
      };

      if (_role == UserRole.merchant) {
        userData['merchantService'] = _selectedMerchantService!.key;
        userData['businessName'] = _businessName.text.trim();
        userData['businessAddress'] = _businessAddress.text.trim();
        userData['status'] = 'pending';
        userData['isActive'] = false;

        final merchantProfile = {
          'uid': user.uid,
          'email': _email.text.trim(),
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'businessName': _businessName.text.trim(),
          'businessAddress': _businessAddress.text.trim(),
          'serviceType': _selectedMerchantService!.key,
          'status': 'pending',
          'isActive': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'rating': 0.0,
          'totalRatings': 0,
          'completedOrders': 0,
        };

        await _firestore.collection('users').doc(user.uid).set(userData);

        final collectionName = _selectedMerchantService!.key == 'marketplace'
            ? 'marketplace_merchants'
            : '${_selectedMerchantService!.key}_merchants';
        await _firestore
            .collection(collectionName)
            .doc(user.uid)
            .set(merchantProfile);
      } else {
        await _firestore.collection('users').doc(user.uid).set(userData);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', user.uid);
      await prefs.setString('email', _email.text.trim());
      final nameVal = _name.text.trim();
      if (nameVal.isNotEmpty) {
        await prefs.setString('fullName', nameVal);
        await prefs.setString('name', nameVal);
      }
      final phoneVal = _phone.text.trim();
      if (phoneVal.isNotEmpty) await prefs.setString('phone', phoneVal);
      await prefs.setString('role', role);
      await prefs.setString('auth_provider', 'firebase_only');

      if (_role == UserRole.merchant) {
        await prefs.setString('merchant_service', _selectedMerchantService!.key);
        await prefs.setString('business_name', _businessName.text.trim());
        await prefs.setString('business_address', _businessAddress.text.trim());
      }

      // Sync role (and merchant data) to backend so API user is merchant when chosen.
      await _syncProfileToBackend(user);

      final firebaseResponse = await _buildResultFromUser(user);

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Account created successfully',
        isSuccess: true,
        errorMessage: '',
      );
      await _handleAuthResult(firebaseResponse);
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Registration failed';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'Email already registered. Please sign in.';
      } else if (e.code == 'weak-password') {
        errorMessage = 'Password is too weak. Use a stronger password.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Invalid email address.';
      }

      ToastHelper.showCustomToast(
        context,
        errorMessage,
        isSuccess: false,
        errorMessage: e.message ?? '',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Firebase registration failed. Please try again.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  // ---------- Social signup/login via Firebase (no platform lock) ----------

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

  // ---------- UI helpers ----------

  InputDecoration _dec({
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
        borderSide: const BorderSide(
          color: AppColors.brandOrange,
          width: 1.2,
        ),
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
              colors: [Color(0xFFFFF4E9), Colors.white],
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
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.brandOrange,
                            Color(0xFFFFB85C),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandOrange.withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
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
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Create your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.title,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),

                    OAuthButtonsRow(
                      onGoogle: _socialLoading ? null : _google,
                      onApple: _socialLoading ? null : _apple,
                    ),
                    const SizedBox(height: 18),

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
                        onChanged: () => setState(() {}),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Customer'),
                                  selected: _role == UserRole.customer,
                                  onSelected: (_) => setState(() {
                                    _role = UserRole.customer;
                                    _businessName.clear();
                                    _businessAddress.clear();
                                    _selectedMerchantService = null;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Merchant'),
                                  selected: _role == UserRole.merchant,
                                  onSelected: (_) =>
                                      setState(() => _role = UserRole.merchant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(
                                label: 'Your name',
                                hint: 'Your full name',
                                icon: Icons.person_outline,
                              ),
                              validator: _validateName,
                            ),
                            const SizedBox(height: 14),

                            if (_role == UserRole.merchant) ...[
                              TextFormField(
                                controller: _businessName,
                                textInputAction: TextInputAction.next,
                                decoration: _dec(
                                  label: 'Business Name',
                                  hint: 'Your business name',
                                  icon: Icons.business_rounded,
                                ),
                                validator: _validateBusinessName,
                              ),
                              const SizedBox(height: 14),
                            ],

                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(
                                label: 'Email',
                                hint: 'you@vero.com',
                                icon: Icons.alternate_email,
                              ),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(
                                label: 'Mobile number',
                                hint:
                                    '08xxxxxxxx, 09xxxxxxxx or +2659xxxxxxxx',
                                icon: Icons.phone_iphone,
                              ),
                              validator: _validatePhone,
                            ),
                            const SizedBox(height: 14),

                            if (_role == UserRole.merchant) ...[
                              DropdownButtonFormField<MerchantService>(
                                initialValue: _selectedMerchantService,
                                decoration: _dec(
                                  label: 'Service You Provide',
                                  hint: 'Select your service',
                                  icon: Icons.work_outline,
                                ),
                                validator: (value) =>
                                    _validateMerchantService(value),
                                items: kMerchantServices.map((service) {
                                  return DropdownMenuItem<MerchantService>(
                                    value: service,
                                    child: Row(
                                      children: [
                                        Icon(
                                          service.icon,
                                          size: 20,
                                          color: AppColors.brandOrange,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(service.name),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (MerchantService? newValue) {
                                  setState(() {
                                    _selectedMerchantService = newValue;
                                  });
                                },
                              ),
                              const SizedBox(height: 14),
                            ],

                            TextFormField(
                              controller: _password,
                              obscureText: _obscure1,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(
                                label: 'Password',
                                hint: '••••••••',
                                icon: Icons.lock_outline,
                                trailing: IconButton(
                                  tooltip: _obscure1 ? 'Show' : 'Hide',
                                  icon: Icon(
                                    _obscure1
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscure1 = !_obscure1,
                                  ),
                                ),
                              ),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirm,
                              obscureText: _obscure2,
                              textInputAction: TextInputAction.done,
                              decoration: _dec(
                                label: 'Confirm password',
                                hint: '••••••••',
                                icon: Icons.lock_outline,
                                trailing: IconButton(
                                  tooltip: _obscure2 ? 'Show' : 'Hide',
                                  icon: Icon(
                                    _obscure2
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscure2 = !_obscure2,
                                  ),
                                ),
                              ),
                              validator: _validateConfirm,
                            ),
                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Checkbox(
                                  value: _agree,
                                  onChanged: (v) =>
                                      setState(() => _agree = v ?? false),
                                ),
                                const Expanded(
                                  child: Text(
                                    'I agree to the Terms & Privacy Policy',
                                    style: TextStyle(
                                      color: AppColors.body,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _registering
                                    ? null
                                    : _registerWithFirebaseOnly,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandOrange,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  _registering
                                      ? 'Creating account…'
                                      : 'Create account',
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

                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Already have an account? Sign in',
                        style: TextStyle(
                          color: AppColors.brandOrange,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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