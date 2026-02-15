import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_service.dart';

import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/config/api_config.dart';

import 'package:vero360_app/utils/toasthelper.dart';

// REQUIRED PAGES
import 'package:vero360_app/GeneralPages/address.dart'; // AddressPage
import 'package:vero360_app/GeneralPages/changepassword.dart'; // ChangePasswordPage
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/GernalServices/address_service.dart';

const Color kBrandOrange = Color(0xFFFF8A00);
const Color kBrandNavy = Color(0xFF16284C);

/// Filters out Firebase identifiers (e.g. +firebase_xxx) so we show real phone numbers only.
String _sanitizePhone(String s) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return '';
  if (t.toLowerCase().startsWith('+firebase_') ||
      t.toLowerCase().contains('firebase_')) return '';
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

  // customer service
  static const String _supportPhone = '+265999955270';
  static const String _supportWhatsApp = '+265992695612';
  static const String _supportEmail = 'support@vero360.app';

  /// Display phone; filters out Firebase identifiers so we never show +firebase_xxx.
  String get _displayPhone {
    final s = _sanitizePhone(_phone);
    return s.isEmpty ? 'No Phone' : _phone;
  }

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
      await _loadProfileFromFirestore();
    } catch (_) {}

    if (mounted) setState(() => _loading = false);

    // load app info + address count in background (do not block page open)
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
    if (_addressCount == 0) return 'No addresses';
    if (_addressCount == 1) return '1 address';
    return '$_addressCount addresses';
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
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _buildNumber = info.buildNumber;
    } catch (_) {}
  }

  Future<void> _loadPersonalizationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _compactMode = prefs.getBool('pref_compact_mode') ?? false;
      _haptics = prefs.getBool('pref_haptics') ?? true;
      _languageCode = prefs.getString('pref_language_code') ?? 'en';
    });
  }

  Future<void> _savePersonalizationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_compact_mode', _compactMode);
    await prefs.setBool('pref_haptics', _haptics);
    await prefs.setString('pref_language_code', _languageCode);
  }

  void _maybeHaptic() {
    if (_haptics) HapticFeedback.selectionClick();
  }

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final phone = _sanitizePhone(prefs.getString('phone') ?? '');
    setState(() {
      _name = prefs.getString('fullName') ?? prefs.getString('name') ?? _name;
      _email = prefs.getString('email') ?? _email;
      if (phone.isNotEmpty) _phone = phone;
      _address = prefs.getString('address') ?? _address;
      _photoUrl = prefs.getString('profilepicture') ?? '';
    });
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
        'Refreshed',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (_) {
      ToastHelper.showCustomToast(
        context,
        'Could not refresh right now',
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
    final addressController = TextEditingController(text: _address);

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
              const Text(
                'Edit profile',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  hintText: 'Your name',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                  hintText: 'Phone number',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                  hintText: 'Your address',
                ),
                maxLines: 2,
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
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;

    final newName = nameController.text.trim();
    final newPhone = phoneController.text.trim();
    final newAddress = addressController.text.trim();

    final u = _auth.currentUser;
    if (u == null) return;

    setState(() => _refreshing = true);
    try {
      await _firestore.collection('users').doc(u.uid).set(
        {
          'name': newName.isEmpty ? _name : newName,
          'phone': newPhone.isEmpty ? _phone : newPhone,
          'address': newAddress.isEmpty ? _address : newAddress,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (newName.isNotEmpty) {
        await u.updateDisplayName(newName);
        _name = newName;
      }
      if (newPhone.isNotEmpty) _phone = newPhone;
      if (newAddress.isNotEmpty) _address = newAddress;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fullName', _name);
      await prefs.setString('name', _name);
      await prefs.setString('phone', _phone);
      await prefs.setString('address', _address);

      if (mounted) setState(() {});
      ToastHelper.showCustomToast(context, 'Profile updated', isSuccess: true, errorMessage: '');
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Could not update profile',
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
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Personalization',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _compactMode,
                  onChanged: (v) async {
                    setLocal(() => _compactMode = v);
                    setState(() => _compactMode = v);
                    await _savePersonalizationPrefs();
                  },
                  title: const Text('Compact mode',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Smaller spacing in settings list'),
                ),
                SwitchListTile(
                  value: _haptics,
                  onChanged: (v) async {
                    setLocal(() => _haptics = v);
                    setState(() => _haptics = v);
                    await _savePersonalizationPrefs();
                  },
                  title: const Text('Haptics',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Vibration feedback when tapping'),
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
                const Text(
                  'Language',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
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
                      'Language set to English. Restart app for full effect.',
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
                      'Language set to Chichewa. Restart app for full effect.',
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
      title: 'Clear cache',
      message:
          'This will clear temporary cached data and image cache. You will stay logged in.',
      confirmText: 'Clear',
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

      ToastHelper.showCustomToast(context, 'Cache cleared',
          isSuccess: true, errorMessage: '');
    } catch (_) {
      ToastHelper.showCustomToast(context, 'Failed to clear cache',
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
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Customer service',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: _roundIcon(Icons.call_outlined),
              title: const Text('Call support',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text(_supportPhone),
              onTap: () async {
                Navigator.pop(context);
                await _launchTel(_supportPhone);
              },
            ),
            ListTile(
              leading: _roundIcon(Icons.chat_bubble_outline),
              title: const Text('WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text(_supportWhatsApp),
              onTap: () async {
                Navigator.pop(context);
                await _launchWhatsApp(
                    _supportWhatsApp, 'Hello vero support, I need help.');
              },
            ),
            ListTile(
              leading: _roundIcon(Icons.email_outlined),
              title: const Text('Email',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text(_supportEmail),
              onTap: () async {
                Navigator.pop(context);
                await _launchEmail(_supportEmail,
                    subject: 'Support request',
                    body: 'Hi, I need help with...');
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
        color: kBrandOrange.withOpacity(0.12),
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

  Future<void> _launchWhatsApp(String phone, String message) async {
    final p = phone.replaceAll(' ', '').replaceAll('+', '');
    final uri =
        Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(message)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText,
                style: TextStyle(
                    color: confirmColor, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ---------- LOGOUT ----------
  Future<void> _logout() async {
    _maybeHaptic();
    final ok = await _confirm(
      title: 'Logout',
      message: 'Do you want to log out of this account?',
      confirmText: 'Logout',
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);
    try {
      await AuthService().logout(context: context);

      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        'fullName',
        'name',
        'email',
        'phone',
        'address',
        'profilepicture',
        'uid',
        'role',
        'user_role',
        'merchant_service',
        'business_name',
        'business_address',
      ]) {
        await prefs.remove(k);
      }
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
        (_) => false,
      );
    }
  }

  // ---------- DELETE ACCOUNT ----------
  Future<void> _deleteAccount() async {
    _maybeHaptic();
    final ok = await _confirm(
      title: 'Delete account',
      message:
          'This will permanently delete your account.\n\nThis cannot be undone.',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );
    if (ok != true) return;

    setState(() => _refreshing = true);

    try {
      // 1) Delete on Nest backend (best effort)
      final token = await _getAuthToken();
      if (token.isNotEmpty) {
        try {
          final base = await ApiConfig.readBase();
          await http.delete(
            Uri.parse('$base/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json'
            },
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      }

      // 2) Delete Firestore profile + service collection (best effort)
      final u = _auth.currentUser;
      if (u != null) {
        try {
          final doc = await _firestore.collection('users').doc(u.uid).get();
          final data = doc.data() ?? {};
          final serviceKey = (data['merchantService'] ?? '').toString();

          await _firestore.collection('users').doc(u.uid).delete();

          if (serviceKey.trim().isNotEmpty) {
            await _firestore
                .collection('${serviceKey}_merchants')
                .doc(u.uid)
                .delete();
          }
        } catch (_) {}

        // 3) Delete Firebase auth user
        try {
          await u.delete();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
        if (mounted) {
              ToastHelper.showCustomToast(
                context,
                'Please login again',
                isSuccess: false,
                errorMessage: 'Login again then try deleting your account.',
              );
            }
            await AuthService().logout(context: context);
            return;
          }
          rethrow;
        }
      }

      // 4) Clear local prefs and logout
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        'fullName', 'name', 'email', 'phone', 'address', 'profilepicture',
        'uid', 'role', 'user_role', 'merchant_service', 'business_name',
        'business_address', 'jwt_token', 'token', 'authToken', 'jwt',
      ]) {
        await prefs.remove(k);
      }
      await AuthService().logout(context: context);

      ToastHelper.showCustomToast(context, 'Account deleted',
          isSuccess: true, errorMessage: '');
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
        (_) => false,
      );
    } catch (_) {
      ToastHelper.showCustomToast(context, 'Delete failed',
          isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _refreshing = false);
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
          backgroundColor: kBrandNavy,
          foregroundColor: Colors.white,
          title: const Text('Settings'),
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
              _sectionTitle('Account'),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  subtitle: 'Name, phone, address',
                  onTap: _openEditProfile,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.location_on_outlined,
                  title: 'My address',
                  subtitle: _addressCountSubtitle,
                  onTap: _openAddressBottomSheet,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle('Security'),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.lock_outline,
                  title: 'Change password',
                  subtitle: 'Update your password',
                  onTap: _openChangePassword,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle('Preferences'),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.language,
                  title: 'Language',
                  subtitle: _languageSubtitle,
                  onTap: _openLanguage,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.tune,
                  title: 'Personalization',
                  subtitle: 'Compact mode, haptics',
                  onTap: _openPersonalization,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.cleaning_services_outlined,
                  title: 'Clear cache',
                  subtitle: 'Clear temporary cached data',
                  onTap: _clearCache,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle('Support'),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.support_agent_outlined,
                  title: 'Customer service',
                  subtitle: 'Call, WhatsApp, or email',
                  onTap: _openCustomerService,
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle('About'),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.info_outline,
                  title: 'About us',
                  subtitle: 'App details and information',
                  onTap: _openAboutUs,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.verified_user_outlined,
                  title: 'Privacy policy & Terms',
                  subtitle: 'Read our policy',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PolicyPage()),
                  ),
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.apps_outlined,
                  title: 'App version',
                  subtitle: 'v$_appVersion ($_buildNumber)',
                  onTap: () => _maybeHaptic(),
                  trailing: const SizedBox.shrink(),
                ),
              ]),
              const SizedBox(height: 14),
              _sectionTitle('Danger zone'),
              _card([
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of this device',
                  onTap: _logout,
                  iconColor: Colors.red,
                  titleColor: Colors.red,
                ),
                _SettingsTile(
                  compact: _compactMode,
                  icon: Icons.delete_forever,
                  title: 'Delete my account',
                  subtitle: 'Permanently delete your account',
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
              colors: [kBrandNavy, kBrandOrange.withOpacity(0.95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
                    color: Colors.white.withOpacity(0.15),
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
                          color: Colors.white.withOpacity(0.9),
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
                  color: Colors.white.withOpacity(0.9),
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
        color: Colors.white.withOpacity(0.14),
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
          color: (iconColor ?? kBrandOrange).withOpacity(0.12),
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
        backgroundColor: kBrandNavy,
        foregroundColor: Colors.white,
        title: const Text('About Us'),
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



// make sure this exists
// const kBrandNavy = Color(0xFF0B1C2D);

class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: kBrandNavy,
        foregroundColor: Colors.white,
        title: const Text('Privacy & Terms'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ================= PRIVACY POLICY =================
                Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your privacy matters to us. Vero360 collects only the information necessary to operate and improve the app.',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 10),
                Text(
                  '• Basic account details such as name, email, phone number, and address.\n'
                  '• Google and apple Login and authentication data .\n'
                  '• Order, booking, and service history for app functionality.\n'
                  '• Chat messages required for communication between users and merchants.\n'
                  '• App usage data for performance and security improvements.\n',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 8),
                Text(
                  'We do not sell or rent your personal data. Payments are handled securely by trusted third-party providers, and Vero360 does not store your payment credentials.',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 8),
                Text(
                  'You may clear cached data, update your information, or request account deletion at any time through the Settings section.',
                  style: TextStyle(height: 1.35),
                ),

                SizedBox(height: 18),

                // ================= TERMS & CONDITIONS =================
                Text(
                  'Terms & Conditions',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'By using Vero360, you agree to the following terms:',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 10),
                Text(
                  '• Use the app in a lawful and responsible manner.\n'
                  '• Do not upload or share illegal, harmful, or misleading content.\n'
                  '• Respect other users, merchants, and service providers.\n'
                  '• The system holds Money untill both parties are satisified with the business.\n'
                  '• Merchants are responsible for the accuracy of their products and services.\n'
                  '• Vero360 acts as a technology platform and is not the direct provider of services.\n',
                  style: TextStyle(height: 1.35),
                ),
                SizedBox(height: 8),
                Text(
                  'We reserve the right to update these terms and policies as the platform evolves. Continued use of the app indicates acceptance of any updates.',
                  style: TextStyle(height: 1.35),
                ),

                SizedBox(height: 18),

                // ================= FOOTER =================
                Text(
                  'Last updated: February 2026',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
