import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/utils/app_logger.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/GernalServices/api_client.dart';

// Merchant dashboards
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vero360_app/features/Auth/AuthPresenter/auth_ui.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/oauth_buttons.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_otp_screen.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/signup_password_rules.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Auth/AuthServices/firebaseAuth.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/registration_verification_service.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/settings/Settings.dart' show PolicyPage;

class AppColors {
  static const brandOrange = AuthPalette.orange;
  static const title = AuthPalette.ink;
  static const body = AuthPalette.muted;
  static const fieldFill = AuthPalette.field;
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
  final RegistrationVerificationService _verificationService =
      RegistrationVerificationService();
  final AuthService _authService = AuthService();

  RegistrationVerificationResult? _verificationResult;

  final _name = TextEditingController();
  final _identifier = TextEditingController(); // email or phone (one field)
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _businessName = TextEditingController();
  final _businessAddress = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _agree = false;
  bool _submittedOnce = false;

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

  String? _validateIdentifier(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email or phone number is required';
    if (_looksLikeEmail(s)) return null;
    if (_looksLikePhone(s)) return null;
    return 'Enter a valid email or phone (08/09xxxxxxxx or +2659xxxxxxxx)';
  }

  String? _validatePassword(String? v) => SignupPasswordRules.validate(v);

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

    await AuthStorage.syncBackendUserIdFromMe();

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
    }
    merchantService = normalizeMerchantServiceKey(merchantService);

    var role = RoleHelper.roleFromUserMap(user);
    if (_role == UserRole.merchant || _role == UserRole.driver) {
      role = _roleString;
    } else if (role.isEmpty) {
      role = RoleHelper.customer;
    }
    user['role'] = role;
    if (_role == UserRole.merchant && merchantService != null) {
      user['merchantService'] = merchantService;
    } else {
      user.remove('merchantService');
      user.remove('serviceType');
      user.remove('merchant_service');
    }

    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final uid = fbUid.isNotEmpty
        ? fbUid
        : (user['uid']?.toString() ?? user['firebaseUid']?.toString());
    if (uid != null && uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }
    await RoleSessionService.lockIntendedRole(
      prefs: prefs,
      role: role,
      merchantService: _role == UserRole.merchant ? merchantService : null,
      uid: uid,
    );
    await RoleSessionService.persistUserToPrefs(prefs, user);
    if (_role == UserRole.merchant) {
      if (_businessName.text.trim().isNotEmpty) {
        await prefs.setString('business_name', _businessName.text.trim());
      }
      if (_businessAddress.text.trim().isNotEmpty) {
        await prefs.setString('business_address', _businessAddress.text.trim());
      }
    }

    // Marketplace onboarding guide only for marketplace merchants (once per account).
    final guideDone = prefs.getBool('marketplace_merchant_guide_v1_done') == true ||
        (uid != null &&
            uid.isNotEmpty &&
            prefs.getBool('marketplace_merchant_guide_v1_done_$uid') == true);
    if (role == 'merchant' && merchantService == 'marketplace' && !guideDone) {
      await prefs.setBool('marketplace_merchant_guide_show_on_next_open', true);
    }

    if (!mounted) return;

    if (role == 'merchant') {
      await hydrateMerchantServiceFromFirestore(prefs);
      final serviceKey = normalizeMerchantServiceKey(
        prefs.getString('merchant_service') ??
            merchantService ??
            _selectedMerchantService?.key,
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
            builder: (_) => Bottomnavbar(email: displayId),
          ),
          (route) => false,
        );
      }
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
      case 'courier':
        return CourierMerchantDashboard(email: email);
    }
    return Bottomnavbar(email: email);
  }

  Future<Map<String, dynamic>> _buildResultFromUser(User user) async {
    Map<String, dynamic> profile = {};
    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      if (snap.exists && snap.data() != null) {
        profile = Map<String, dynamic>.from(snap.data()!);
      }
    } catch (e) {
      AppLogger.d('[Register] Firebase profile load failed', e);
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
    final token = await AuthHandler.getFirebaseToken();
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
    final token = await AuthHandler.getFirebaseToken();
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

  /// Short delay so the auth guard can create the API user. Avoid polling GET
  /// /users/me here — the backend getMe handler auto-creates a driver row and
  /// repeated calls cause duplicate-key errors.
  Future<void> _waitForBackendUserRecord() async {
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<bool> _putUsersMe(
    Map<String, dynamic> body, {
    required String logLabel,
  }) async {
    try {
      final res = await ApiClient.put(
        '/users/me',
        body: jsonEncode(body),
        timeout: const Duration(seconds: 10),
      );
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] PUT /users/me ($logLabel) => ${res.statusCode}');
      }
      return ok;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] PUT /users/me ($logLabel) failed: $e');
      }
      return false;
    }
  }

  /// Syncs the chosen role (and merchant data) to the backend so the API user
  /// record matches registration. Uses PUT /users/me.
  /// Returns true if sync succeeded (2xx), false otherwise.
  Future<bool> _syncProfileToBackend(
    User user, {
    bool showUserFeedback = false,
  }) async {
    final role = _roleString;
    final name = _name.text.trim().isEmpty
        ? (user.displayName ?? user.email ?? '')
        : _name.text.trim();
    final rawEmail = _identifierEmail.isEmpty
        ? (user.email ?? '')
        : _identifierEmail;
    final email = rawEmail.endsWith('@phone.vero360.app') ? '' : rawEmail;

    String? token;
    try {
      token = await user
          .getIdToken(true)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      token = await AuthHandler.getFirebaseToken();
    }
    if (token != null && token.isNotEmpty) {
      await AuthHandler.persistTokenToSp(token);
    }

    await _waitForBackendUserRecord();

    try {
      // Minimal payload first — full profile updates often 500 right after signup.
      if (_role == UserRole.driver || _role == UserRole.merchant) {
        if (await _putUsersMe({'role': role}, logLabel: 'role-only')) {
          return true;
        }
      }

      // Never send phone: '' — Postgres unique on phone treats '' as a value.
      final body = <String, dynamic>{'role': role};
      if (name.trim().isNotEmpty) body['name'] = name.trim();
      if (email.trim().isNotEmpty) body['email'] = email.trim();
      final phone = _identifierPhone.trim();
      if (phone.isNotEmpty) body['phone'] = phone;
      if (_role == UserRole.merchant) {
        if (_selectedMerchantService != null) {
          body['merchantService'] = _selectedMerchantService!.key;
        }
        final bn = _businessName.text.trim();
        final ba = _businessAddress.text.trim();
        if (bn.isNotEmpty) body['businessName'] = bn;
        if (ba.isNotEmpty) body['businessAddress'] = ba;
      }

      if (await _putUsersMe(body, logLabel: 'full-profile')) {
        return true;
      }

      if (showUserFeedback && mounted) {
        ToastHelper.showCustomToast(
          context,
          'Account created. Driver mode is active in the app; the server could not save your role yet (error 500).',
          isSuccess: true,
          errorMessage: '',
        );
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[Register] PUT /users/me failed: $e');
      }
      if (showUserFeedback && mounted) {
        ToastHelper.showCustomToast(
          context,
          'Account created. Driver mode is active in the app; server role sync failed — try again from Profile later.',
          isSuccess: true,
          errorMessage: '',
        );
      }
      return false;
    }
  }

  /// Persists the selected role to Firestore so later server syncs can recover
  /// when PUT /users/me fails or the API still reports "customer".
  Future<void> _persistRoleToFirestore(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'role': _roleString,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Retry syncing role to backend (handles guard creating user with default role on first request).
  void _retrySyncRoleToBackend(User user) {
    unawaited(_retrySyncRoleToBackendLoop(user));
  }

  Future<void> _retrySyncRoleToBackendLoop(User user) async {
    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ];
    for (final delay in delays) {
      await Future.delayed(delay);
      if (!mounted) return;
      await _persistRoleToFirestore(user);
      final ok = await _syncProfileToBackend(user, showUserFeedback: false);
      if (ok) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[Register] Retry PUT /users/me succeeded');
        }
        return;
      }
    }
    if (mounted && (_role == UserRole.driver || _role == UserRole.merchant)) {
      ToastHelper.showCustomToast(
        context,
        'Account created. ${_roleString == 'driver' ? 'Driver' : 'Merchant'} mode is active; server role sync is still pending.',
        isSuccess: true,
        errorMessage: '',
      );
    }
  }

  // ---------- Registration with API OTP verification ----------

  Future<bool> _sendRegistrationOtp() async {
    final email = _identifierEmail;
    final phone = _identifierPhone;
    _verificationResult = null;
    try {
      if (email.isNotEmpty) {
        await _verificationService.requestOtp(
          channel: 'email',
          email: email,
        );
      } else {
        await _verificationService.requestOtp(
          channel: 'phone',
          phone: phone,
        );
      }
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      ToastHelper.showCustomToast(
        context,
        RegistrationVerificationService.friendlyError(e, forSend: true),
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ToastHelper.showCustomToast(
        context,
        'Could not send verification code. Try again.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> _verifyRegistrationOtp(String code) async {
    final email = _identifierEmail;
    final phone = _identifierPhone;
    final channel = email.isNotEmpty ? 'email' : 'phone';
    final ticket = await _verificationService.verifyOtp(
      channel: channel,
      email: email.isNotEmpty ? email : null,
      phone: phone.isNotEmpty ? phone : null,
      code: code,
    );
    _verificationResult = RegistrationVerificationResult(
      channel: channel,
      verificationTicket: ticket,
    );
    return true;
  }

  Future<void> _createAccountAfterVerification() async {
    final verification = _verificationResult;
    if (verification == null || !verification.isVerified) {
      ToastHelper.showCustomToast(
        context,
        'Verification required before creating your account.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    final email = _identifierEmail;
    final phone = _identifierPhone.isNotEmpty
        ? RegistrationVerificationService.formatPhoneE164(_identifierPhone)
        : '';

    Map<String, dynamic>? merchantData;
    if (_role == UserRole.merchant && _selectedMerchantService != null) {
      merchantData = {
        'merchantService': _selectedMerchantService!.key,
        'serviceType': _selectedMerchantService!.key,
        'businessName': _businessName.text.trim(),
        'businessAddress': _businessAddress.text.trim(),
        'status': 'pending',
        'isActive': false,
      };
    }

    // OTP verified via API; account is created in Firebase (not NestJS DB).
    final result = await _authService.registerUser(
      name: _name.text.trim(),
      email: email,
      phone: phone.isNotEmpty ? phone : _identifierPhone,
      password: _password.text,
      role: _roleString,
      profilePicture: '',
      preferredVerification: verification.channel,
      verificationTicket: verification.verificationTicket,
      merchantData: merchantData,
      context: context,
    );

    if (result == null || !mounted) return;

    final userMap = result['user'];
    final uid = userMap is Map
        ? (userMap['uid'] ?? userMap['firebaseUid'])?.toString()
        : null;
    if (uid != null && uid.isNotEmpty) {
      await NotificationService.instance.sendWelcomeNotificationIfFirstTime(
        uid: uid,
        name: _name.text.trim(),
        role: _roleString,
        merchantService:
            _role == UserRole.merchant ? _selectedMerchantService?.key : null,
      );
    }

    await _handleAuthResult(result);
  }

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

    setState(() => _submittedOnce = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _registering = true);
    try {
      final sent = await _sendRegistrationOtp();
      if (!sent || !mounted) return;

      ToastHelper.showCustomToast(
        context,
        _identifierEmail.isNotEmpty
            ? '6-digit code sent to your email'
            : '6-digit code sent via SMS',
        isSuccess: true,
        errorMessage: '',
      );

      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RegisterOtpScreen(
            identifier: _identifierValue,
            channel: _identifierEmail.isNotEmpty ? 'email' : 'phone',
            onVerify: _verifyRegistrationOtp,
            onResend: _sendRegistrationOtp,
          ),
        ),
      );

      if (verified != true || !mounted) return;

      setState(() => _registering = true);
      await _createAccountAfterVerification();
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
    if (msg.contains('SHA') ||
        msg.contains('google-config') ||
        msg.contains('com.vero265.app') ||
        msg.contains('DEVELOPER_ERROR') ||
        msg.contains('ApiException: 10')) {
      return 'Google Sign-In is not set up for this app build. Add SHA-1 for com.vero265.app in Firebase Console.';
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

  // ---------- Terms & Conditions ----------

  void _openTermsAndConditionsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PolicyPage()),
    );
  }

  // ---------- UI helpers ----------

  InputDecoration _dec({
    required String label,
    required String hint,
    required IconData icon,
    Widget? trailing,
  }) {
    return authFieldDecoration(
      label: label,
      hint: hint,
      icon: icon,
      trailing: trailing,
    );
  }

  Widget _buildRoleSelector() {
    Widget chip(UserRole role, String label, IconData icon) {
      final selected = _role == role;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _role = role;
            if (role != UserRole.merchant) {
              _businessName.clear();
              _businessAddress.clear();
              _selectedMerchantService = null;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AuthPalette.orange : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AuthPalette.orange.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : AuthPalette.muted,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AuthPalette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AuthPalette.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          chip(UserRole.customer, 'Customer', Icons.person_rounded),
          chip(UserRole.merchant, 'Merchant', Icons.storefront_rounded),
          chip(UserRole.driver, 'Driver', Icons.local_taxi_rounded),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AuthHeroHeader(
                      title: 'Create your account',
                      subtitle: 'Join Vero360 in a minute.',
                    ),
                    const SizedBox(height: 22),
                    AuthCard(
                      child: Form(
                        key: _formKey,
                        autovalidateMode: _submittedOnce
                            ? AutovalidateMode.always
                            : AutovalidateMode.disabled,
                        onChanged: () => setState(() {}),
                        child: Column(
                          children: [
                            _buildRoleSelector(),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              decoration: _dec(
                                label: 'Your name',
                                hint: 'Your full name',
                                icon: Icons.person_outline_rounded,
                              ),
                              validator: _validateName,
                            ),
                            const SizedBox(height: 14),
                            if (_role == UserRole.merchant) ...[
                              TextFormField(
                                controller: _businessName,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: _dec(
                                  label: 'Business name',
                                  hint: 'Your business name',
                                  icon: Icons.storefront_outlined,
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
                                label: 'Phone number or email',
                                hint: '09xxxxxxxx or you@vero360.com',
                                icon: Icons.contact_mail_outlined,
                              ),
                              validator: _validateIdentifier,
                            ),
                            const SizedBox(height: 14),
                            if (_role == UserRole.merchant) ...[
                              DropdownButtonFormField<MerchantService>(
                                value: _selectedMerchantService,
                                decoration: _dec(
                                  label: 'Service you provide',
                                  hint: 'Select your service',
                                  icon: Icons.work_outline_rounded,
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
                                          color: AuthPalette.orange,
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
                                hint: 'At least 8 characters',
                                icon: Icons.lock_outline_rounded,
                                trailing: IconButton(
                                  tooltip: _obscure1 ? 'Show' : 'Hide',
                                  icon: Icon(
                                    _obscure1
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscure1 = !_obscure1,
                                  ),
                                ),
                              ),
                              validator: _validatePassword,
                            ),
                            AuthPasswordStrengthMeter(password: _password.text),
                            const SizedBox(height: 6),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'Use letters and numbers',
                                  style: TextStyle(
                                    color: AuthPalette.muted,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                            TextFormField(
                              controller: _confirm,
                              obscureText: _obscure2,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) {
                                if (!_registering) _registerWithFirebaseOnly();
                              },
                              decoration: _dec(
                                label: 'Confirm password',
                                hint: 'Re-enter your password',
                                icon: Icons.lock_outline_rounded,
                                trailing: IconButton(
                                  tooltip: _obscure2 ? 'Show' : 'Hide',
                                  icon: Icon(
                                    _obscure2
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscure2 = !_obscure2,
                                  ),
                                ),
                              ),
                              validator: _validateConfirm,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Checkbox(
                                  value: _agree,
                                  activeColor: AuthPalette.orange,
                                  onChanged: (v) =>
                                      setState(() => _agree = v ?? false),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _openTermsAndConditionsPage,
                                    child: const Text.rich(
                                      TextSpan(
                                        text: 'I agree to the ',
                                        style: TextStyle(
                                          color: AuthPalette.muted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: 'Terms & Privacy Policy',
                                            style: TextStyle(
                                              color: AuthPalette.orange,
                                              fontWeight: FontWeight.w800,
                                              decoration:
                                                  TextDecoration.underline,
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
                            AuthPrimaryButton(
                              label: _registering
                                  ? 'Sending code…'
                                  : 'Create account',
                              loading: _registering,
                              onPressed: _registering
                                  ? null
                                  : _registerWithFirebaseOnly,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const AuthOrDivider(),
                    const SizedBox(height: 18),
                    OAuthButtonsRow(
                      onGoogle: _socialLoading ? null : _google,
                      onApple: _socialLoading ? null : _apple,
                      iconOnly: true,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text.rich(
                        TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(
                            color: AuthPalette.muted,
                            fontWeight: FontWeight.w600,
                          ),
                          children: [
                            TextSpan(
                              text: 'Sign in',
                              style: TextStyle(
                                color: AuthPalette.orange,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}