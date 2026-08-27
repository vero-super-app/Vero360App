import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:local_auth/local_auth.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/account_data_purge.dart';

import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/config/api_config.dart';

import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/display_name_sync.dart';
import 'package:vero360_app/utils/app_update_checker.dart';
import 'package:vero360_app/utils/app_version_info.dart';
import 'package:vero360_app/GernalServices/engagement_notification_service.dart';
import 'package:vero360_app/settings/blocked_merchants_page.dart';

// REQUIRED PAGES
import 'package:vero360_app/GeneralPages/address.dart'; // AddressPage
import 'package:vero360_app/GeneralPages/changepassword.dart'; // ChangePasswordPage
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/become_driver_page.dart';

const Color kBrandOrange = Color(0xFFFF8A00); // Vero360 main color

/// Filters out Firebase identifiers (e.g. +firebase_xxx) so we show real phone numbers only.
String _sanitizePhone(String? s) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return '';
  if (t.toLowerCase().startsWith('+firebase_') ||
      t.toLowerCase().contains('firebase_')) {
    return '';
  }
  return t;
}

class SettingsPage extends StatefulWidget {
  /// If Settings is shown as a TAB/root, pass this so back goes to home tab instead of closing app.
  final VoidCallback? onBackToHomeTab;

  const SettingsPage({super.key, this.onBackToHomeTab});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  bool _refreshing = false;
  bool _isDriver = false;
  bool _isMerchant = false;
  bool _switchingDriverMode = false;
  final _driverService = DriverService();

  // cached profile
  String _name = 'Guest User';
  String _email = 'No Email';
  String _phone = 'No Phone';
  String _address = 'my address';
  String _photoUrl = '';

  // app info
  String _appVersion = '—';
  String _buildNumber = '—';

  // address count + default address for profile header (from API)
  int _addressCount = -1; // -1 = not loaded yet
  String _defaultAddressDisplay = ''; // default address line on profile card

  // personalization
  bool _compactMode = false;
  bool _haptics = true;
  String _languageCode = 'en'; // en = English, ny = Chichewa

  // notifications (prefs; actual FCM can be wired elsewhere)
  bool _notificationsEnabled = true;
  bool _notificationsOrders = true;
  bool _notificationsMessages = true;
  bool _notificationsEngagement = true;

  // security: Face ID / fingerprint app lock
  bool _biometricLockEnabled = false;

  // customer service & app links
  static const String _supportPhone = '+265992695612';
  static const String _supportWhatsApp = '+265992695612';
  static const String _supportEmail = 'info@vero360.app';

  /// Display phone; filters out Firebase identifiers so we never show +firebase_xxx.
  String get _displayPhone {
    final s = _sanitizePhone(_phone);
    return s.isEmpty ? 'No Phone' : _phone;
  }

  /// Localization: returns English or Chichewa based on _languageCode (Settings-only).
  String _t(String en, String ny) =>
      _languageCode == 'ny' ? ny : en;

  @override
  void initState() {
    super.initState();
    _bootstrapFast();
  }

  /// FAST BOOTSTRAP:
  /// - load prefs + firebase auth only (quick)
  /// - DO NOT call API here (no waiting)
  /// - app version loads in background (non-blocking)
  Future<void> _bootstrapFast() async {
    try {
      await Future.wait([
        _loadPersonalizationPrefs(),
        _loadCachedProfile(),
        _hydrateFromFirebaseAuth(),
      ]);
    } catch (_) {}

    if (mounted) setState(() => _loading = false);

    // Load Firestore profile, app info, and address count in background
    // so the Settings screen appears quickly, then hydrates with fresher data.
    unawaited(_loadProfileFromFirestore());
    unawaited(_loadAppInfo().then((_) {
      if (mounted) setState(() {});
    }));
    unawaited(_loadAddressCount());
  }

  Future<void> _loadAddressCount() async {
    try {
      final list = await AddressService().getMyAddresses();
      Address? defaultOrFirst;
      for (final a in list) {
        if (a.isDefault) {
          defaultOrFirst = a;
          break;
        }
      }
      defaultOrFirst ??= list.isNotEmpty ? list.first : null;
      final display = defaultOrFirst?.displayLine ?? '';
      if (mounted) {
        setState(() {
          _addressCount = list.length;
          _defaultAddressDisplay = display.trim().isEmpty ? _address : display;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addressCount = 0;
          _defaultAddressDisplay = _address;
        });
      }
    }
  }

  String get _addressCountSubtitle {
    if (_addressCount < 0) return '—';
    if (_addressCount == 0) return _t('No addresses', 'Palibe maadiresi');
    if (_addressCount == 1) return _t('1 address', 'Adiresi imodzi');
    return _t('$_addressCount addresses', 'Maadiresi $_addressCount');
  }

  String get _languageSubtitle {
    switch (_languageCode) {
      case 'ny':
        return 'Chichewa';
      case 'en':
      default:
        return 'English';
    }
  }

  Future<void> _loadAppInfo() async {
    _appVersion = AppVersionInfo.version;
    _buildNumber = AppVersionInfo.buildNumber;
  }

  Future<void> _loadPersonalizationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _compactMode = prefs.getBool('pref_compact_mode') ?? false;
      _haptics = prefs.getBool('pref_haptics') ?? true;
      _languageCode = prefs.getString('pref_language_code') ?? 'en';
      _notificationsEnabled = prefs.getBool('pref_notifications_enabled') ?? true;
      _notificationsOrders = prefs.getBool('pref_notifications_orders') ?? true;
      _notificationsMessages = prefs.getBool('pref_notifications_messages') ?? true;
      _notificationsEngagement =
          prefs.getBool(EngagementNotificationService.prefEnabled) ?? true;
      _biometricLockEnabled = prefs.getBool('pref_biometric_lock') ?? false;
    });
  }

  Future<void> _saveBiometricLockPref(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_biometric_lock', value);
  }

  Future<void> _savePersonalizationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_compact_mode', _compactMode);
    await prefs.setBool('pref_haptics', _haptics);
    await prefs.setString('pref_language_code', _languageCode);
    await prefs.setBool('pref_notifications_enabled', _notificationsEnabled);
    await prefs.setBool('pref_notifications_orders', _notificationsOrders);
    await prefs.setBool('pref_notifications_messages', _notificationsMessages);
    await prefs.setBool(
      EngagementNotificationService.prefEnabled,
      _notificationsEngagement,
    );
    unawaited(
      EngagementNotificationService.instance.syncTopicSubscription(
        enabledOverride: _notificationsEnabled && _notificationsEngagement,
      ),
    );
    await prefs.setBool('pref_biometric_lock', _biometricLockEnabled);
  }

  void _maybeHaptic() {
    if (_haptics) HapticFeedback.selectionClick();
  }

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final phone = _sanitizePhone(prefs.getString('phone') ?? '');
    final role = RoleHelper.normalizeAccountRole(
          prefs.getString('user_role') ?? prefs.getString('role'),
        ) ??
        RoleHelper.customer;
    setState(() {
      _name = prefs.getString('fullName') ?? prefs.getString('name') ?? _name;
      _email = prefs.getString('email') ?? _email;
      if (phone.isNotEmpty) _phone = phone;
      _address = prefs.getString('address') ?? _address;
      _photoUrl = prefs.getString('profilepicture') ?? '';
      _isDriver = role == RoleHelper.driver;
      _isMerchant = role == RoleHelper.merchant;
    });
  }

  Future<void> _remountMainShell() async {
    if (!mounted) return;
    openVeroMainShell(context, email: _email.trim());
  }

  Future<void> _onDriverModeChanged(bool enableDriver) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      ToastHelper.showCustomToast(
        context,
        _t('Sign in to switch to driver mode.', 'Lowani kuti musinthe ku driver.'),
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    if (_switchingDriverMode || _isMerchant) return;

    if (!enableDriver) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(_t('Switch to passenger?', 'Musinthe kupita kwa passenger?')),
              content: Text(
                _t(
                  'You will use the app as a passenger. You can switch back to driver mode anytime.',
                  'Mudzagwiritsa ntchito ngati passenger. Mutha kubwerera ku driver nthawi ina.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_t('Cancel', 'Letsani')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(_t('Switch', 'Sinthani')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;

      setState(() => _switchingDriverMode = true);
      try {
        await RoleSessionService.setAccountRole(RoleHelper.customer);
        if (!mounted) return;
        setState(() {
          _isDriver = false;
          _switchingDriverMode = false;
        });
        ToastHelper.showCustomToast(
          context,
          _t('Switched to passenger mode', 'Mwasintha kupita kwa passenger'),
          isSuccess: true,
          errorMessage: '',
        );
        await _remountMainShell();
      } catch (_) {
        if (!mounted) return;
        setState(() => _switchingDriverMode = false);
        ToastHelper.showCustomToast(
          context,
          _t('Could not switch mode. Try again.', 'Sizinathe. Yesaninso.'),
          isSuccess: false,
          errorMessage: '',
        );
      }
      return;
    }

    setState(() => _switchingDriverMode = true);
    try {
      final hasProfile = await _driverService.hasDriverProfile();
      if (!mounted) return;
      if (!hasProfile) {
        setState(() => _switchingDriverMode = false);
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BecomeDriverPage()),
        );
        if (!mounted) return;
        await _loadCachedProfile();
        return;
      }

      await RoleSessionService.setAccountRole(RoleHelper.driver);
      if (!mounted) return;
      setState(() {
        _isDriver = true;
        _switchingDriverMode = false;
      });
      ToastHelper.showCustomToast(
        context,
        _t('Switched to driver mode', 'Mwasintha kupita ku driver'),
        isSuccess: true,
        errorMessage: '',
      );
      await _remountMainShell();
    } catch (_) {
      if (!mounted) return;
      setState(() => _switchingDriverMode = false);
      ToastHelper.showCustomToast(
        context,
        _t('Could not switch to driver. Try again.', 'Sizinathe. Yesaninso.'),
        isSuccess: false,
        errorMessage: '',
      );
    }
  }

  Future<void> _hydrateFromFirebaseAuth() async {
    final u = _auth.currentUser;
    if (u == null) return;

    if ((u.displayName ?? '').trim().isNotEmpty) _name = u.displayName!.trim();
    if ((u.email ?? '').trim().isNotEmpty) _email = u.email!.trim();
    if ((u.photoURL ?? '').trim().isNotEmpty) _photoUrl = u.photoURL!.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', _email);
    if (_name.trim().isNotEmpty) {
      await prefs.setString('fullName', _name);
      await prefs.setString('name', _name);
    }
    if (_photoUrl.trim().isNotEmpty) {
      await prefs.setString('profilepicture', _photoUrl);
    }

    if (mounted) setState(() {});
  }

  /// Load profile (name, phone, address, photo) from Firestore users/{uid}.
  Future<void> _loadProfileFromFirestore() async {
    final u = _auth.currentUser;
    if (u == null) return;

    try {
      final snap = await _firestore.collection('users').doc(u.uid).get();
      if (!snap.exists || snap.data() == null) return;

      final data = Map<String, dynamic>.from(snap.data()!);
      if ((data['name'] ?? '').toString().trim().isNotEmpty) {
        _name = data['name'].toString().trim();
      }
      if ((data['email'] ?? '').toString().trim().isNotEmpty) {
        _email = data['email'].toString().trim();
      }
      final phoneVal = _sanitizePhone(
          (data['phone'] ?? '').toString().trim());
      if (phoneVal.isNotEmpty) {
        _phone = phoneVal;
      }
      if ((data['address'] ?? '').toString().trim().isNotEmpty) {
        _address = data['address'].toString().trim();
      }
      final pic = (data['profilepicture'] ??
              data['profilePicture'] ??
              data['photoURL'] ??
              '')
          .toString()
          .trim();
      if (pic.isNotEmpty) _photoUrl = pic;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fullName', _name);
      await prefs.setString('name', _name);
      await prefs.setString('email', _email);
      await prefs.setString('phone', _phone);
      await prefs.setString('address', _address);
      await prefs.setString('profilepicture', _photoUrl);

      if (mounted) setState(() {});
    } catch (_) {
      // Silent: keep existing cached values
    }
  }

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt') ??
        '';
  }

  /// Optional: manual refresh only (NOT used in initState)
  Future<void> _fetchUserMeFromApiQuick() async {
    try {
      final token = await _getAuthToken();
      if (token.isEmpty) return;

      final base = await ApiConfig.readBase();
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json'
        },
      ).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final data = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{});

        final user = (data['user'] is Map)
            ? Map<String, dynamic>.from(data['user'])
            : data;

        await _persistUserToPrefsFromApi(user);
      }
    } catch (_) {
      // NO offline banner. Just silent / friendly.
    }
  }

  Future<void> _persistUserToPrefsFromApi(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();

    final name = (user['name'] ?? 'Guest User').toString().trim();
    final email = (user['email'] ?? '').toString().trim();
    final phone = _sanitizePhone(
        (user['phone'] ?? '').toString().trim());
    final pic = (user['profilepicture'] ??
            user['profilePicture'] ??
            user['photoURL'] ??
            '')
        .toString()
        .trim();

    String addr = _address;
    final addresses = user['addresses'];
    if (addresses is List && addresses.isNotEmpty) {
      final first = addresses.first;
      if (first is Map && first['address'] != null) {
        addr = first['address'].toString();
      } else if (first is String && first.trim().isNotEmpty) {
        addr = first;
      }
    } else if (user['address'] != null) {
      addr = user['address'].toString();
    }

    _name = name.isEmpty ? _name : name;
    _email = email.isEmpty ? _email : email;
    _phone = phone.isEmpty ? _phone : phone;
    _address = addr.trim().isEmpty ? _address : addr.trim();
    if (pic.isNotEmpty) _photoUrl = pic;

    await prefs.setString('fullName', _name);
    await prefs.setString('name', _name);
    await prefs.setString('email', _email);
    await prefs.setString('phone', _phone);
    await prefs.setString('address', _address);
    await prefs.setString('profilepicture', _photoUrl);

    if (mounted) setState(() {});
  }

  Future<void> _onRefresh() async {
    _maybeHaptic();
    setState(() => _refreshing = true);
    try {
      await _hydrateFromFirebaseAuth();
      await _loadProfileFromFirestore();
      await _fetchUserMeFromApiQuick(); // optional + quick timeout
      await _loadCachedProfile();
      await _loadAddressCount();
      ToastHelper.showCustomToast(
        context,
        _t('Refreshed', 'Zafikidwanso'),
        isSuccess: true,
        errorMessage: '',
      );
    } catch (_) {
      ToastHelper.showCustomToast(
        context,
        _t('Could not refresh right now', 'Sizingathe kusintha pano'),
        isSuccess: false,
        errorMessage: '',
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ---------- BACK FIX ----------
  Future<bool> _handleWillPop() async {
    final nav = Navigator.of(context);
    if (nav.canPop()) return true;

    if (widget.onBackToHomeTab != null) {
      widget.onBackToHomeTab!();
      return false;
    }
    return true;
  }

  void _backPressed() {
    _maybeHaptic();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    if (widget.onBackToHomeTab != null) {
      widget.onBackToHomeTab!();
    }
  }

  // ---------- Edit profile (Firestore) ----------
  Future<void> _openEditProfile() async {
    _maybeHaptic();
    final nameController = TextEditingController(text: _name);
    final phoneController = TextEditingController(
        text: _sanitizePhone(_phone).isEmpty ? '' : _phone);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kBrandOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: kBrandOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t('Edit profile', 'Sinthani mbiri'),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: _t('Name', 'Dzina'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: const Color(0xFFF6F7FB),
                  hintText: _t('Your name', 'Dzina lanu'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: _t('Phone', 'Foni'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: const Color(0xFFF6F7FB),
                  hintText: _t('Phone number', 'Nambala yafoni'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: kBrandOrange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_t('Save', 'Sungani'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;

    final newName = nameController.text.trim();
    final newPhone = phoneController.text.trim();

    final u = _auth.currentUser;
    if (u == null) return;

    setState(() => _refreshing = true);
    try {
      final display = newName.isEmpty ? _name.trim() : newName;
      final phoneVal = newPhone.isEmpty ? _phone : newPhone;

      // Propagate name to Auth, prefs, merchant docs, items, and stories.
      if (display.isNotEmpty) {
        await DisplayNameSync.syncEverywhere(uid: u.uid, name: display);
        _name = display;
      } else {
        await _firestore.collection('users').doc(u.uid).set(
          {
            'phone': phoneVal,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      if (newPhone.isNotEmpty || phoneVal.isNotEmpty) {
        await _firestore.collection('users').doc(u.uid).set(
          {
            'phone': phoneVal,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        // Keep merchant shop phone in sync when present.
        await _firestore.collection('marketplace_merchants').doc(u.uid).set(
          {
            'phone': phoneVal,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        _phone = phoneVal;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fullName', _name);
      await prefs.setString('name', _name);
      await prefs.setString('business_name', _name);
      await prefs.setString('phone', _phone);

      if (mounted) setState(() {});
      ToastHelper.showCustomToast(context, _t('Profile updated', 'Mbiri yasinthidwa'), isSuccess: true, errorMessage: '');
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Could not update profile', 'Sidathe kusintha mbiri'),
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ---------- NAV: Address bottom sheet ----------
  Future<void> _openAddressBottomSheet() async {
    _maybeHaptic();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: const AddressPage(),
      ),
    );

    await _loadCachedProfile();
    await _loadAddressCount();
  }

  void _openChangePassword() {
    _maybeHaptic();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
    );
  }

  /// Opens the App lock (Face ID / fingerprint) settings bottom sheet.
  Future<void> _openAppLockSettings() async {
    _maybeHaptic();
    final auth = LocalAuthentication();
    bool canCheck = false;
    bool isSupported = false;
    List<BiometricType> available = [];
    try {
      isSupported = await auth.isDeviceSupported();
      canCheck = await auth.canCheckBiometrics;
      available = await auth.getAvailableBiometrics();
    } catch (_) {}

    if (!mounted) return;
    // Some Android devices report empty types while still supporting biometrics.
    final hasBiometric =
        isSupported && (canCheck || available.isNotEmpty);
    final isFace = available.contains(BiometricType.face);
    final isFinger = available.contains(BiometricType.fingerprint);
    final biometricLabel = isFace && isFinger
        ? _t('Face ID or fingerprint', 'Face ID kapena chala')
        : isFace
            ? _t('Face ID', 'Face ID')
            : isFinger
                ? _t('Fingerprint', 'Chala')
                : _t('Biometric', 'Chala');

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _t('App lock', 'Chitseko cha pulogalamu'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                if (!hasBiometric)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _t(
                        'Face ID or fingerprint is not available on this device. Set one up in your phone settings first.',
                        'Face ID kapena chala silipezeka pa chipangizochi. Kayikani mu settings za foni yanu.',
                      ),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  )
                else ...[
                  SwitchListTile(
                    value: _biometricLockEnabled,
                    onChanged: (v) async {
                      if (v) {
                        // Verify biometrics work before enabling app lock.
                        try {
                          final ok = await auth.authenticate(
                            localizedReason: _t(
                              'Confirm $biometricLabel to enable app lock',
                              'Tsimikizirani $biometricLabel kuti muyatsitse chitseko',
                            ),
                            options: const AuthenticationOptions(
                              stickyAuth: true,
                              useErrorDialogs: true,
                              biometricOnly: false,
                            ),
                          );
                          if (!ok) {
                            if (mounted) {
                              ToastHelper.showCustomToast(
                                context,
                                _t(
                                  'Could not verify biometrics. App lock was not enabled.',
                                  'Sitinathe kutsimikizira biometric. Chitseko sichinayatsidwe.',
                                ),
                                isSuccess: false,
                                errorMessage: '',
                              );
                            }
                            return;
                          }
                        } catch (_) {
                          if (mounted) {
                            ToastHelper.showCustomToast(
                              context,
                              _t(
                                'Biometrics failed. Check phone settings and try again.',
                                'Biometric yalephera. Onani settings za foni ndikuyesanso.',
                              ),
                              isSuccess: false,
                              errorMessage: '',
                            );
                          }
                          return;
                        }
                      }
                      setLocal(() => _biometricLockEnabled = v);
                      setState(() => _biometricLockEnabled = v);
                      await _saveBiometricLockPref(v);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (v && mounted) {
                        ToastHelper.showCustomToast(
                          context,
                          _t(
                            'App lock enabled. You will need $biometricLabel when returning to the app.',
                            'Chitseko chayatsidwa. Mudzafuna $biometricLabel mukabwerera ku pulogalamu.',
                          ),
                          isSuccess: true,
                          errorMessage: '',
                        );
                      }
                    },
                    title: Text(
                      _t('Unlock with $biometricLabel', 'Tsegulani ndi $biometricLabel'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _t(
                        'Require $biometricLabel when opening or returning to the app.',
                        'Funsani $biometricLabel mukatsegula kapena kubwerera ku pulogalamu.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Personalization ----------
  void _openPersonalization() {
    _maybeHaptic();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: kBrandOrange.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune, color: kBrandOrange, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('Personalization', 'Zokonda'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _t('Layout density and haptics', 'Kapangidwe ndi kuthamangira'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _compactMode,
                    onChanged: (v) async {
                      setLocal(() => _compactMode = v);
                      setState(() => _compactMode = v);
                      await _savePersonalizationPrefs();
                    },
                    title: Text(_t('Compact mode', 'Mtundu wofupi'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(_t('Smaller spacing in settings list', 'Mtunda wopingasa pamndandanda wa setingi')),
                  ),
                  SwitchListTile(
                    value: _haptics,
                    onChanged: (v) async {
                      setLocal(() => _haptics = v);
                      setState(() => _haptics = v);
                      await _savePersonalizationPrefs();
                    },
                    title: Text(_t('Haptics', 'Kuthamangira'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(_t('Vibration feedback when tapping', 'Kuthamangira mukafinya')),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openNotifications() {
    _maybeHaptic();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_active_rounded,
                          color: Colors.blue, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('Notifications', 'Zidziwitso'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _t('Control push, orders and messages',
                                'Sankhani zidziwitso zomwe mumafuna'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _notificationsEnabled,
                  onChanged: (v) async {
                    setLocal(() => _notificationsEnabled = v);
                    setState(() => _notificationsEnabled = v);
                    await _savePersonalizationPrefs();
                  },
                  title: Text(_t('Push notifications', 'Zidziwitso zapush'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_t('Receive alerts and updates', 'Landirani zidziwitso ndi zosintha')),
                ),
                SwitchListTile(
                  value: _notificationsOrders,
                  onChanged: _notificationsEnabled
                      ? (v) async {
                          setLocal(() => _notificationsOrders = v);
                          setState(() => _notificationsOrders = v);
                          await _savePersonalizationPrefs();
                        }
                      : null,
                  title: Text(_t('Order updates', 'Zosintha za maoda'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_t('Status of orders and deliveries', 'Mkhalidwe wa maoda ndi zopereka')),
                ),
                SwitchListTile(
                  value: _notificationsMessages,
                  onChanged: _notificationsEnabled
                      ? (v) async {
                          setLocal(() => _notificationsMessages = v);
                          setState(() => _notificationsMessages = v);
                          await _savePersonalizationPrefs();
                        }
                      : null,
                  title: Text(_t('Messages', 'Mauthenga'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_t('Chat and support messages', 'Mauthenga a nkhani ndi thandizo')),
                ),
                SwitchListTile(
                  value: _notificationsEngagement,
                  onChanged: _notificationsEnabled
                      ? (v) async {
                          setLocal(() => _notificationsEngagement = v);
                          setState(() => _notificationsEngagement = v);
                          await _savePersonalizationPrefs();
                        }
                      : null,
                  title: Text(
                    _t('Deals & new listings', 'Zogulitsa ndi zatsopano'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _t(
                      'Promotions, today’s arrivals, and marketplace (often when something new is posted)',
                      'Zotsatsa, zofika lero, ndi msika (nthawi zambiri zikakhala zatsopano)',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openLanguage() {
    _maybeHaptic();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.language_rounded,
                          color: Colors.green, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('Language', 'Chilankhulo'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _t('Choose your app language',
                                'Sankhani chilankhulo cha pulogalamu'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  value: 'en',
                  groupValue: _languageCode,
                  onChanged: (v) async {
                    if (v == null) return;
                    setLocal(() => _languageCode = v);
                    setState(() => _languageCode = v);
                    await _savePersonalizationPrefs();
                    if (ctx.mounted) Navigator.pop(ctx);
                    ToastHelper.showCustomToast(
                      context,
                      _t('Language set to English.', 'Chilankhulo chasankhidwa Chingerezi..'),
                      isSuccess: true,
                      errorMessage: '',
                    );
                  },
                  title: const Text('English',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                RadioListTile<String>(
                  value: 'ny',
                  groupValue: _languageCode,
                  onChanged: (v) async {
                    if (v == null) return;
                    setLocal(() => _languageCode = v);
                    setState(() => _languageCode = v);
                    await _savePersonalizationPrefs();
                    if (ctx.mounted) Navigator.pop(ctx);
                    ToastHelper.showCustomToast(
                      context,
                      _t('Language set to Chichewa. ', 'Chilankhulo chasankhidwa Chichewa.'),
                      isSuccess: true,
                      errorMessage: '',
                    );
                  },
                  title: const Text('Chichewa',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAboutUs() {
    _maybeHaptic();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AboutUsPage(appVersion: _appVersion, buildNumber: _buildNumber),
      ),
    );
  }

  // ---------- Clear cache ----------
  Future<void> _clearCache() async {
    _maybeHaptic();
    final ok = await _confirm(
      title: _t('Clear cache', 'Chotsani cache'),
      message:
          _t('This will clear temporary cached data and image cache. You will stay logged in.', 'Izi zidzachotsa data yosungidwa ndi cache ya chithunzi. Mudzakhala muli lowa muakaunti.'),
      confirmText: _t('Clear', 'Chotsani'),
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      bool isCacheKey(String k) {
        final lk = k.toLowerCase();
        return lk.startsWith('cache_') ||
            lk.startsWith('tmp_') ||
            lk.contains('cache') ||
            lk.contains('latest') ||
            lk.contains('marketplace') ||
            lk.contains('homefeed') ||
            lk.contains('image_');
      }

      for (final k in keys) {
        if (isCacheKey(k)) await prefs.remove(k);
      }

      ToastHelper.showCustomToast(context, _t('Cache cleared', 'Cache yachotsedwa'),
          isSuccess: true, errorMessage: '');
    } catch (_) {
      ToastHelper.showCustomToast(context, _t('Failed to clear cache', 'Sidathe kuchotsa cache'),
          isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ---------- Customer Service ----------
  void _openCustomerService() {
    _maybeHaptic();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kBrandOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: kBrandOrange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t('Customer service', 'Thandizo la makasitomala'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: _roundIcon(Icons.call_outlined),
              title: Text(
                _t('Call support', 'Imbani thandizo'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(_supportPhone),
              onTap: () async {
                Navigator.pop(context);
                await _launchTel(_supportPhone);
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Color(0xFF25D366),
                ),
              ),
              title: Text(
                _t('WhatsApp', 'WhatsApp'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(_supportWhatsApp),
              onTap: () async {
                Navigator.pop(context);
                await _launchWhatsApp(
                    _supportWhatsApp, 'Hello vero support, I need help.');
              },
            ),
            ListTile(
              leading: _roundIcon(Icons.email_outlined),
              title: Text(
                _t('Email', 'Imelo'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(_supportEmail),
              onTap: () async {
                Navigator.pop(context);
                await _launchEmail(
                  _supportEmail,
                  subject: _t('Support request', 'Kufuna thandizo'),
                  body: _t('Hi, I need help with...', 'Moni, ndikufuna thandizo pa...'),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _roundIcon(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: kBrandOrange),
    );
  }

  Future<void> _launchTel(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    await launchUrl(uri);
  }

  Future<void> _launchEmail(String email,
      {String? subject, String? body}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        if (subject != null) 'subject': subject,
        if (body != null) 'body': body,
      },
    );
    await launchUrl(uri);
  }

  /// Opens the default email app with a pre-filled bug report (subject + app version + placeholder for description).
  Future<void> _reportBug() async {
    _maybeHaptic();
    final subject = _t('Bug report - Vero360', 'Vuto la pulogalamu - Vero360');
    final body = _t(
      'Please describe the problem or what went wrong:\n\n\n---\nApp version: $_appVersion (build $_buildNumber)',
      'Chonde fotokozani vuto kapena chimene chinachitika:\n\n\n---\nMtundu wa pulogalamu: $_appVersion (build $_buildNumber)',
    );
    await _launchEmail(_supportEmail, subject: subject, body: body);
  }

  Future<void> _launchWhatsApp(String phone, String message) async {
    final p = phone.replaceAll(' ', '').replaceAll('+', '');
    final uri =
        Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(message)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Opens the store listing so the user can rate the app.
  Future<void> _rateApp() async {
    _maybeHaptic();
    try {
      final result = await AppUpdateChecker.check();
      final opened = await AppUpdateChecker.openStore(result.storeUrl);
      if (!opened && mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Could not open store', 'Sidathe kutsegula sitolo'),
          isSuccess: false,
          errorMessage: '',
        );
      }
    } catch (_) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Could not open store', 'Sidathe kutsegula sitolo'),
          isSuccess: false,
          errorMessage: '',
        );
      }
    }
  }

  /// Tap App version → compare with Play Store / App Store and offer update.
  Future<void> _checkForAppUpdates() async {
    _maybeHaptic();
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );

    AppUpdateCheckResult result;
    try {
      result = await AppUpdateChecker.check();
    } catch (_) {
      result = AppUpdateCheckResult(
        installedVersion: _appVersion,
        storeVersion: null,
        storeUrl: AppUpdateChecker.playStoreUrl(AppUpdateChecker.playStoreId),
        updateAvailable: false,
        errorMessage: 'check_failed',
      );
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!result.ok) {
      ToastHelper.showCustomToast(
        context,
        _t(
          'Could not check for updates. Try again later.',
          'Sidathe kuyang\'ana zatsopano. Yesaninso pambuyo pake.',
        ),
        isSuccess: false,
        errorMessage: result.errorMessage ?? '',
      );
      return;
    }

    if (!result.updateAvailable) {
      ToastHelper.showCustomToast(
        context,
        _t(
          'You are on the latest version (v${result.installedVersion}).',
          'Muli pa mtundu watsopano (v${result.installedVersion}).',
        ),
        isSuccess: true,
        errorMessage: '',
      );
      return;
    }

    final storeVer = result.storeVersion ?? '';
    final goUpdate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _t('Update available', 'Kusintha kulipo'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          _t(
            'A newer version is available on the store.\n\n'
            'Installed: v${result.installedVersion}\n'
            'Store: v$storeVer',
            'Mtundu watsopano ulipo pa sitolo.\n\n'
            'Womwe muli nawo: v${result.installedVersion}\n'
            'Pa sitolo: v$storeVer',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Later', 'Pambuyo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBrandOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('Update', 'Sinthani')),
          ),
        ],
      ),
    );

    if (goUpdate == true) {
      final opened = await AppUpdateChecker.openStore(result.storeUrl);
      if (!opened && mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Could not open store', 'Sidathe kutsegula sitolo'),
          isSuccess: false,
          errorMessage: '',
        );
      }
    }
  }

  /// Shares the app link and short message (share_plus).
  Future<void> _shareApp() async {
    _maybeHaptic();
    try {
      const storeUrl =
          'https://play.google.com/store/apps/details?id=com.vero265.app';
      final text = _t(
        'Try Vero360 – one app for VeroRide,marketplace, food, transport,accomodation and more. $storeUrl',
        'Yesani Vero360 – pulogalamu imodzi ya msika, chakudya, mayendedwe, ndi zina. $storeUrl',
      );
      await Share.share(text, subject: 'Vero360');
    } catch (_) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Could not share', 'Sidathe kugawana'),
          isSuccess: false,
          errorMessage: '',
        );
      }
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: confirmColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.warning_rounded,
                        color: confirmColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _t('Cancel', 'Lekani'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: confirmColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          confirmText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- LOGOUT ----------
  Future<void> _logout() async {
    _maybeHaptic();
    final ok = await _confirm(
      title: _t('Logout', 'Tulukani'),
      message: _t('Do you want to log out of this account?', 'Mukufuna kutuluka mu akauntiyi?'),
      confirmText: _t('Logout', 'Tulukani'),
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);
    final rootNav = Navigator.of(context, rootNavigator: true);
    try {
      // AuthService clears tokens + prefs; don't duplicate slow sequential removes here.
      await AuthService().logout(context: context);
    } finally {
      if (mounted) setState(() => _refreshing = false);

      // Always reset the stack on the root navigator — even if Settings unmounted
      // mid-logout (otherwise Profile stays visible as “Guest User”).
      openVeroMainShell(rootNav.context, email: '', tabIndex: 0);
    }
  }

  /// Deletes the Firebase Auth user. If Firebase requires recent login, prompts for password and re-authenticates, then deletes.
  /// Returns true if the Firebase user was deleted (or was already gone), false if user cancelled or reauth failed.
  Future<bool> _deleteFirebaseUserWithReauth(User u) async {
    try {
      await u.delete();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            _t('Delete failed', 'Kuchotsa kudagonjetsedwa'),
            isSuccess: false,
            errorMessage: e.message ?? 'Could not delete account.',
          );
        }
        return false;
      }

      final verified = await _authenticateDeleteWithProvider(u);
      if (!verified) return false;
      try {
        await u.delete();
        return true;
      } on FirebaseAuthException catch (deleteAfterReauth) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            deleteAfterReauth.message ?? _t('Delete failed', 'Kuchotsa kudagonjetsedwa'),
            isSuccess: false,
            errorMessage: '',
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Delete failed', 'Kuchotsa kudagonjetsedwa'),
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
      return false;
    }
  }

  Future<bool> _authenticateDeleteWithPassword(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final email =
        user.email?.trim() ?? prefs.getString('email')?.trim() ?? '';
    if (email.isEmpty) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t(
            'Password sign-in is not available for this account. Use biometric instead.',
            'Kulowa ndi password kulibe pa akaunti iyi. Gwiritsani biometric.',
          ),
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    }

    final password = await _showPasswordDialogForDelete();
    if (password == null || password.isEmpty) return false;

    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      return true;
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? _t('Wrong password', 'Password yolakwika')
            : (e.message ??
                _t(
                  'Could not verify password',
                  'Sitinathe kutsimikizira password',
                ));
        ToastHelper.showCustomToast(
          context,
          msg,
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    }
  }

  String _primaryAuthProvider(User user) {
    final ids = user.providerData
        .map((p) => p.providerId)
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (ids.contains('google.com')) return 'google.com';
    if (ids.contains('apple.com')) return 'apple.com';
    if (ids.contains('password')) return 'password';
    return ids.isNotEmpty ? ids.first : 'password';
  }

  Future<bool> _authenticateDeleteWithProvider(User user) async {
    final authProvider = _primaryAuthProvider(user);
    try {
      if (authProvider == 'google.com') {
        final google = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        await user.reauthenticateWithProvider(google);
        return true;
      }

      if (authProvider == 'apple.com') {
        final appleCred = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final oauthCred = OAuthProvider('apple.com').credential(
          idToken: appleCred.identityToken,
          accessToken: appleCred.authorizationCode,
        );
        await user.reauthenticateWithCredential(oauthCred);
        return true;
      }

      return _authenticateDeleteWithPassword(user);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          e.message ??
              _t(
                'Could not verify your account. Please try again.',
                'Sitinathe kutsimikizira akaunti yanu. Yesaninso.',
              ),
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    } catch (_) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t(
            'Could not verify your account. Please try again.',
            'Sitinathe kutsimikizira akaunti yanu. Yesaninso.',
          ),
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    }
  }

  Future<bool> _authenticateDeleteWithBiometric() async {
    final auth = LocalAuthentication();
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();
      if (!isSupported && !canCheck) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            _t(
              'Biometric authentication is not available on this device.',
              'Biometric ilibe pa chipangizochi.',
            ),
            isSuccess: false,
            errorMessage: '',
          );
        }
        return false;
      }

      final ok = await auth.authenticate(
        localizedReason: _t(
          'Verify your identity to delete your account',
          'Tsimikizirani kuti ndinu inu kuti muchotse akaunti',
        ),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok && mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Biometric verification failed', 'Kutsimikizira biometric kwalephera'),
          isSuccess: false,
          errorMessage: '',
        );
      }
      return ok;
    } catch (_) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          _t('Biometric verification failed', 'Kutsimikizira biometric kwalephera'),
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    }
  }

  Future<bool> _promptDeleteAuthMethod(User user) async {
    final provider = _primaryAuthProvider(user);
    final providerLabel = provider == 'google.com'
        ? _t('Google sign-in', 'Google sign-in')
        : provider == 'apple.com'
            ? _t('Apple sign-in', 'Apple sign-in')
            : _t('App password', 'Password ya app');

    final method = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _t('Verify before delete', 'Tsimikizirani musanachotse'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Use your sign-in method or biometric to continue.',
                'Gwiritsani njira yolowera kapena biometric kuti mupitirire.',
              ),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _roundIcon(Icons.lock_outline),
              title: Text(
                _t('Use $providerLabel', 'Gwiritsani $providerLabel'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                provider == 'password'
                    ? _t('Enter your account password', 'Lembani password ya akaunti')
                    : _t('Verify with your sign-in provider', 'Tsimikizirani ndi njira yolowera'),
              ),
              onTap: () => Navigator.pop(ctx, 'provider'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _roundIcon(Icons.fingerprint),
              title: Text(
                _t('Use biometric', 'Gwiritsani biometric'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _t('Face ID or fingerprint', 'Face ID kapena chala'),
              ),
              onTap: () => Navigator.pop(ctx, 'biometric'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    if (method == 'provider') return _authenticateDeleteWithProvider(user);
    if (method == 'biometric') return _authenticateDeleteWithBiometric();
    return false;
  }

  /// Shows a dialog asking for the user's password to confirm account deletion. Returns the password or null if cancelled.
  Future<String?> _showPasswordDialogForDelete() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _t('Confirm your password', 'Lembetsani password yanu'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _t(
                    'Enter your password to permanently delete your account.',
                    'Ingizani password yanu kuti muchotse akaunti yanu mwamuyaya.',
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _t('Password', 'Password'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (_) =>
                      Navigator.of(ctx).pop(controller.text.trim()),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _t('Cancel', 'Lekani'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(controller.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          _t('Delete account', 'Chotsani akaunti'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
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
    );
    // Defer dispose until after the dialog is fully closed to avoid "used after being disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  // ---------- DELETE ACCOUNT ----------
  Future<void> _deleteAccount() async {
    _maybeHaptic();
    final ok = await _confirm(
      title: _t('Delete account', 'Chotsani akaunti'),
      message: _t(
        'This permanently deletes your account and all related data:\n'
        '• Profile & login\n'
        '• Marketplace items & shop\n'
        '• Food menus, restaurants & orders\n'
        '• Accommodation listings, bookings & calendar blocks\n'
        '• Cart, promos, stories & wallets\n'
        '• Merchant / customer records\n\n'
        'This cannot be undone.',
        'Izi zidzachotsa akaunti yanu ndi zinthu zonse:\n'
        '• Profile ndi login\n'
        '• Zogulitsa pa Marketplace ndi shop\n'
        '• Menyu ya chakudya, ma restaurant ndi ma order\n'
        '• Malo ogona, ma booking ndi masiku obisika\n'
        '• Cart, promos, stories ndi wallets\n'
        '• Zolemba za merchant / customer\n\n'
        'Sizingabwererenso.',
      ),
      confirmText: _t('Delete', 'Chotsani'),
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        ToastHelper.showCustomToast(
          context,
          _t('Please sign in again', 'Chonde lowani kachiwiri'),
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }

      final verified = await _promptDeleteAuthMethod(currentUser);
      if (!verified) return;

      // Remote wipe while still signed in (capped — do not hang Settings).
      // Purge clears local chats/rides/hive first, then deletes API + Firestore.
      await AccountDataPurge.purgeCurrentUser(
        budget: const Duration(seconds: 10),
      );

      final u = _auth.currentUser;
      if (u != null) {
        final deleted = await _deleteFirebaseUserWithReauth(u);
        if (!deleted) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _refreshing = false);
            });
          }
          return;
        }
      }

      await AuthService().logout();

      ToastHelper.showCustomToast(context, _t('Account deleted', 'Akaunti yachotsedwa'),
          isSuccess: true, errorMessage: '');

      openVeroMainShell(
        Navigator.of(context, rootNavigator: true).context,
        email: '',
        tabIndex: 0,
      );
    } catch (_) {
      ToastHelper.showCustomToast(context, _t('Delete failed', 'Kuchotsa kwakanika'),
          isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _refreshing = false);
        });
      }
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: AppBar(
          backgroundColor: kBrandOrange,
          foregroundColor: Colors.white,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_rounded, size: 22, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                _t('Settings', 'Zokonda'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _backPressed,
          ),
          actions: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : _onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            children: [
              _profileCard(),
              const SizedBox(height: 14),
              _sectionTitle(_t('Account', 'Akaunti')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.person_outline,
                  title: _t('Edit profile', 'Sinthani mbiri'),
                  subtitle: _t('Name, phone', 'Dzina, foni'),
                  onTap: _openEditProfile,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.location_on_outlined,
                  title: _t('My address', 'Adiresi yanga'),
                  subtitle: _addressCountSubtitle,
                  onTap: _openAddressBottomSheet,
                ),
                if (!_isMerchant)
                  _SettingsTile(
                    compact: _compactMode,
                    icon: Icons.local_taxi_rounded,
                    title: _t('Driver mode', 'Driver mode'),
                    subtitle: _isDriver
                        ? _t('On – using app as a driver', 'Yayatsidwa – ngati driver')
                        : _t('Off – switch on to drive with VeroRide', 'Yazimitsidwa – yatsani kuti muyendetse'),
                    onTap: () => _onDriverModeChanged(!_isDriver),
                    trailing: _switchingDriverMode
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Switch.adaptive(
                            value: _isDriver,
                            activeThumbColor: kBrandOrange,
                            onChanged: _onDriverModeChanged,
                          ),
                  ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle(_t('Security', 'Chitetezo')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.fingerprint,
                  title: _t('App lock (Face ID / fingerprint)', 'Chitseko (Face ID / chala)'),
                  subtitle: _biometricLockEnabled
                      ? _t('On – unlock when returning to app', 'Yayatsidwa – tsegulani mukabwerera')
                      : _t('Off – require Face ID or fingerprint', 'Yazimitsidwa – Face ID kapena chala'),
                  onTap: _openAppLockSettings,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.lock_outline,
                  title: _t('Change password', 'Sinthani chipangizo'),
                  subtitle: _t('Update your password', 'Sinthani chipangizo chanu'),
                  onTap: _openChangePassword,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle(_t('Preferences', 'Zokonda')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.language,
                  title: _t('Language', 'Chilankhulo'),
                  subtitle: _languageSubtitle,
                  onTap: _openLanguage,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.tune,
                  title: _t('Personalization', 'Zokonda'),
                  subtitle: _t('Compact mode, haptics', 'Mtundu wofupi, haptics'),
                  onTap: _openPersonalization,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.notifications_outlined,
                  title: _t('Notifications', 'Zidziwitso'),
                  subtitle: _t('Push, orders, messages', 'Zidziwitso, maoda, mauthenga'),
                  onTap: _openNotifications,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.block_outlined,
                  title: _t('Blocked merchants', 'Amalonda oblocked'),
                  subtitle: _t(
                    'Manage hidden shops and sellers',
                    'Sinthani malonda oblocked',
                  ),
                  onTap: () {
                    _maybeHaptic();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BlockedMerchantsPage(),
                      ),
                    );
                  },
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.cleaning_services_outlined,
                  title: _t('Clear cache', 'Chotsani cache'),
                  subtitle: _t('Clear temporary cached data', 'Chotsani data yosungidwa'),
                  onTap: _clearCache,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle(_t('Support', 'Thandizo')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.support_agent_outlined,
                  title: _t('Customer service', 'Thandizo la makasitomala'),
                  subtitle: _t('Call, WhatsApp, or email', 'Imbani, WhatsApp, kapena imelo'),
                  onTap: _openCustomerService,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.bug_report_outlined,
                  title: _t('Report a bug', 'Lemberani vuto'),
                  subtitle: _t('Send us a problem or feedback', 'Titumizireni vuto kapena malingaliro'),
                  onTap: _reportBug,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle(_t('App', 'Pulogalamu')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.star_outline,
                  title: _t('Rate the app', 'Votani pulogalamu'),
                  subtitle: _t('Leave a review on the store', 'Siylani ndemanga pa sitolo'),
                  onTap: _rateApp,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.share_outlined,
                  title: _t('Share the app', 'Gawanani pulogalamu'),
                  subtitle: _t('Invite friends with a link', 'Itanani anzanu ndi ulalo'),
                  onTap: _shareApp,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle(_t('About', 'Za ife')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.info_outline,
                  title: _t('About us', 'Za ife'),
                  subtitle: _t('App details and information', 'Zambiri za pulogalamu'),
                  onTap: _openAboutUs,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.verified_user_outlined,
                  title: _t('Privacy policy & Terms', 'Polisi ya uchi ndi malamulo'),
                  subtitle: _t('Read our policy', 'Werengani polisi yathu'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PolicyPage()),
                  ),
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.apps_outlined,
                  title: _t('App version', 'Mtundu wa pulogalamu'),
                  subtitle: _t(
                    'v$_appVersion ($_buildNumber) · Tap to check for updates',
                    'v$_appVersion ($_buildNumber) · Dinani kuyang\'ana zatsopano',
                  ),
                  onTap: _checkForAppUpdates,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle(_t('Danger zone', 'Gawo la ngozi')),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.logout,
                  title: _t('Logout', 'Tulukani'),
                  subtitle: _t('Sign out of this device', 'Tulukani pa chipangizochi'),
                  onTap: _logout,
                  iconColor: Colors.red,
                  titleColor: Colors.red,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.delete_forever,
                  title: _t('Delete my account', 'Chotsani akaunti yanga'),
                  subtitle: _t('Permanently delete your account', 'Chotsani akaunti yanu mwamuyaya'),
                  onTap: _deleteAccount,
                  iconColor: Colors.red,
                  titleColor: Colors.red,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openEditProfile,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kBrandOrange, kBrandOrange.withValues(alpha: 0.95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 58,
                    height: 58,
                    color: Colors.white.withValues(alpha: 0.15),
                    child: _photoUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 30)
                        : Image.network(
                            _photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.person,
                                color: Colors.white, size: 30),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(Icons.phone_outlined, _displayPhone),
                          _chip(Icons.location_on_outlined,
                              _defaultAddressDisplay.isEmpty
                                  ? _address
                                  : _defaultAddressDisplay),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const Divider(height: 0),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final bool compact;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsTile({
    required this.compact,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: compact,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? kBrandOrange).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor ?? kBrandOrange),
      ),
      title: Text(title,
          style: TextStyle(fontWeight: FontWeight.w900, color: titleColor)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? const Icon(Icons.chevron_right),
    );
  }
}

class AboutUsPage extends StatelessWidget {
  final String appVersion;
  final String buildNumber;

  const AboutUsPage({
    super.key,
    required this.appVersion,
    required this.buildNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.info_outline, size: 22, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'About Us',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App name
              const Text(
                'Vero360',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),

              const Text(
                'One app. Everything.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 14),

              // Description
              const Text(
                'Vero360 is an all-in-one digital platform designed to connect customers, merchants, and service providers in one secure and convenient ecosystem.',
                style: TextStyle(height: 1.4),
              ),

              const SizedBox(height: 14),

              const Text(
                'Through Vero360, users can access marketplace products, food services, transport, courier services, accommodation bookings, and secure communication — all from a single app.',
                style: TextStyle(height: 1.4),
              ),

              const SizedBox(height: 20),

              // Mission
              const Text(
                'Our Mission',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'To simplify everyday life by providing a reliable, secure, and unified digital platform for services and commerce.',
                style: TextStyle(height: 1.4),
              ),

              const SizedBox(height: 16),

              // Vision
              const Text(
                'Our Vision',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'To become Malawi’s leading super app for digital services, empowering businesses and improving customer experiences.',
                style: TextStyle(height: 1.4),
              ),

              const SizedBox(height: 20),
              const Text(
                'Our Values',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Innovation · Reliability · Security ·Accessibility · Customer-Centricity',
                style: TextStyle(height: 1.4),
              ),

              const SizedBox(height: 20),

              // App version
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Version v$appVersion ($buildNumber)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

             
              
              const SizedBox(height: 10),

              // Footer
              const Center(
                child: Text(
                  '© 2026 Vero360. All rights reserved.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key});

  /// Bundled PDFs under `assets/documents/` (see pubspec.yaml).
  static const String _platformAgreementAsset =
      'assets/documents/Vero360_Platform_Agreement_Policy.pdf';
  static const String _privacyPolicyAsset =
      'assets/documents/Vero360_Privacy_Policy.pdf';
  static const String _merchantTermsAsset =
      'assets/documents/Vero360_Merchant_Terms_Conditions.pdf';

  static const Color _cream = Color(0xFFFFFBF6);
  static const Color _ink = Color(0xFF101010);
  static const Color _muted = Color(0xFF6B6B6B);
  static const Color _escrowRed = Color(0xFFC62828);

  void _openAssetPdf(
    BuildContext context, {
    required String assetPath,
    required String title,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AssetPdfViewerPage(
          assetPath: assetPath,
          title: title,
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8E4DE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _docTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String assetPath,
  }) {
    return Material(
      color: const Color(0xFFFFF8F0),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openAssetPdf(
          context,
          assetPath: assetPath,
          title: title,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kBrandOrange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kBrandOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _muted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kBrandOrange,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'Read more',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Terms & Privacy',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Before you continue',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please review how Vero360 protects payments and your data. '
                  'Full legal documents are available below.',
                  style: TextStyle(height: 1.4, color: _muted, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Escrow highlight
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _escrowRed.withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _escrowRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: _escrowRed,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment protection',
                        style: TextStyle(
                          color: _escrowRed,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'The system holds money for 7 days until both parties are satisfied with the business.',
                        style: TextStyle(
                          color: _escrowRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Terms & Conditions',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'By using Vero360, you agree to the following:',
                  style: TextStyle(height: 1.35, color: _muted),
                ),
                const SizedBox(height: 12),
                const Text(
                  '• Use the app in a lawful and responsible manner.\n'
                  '• Do not upload or share illegal, harmful, or misleading content.\n'
                  '• Respect other users, merchants, and service providers.',
                  style: TextStyle(height: 1.45, color: _ink, fontSize: 14),
                ),
                const SizedBox(height: 10),
                const Text(
                  '• The system holds money for 7 days until both parties are satisfied with the business.',
                  style: TextStyle(
                    height: 1.45,
                    color: _escrowRed,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '• Merchants are responsible for the accuracy of their products and services.\n'
                  '• Vero360 acts as a technology platform and is not the direct provider of services.',
                  style: TextStyle(height: 1.45, color: _ink, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'We may update these terms as the platform evolves. Continued use means you accept the updates.',
                  style: TextStyle(height: 1.4, color: _muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vero360 collects only what is needed to run and improve the app: account details, '
                  'login data, orders/bookings, chat for buyer and seller communication, and usage for security.',
                  style: TextStyle(height: 1.4, color: _muted, fontSize: 14),
                ),
                const SizedBox(height: 10),
                const Text(
                  'We do not sell your personal data. Payments are handled by trusted providers  '
                  'Vero360 does not store your card credentials.',
                  style: TextStyle(height: 1.4, color: _ink, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Legal documents',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap Read more to open the full PDF.',
                  style: TextStyle(height: 1.35, color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                _docTile(
                  context,
                  icon: Icons.description_outlined,
                  title: 'Platform Agreement & Policy',
                  subtitle: 'Vero360 platform agreement (PDF)',
                  assetPath: _platformAgreementAsset,
                ),
                const SizedBox(height: 10),
                _docTile(
                  context,
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'Vero360 privacy policy (PDF)',
                  assetPath: _privacyPolicyAsset,
                ),
                const SizedBox(height: 10),
                _docTile(
                  context,
                  icon: Icons.storefront_outlined,
                  title: 'Merchant Terms & Conditions',
                  subtitle: 'Merchant terms (PDF)',
                  assetPath: _merchantTermsAsset,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Last updated: July 2026',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetPdfViewerPage extends StatefulWidget {
  const _AssetPdfViewerPage({
    required this.assetPath,
    required this.title,
  });

  final String assetPath;
  final String title;

  @override
  State<_AssetPdfViewerPage> createState() => _AssetPdfViewerPageState();
}

class _AssetPdfViewerPageState extends State<_AssetPdfViewerPage> {
  PdfControllerPinch? _pdfController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _openPdf();
  }

  Future<void> _openPdf() async {
    try {
      final controller = PdfControllerPinch(
        document: PdfDocument.openAsset(widget.assetPath),
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _pdfController = controller;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: kBrandOrange,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not open document',
                      style: TextStyle(fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        _pdfController?.dispose();
                        setState(() {
                          _loading = true;
                          _error = null;
                          _pdfController = null;
                        });
                        _openPdf();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kBrandOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                if (_pdfController != null)
                  PdfViewPinch(controller: _pdfController!)
                else
                  const SizedBox.expand(),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
