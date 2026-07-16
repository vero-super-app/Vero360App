import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';

// Merchant dashboards
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/forgot_password_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/oauth_buttons.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/firebaseAuth.dart';
import 'package:vero360_app/features/Auth/AuthServices/recent_login_storage.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';

class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const fieldFill = Color(0xFFF7F7F9);
}

/// Google/Apple: [providerSheet] = system account picker is open;
/// [finishingVero] = account chosen; token + prefs + navigation.
enum _OAuthPhase { idle, providerSheet, finishingVero }

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
  _OAuthPhase _oauthPhase = _OAuthPhase.idle;
  /// Which provider flow is active (for overlay copy). Cleared when idle.
  String? _oauthProviderLabel;

  List<SavedLoginAccount> _savedAccounts = [];
  SavedLoginAccount? _selectedAccount;
  bool _showFullForm = false;
  bool _loadingSavedAccounts = true;

  /// True while Google/Apple flow is running (buttons disabled + overlay shown).
  bool get _socialLoading => _oauthPhase != _OAuthPhase.idle;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await RecentLoginStorage.loadAccounts();
    if (!mounted) return;
    setState(() {
      _savedAccounts = accounts;
      _loadingSavedAccounts = false;
      if (accounts.length == 1 && !_showFullForm) {
        _applySelectedAccount(accounts.first);
      }
    });
  }

  void _applySelectedAccount(SavedLoginAccount account) {
    _selectedAccount = account;
    _identifier.text = account.identifier;
    _password.clear();
  }

  void _selectAccount(SavedLoginAccount account) {
    setState(() => _applySelectedAccount(account));
  }

  void _switchAccount({bool addNewAccount = false}) {
    setState(() {
      _password.clear();
      if (addNewAccount) {
        _selectedAccount = null;
        _showFullForm = true;
        _identifier.clear();
        return;
      }
      _selectedAccount = null;
      _showFullForm = false;
      _identifier.clear();
    });
  }

  Future<void> _removeSavedAccount(SavedLoginAccount account) async {
    await RecentLoginStorage.removeAccount(account.id);
    if (!mounted) return;
    final remaining = _savedAccounts.where((a) => a.id != account.id).toList();
    setState(() {
      _savedAccounts = remaining;
      if (_selectedAccount?.id == account.id) {
        _selectedAccount = null;
        _identifier.clear();
        _password.clear();
        if (remaining.length == 1) {
          _applySelectedAccount(remaining.first);
          _showFullForm = false;
        } else if (remaining.isEmpty) {
          _showFullForm = true;
        }
      }
    });
  }

  Future<void> _persistSavedLoginAccount(
    Map<String, dynamic> result,
    Map<String, dynamic> user,
    String displayId,
  ) async {
    final authProvider =
        (result['authProvider'] ?? 'firebase').toString().toLowerCase();
    final name = (user['name'] ?? user['fullName'] ?? user['displayName'] ?? '')
        .toString()
        .trim();
    final email = user['email']?.toString().trim() ?? '';
    final phone = user['phone']?.toString().trim() ?? '';
    final identifier = phone.isNotEmpty && email.isEmpty
        ? phone
        : (email.isNotEmpty ? email : displayId);
    if (identifier.isEmpty) return;

    final photo = user['photoURL']?.toString() ??
        user['profilepicture']?.toString() ??
        user['profilePicture']?.toString();

    String provider = 'password';
    if (authProvider.contains('google')) {
      provider = 'google';
    } else if (authProvider.contains('apple')) {
      provider = 'apple';
    }

    await RecentLoginStorage.saveAccount(
      identifier: identifier,
      displayName: name.isNotEmpty ? name : identifier,
      photoUrl: photo,
      authProvider: provider,
    );
  }

  bool get _showSavedAccountPicker =>
      !_loadingSavedAccounts &&
      _savedAccounts.isNotEmpty &&
      !_showFullForm &&
      _selectedAccount == null;

  bool get _showSavedAccountSignIn =>
      !_loadingSavedAccounts &&
      _selectedAccount != null &&
      !_showFullForm;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  // -------------------- Merchant dashboard selection --------------------

  Widget _getMerchantDashboard(String serviceKey, String email) {
    final key = normalizeMerchantServiceKey(serviceKey) ?? serviceKey.trim().toLowerCase();
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

    final displayId = FirebaseAuth.instance.currentUser?.email?.trim().isNotEmpty == true
        ? FirebaseAuth.instance.currentUser!.email!.trim()
        : (user['email']?.toString() ??
            user['phone']?.toString() ??
            _identifier.text.trim());
    await prefs.setString('email', displayId);

    // Always overwrite identity fields so a previous account cannot linger.
    final nameVal = (user['name'] ??
            user['fullName'] ??
            user['displayName'] ??
            FirebaseAuth.instance.currentUser?.displayName ??
            '')
        .toString()
        .trim();
    if (nameVal.isNotEmpty) {
      await prefs.setString('fullName', nameVal);
      await prefs.setString('name', nameVal);
    } else {
      await prefs.remove('fullName');
      await prefs.remove('name');
    }
    final phoneVal = (user['phone'] ?? user['phoneNumber'] ?? user['mobile'] ?? '').toString().trim();
    if (phoneVal.isNotEmpty) {
      await prefs.setString('phone', phoneVal);
    }

    final role =
        (user['role'] ?? user['userRole'] ?? 'customer').toString().toLowerCase();
    await prefs.setString('role', role);
    await prefs.setString('user_role', role);
    await prefs.setBool('is_merchant', role == 'merchant');
    await loadDriverStatusFromPrefs();
    
    print('🔐 Login: user=$user');
    print('🔐 Login: role=$role');

    final uid = user['uid']?.toString() ??
        user['id']?.toString() ??
        user['firebaseUid']?.toString();
    if (uid != null && uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }

    await _persistSavedLoginAccount(result, user, displayId);

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

    // Always align numeric userId with backend /users/me for messaging
    await AuthStorage.syncBackendUserIdFromMe();

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
        await persistMerchantServiceFromApi(prefs, merchantService);
      }
      await hydrateMerchantServiceFromFirestore(prefs);

      final businessName = user['businessName']?.toString();
      if (businessName != null && businessName.isNotEmpty) {
        await prefs.setString('business_name', businessName);
      }

      final businessAddress = user['businessAddress']?.toString();
      if (businessAddress != null && businessAddress.isNotEmpty) {
        await prefs.setString('business_address', businessAddress);
      }

      final savedService = normalizeMerchantServiceKey(
            prefs.getString('merchant_service') ?? merchantService,
          ) ??
          '';
      if (savedService == 'marketplace' &&
          prefs.getBool('marketplace_merchant_guide_v1_done') != true) {
        await prefs.setBool('marketplace_merchant_guide_show_on_next_open', true);
      }
    }

    if (!mounted) return;

    TextInput.finishAutofillContext(shouldSave: true);

     if (role == 'merchant') {
       final merchantService = prefs.getString('merchant_service');

       if (merchantService != null && merchantService.isNotEmpty) {
         final merchantDashboard =
             _getMerchantDashboard(merchantService, displayId);

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
     } else {
       Navigator.of(context).pushAndRemoveUntil(
         MaterialPageRoute(
           builder: (_) => Bottomnavbar(email: displayId),
         ),
         (route) => false,
       );
     }
  }

  // -------------------- Firebase profile helpers --------------------

  Future<String?> _fetchMerchantServiceFromFirebase(String uid) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
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

        final merchantDoc = await _firestore
            .collection(collectionName)
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 8));
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
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 12));
      if (snap.exists && snap.data() != null) {
        profile = Map<String, dynamic>.from(snap.data()!);
      }
    } catch (e) {
      print('Failed to load Firebase profile: $e');
    }

    // Ensure at least a basic profile exists
    if (profile.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final cachedRole = (prefs.getString('user_role') ?? 'customer').toLowerCase();
      profile = {
        'email': user.email,
        'name': user.displayName,
        'phone': '',
        'role': cachedRole,
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
    final token = await AuthHandler.getFirebaseToken();
    final rawEmail = user.email ?? _identifier.text.trim();
    final isPhoneAccount = rawEmail.endsWith('@phone.vero360.app');
    final displayEmail = isPhoneAccount ? '' : rawEmail;
    final displayPhone = profile['phone']?.toString() ?? (isPhoneAccount ? _identifier.text.trim() : '');

    return <String, dynamic>{
      'authProvider': 'firebase',
      'token': token,
      'user': <String, dynamic>{
        'uid': user.uid,
        'firebaseUid': user.uid,
        'email': displayEmail,
        'phone': displayPhone,
        'name': profile['name']?.toString() ?? (user.displayName ?? ''),
        'role': role,
        'photoURL': user.photoURL ?? profile['photoURL'] ?? profile['profilepicture'],
        'merchantService': profile['merchantService'],
        'businessName': profile['businessName'],
        'businessAddress': profile['businessAddress'],
      },
    };
  }

  /// Fast auth result for Google/Apple login. Reads role from Firestore
  /// (or SharedPreferences as fallback) so drivers/merchants route correctly.
  Future<Map<String, dynamic>> _buildQuickResultFromUser(User user) async {
    final email = user.email ?? _identifier.text.trim();

    // Start token + Firestore together; await separately so one failure doesn’t drop the other.
    final tokenFut = user.getIdToken(false);
    final snapFut = _firestore.collection('users').doc(user.uid).get();
    String role = 'customer';
    String? token;
    try {
      token = await tokenFut;
    } catch (_) {}
    try {
      final snap = await snapFut;
      if (snap.exists && snap.data() != null) {
        role = (snap.data()!['role'] ?? '').toString().toLowerCase();
      }
    } catch (_) {}
    if (role.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      role = (prefs.getString('user_role') ?? 'customer').toLowerCase();
    }

    return <String, dynamic>{
      'authProvider': 'firebase',
      'token': token,
      'user': <String, dynamic>{
        'uid': user.uid,
        'firebaseUid': user.uid,
        'email': email,
        'phone': user.phoneNumber ?? '',
        'name': user.displayName ?? '',
        'photoURL': user.photoURL,
        'role': role,
        'merchantService': null,
        'businessName': null,
        'businessAddress': null,
      },
    };
  }

  // -------------------- Email/phone + password submit --------------------

  static bool _looksLikeEmail(String v) =>
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(v);

  static bool _looksLikePhone(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(08|09)\d{8}$').hasMatch(digits) ||
        RegExp(r'^\+265[89]\d{8}$').hasMatch(t);
  }

  static String _normalizePhoneForAuth(String raw) {
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final identifier = _identifier.text.trim();
    final password = _password.text.trim();

    setState(() => _loading = true);
    try {
      // Phone or backend-first: use AuthService (backend + Firebase fallback for email)
      if (!_looksLikeEmail(identifier)) {
        // For phone: don't show backend error toast yet; try Firebase fallback first, then show one error if both fail.
        final isPhone = _looksLikePhone(identifier);
        var result = await _authService.loginWithIdentifier(
          identifier,
          password,
          context,
          showErrorToast: !isPhone,
        );
        if (result != null && mounted) {
          await _handleAuthResult(result);
          return;
        }
        // Phone-only accounts created on register use Firebase with synthetic email.
        // Try signing in with that when backend doesn't know the phone.
        if (isPhone && mounted) {
          final authEmail =
              '${_normalizePhoneForAuth(identifier)}@phone.vero360.app';
          try {
            final cred = await _auth.signInWithEmailAndPassword(
              email: authEmail,
              password: password,
            );
            final user = cred.user;
            if (user != null && mounted) {
              result = await _buildResultFromUser(user);
              ToastHelper.showCustomToast(
                context,
                'Logged in successfully',
                isSuccess: true,
                errorMessage: '',
              );
              await _handleAuthResult(result);
              return;
            }
          } on FirebaseAuthException catch (_) {}
        }
        if (mounted && isPhone) {
          ToastHelper.showCustomToast(
            context,
            'Incorrect phone number or password.',
            isSuccess: false,
            errorMessage: '',
          );
        }
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

  Future<void> _showForgotPasswordDialog() async {
    if (!mounted) return;
    final identifier = _identifier.text.trim();
    final updatedIdentifier = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ForgotPasswordScreen(initialIdentifier: identifier),
      ),
    );
    if (updatedIdentifier != null &&
        updatedIdentifier.trim().isNotEmpty &&
        mounted) {
      _identifier.text = updatedIdentifier.trim();
    }
  }

  // -------------------- Social sign-in via Firebase (no platform lock) --------------------

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
    FocusScope.of(context).unfocus();
    // 1) Show Vero UI + overlay while the system Google sheet is open (not empty).
    setState(() {
      _oauthProviderLabel = 'Google';
      _oauthPhase = _OAuthPhase.providerSheet;
    });
    try {
      // 2) Returns only after the user finishes or cancels the Google flow.
      final user = await _firebaseAuthService.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        ToastHelper.showCustomToast(
          context,
          'Google sign-in was cancelled.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      // 3) Google is done — now token + prefs + navigate to Vero.
      setState(() => _oauthPhase = _OAuthPhase.finishingVero);
      final result = await _buildQuickResultFromUser(user);
      await _handleAuthResult(result);
      unawaited(_buildResultFromUser(user));
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        _googleSignInErrorMessage(e),
        isSuccess: false,
        errorMessage: '',
      );
    } finally {
      if (mounted) {
        setState(() {
          _oauthPhase = _OAuthPhase.idle;
          _oauthProviderLabel = null;
        });
      }
    }
  }

  Future<void> _apple() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _oauthProviderLabel = 'Apple';
      _oauthPhase = _OAuthPhase.providerSheet;
    });
    try {
      final user = await _firebaseAuthService.signInWithApple();
      if (!mounted) return;
      if (user == null) {
        ToastHelper.showCustomToast(
          context,
          'Apple sign-in was cancelled or is not available on this device.',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      setState(() => _oauthPhase = _OAuthPhase.finishingVero);
      final result = await _buildQuickResultFromUser(user);
      await _handleAuthResult(result);
      unawaited(_buildResultFromUser(user));
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Apple sign-in failed.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _oauthPhase = _OAuthPhase.idle;
          _oauthProviderLabel = null;
        });
      }
    }
  }

  Widget _buildOAuthBlockingOverlay() {
    final label = _oauthProviderLabel ?? '';
    final isFinishing = _oauthPhase == _OAuthPhase.finishingVero;
    final title = isFinishing
        ? 'Signing you in to Vero…'
        : 'Continue with $label…';
    final subtitle = isFinishing
        ? 'Setting up your session…'
        : 'Finish the $label window first — we\'ll take you to Vero right after.';

    return Positioned.fill(
      child: AbsorbPointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.45),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
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

  Widget _avatarForAccount(SavedLoginAccount account, {double radius = 26}) {
    final photo = account.photoUrl;
    if (photo != null && photo.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.fieldFill,
        backgroundImage: NetworkImage(photo),
        onBackgroundImageError: (_, __) {},
        child: photo.isEmpty ? Text(account.initials) : null,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.brandOrange.withValues(alpha: 0.15),
      child: Text(
        account.initials,
        style: TextStyle(
          color: AppColors.brandOrange,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }

  Widget _buildSavedAccountCard(SavedLoginAccount account) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: (_loading || _socialLoading)
              ? null
              : () => _selectAccount(account),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _avatarForAccount(account),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.identifier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove saved account',
                  onPressed: (_loading || _socialLoading)
                      ? null
                      : () => _removeSavedAccount(account),
                  icon: Icon(Icons.close, size: 20, color: Colors.grey.shade500),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.brandOrange,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedAccountHeader() {
    final account = _selectedAccount!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          _avatarForAccount(account, radius: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: AppColors.title,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  account.identifier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: (_loading || _socialLoading) ? null : _switchAccount,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandOrange,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Switch',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continueWithSavedSocial(SavedLoginAccount account) async {
    if (account.authProvider == 'google') {
      await _google();
    } else if (account.authProvider == 'apple') {
      await _apple();
    }
  }

  Widget _buildCredentialForm() {
    return AutofillGroup(
      child: Column(
        children: [
          if (_showSavedAccountSignIn) ...[
            _buildSelectedAccountHeader(),
            const SizedBox(height: 16),
            if (_selectedAccount!.isSocial) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_loading || _socialLoading)
                      ? null
                      : () => _continueWithSavedSocial(_selectedAccount!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _selectedAccount!.authProvider == 'google'
                        ? 'Continue with Google'
                        : 'Continue with Apple',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ] else ...[
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: _fieldDecoration(
                  label: 'Password',
                  hint: 'Enter your password',
                  icon: Icons.lock_outline,
                  trailing: IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'Must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_loading || _socialLoading)
                      ? null
                      : _showForgotPasswordDialog,
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
                  onPressed: (_loading || _socialLoading) ? null : _submit,
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
            if (_savedAccounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: (_loading || _socialLoading) ? null : _switchAccount,
                child: const Text(
                  'Switch account',
                  style: TextStyle(
                    color: AppColors.brandOrange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ] else ...[
            TextFormField(
              controller: _identifier,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
                AutofillHints.telephoneNumber,
              ],
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: 'Phone number or email',
                hint: '09xxxxxxxx or you@vero.com',
                icon: Icons.person_outline,
              ),
              validator: (v) {
                final val = v?.trim() ?? '';
                if (val.isEmpty) return 'Email or phone is required';
                if (!_looksLikeEmail(val) && !_looksLikePhone(val)) {
                  return 'Enter a valid email or phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: _fieldDecoration(
                label: 'Password',
                hint: '••••••••',
                icon: Icons.lock_outline,
                trailing: IconButton(
                  tooltip: _obscure ? 'Show' : 'Hide',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 6) return 'Must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (_loading || _socialLoading)
                    ? null
                    : _showForgotPasswordDialog,
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
                onPressed: (_loading || _socialLoading) ? null : _submit,
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
            if (_savedAccounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: (_loading || _socialLoading)
                    ? null
                    : () => setState(() {
                          _showFullForm = false;
                          _selectedAccount = null;
                        }),
                child: const Text(
                  'Switch account',
                  style: TextStyle(
                    color: AppColors.brandOrange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
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
                    Text(
                      _showSavedAccountPicker
                          ? (_savedAccounts.length > 1
                              ? 'Switch account'
                              : 'Continue as')
                          : 'Welcome back',
                      style: const TextStyle(
                        color: AppColors.title,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_showSavedAccountPicker) ...[
                      const SizedBox(height: 6),
                      Text(
                        _savedAccounts.length > 1
                            ? 'Choose an account or add another one'
                            : 'Tap your account, then enter your password',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ] else if (_showSavedAccountSignIn) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Enter your password to continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to pick up where you left off',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
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
                      child: _loadingSavedAccounts
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.brandOrange,
                                  ),
                                ),
                              ),
                            )
                          : _showSavedAccountPicker
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ..._savedAccounts.map(_buildSavedAccountCard),
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: (_loading || _socialLoading)
                                      ? null
                                      : () => _switchAccount(addNewAccount: true),
                                  child: const Text(
                                    'Add another account',
                                    style: TextStyle(
                                      color: AppColors.brandOrange,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Form(
                              key: _formKey,
                              child: _buildCredentialForm(),
                            ),
                    ),

                    if (!_showSavedAccountPicker) ...[
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
                          onPressed: (_loading || _socialLoading)
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
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_oauthPhase != _OAuthPhase.idle) _buildOAuthBlockingOverlay(),
      ]),
    );
  }
}
