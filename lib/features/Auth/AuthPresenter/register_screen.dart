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
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vero360_app/features/Auth/AuthPresenter/oauth_buttons.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/firebaseAuth.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';

class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const fieldFill = Color(0xFFF7F7F9);
}

enum UserRole { customer, merchant, driver }

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
  final _identifier = TextEditingController(); // email or phone (one field)
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
    _identifier.dispose();
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

  String get _roleString {
    switch (_role) {
      case UserRole.merchant:
        return 'merchant';
      case UserRole.driver:
        return 'driver';
      case UserRole.customer:
        return 'customer';
    }
  }

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(s.trim());

  static bool _looksLikePhone(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(08|09)\d{8}$').hasMatch(digits) ||
        RegExp(r'^\+265[89]\d{8}$').hasMatch(t);
  }

  String get _identifierValue => _identifier.text.trim();

  String get _identifierEmail =>
      _looksLikeEmail(_identifierValue) ? _identifierValue : '';

  String get _identifierPhone =>
      _looksLikePhone(_identifierValue) ? _identifierValue : '';

  /// Normalise a phone number to a compact numeric form for auth-only use.
  /// Example: "0992 695 612" -> "0992695612".
  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits;
  }

  String? _validateIdentifier(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email or phone number is required';
    if (_looksLikeEmail(s)) return null;
    if (_looksLikePhone(s)) return null;
    return 'Enter a valid email or phone (08/09xxxxxxxx or +2659xxxxxxxx)';
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

  /// Minimal validation rules before allowing Google/Apple sign-up.
  /// We do *not* require password fields here, but we do enforce:
  /// - Terms & Privacy must be accepted
  /// - For merchants: a service and business name must be provided
  bool _canProceedWithSocialSignIn() {
    if (!_agree) {
      ToastHelper.showCustomToast(
        context,
        'Please agree to the Terms & Privacy before continuing.',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
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
        return false;
      }

      final businessNameErr = _validateBusinessName(_businessName.text);
      if (businessNameErr != null) {
        ToastHelper.showCustomToast(
          context,
          businessNameErr,
          isSuccess: false,
          errorMessage: '',
        );
        return false;
      }
    }

    return true;
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

    // Prefer phone for display when present (so phone-only signups show their number,
    // not an internal email used only for Firebase auth).
    final displayId = user['phone']?.toString() ??
        user['email']?.toString() ??
        _identifierValue;
    if (displayId.isNotEmpty) {
      await prefs.setString('email', displayId);
    }

    // Prefer the service the user picked on this screen. The API often sends a generic
    // `serviceType` (e.g. "marketplace") that would wrongly override accommodation/food.
    String? merchantService;
    if (_role == UserRole.merchant) {
      merchantService = _selectedMerchantService?.key ??
          user['merchantService']?.toString() ??
          user['serviceType']?.toString();
    } else {
      merchantService = user['merchantService']?.toString() ??
          user['serviceType']?.toString() ??
          _selectedMerchantService?.key;
    }
    merchantService = normalizeMerchantServiceKey(merchantService);
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
    await prefs.setString('user_role', role);
    await prefs.setBool('is_merchant', role == 'merchant');

    final uid = user['uid']?.toString() ?? user['firebaseUid']?.toString();
    if (uid != null && uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }

    // Marketplace onboarding guide only for marketplace merchants.
    if (role == 'merchant' &&
        merchantService == 'marketplace' &&
        prefs.getBool('marketplace_merchant_guide_v1_done') != true) {
      await prefs.setBool('marketplace_merchant_guide_show_on_next_open', true);
    }

    if (!mounted) return;

    if (role == 'merchant') {
      await hydrateMerchantServiceFromFirestore(prefs);
      final serviceKey = normalizeMerchantServiceKey(
        merchantService ?? _selectedMerchantService?.key,
      );

      if (serviceKey != null && serviceKey.isNotEmpty) {
        final merchantDashboard =
            _getMerchantDashboard(serviceKey, displayId);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => merchantDashboard),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MarketplaceMerchantDashboard(
              email: displayId,
              onBackToHomeTab: () {},
            ),
          ),
          (route) => false,
        );
      }
    } else if (role == 'driver') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverDashboard()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => Bottomnavbar(email: displayId),
        ),
        (route) => false,
      );
    }
  }

  Widget _getMerchantDashboard(String serviceKey, String email) {
    final key = normalizeMerchantServiceKey(serviceKey) ?? serviceKey;
    switch (key) {
      case 'marketplace':
        return MarketplaceMerchantDashboard(
          email: email,
          onBackToHomeTab: () {},
        );
      case 'food':
        return FoodMerchantDashboard(email: email);
      case 'accommodation':
        return AccommodationMerchantDashboard(email: email);
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
      final newRole = _roleString;
      final rawEmail = user.email ?? _identifierEmail;
      final emailForProfile = !rawEmail.endsWith('@phone.vero360.app')
          ? rawEmail
          : _identifierEmail;

      profile = {
        'email': emailForProfile,
        'name': user.displayName ?? _name.text.trim(),
        'phone': _identifierPhone,
        'role': newRole,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'authProvider': 'firebase_only',
      };
      if (_role == UserRole.merchant && _selectedMerchantService != null) {
        profile['merchantService'] = _selectedMerchantService!.key;
        profile['businessName'] = _businessName.text.trim();
        profile['businessAddress'] = _businessAddress.text.trim();
        profile['status'] = 'pending';
        profile['isActive'] = false;
      }
      try {
        await _firestore.collection('users').doc(user.uid).set(
              profile,
              SetOptions(merge: true),
            );
        if (_role == UserRole.merchant &&
            _selectedMerchantService != null &&
            _businessName.text.trim().isNotEmpty) {
          final merchantProfile = {
            'uid': user.uid,
            'email': emailForProfile,
            'name': user.displayName ?? _name.text.trim(),
            'phone': _identifierPhone,
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
          final collectionName = _selectedMerchantService!.key == 'marketplace'
              ? 'marketplace_merchants'
              : '${_selectedMerchantService!.key}_merchants';
          await _firestore
              .collection(collectionName)
              .doc(user.uid)
              .set(merchantProfile);
        }
      } catch (_) {}
    }

    final roleFromProfile =
        (profile['role'] ?? 'customer').toString().toLowerCase();
    // Registration form is source of truth: stale Firestore must not downgrade to customer.
    final role = (_role == UserRole.merchant || _role == UserRole.driver)
        ? _roleString
        : roleFromProfile;
    final token = await user.getIdToken();
    final re = user.email ?? _identifierEmail;
    final responseEmail = profile['email']?.toString() ??
        (!re.endsWith('@phone.vero360.app') ? re : _identifierEmail);

    return <String, dynamic>{
      'authProvider': 'firebase_only',
      'token': token,
      'user': <String, dynamic>{
        'uid': user.uid,
        'firebaseUid': user.uid,
        'email': responseEmail,
        'name': profile['name']?.toString() ?? _name.text.trim(),
        'phone': profile['phone']?.toString() ?? _identifierPhone,
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

  /// Fast auth result for social signup so we can navigate quickly without
  /// waiting for Firestore reads/writes. Uses current form state for fields.
  Future<Map<String, dynamic>> _buildQuickResultFromUser(User user) async {
    final role = _roleString;
    final token = await user.getIdToken();
    // Prefer explicit email from form, fall back to Firebase email.
    final rawEmail = user.email ?? _identifierEmail;
    final emailForUser = _identifierEmail.isNotEmpty ? _identifierEmail : rawEmail;

    return <String, dynamic>{
      'authProvider': 'firebase_only',
      'token': token,
      'user': <String, dynamic>{
        'uid': user.uid,
        'firebaseUid': user.uid,
        'email': emailForUser,
        'phone': _identifierPhone,
        'name': user.displayName ?? _name.text.trim(),
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
  /// When form fields are empty (e.g. after Google/Apple sign-in), uses [user] email/displayName.
  /// Returns true if sync succeeded (2xx), false otherwise.
  Future<bool> _syncProfileToBackend(User user) async {
    final role = _roleString;
    final name = _name.text.trim().isEmpty
        ? (user.displayName ?? user.email ?? '')
        : _name.text.trim();
    // When user signed up with phone only, don't send synthetic auth email to backend.
    final rawEmail = _identifierEmail.isEmpty
        ? (user.email ?? '')
        : _identifierEmail;
    final email = rawEmail.endsWith('@phone.vero360.app') ? '' : rawEmail;
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'phone': _identifierPhone,
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
      final res = await ApiClient.put(
        '/users/me',
        body: jsonEncode(body),
        timeout: const Duration(seconds: 10),
      );
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] PUT /users/me (role: $role) => ${res.statusCode}');
      }
      if (!ok && mounted) {
        ToastHelper.showCustomToast(
          context,
          'Profile sync failed (${res.statusCode}). Role may show as customer.',
          isSuccess: false,
          errorMessage: '',
        );
      }
      return ok;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] PUT /users/me failed: $e');
      }
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Could not sync role to server. Check connection and try again from Profile.',
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    }
  }

  /// Retry syncing role to backend after a short delay (handles guard creating user with default role on first request).
  void _retrySyncRoleToBackend(User user) {
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final ok = await _syncProfileToBackend(user);
      if (kDebugMode && ok) {
        // ignore: avoid_print
        print('[Register] Retry PUT /users/me succeeded');
      }
    });
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

    final email = _identifierEmail;
    final phone = _identifierPhone;
    if (email.isEmpty && phone.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Enter email or phone number.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    // Firebase Auth requires an email for createUserWithEmailAndPassword.
    // When user enters only a phone number, use a synthetic email so we can still create the account;
    // we store and display the real phone everywhere else.
    final authEmail = email.isNotEmpty
        ? email
        : '${_normalizePhone(phone)}@phone.vero360.app';

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
        email: authEmail,
        password: _password.text,
      );

      final user = userCredential.user;
      if (user == null) throw Exception('Firebase user creation failed');

      final role = _roleString;

      final userData = <String, dynamic>{
        'uid': user.uid,
        'email': _identifierEmail,
        'name': _name.text.trim(),
        'phone': _identifierPhone,
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
          'email': _identifierEmail,
          'name': _name.text.trim(),
          'phone': _identifierPhone,
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
      // Store the identifier the user actually entered (email or phone) for display/login.
      await prefs.setString(
        'email',
        _identifierEmail.isNotEmpty ? _identifierEmail : _identifierValue,
      );
      if (_identifierPhone.isNotEmpty) {
        await prefs.setString('phone', _identifierPhone);
      }
      final nameVal = _name.text.trim();
      if (nameVal.isNotEmpty) {
        await prefs.setString('fullName', nameVal);
        await prefs.setString('name', nameVal);
      }
      await prefs.setString('role', role);
      await prefs.setString('user_role', role);
      await prefs.setBool('is_merchant', role == 'merchant');
      await prefs.setString('auth_provider', 'firebase_only');

      if (_role == UserRole.merchant) {
        await prefs.setString('merchant_service', _selectedMerchantService!.key);
        await prefs.setString('business_name', _businessName.text.trim());
        await prefs.setString('business_address', _businessAddress.text.trim());
      }

      // Sync role to backend so the API user record matches the chosen role.
      // Both merchants and drivers need the retry to ensure the backend profile is created.
      await _syncProfileToBackend(user);
      if (_role == UserRole.merchant || _role == UserRole.driver) {
        _retrySyncRoleToBackend(user);
      }

      final firebaseResponse = await _buildResultFromUser(user);

      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Account created successfully',
        isSuccess: true,
        errorMessage: '',
      );
      await NotificationService.instance.sendWelcomeNotificationIfFirstTime(
        uid: user.uid,
        name: _name.text.trim(),
        role: _roleString,
        merchantService: _role == UserRole.merchant
            ? _selectedMerchantService?.key
            : null,
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

  static String _googleSignInErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'network-request-failed':
          return 'Network error. Check your connection and try again.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
        default:
          return e.message?.trim().isNotEmpty == true
              ? e.message!
              : 'Google sign-in failed. Please try again.';
      }
    }
    final msg = e.toString();
    if (msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('hostname') ||
        msg.contains('unreachable') ||
        msg.contains('UNAVAILABLE')) {
      return 'Network error. Check your connection and try again.';
    }
    return msg.length > 80 ? 'Google sign-in failed. Please try again.' : msg;
  }

  Future<void> _google() async {
    if (!_canProceedWithSocialSignIn()) return;
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

      // If this Google account already has a profile in Firestore, treat it
      // as an existing account and ask the user to sign in instead of
      // creating a duplicate via the register screen.
      try {
        final snap = await _firestore.collection('users').doc(user.uid).get();
        if (snap.exists) {
          await _auth.signOut();
          if (!mounted) return;
          ToastHelper.showCustomToast(
            context,
            'Account already exists. Please sign in.',
            isSuccess: false,
            errorMessage: '',
          );
          return;
        }
      } catch (_) {
        // If this check fails, continue with normal flow to avoid blocking login.
      }

      // Build a lightweight result so we can navigate immediately.
      final result = await _buildQuickResultFromUser(user);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Signed in with Google',
        isSuccess: true,
        errorMessage: '',
      );
      await NotificationService.instance.sendWelcomeNotificationIfFirstTime(
        uid: user.uid,
        name: user.displayName ?? _name.text.trim(),
        role: _roleString,
        merchantService: _role == UserRole.merchant
            ? _selectedMerchantService?.key
            : null,
      );
      await _handleAuthResult(result);

      // Run heavy Firebase + backend sync in the background so navigation is not blocked.
      _buildResultFromUser(user).then((_) {
        _syncProfileToBackend(user).then((_) {
          if (_role == UserRole.merchant || _role == UserRole.driver) {
            _retrySyncRoleToBackend(user);
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        _googleSignInErrorMessage(e),
        isSuccess: false,
        errorMessage: '',
      );
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _apple() async {
    if (!_canProceedWithSocialSignIn()) return;
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

      // Prevent duplicate Apple-based accounts from the register screen.
      try {
        final snap = await _firestore.collection('users').doc(user.uid).get();
        if (snap.exists) {
          await _auth.signOut();
          if (!mounted) return;
          ToastHelper.showCustomToast(
            context,
            'Account already exists. Please sign in.',
            isSuccess: false,
            errorMessage: '',
          );
          return;
        }
      } catch (_) {
        // Ignore and continue with normal flow on failure.
      }

      // Build a lightweight result so we can navigate immediately.
      final result = await _buildQuickResultFromUser(user);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Signed in with Apple',
        isSuccess: true,
        errorMessage: '',
      );
      await NotificationService.instance.sendWelcomeNotificationIfFirstTime(
        uid: user.uid,
        name: user.displayName ?? _name.text.trim(),
        role: _roleString,
        merchantService: _role == UserRole.merchant
            ? _selectedMerchantService?.key
            : null,
      );
      await _handleAuthResult(result);

      // Run heavy Firebase + backend sync in the background so navigation is not blocked.
      _buildResultFromUser(user).then((_) {
        _syncProfileToBackend(user).then((_) {
          if (_role == UserRole.merchant || _role == UserRole.driver) {
            _retrySyncRoleToBackend(user);
          }
        });
      });
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

  // ---------- Terms & Conditions (aligned with Settings) ----------

  static const String _termsConditionsText =
      'By using Vero360, you agree to the following terms:\n\n'
      '• Use the app in a lawful and responsible manner.\n'
      '• Do not upload or share illegal, harmful, or misleading content.\n'
      '• Respect other users, merchants, and service providers.\n'
      '• The system holds money until both parties are satisfied with the business.\n'
      '• Merchants are responsible for the accuracy of their products and services.\n'
      '• Vero360 acts as a technology platform and is not the direct provider of services.\n\n'
      'We reserve the right to update these terms and policies as the platform evolves. '
      'Continued use of the app indicates acceptance of any updates.';

  void _showTermsAndConditionsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms & Conditions'),
        content: SingleChildScrollView(
          child: Text(
            _termsConditionsText,
            style: const TextStyle(height: 1.35),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
                            Wrap(
                              spacing: 8,
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
                                 ChoiceChip(
                                  label: const Text('Merchant'),
                                  selected: _role == UserRole.merchant,
                                  onSelected: (_) =>
                                      setState(() => _role = UserRole.merchant),
                                ),
                                ChoiceChip(
                                  label: const Text('Driver'),
                                  selected: _role == UserRole.driver,
                                  onSelected: (_) => setState(() {
                                    _role = UserRole.driver;
                                    _businessName.clear();
                                    _businessAddress.clear();
                                    _selectedMerchantService = null;
                                  }),
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
                              controller: _identifier,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(
                                label: ' phone number or email',
                                hint: ' 09xxxxxxxx or you@vero.com',
                                icon: Icons.contact_mail_outlined,
                              ),
                              validator: _validateIdentifier,
                            ),
                            const SizedBox(height: 14),

                            if (_role == UserRole.merchant) ...[
                              DropdownButtonFormField<MerchantService>(
                                value: _selectedMerchantService,
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
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Checkbox(
                                  value: _agree,
                                  onChanged: (v) =>
                                      setState(() => _agree = v ?? false),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _showTermsAndConditionsDialog,
                                    child: const Text.rich(
                                      TextSpan(
                                        text: 'I agree to the ',
                                        style: TextStyle(
                                          color: AppColors.body,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: 'Terms & Privacy Policy',
                                            style: TextStyle(
                                              color: AppColors.brandOrange,
                                              fontWeight: FontWeight.w700,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ],
                                      ),
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