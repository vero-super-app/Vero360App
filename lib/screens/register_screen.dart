import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/services/auth_service.dart';
import 'package:vero360_app/toasthelper.dart';
import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/merchantbottomnavbar.dart';
// Import merchant dashboards
import 'package:vero360_app/Pages/MerchantDashboards/marketplace_merchant_dashboard.dart'; // Add this
import 'package:vero360_app/Pages/MerchantDashboards/food_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/taxi_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/courier_merchant_dashboard.dart';
import 'package:vero360_app/widget/oauth_buttons.dart';

class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const fieldFill = Color(0xFFF7F7F9);
}

enum VerifyMethod { email, phone }
enum UserRole { customer, merchant }

// Merchant service types - should match with kQuickServices keys
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

// List of merchant services - ADD MARKETPLACE HERE
const List<MerchantService> kMerchantServices = [
  MerchantService(
    key: 'marketplace',  // New marketplace service
    name: 'General Dealers',
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
  MerchantService(
    key: 'courier',
    name: 'Vero Courier',
    icon: Icons.local_shipping_rounded,
  ),
  MerchantService(
    key: 'vero_bike',
    name: 'Vero Bike',
    icon: Icons.pedal_bike_rounded,
  ),
  MerchantService(
    key: 'airport_pickup',
    name: 'Airport Pickup',
    icon: Icons.flight_takeoff_rounded,
  ),
  // MerchantService(
  //   key: 'car_hire',
  //   name: 'Car Hire',
  //   icon: Icons.car_rental_rounded,
  // ),
  // MerchantService(
  //   key: 'hair',
  //   name: 'Hair Salon',
  //   icon: Icons.cut_rounded,
  // ),
  // MerchantService(
  //   key: 'fitness',
  //   name: 'Fitness Center',
  //   icon: Icons.fitness_center_rounded,
  // ),
  // MerchantService(
  //   key: 'mobile_money',
  //   name: 'Mobile Money',
  //   icon: Icons.money_rounded,
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

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _businessName = TextEditingController();
  final _businessAddress = TextEditingController();
  final _code = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _agree = false;

  VerifyMethod _method = VerifyMethod.email;
  UserRole _role = UserRole.customer;
  MerchantService? _selectedMerchantService;

  bool _sending = false;
  bool _otpSent = false;
  bool _verifying = false;
  bool _registering = false;
  bool _socialLoading = false;

  static const int _cooldownSecs = 45;
  int _resendSecs = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
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

  // String? _validateBusinessAddress(String? v) {
  //   if (_role == UserRole.merchant && (v == null || v.trim().isEmpty)) {
  //     return 'Business address is required';
  //   }
  //   return null;
  // }

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

  bool _isValidEmailForOtp(String s) =>
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(s.trim());

  bool _isValidPhoneForOtp(String s) {
    final d = s.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(08|09)\d{8}$').hasMatch(d) ||
        RegExp(r'^\+265[89]\d{8}$').hasMatch(s.trim());
  }

  void _startCooldown() {
    setState(() => _resendSecs = _cooldownSecs);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSecs <= 1) {
        t.cancel();
        setState(() => _resendSecs = 0);
      } else {
        setState(() => _resendSecs -= 1);
      }
    });
  }

  // ---------- Shared handler for both backend & Firebase auth ----------
  Future<void> _handleAuthResult(Map<String, dynamic>? resp) async {
    if (resp == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Who authenticated the user: 'backend' or 'firebase'
    final authProvider =
        (resp['authProvider'] ?? 'backend').toString().toLowerCase();
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

    // Keep these for the rest of the app (cart, profile, etc.)
    await prefs.setString('token', token);
    await prefs.setString('jwt_token', token);

    // Normalise user payload a bit defensively
    Map<String, dynamic> user = {};
    final rawUser = resp['user'];
    if (rawUser is Map<String, dynamic>) {
      user = Map<String, dynamic>.from(rawUser);
    }

    final displayId = user['email']?.toString() ??
        user['phone']?.toString() ??
        _email.text.trim() ??
        _phone.text.trim();
    if (displayId.isNotEmpty) {
      await prefs.setString('email', displayId);
    }

    // Store merchant service if available (from response or local selection)
    final merchantService = user['merchantService']?.toString() ??
        user['serviceType']?.toString() ??
        _selectedMerchantService?.key;
    if (merchantService != null && merchantService.isNotEmpty) {
      await prefs.setString('merchant_service', merchantService);
      
      // Also store business info for merchants
      if (_role == UserRole.merchant) {
        await prefs.setString('business_name', _businessName.text.trim());
        await prefs.setString('business_address', _businessAddress.text.trim());
      }
    }

    final role =
        (user['role'] ?? user['userRole'] ?? '').toString().toLowerCase();

    if (!mounted) return;

    // Redirect to appropriate dashboard based on role and service
    if (role == 'merchant') {
      // Get the merchant service from user data or local selection
      final serviceKey = merchantService ?? _selectedMerchantService?.key;
      
      if (serviceKey != null) {
        // Navigate to specific merchant dashboard based on service
        Widget merchantDashboard = _getMerchantDashboard(serviceKey, displayId);
        
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => merchantDashboard),
          (_) => false,
        );
      } else {
        // Fallback to generic merchant dashboard
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MarketplaceMerchantDashboard(email: displayId),
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

  // Helper method to get the appropriate merchant dashboard - ADD MARKETPLACE CASE
  Widget _getMerchantDashboard(String serviceKey, String email) {
    switch (serviceKey) {
      case 'marketplace':  // Add marketplace case
        return MarketplaceMerchantDashboard(email: email);
      case 'food':
        return FoodMerchantDashboard(email: email);
      case 'taxi':
        return TaxiMerchantDashboard(email: email);
      case 'accommodation':
        return AccommodationMerchantDashboard(email: email);
      case 'courier':
        return CourierMerchantDashboard(email: email);
      // Add more cases for other services
      default:
        return MarketplaceMerchantDashboard(email: email);
    }
  }

  // ---------- OTP flow ----------
  Future<void> _sendCode() async {
    if (_method == VerifyMethod.email) {
      final err = _validateEmail(_email.text);
      if (err != null) {
        ToastHelper.showCustomToast(
          context,
          err,
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }
    } else {
      final err = _validatePhone(_phone.text);
      if (err != null) {
        ToastHelper.showCustomToast(
          context,
          err,
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }
    }

    setState(() {
      _sending = true;
      _otpSent = false;
    });

    try {
      final method = _method == VerifyMethod.email ? 'email' : 'phone';
      final ok = await AuthService().requestOtp(
        channel: method,
        email: method == 'email' ? _email.text.trim() : null,
        phone: method == 'phone' ? _phone.text.trim() : null,
        context: context,
      );
      if (ok) {
        setState(() => _otpSent = true);
        _startCooldown();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- Register (NestJS + Firebase backup) ----------
  Future<void> _verifyAndRegister() async {
    if (!_agree) {
      ToastHelper.showCustomToast(
        context,
        'Please agree to the Terms & Privacy',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    
    // Validate merchant-specific fields
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
      
    //   final businessAddressErr = _validateBusinessAddress(_businessAddress.text);
    //   if (businessAddressErr != null) {
    //     ToastHelper.showCustomToast(
    //       context,
    //       businessAddressErr,
    //       isSuccess: false,
    //       errorMessage: '',
    //     );
    //     return;
    //   }
    // }
    
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final preferred =
        _method == VerifyMethod.email ? 'email' : 'phone';
    final identifier =
        preferred == 'email' ? _email.text.trim() : _phone.text.trim();

    // ✅ OTP is OPTIONAL (Firebase backup will be used if OTP fails)
    String ticket = '';
    if (_otpSent && _code.text.trim().isNotEmpty) {
      setState(() => _verifying = true);
      try {
        final t = await AuthService().verifyOtpGetTicket(
          identifier: identifier,
          code: _code.text.trim(),
          context: context,
        );
        if (t != null && t.isNotEmpty) {
          ticket = t;
        }
      } finally {
        if (mounted) setState(() => _verifying = false);
      }
    }

    setState(() => _registering = true);
    try {
      // Prepare merchant-specific data
      Map<String, dynamic> merchantData = {};
      if (_role == UserRole.merchant) {
        merchantData = {
          'merchantService': _selectedMerchantService!.key,
          'businessName': _businessName.text.trim(),
          'businessAddress': _businessAddress.text.trim(),
        };
      }

      // Try NestJS registration first (with or without ticket)
      final resp = await AuthService().registerUser(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        password: _password.text,
        role: _role == UserRole.merchant ? 'merchant' : 'customer',
        profilePicture: '',
        preferredVerification: preferred,
        verificationTicket: ticket,
        merchantData: merchantData,
        context: context,
      );

      if (!mounted) return;
      
      if (resp != null) {
        // NestJS registration succeeded
        await _handleAuthResult(resp);
        
        // Also create Firebase account as backup mirror
        await _createFirebaseBackupAccount(resp['user']);
      } else {
        // NestJS failed - try Firebase-only registration
        await _registerWithFirebaseOnly();
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }}

  // Create Firebase backup account for NestJS-registered users
  Future<void> _createFirebaseBackupAccount(Map<String, dynamic>? userData) async {
    try {
      // Only create Firebase account if we have valid credentials
      final email = _email.text.trim();
      final password = _password.text;
      
      if (email.isNotEmpty && password.isNotEmpty) {
        UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final firebaseUser = userCredential.user;
        if (firebaseUser != null) {
          // Prepare user data for Firestore
          final userDataForFirestore = {
            'uid': firebaseUser.uid,
            'email': email,
            'name': _name.text.trim(),
            'phone': _phone.text.trim(),
            'role': _role == UserRole.merchant ? 'merchant' : 'customer',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'authProvider': 'nestjs_mirrored', // Mark as mirrored from NestJS
          };

          // Add merchant-specific data if merchant
          if (_role == UserRole.merchant) {
            userDataForFirestore['merchantService'] = _selectedMerchantService!.key;
            userDataForFirestore['businessName'] = _businessName.text.trim();
            userDataForFirestore['businessAddress'] = _businessAddress.text.trim();
            userDataForFirestore['status'] = 'pending';
            userDataForFirestore['isActive'] = false;
            
            // Create merchant profile in service-specific collection
            final merchantProfile = {
              'uid': firebaseUser.uid,
              'email': email,
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
            
            // Store in both users collection
            await _firestore.collection('users').doc(firebaseUser.uid).set(userDataForFirestore);
            
            // Determine collection name based on service type - SPECIAL HANDLING FOR MARKETPLACE
            final collectionName = _selectedMerchantService!.key == 'marketplace' 
                ? 'marketplace_merchants'
                : '${_selectedMerchantService!.key}_merchants';
            await _firestore
                .collection(collectionName)
                .doc(firebaseUser.uid)
                .set(merchantProfile);
          } else {
            // For customers, just store in users collection
            await _firestore.collection('users').doc(firebaseUser.uid).set(userDataForFirestore);
          }
        }
      }
    } catch (e) {
      // Silent fail - Firebase is just a backup
      print('Firebase backup account creation failed: $e');
    }
  }

  // Firebase-only registration (when NestJS fails)
  Future<void> _registerWithFirebaseOnly() async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = userCredential.user;
      if (user == null) throw Exception('Firebase user creation failed');

      // Prepare user data for Firestore
      final userData = {
        'uid': user.uid,
        'email': _email.text.trim(),
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'role': _role == UserRole.merchant ? 'merchant' : 'customer',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'authProvider': 'firebase_only', // Mark as Firebase-only registration
      };

      // Add merchant-specific data if merchant
      if (_role == UserRole.merchant) {
        userData['merchantService'] = _selectedMerchantService!.key;
        userData['businessName'] = _businessName.text.trim();
        userData['businessAddress'] = _businessAddress.text.trim();
        userData['status'] = 'pending';
        userData['isActive'] = false;
        
        // Create merchant profile in service-specific collection
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
        
        // Determine collection name based on service type - SPECIAL HANDLING FOR MARKETPLACE
        final collectionName = _selectedMerchantService!.key == 'marketplace' 
            ? 'marketplace_merchants'
            : '${_selectedMerchantService!.key}_merchants';
        
        // Store in both users collection and service-specific collection
        await _firestore.collection('users').doc(user.uid).set(userData);
        await _firestore
            .collection(collectionName)
            .doc(user.uid)
            .set(merchantProfile);
      } else {
        // For customers, just store in users collection
        await _firestore.collection('users').doc(user.uid).set(userData);
      }

      // Store in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', user.uid);
      await prefs.setString('email', _email.text.trim());
      await prefs.setString('name', _name.text.trim());
      await prefs.setString('role', _role == UserRole.merchant ? 'merchant' : 'customer');
      await prefs.setString('auth_provider', 'firebase_only');
      
      if (_role == UserRole.merchant) {
        await prefs.setString('merchant_service', _selectedMerchantService!.key);
        await prefs.setString('business_name', _businessName.text.trim());
        await prefs.setString('business_address', _businessAddress.text.trim());
      }

      // Create a response map similar to NestJS response
      final firebaseResponse = {
        'token': await user.getIdToken(),
        'user': {
          'uid': user.uid,
          'email': _email.text.trim(),
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'role': _role == UserRole.merchant ? 'merchant' : 'customer',
          'merchantService': _role == UserRole.merchant ? _selectedMerchantService!.key : null,
          'businessName': _role == UserRole.merchant ? _businessName.text.trim() : null,
          'businessAddress': _role == UserRole.merchant ? _businessAddress.text.trim() : null,
        },
        'authProvider': 'firebase_only',
      };

      // Navigate to appropriate dashboard
      if (!mounted) return;
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
    }
  }

  // ---------- Social (logo-only) ----------
  Future<void> _google() async {
    setState(() => _socialLoading = true);
    try {
      final resp = await AuthService().continueWithGoogle(context);
      await _handleAuthResult(resp);
      
      // If social login successful, ask for additional merchant info if needed
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      final merchantService = prefs.getString('merchant_service');
      
      if (role == 'merchant' && (merchantService == null || merchantService.isEmpty)) {
        await _askForMerchantServiceAfterSocialLogin();
      }
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _apple() async {
    if (!Platform.isIOS) return;
    setState(() => _socialLoading = true);
    try {
      final resp = await AuthService().continueWithApple(context);
      await _handleAuthResult(resp);
      
      // If social login successful, ask for additional merchant info if needed
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      final merchantService = prefs.getString('merchant_service');
      
      if (role == 'merchant' && (merchantService == null || merchantService.isEmpty)) {
        await _askForMerchantServiceAfterSocialLogin();
      }
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _askForMerchantServiceAfterSocialLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid');
    final email = prefs.getString('email');
    
    if (uid == null || email == null) return;
    
    final businessNameController = TextEditingController();
    final businessAddressController = TextEditingController();
    MerchantService? selectedService;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Complete Merchant Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<MerchantService>(
                    value: selectedService,
                    decoration: const InputDecoration(
                      labelText: 'Service You Provide',
                      border: OutlineInputBorder(),
                    ),
                    items: kMerchantServices.map((service) {
                      return DropdownMenuItem<MerchantService>(
                        value: service,
                        child: Row(
                          children: [
                            Icon(service.icon, size: 20),
                            const SizedBox(width: 10),
                            Text(service.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => selectedService = value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: businessNameController,
                    decoration: const InputDecoration(
                      labelText: 'Business Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: businessAddressController,
                    decoration: const InputDecoration(
                      labelText: 'Business Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedService == null || 
                      businessNameController.text.trim().isEmpty || 
                      businessAddressController.text.trim().isEmpty) {
                    ToastHelper.showCustomToast(
                      context,
                      'Please fill all merchant fields',
                      isSuccess: false,
                      errorMessage: '',
                    );
                    return;
                  }
                  
                  // Use a local variable to avoid repeated ! operator
                  final MerchantService service = selectedService!;
                  
                  // Update Firebase with merchant info
                  await _firestore.collection('users').doc(uid).update({
                    'merchantService': service.key,
                    'businessName': businessNameController.text.trim(),
                    'businessAddress': businessAddressController.text.trim(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  
                  // Create merchant profile
                  final merchantProfile = {
                    'uid': uid,
                    'email': email,
                    'name': prefs.getString('name') ?? '',
                    'phone': prefs.getString('phone') ?? '',
                    'businessName': businessNameController.text.trim(),
                    'businessAddress': businessAddressController.text.trim(),
                    'serviceType': service.key,
                    'status': 'pending',
                    'isActive': false,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                    'rating': 0.0,
                    'totalRatings': 0,
                    'completedOrders': 0,
                  };
                  
                  // Determine collection name based on service type - SPECIAL HANDLING FOR MARKETPLACE
                  final collectionName = service.key == 'marketplace' 
                      ? 'marketplace_merchants'
                      : '${service.key}_merchants';
                  
                  await _firestore
                      .collection(collectionName)
                      .doc(uid)
                      .set(merchantProfile);
                  
                  // Update SharedPreferences
                  await prefs.setString('merchant_service', service.key);
                  await prefs.setString('business_name', businessNameController.text.trim());
                  await prefs.setString('business_address', businessAddressController.text.trim());
                  
                  Navigator.pop(context);
                  
                  // Navigate to merchant dashboard
                  Widget merchantDashboard = _getMerchantDashboard(service.key, email);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => merchantDashboard),
                    (_) => false,
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

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
    final canSend = _method == VerifyMethod.email
        ? _isValidEmailForOtp(_email.text)
        : _isValidPhoneForOtp(_phone.text);
    final sendBtnDisabled =
        _sending || _verifying || _registering || !canSend || _resendSecs > 0;

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
                    // Brand
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
                        boxShadow: [BoxShadow(color: AppColors.brandOrange.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10))],
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

                    // Logo-only socials
                    OAuthButtonsRow(
                      onGoogle: _socialLoading ? null : _google,
                      onApple: _socialLoading ? null : _apple,
                    ),
                    const SizedBox(height: 18),

                    // Card + Form
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: _formKey,
                        onChanged: () => setState(() {}),
                        child: Column(
                          children: [
                            // role
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Customer'),
                                  selected: _role == UserRole.customer,
                                  onSelected: (_) => setState(
                                    () {
                                      _role = UserRole.customer;
                                      // Clear merchant-specific fields
                                      _businessName.clear();
                                      _businessAddress.clear();
                                      _selectedMerchantService = null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Merchant'),
                                  selected: _role == UserRole.merchant,
                                  onSelected: (_) => setState(
                                    () => _role = UserRole.merchant,
                                  ),
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
                            
                           // Business Name (for merchants)
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
                            
                            // Business Address (for merchants)
                            // if (_role == UserRole.merchant) ...[
                            //   TextFormField(
                            //     controller: _businessAddress,
                            //     textInputAction: TextInputAction.next,
                            //     decoration: _dec(
                            //       label: 'Business Address',
                            //       hint: 'Your business location',
                            //       icon: Icons.location_on_rounded,
                            //     ),
                            //     validator: _validateBusinessAddress,
                            //   ),
                            //   const SizedBox(height: 14),
                            // ],
                            
                            // Merchant Service Selection (for merchants)
                            if (_role == UserRole.merchant) ...[
                              DropdownButtonFormField<MerchantService>(
                                value: _selectedMerchantService,
                                decoration: _dec(
                                  label: 'Service You Provide',
                                  hint: 'Select your service',
                                  icon: Icons.work_outline,
                                ),
                                validator: (value) => _validateMerchantService(value),
                                items: kMerchantServices.map((service) {
                                  return DropdownMenuItem<MerchantService>(
                                    value: service,
                                    child: Row(
                                      children: [
                                        Icon(service.icon, size: 20, color: AppColors.brandOrange),
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

                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Email'),
                                  selected: _method == VerifyMethod.email,
                                  onSelected: (_) => setState(() {
                                    _method = VerifyMethod.email;
                                    _code.clear();
                                    _otpSent = false;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Phone'),
                                  selected: _method == VerifyMethod.phone,
                                  onSelected: (_) => setState(() {
                                    _method = VerifyMethod.phone;
                                    _code.clear();
                                    _otpSent = false;
                                  }),
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed:
                                      sendBtnDisabled ? null : _sendCode,
                                  icon: const Icon(
                                    Icons.sms_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _sending
                                        ? 'Sending…'
                                        : (_resendSecs > 0
                                            ? 'Resend ${_resendSecs}s'
                                            : 'Send code'),
                                  ),
                                ),
                              ],
                            ),

                            if (_otpSent) ...[
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _code,
                                keyboardType: TextInputType.number,
                                decoration: _dec(
                                  label: 'Verification code',
                                  hint: 'Enter the code',
                                  icon: Icons.verified_outlined,
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: (_registering || _verifying)
                                    ? null
                                    : _verifyAndRegister,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandOrange,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  _registering
                                      ? 'Creating account…'
                                      : _verifying
                                          ? 'Verifying…'
                                          : 'Verify & Create account',
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