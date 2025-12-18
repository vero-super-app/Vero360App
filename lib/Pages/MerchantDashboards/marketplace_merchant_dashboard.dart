// lib/Pages/MerchantDashboards/marketplace_merchant_dashboard.dart
//
// ✅ Adds:
// 1) Pull-to-refresh (Dashboard tab)
// 2) Search + filter chips (My Items tab)
// 3) Edit item (modern bottom-sheet)
// 4) Skeleton loaders (no spinners)
// 5) Business name FIX: resolves from Auth → Firestore → API → Prefs (and can backfill Auth displayName)
// 6) Business overview cards are compact (not big)
// 7) ✅ Wallet is LOCKED by default: balance hidden + PIN prompt before opening wallet
// 8) ✅ Settings “back” works (uses push instead of pushAndRemoveUntil)
//
// ✅ Add to pubspec.yaml if missing:
// firebase_storage: ^11.6.0
// crypto: ^3.0.3

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:crypto/crypto.dart' show sha256;

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:http/http.dart' as http;
import 'package:vero360_app/services/api_config.dart';

import 'package:vero360_app/services/merchant_service_helper.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/settings/Settings.dart';
import 'package:vero360_app/toasthelper.dart';
// Add login screen import (using your correct path)
import 'package:vero360_app/screens/login_screen.dart';

import 'package:vero360_app/Pages/homepage.dart';
import 'package:vero360_app/Pages/marketPlace.dart';
import 'package:vero360_app/Pages/cartpage.dart';
import 'package:vero360_app/screens/chat_list_page.dart';
import 'package:vero360_app/Pages/MerchantDashboards/merchant_wallet.dart';

import 'package:vero360_app/Pages/Home/myorders.dart';
import 'package:vero360_app/Pages/ToRefund.dart';
import 'package:vero360_app/Pages/Toreceive.dart';
import 'package:vero360_app/Pages/Toship.dart';

class LocalMedia {
  final Uint8List bytes;
  final String filename;
  final String? mime;
  final bool isVideo;
  const LocalMedia({
    required this.bytes,
    required this.filename,
    this.mime,
    this.isVideo = false,
  });
}

class MarketplaceMerchantDashboard extends StatefulWidget {
  final String email;
  const MarketplaceMerchantDashboard({super.key, required this.email});

  @override
  State<MarketplaceMerchantDashboard> createState() =>
      _MarketplaceMerchantDashboardState();
}

class _MarketplaceMerchantDashboardState extends State<MarketplaceMerchantDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();

  // ✅ keep constructor exactly as you use elsewhere
  final CartService _cartService =
      CartService('https://heflexitservice.co.za', apiPrefix: 'vero');

  final _picker = ImagePicker();

  // Form controllers (create)
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();

  late TabController _marketplaceTabs;

  // Create form state
  bool _isActive = true;
  bool _submitting = false;
  LocalMedia? _cover;
  final List<LocalMedia> _gallery = <LocalMedia>[];

  static const List<String> _kCategories = <String>[
    'food',
    'drinks',
    'electronics',
    'clothes',
    'shoes',
    'other',
  ];
  String? _category = 'other';

  // Items
  List<Map<String, dynamic>> _items = [];
  bool _loadingItems = true;
  bool _busyRow = false;

  // Filters (My Items)
  String _searchQuery = '';
  String _filterCategory = 'all'; // all | food | ...
  String _filterStatus = 'all'; // all | active | inactive

  // Dashboard state
  List<dynamic> _recentSales = [];
  bool _isLoading = true;
  bool _initialLoadComplete = false;

  String _uid = '';
  String _businessName = ''; // resolved name for UI
  double _walletBalance = 0;

  // Stats
  int _totalItems = 0;
  int _activeItems = 0;
  int _soldItems = 0;
  double _totalEarnings = 0;
  double _rating = 0.0;
  String _status = 'pending';

  // Merchant profile details
  String _merchantEmail = 'No Email';
  String _merchantPhone = 'No Phone';
  String _merchantProfileUrl = '';

  bool _meOffline = false;
  bool _loadingMe = false;
  bool _profileUploading = false;

  Timer? _ticker;

  // Brand
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  // ----------------- Wallet lock (PIN) -----------------
  DateTime? _walletUnlockedUntil;
  static const Duration _walletUnlockDuration = Duration(minutes: 5);

  bool get _walletUnlockedNow {
    final until = _walletUnlockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Random _safeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _randomSalt([int len = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = _safeRandom();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin::$salt');
    return sha256.convert(bytes).toString();
  }

  Future<bool> _ensureAppPinExists() async {
    final sp = await SharedPreferences.getInstance();
    final existingHash = sp.getString('app_pin_hash');
    final existingSalt = sp.getString('app_pin_salt');

    if (existingHash != null &&
        existingHash.trim().isNotEmpty &&
        existingSalt != null &&
        existingSalt.trim().isNotEmpty) {
      return true;
    }

    final pin = await _showSetPinDialog();
    if (pin == null) return false;

    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);

    await sp.setString('app_pin_salt', salt);
    await sp.setString('app_pin_hash', hash);

    ToastHelper.showCustomToast(
      context,
      'App password set',
      isSuccess: true,
      errorMessage: '',
    );

    return true;
  }

  Future<bool> _unlockWalletWithPin() async {
    if (_walletUnlockedNow) return true;

    final okSetup = await _ensureAppPinExists();
    if (!okSetup) return false;

    final sp = await SharedPreferences.getInstance();
    final salt = (sp.getString('app_pin_salt') ?? '').trim();
    final hash = (sp.getString('app_pin_hash') ?? '').trim();
    if (salt.isEmpty || hash.isEmpty) return false;

    final entered = await _showEnterPinDialog();
    if (entered == null) return false;

    final enteredHash = _hashPin(entered, salt);
    final ok = enteredHash == hash;

    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Wrong password',
        isSuccess: false,
        errorMessage: 'Wrong ,password',
      );
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _walletUnlockedUntil = DateTime.now().add(_walletUnlockDuration);
    });

    return true;
  }

  Future<String?> _showEnterPinDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Enter Your Password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'PIN (4–6 digits)',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length < 4) return;
              Navigator.pop(context, pin);
            },
            child: const Text(
              'Unlock',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSetPinDialog() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Set App Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create a PIN to protect your wallet.'),
              const SizedBox(height: 10),
              TextField(
                controller: p1,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'New PIN (4–6 digits)',
                  counterText: '',
                ),
              ),
              TextField(
                controller: p2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'Confirm PIN',
                  counterText: '',
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(
                  err!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final a = p1.text.trim();
                final b = p2.text.trim();

                if (a.length < 4) {
                  setLocal(() => err = 'PIN must be at least 4 digits.');
                  return;
                }
                if (a != b) {
                  setLocal(() => err = 'PINs do not match.');
                  return;
                }
                Navigator.pop(context, a);
              },
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _marketplaceTabs = TabController(length: 3, vsync: this);

    _uid = _auth.currentUser?.uid ?? '';

    _loadMerchantProfileFromPrefs();
    _hydrateFromFirebaseAuth();
    _ensureBusinessName(); // ✅ FIX business name

    _fetchCurrentUserMe(); // ✅ API /users/me

    _loadMerchantData(); // ✅ API dashboard stats
    _loadItems(); // ✅ Firestore items counts + list
    _startPeriodicUpdates();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _marketplaceTabs.dispose();
    _name.dispose();
    _price.dispose();
    _location.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _startPeriodicUpdates() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _hydrateFromFirebaseAuth();
      _ensureBusinessName();
      _fetchCurrentUserMe();
      _loadMerchantData();
      _loadItems();
    });
  }

  // ----------------- Business name FIX (Auth → Firestore → API → Prefs) -----------------
  void _hydrateFromFirebaseAuth() {
    final u = _auth.currentUser;
    if (u == null) return;

    _uid = u.uid;

    final email = (u.email ?? '').trim();
    final phone = (u.phoneNumber ?? '').trim();
    final photo = (u.photoURL ?? '').trim();

    if (mounted) {
      setState(() {
        if (email.isNotEmpty) _merchantEmail = email;
        if (phone.isNotEmpty) _merchantPhone = phone;
        if (photo.isNotEmpty) _merchantProfileUrl = photo;
      });
    }
  }

  Future<void> _ensureBusinessName() async {
    final u = _auth.currentUser;
    if (u == null) return;

    final authDisplay = (u.displayName ?? '').trim();
    if (authDisplay.isNotEmpty) {
      if (mounted) setState(() => _businessName = authDisplay);
      return;
    }

    String resolved = '';

    // 1) Firestore marketplace_merchants
    try {
      final doc = await _firestore
          .collection('marketplace_merchants')
          .doc(u.uid)
          .get();
      final data = doc.data();
      if (data != null) {
        resolved =
            (data['businessName'] ?? data['name'] ?? '').toString().trim();
      }
    } catch (_) {}

    // 2) Firestore users
    if (resolved.isEmpty) {
      try {
        final doc = await _firestore.collection('users').doc(u.uid).get();
        final data = doc.data();
        if (data != null) {
          resolved = (data['businessName'] ??
                  data['fullName'] ??
                  data['name'] ??
                  data['displayName'] ??
                  '')
              .toString()
              .trim();
        }
      } catch (_) {}
    }

    // 3) API /users/me
    if (resolved.isEmpty) {
      try {
        final bearer = await _getBearerTokenForApi();
        if (bearer != null && bearer.isNotEmpty) {
          final base = await ApiConfig.readBase();
          final resp = await http.get(
            Uri.parse('$base/users/me'),
            headers: {
              'Authorization': 'Bearer $bearer',
              'Accept': 'application/json'
            },
          );
          if (resp.statusCode == 200) {
            final decoded = jsonDecode(resp.body);
            final Map<String, dynamic> payload =
                (decoded is Map && decoded['data'] is Map)
                    ? Map<String, dynamic>.from(decoded['data'])
                    : (decoded is Map
                        ? Map<String, dynamic>.from(decoded)
                        : {});
            final user = (payload['user'] is Map)
                ? Map<String, dynamic>.from(payload['user'] as Map)
                : payload;

            final business =
                (user['businessName'] ?? user['merchantName'] ?? '')
                    .toString()
                    .trim();
            final name = (user['name'] ?? '').toString().trim();
            final first = (user['firstName'] ?? '').toString().trim();
            final last = (user['lastName'] ?? '').toString().trim();
            final joined =
                [first, last].where((x) => x.isNotEmpty).join(' ').trim();

            resolved = business.isNotEmpty
                ? business
                : (name.isNotEmpty ? name : joined);
          }
        }
      } catch (_) {}
    }

    // 4) Prefs fallback
    if (resolved.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      resolved = (prefs.getString('business_name') ??
              prefs.getString('fullName') ??
              prefs.getString('name') ??
              '')
          .trim();
    }

    if (resolved.isEmpty) resolved = 'Marketplace Merchant';

    // ✅ backfill FirebaseAuth displayName so next time it's correct
    try {
      if ((u.displayName ?? '').trim().isEmpty &&
          resolved != 'Marketplace Merchant') {
        await u.updateDisplayName(resolved);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _businessName = resolved);
  }

  String _displayBusinessName() {
    final authName = (_auth.currentUser?.displayName ?? '').trim();
    if (authName.isNotEmpty) return authName;
    if (_businessName.trim().isNotEmpty) return _businessName.trim();
    return 'Marketplace Merchant';
  }

  // ----------------- API auth: prefs token OR Firebase idToken -----------------
  Future<String?> _getBearerTokenForApi() async {
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt');

    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final idToken = await user.getIdToken();
      final t = idToken?.trim();
      return t!.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMerchantProfileFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _merchantEmail = prefs.getString('email') ?? _merchantEmail;
      _merchantPhone = prefs.getString('phone') ?? _merchantPhone;
      _merchantProfileUrl =
          prefs.getString('profilepicture') ?? _merchantProfileUrl;
    });
  }

  // ✅ /users/me for email/phone/pic/rating (keeps name from resolver)
  Future<void> _fetchCurrentUserMe() async {
    if (!mounted) return;

    setState(() {
      _loadingMe = true;
      _meOffline = false;
    });

    try {
      final bearer = await _getBearerTokenForApi();
      if (bearer == null || bearer.isEmpty) {
        if (mounted) setState(() => _loadingMe = false);
        return;
      }

      final base = await ApiConfig.readBase();
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json'
        },
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final Map<String, dynamic> payload =
            (decoded is Map && decoded['data'] is Map)
                ? Map<String, dynamic>.from(decoded['data'])
                : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
        final user = (payload['user'] is Map)
            ? Map<String, dynamic>.from(payload['user'] as Map)
            : payload;

        final emailVal =
            (user['email'] ?? user['userEmail'] ?? '').toString().trim();
        final phoneVal = (user['phone'] ?? '').toString().trim();
        final picVal =
            (user['profilepicture'] ?? user['profilePicture'] ?? '')
                .toString()
                .trim();

        final apiRating = user['rating'];
        if (apiRating is num) _rating = apiRating.toDouble();

        final prefs = await SharedPreferences.getInstance();
        if (emailVal.isNotEmpty) await prefs.setString('email', emailVal);
        if (phoneVal.isNotEmpty) await prefs.setString('phone', phoneVal);
        if (picVal.isNotEmpty) await prefs.setString('profilepicture', picVal);

        if (!mounted) return;
        setState(() {
          if (emailVal.isNotEmpty) _merchantEmail = emailVal;
          if (phoneVal.isNotEmpty) _merchantPhone = phoneVal;

          final authPhoto = (_auth.currentUser?.photoURL ?? '').trim();
          if (authPhoto.isEmpty && picVal.isNotEmpty) _merchantProfileUrl = picVal;
        });
      } else {
        setState(() => _meOffline = true);
      }
    } catch (e) {
      setState(() => _meOffline = true);
      debugPrint('Error fetching /users/me: $e');
    } finally {
      if (mounted) setState(() => _loadingMe = false);
    }
  }

  // ----------------- Dashboard API + Wallet -----------------
  Future<void> _loadMerchantData() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? _uid;

    if (_uid.isNotEmpty) {
      try {
        final dashboardData =
            await _helper.getMerchantDashboardData(_uid, 'marketplace');

        if (!dashboardData.containsKey('error')) {
          final merchant = dashboardData['merchant'];

          setState(() {
            _recentSales = dashboardData['recentOrders'] ?? [];

            _totalEarnings = (dashboardData['totalRevenue'] is num)
                ? (dashboardData['totalRevenue'] as num).toDouble()
                : double.tryParse('${dashboardData['totalRevenue']}') ?? 0;

            final ti = dashboardData['totalItems'];
            final ai = dashboardData['activeItems'];
            final si = dashboardData['soldItems'];
            if (ti is int) _totalItems = ti;
            if (ai is int) _activeItems = ai;
            if (si is int) _soldItems = si;

            if (merchant is Map) {
              final mr = merchant['rating'];
              if (mr is num) _rating = mr.toDouble();

              final ms = merchant['status'];
              if (ms != null && ms.toString().trim().isNotEmpty) {
                _status = ms.toString().trim();
              }
            }
          });
        }

        await _loadWalletBalance();
      } catch (e) {
        debugPrint('Error loading dashboard: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _initialLoadComplete = true;
      });
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final firebaseUid = _auth.currentUser?.uid ?? _uid;
      if (firebaseUid.trim().isEmpty) return;

      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(firebaseUid)
          .get();

      if (!walletDoc.exists || !mounted) return;

      final raw = walletDoc.data()?['balance'];
      double val = 0;
      if (raw is num) {
        val = raw.toDouble();
      } else {
        val = double.tryParse(raw?.toString() ?? '') ?? 0;
      }

      setState(() => _walletBalance = val);
    } catch (e) {
      debugPrint('Error loading wallet: $e');
    }
  }

  // ----------------- Nest/API userId (for sellerUserId filter) -----------------
  Future<String?> _getNestUserId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final token = sp.getString('jwt') ??
          sp.getString('token') ??
          sp.getString('jwt_token') ??
          sp.getString('authToken');

      if (token != null && token.trim().isNotEmpty) {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payloadJson =
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
          final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
          final rawId = payload['sub'] ?? payload['id'] ?? payload['userId'];
          if (rawId != null) return rawId.toString();
        }
      }

      final bearer = await _getBearerTokenForApi();
      if (bearer == null || bearer.isEmpty) return null;

      final base = await ApiConfig.readBase();
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
      );
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body);
      final Map<String, dynamic> payload =
          (decoded is Map && decoded['data'] is Map)
              ? Map<String, dynamic>.from(decoded['data'])
              : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
      final user =
          (payload['user'] is Map) ? payload['user'] as Map : payload;

      final rawId = user['id'] ?? user['userId'] ?? user['sub'];
      if (rawId == null) return null;
      return rawId.toString();
    } catch (_) {
      return null;
    }
  }

  // ----------------- Items load + counts (total/active) -----------------
  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);
    try {
      final nestSellerId = await _getNestUserId();
      final firebaseUid = _auth.currentUser?.uid ?? _uid;

      Query<Map<String, dynamic>> query =
          _firestore.collection('marketplace_items');

      if (nestSellerId != null && nestSellerId.trim().isNotEmpty) {
        query = query.where('sellerUserId', isEqualTo: nestSellerId.trim());
      } else if (firebaseUid.trim().isNotEmpty) {
        query = query.where('merchantId', isEqualTo: firebaseUid.trim());
      }

      final snap = await query.get();
      final list =
          snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();

      final total = list.length;
      final active = list.where((e) => e['isActive'] == true).length;

      int sold = 0;
      for (final it in list) {
        if (it['sold'] == true) sold += 1;
      }

      if (!mounted) return;
      setState(() {
        _items = list;
        _totalItems = total;
        _activeItems = active;
        _soldItems = sold;
      });
    } catch (e) {
      debugPrint('Error loading items: $e');
      if (!mounted) return;
      setState(() {
        _items = [];
        _totalItems = 0;
        _activeItems = 0;
        _soldItems = 0;
      });
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  List<Map<String, dynamic>> _filteredItems() {
    final q = _searchQuery.trim().toLowerCase();
    return _items.where((it) {
      final name = (it['name'] ?? '').toString().toLowerCase();
      final cat = (it['category'] ?? 'other').toString().toLowerCase();
      final active = it['isActive'] == true;

      final okQ = q.isEmpty || name.contains(q);
      final okCat = (_filterCategory == 'all') || cat == _filterCategory;
      final okStatus = (_filterStatus == 'all') ||
          (_filterStatus == 'active' && active) ||
          (_filterStatus == 'inactive' && !active);

      return okQ && okCat && okStatus;
    }).toList();
  }

  // ----------------- Pull-to-refresh -----------------
  Future<void> _refreshAll() async {
    await _ensureBusinessName();
    await _fetchCurrentUserMe();
    await _loadMerchantData();
    await _loadItems();
  }

  // ----------------- Profile image helpers -----------------
  ImageProvider? _profileImageProvider() {
    final s = _merchantProfileUrl.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http')) return NetworkImage(s);
    try {
      final bytes = base64Decode(s);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ----------------- Profile photo (Firebase Storage) -----------------
  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfile(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfile(ImageSource.gallery);
              },
            ),
            if (_merchantProfileUrl.trim().isNotEmpty)
              ListTile(
                leading:
                    const Icon(Icons.remove_circle_outline, color: Colors.red),
                title: const Text('Remove current photo'),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _viewProfilePhoto() {
    final img = _profileImageProvider();
    if (img == null) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              AspectRatio(
                  aspectRatio: 1, child: Image(image: img, fit: BoxFit.cover)),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfile(ImageSource src) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        ToastHelper.showCustomToast(context, 'Please login first',
            isSuccess: false, errorMessage: '');
        return;
      }

      final file = await _picker.pickImage(
          source: src, maxWidth: 1400, imageQuality: 85);
      if (file == null) return;

      setState(() => _profileUploading = true);
      final url = await _uploadProfileToFirebaseStorage(user.uid, file);

      await user.updatePhotoURL(url);

      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);

      if (!mounted) return;
      setState(() => _merchantProfileUrl = url);

      ToastHelper.showCustomToast(context, 'Profile picture updated',
          isSuccess: true, errorMessage: '');
    } catch (e) {
      debugPrint('Profile upload error: $e');
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to upload photo',
          isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {
    final ext = (file.name.contains('.')) ? file.name.split('.').last : 'jpg';
    final mime = lookupMimeType(file.path) ?? 'image/jpeg';

    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_photos')
        .child(uid)
        .child('profile_${DateTime.now().millisecondsSinceEpoch}.$ext');

    final bytes = await file.readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: mime));
    return await ref.getDownloadURL();
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      setState(() => _profileUploading = true);

      await user.updatePhotoURL(null);

      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');

      if (!mounted) return;
      setState(() => _merchantProfileUrl = '');

      ToastHelper.showCustomToast(context, 'Profile picture removed',
          isSuccess: true, errorMessage: '');
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Failed to remove photo',
          isSuccess: false, errorMessage: e.toString());
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  // ----------------- CREATE item -----------------
  Future<void> _create() async {
    if (_cover == null) {
      ToastHelper.showCustomToast(context, 'Please pick a cover photo',
          isSuccess: false, errorMessage: 'Photo required');
      return;
    }
    if (_name.text.isEmpty || _price.text.isEmpty || _location.text.isEmpty) {
      ToastHelper.showCustomToast(context, 'Please fill all required fields',
          isSuccess: false, errorMessage: 'Missing fields');
      return;
    }

    setState(() => _submitting = true);

    try {
      final firebaseUid = _auth.currentUser?.uid ?? _uid;
      if (firebaseUid.trim().isEmpty) {
        ToastHelper.showCustomToast(context, 'Please login first',
            isSuccess: false, errorMessage: 'Not logged in');
        return;
      }

      final sellerId = await _getNestUserId(); // ✅ API seller id if available
      final coverBase64 = base64Encode(_cover!.bytes);

      final galleryBase64 = <String>[];
      for (final m in _gallery) {
        galleryBase64.add(base64Encode(m.bytes));
      }

      final merchantDisplay = _displayBusinessName();

      final data = {
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'image': coverBase64,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'location': _location.text.trim(),
        'isActive': _isActive,
        'category': _category ?? 'other',
        'gallery': galleryBase64,
        'createdAt': FieldValue.serverTimestamp(),
        // ✅ BOTH IDs saved
        'sellerUserId': (sellerId != null && sellerId.trim().isNotEmpty)
            ? sellerId.trim()
            : 'unknown',
        'merchantId': firebaseUid,
        'merchantName': merchantDisplay,
        'serviceType': 'marketplace',
      };

      await _firestore.collection('marketplace_items').add(data);

      ToastHelper.showCustomToast(context, 'Item Posted Successfully!',
          isSuccess: true, errorMessage: '');

      _name.clear();
      _price.clear();
      _location.clear();
      _desc.clear();
      _cover = null;
      _gallery.clear();
      _isActive = true;
      _category = 'other';

      setState(() {});
      await _loadItems();
      _marketplaceTabs.animateTo(2);
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Create failed: $e',
          isSuccess: false, errorMessage: 'Create failed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item'),
        content: Text('Delete "${item['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyRow = true);
    try {
      final id = item['id'] as String;
      await _firestore.collection('marketplace_items').doc(id).delete();
      _items.removeWhere((e) => e['id'] == id);

      ToastHelper.showCustomToast(context, 'Deleted • ${item['name']}',
          isSuccess: true, errorMessage: '');

      setState(() {
        _totalItems = _items.length;
        _activeItems = _items.where((e) => e['isActive'] == true).length;
      });
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Delete failed: $e',
          isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _busyRow = false);
    }
  }

  // ----------------- EDIT item (modern bottom sheet) -----------------
  Future<void> _openEditItemSheet(Map<String, dynamic> item) async {
    final id = (item['id'] ?? '').toString();
    if (id.isEmpty) return;

    final nameCtrl =
        TextEditingController(text: (item['name'] ?? '').toString());
    final priceCtrl =
        TextEditingController(text: (item['price'] ?? '').toString());
    final locationCtrl =
        TextEditingController(text: (item['location'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (item['description'] ?? '').toString());
    String category = (item['category'] ?? 'other').toString();
    bool isActive = item['isActive'] == true;

    LocalMedia? newCover;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setSheet) {
            Future<void> pickNewCover() async {
              final x = await _picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1800,
                  imageQuality: 90);
              if (x == null) return;
              final bytes = await x.readAsBytes();
              setSheet(() {
                newCover = LocalMedia(
                  bytes: bytes,
                  filename: x.name,
                  mime: lookupMimeType(x.name, headerBytes: bytes),
                );
              });
            }

            Future<void> save() async {
              if (saving) return;

              final n = nameCtrl.text.trim();
              final p = double.tryParse(priceCtrl.text.trim()) ?? 0;
              final loc = locationCtrl.text.trim();

              if (n.isEmpty || p <= 0 || loc.isEmpty) {
                ToastHelper.showCustomToast(context, 'Fill name, price and location',
                    isSuccess: false, errorMessage: '');
                return;
              }

              setSheet(() => saving = true);
              try {
                final patch = <String, dynamic>{
                  'name': n,
                  'price': p,
                  'location': loc,
                  'category': category,
                  'description':
                      descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'isActive': isActive,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (newCover != null) {
                  patch['image'] = base64Encode(newCover!.bytes);
                }

                await _firestore.collection('marketplace_items').doc(id).update(patch);

                final idx = _items.indexWhere((e) => (e['id'] ?? '') == id);
                if (idx != -1) {
                  _items[idx] = {..._items[idx], ...patch};
                }

                if (mounted) {
                  setState(() {
                    _totalItems = _items.length;
                    _activeItems = _items.where((e) => e['isActive'] == true).length;
                  });
                }

                if (mounted) Navigator.pop(context);
                ToastHelper.showCustomToast(context, 'Item updated',
                    isSuccess: true, errorMessage: '');
              } catch (e) {
                ToastHelper.showCustomToast(context, 'Update failed: $e',
                    isSuccess: false, errorMessage: '');
              } finally {
                setSheet(() => saving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                  left: 16, right: 16, bottom: 16 + bottomInset, top: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Edit Item',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: newCover != null
                          ? Image.memory(newCover!.bytes, fit: BoxFit.cover)
                          : _ImageAny(item['image']),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: pickNewCover,
                        icon: const Icon(Icons.photo),
                        label: const Text('Change Cover'),
                      ),
                      const Spacer(),
                      Switch(
                        value: isActive,
                        onChanged: (v) => setSheet(() => isActive = v),
                      ),
                      Text(isActive ? 'Active' : 'Inactive',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: nameCtrl,
                      decoration: _inputDecoration(label: 'Item Name')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(label: 'Price (MWK)')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: locationCtrl,
                      decoration: _inputDecoration(label: 'Location')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: category,
                    items: _kCategories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                  c[0].toUpperCase() + c.substring(1)),
                            ))
                        .toList(),
                    onChanged: (v) => setSheet(() => category = v ?? 'other'),
                    decoration: _inputDecoration(label: 'Category'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _inputDecoration(label: 'Description (optional)'),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    priceCtrl.dispose();
    locationCtrl.dispose();
    descCtrl.dispose();
  }

  // ----------------- Location helpers -----------------
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ToastHelper.showCustomToast(context, 'Location services are disabled.',
            isSuccess: false, errorMessage: '');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ToastHelper.showCustomToast(context, 'Location permissions are denied.',
              isSuccess: false, errorMessage: '');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ToastHelper.showCustomToast(
            context, 'Location permissions are permanently denied.',
            isSuccess: false, errorMessage: '');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isEmpty) {
        ToastHelper.showCustomToast(context, 'Could not fetch address.',
            isSuccess: false, errorMessage: '');
        return;
      }

      final place = placemarks[0];
      final address = [
        place.name,
        place.street,
        place.locality,
        place.administrativeArea,
        place.country,
      ].where((e) => e != null && e.isNotEmpty).join(', ');

      setState(() => _location.text = address);
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Failed to get location: $e',
          isSuccess: false, errorMessage: '');
    }
  }

  Future<void> _openGoogleMap() async {
    if (_location.text.trim().isEmpty) {
      ToastHelper.showCustomToast(context, 'Enter a location first.',
          isSuccess: false, errorMessage: '');
      return;
    }
    final query = Uri.encodeComponent(_location.text.trim());
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showCustomToast(context, 'Could not open Google Maps.',
          isSuccess: false, errorMessage: '');
    }
  }

  // ----------------- UI helpers -----------------
  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black12),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  ButtonStyle _filledBtnStyle({double padV = 14}) => FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: EdgeInsets.symmetric(vertical: padV, horizontal: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      );

  Widget _compactStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------- NAV + Scaffold -----------------
  int _selectedIndex = 0;

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null,
      body: _getCurrentPage(),
      bottomNavigationBar: _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    final titleName = _displayBusinessName();
    return AppBar(
      title: Text(_initialLoadComplete ? '$titleName Dashboard' : 'Loading...'),
      backgroundColor: _brandOrange,
      actions: [
        IconButton(
          icon: const Icon(Icons.account_balance_wallet),
          onPressed: () async {
            final ok = await _unlockWalletWithPin();
            if (!ok || !mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MerchantWalletPage(
                  merchantId: _uid,
                  merchantName: titleName,
                  serviceType: 'marketplace',
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            // ✅ back will work now
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsPage(onBackToHomeTab: () {  },)),
            );
          },
        ),
      ],
    );
  }

  Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return Vero360Homepage(email: widget.email);
      case 1:
        return MarketPage(cartService: _cartService);
      case 2:
        return CartPage(cartService: _cartService);
      case 3:
        return ChatListPage();
      case 4:
        return _buildDashboardContent();
      default:
        return Vero360Homepage(email: widget.email);
    }
  }

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const _DashboardSkeleton();
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _marketplaceTabs,
              labelColor: _brandOrange,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _brandOrange,
              tabs: const [
                Tab(text: 'Dashboard'),
                Tab(text: 'Add Item'),
                Tab(text: 'My Items'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _marketplaceTabs,
              children: [
                RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildModernHeaderCard(),
                        const SizedBox(height: 12),
                        _buildStatsSection(),
                        const SizedBox(height: 12),
                        _buildQuickActionsSection(),
                        const SizedBox(height: 12),
                        _buildWalletSummary(),
                        const SizedBox(height: 12),
                        _buildRecentSales(),
                        const SizedBox(height: 12),
                        _buildAllClientItemsSection(),
                      ],
                    ),
                  ),
                ),
                _buildAddItemTab(),
                _buildMyItemsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------- Header (modern) -----------------
  Widget _buildModernHeaderCard() {
    final business = _displayBusinessName();
    final st = _status.trim().toLowerCase();
    final statusText = st.isEmpty ? 'PENDING' : st.toUpperCase();

    Color statusBg;
    Color statusFg;
    if (st == 'approved' || st == 'active') {
      statusBg = const Color(0xFFE7F6EC);
      statusFg = Colors.green.shade700;
    } else if (st == 'pending' || st == 'under_review' || st == 'submitted') {
      statusBg = const Color(0xFFFFF3E5);
      statusFg = const Color(0xFFB86E00);
    } else {
      statusBg = const Color(0xFFFFEDEE);
      statusFg = Colors.red.shade700;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_brandNavy, _brandNavy.withOpacity(0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _viewProfilePhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    backgroundImage: _profileImageProvider(),
                    child: _profileImageProvider() == null
                        ? const Icon(Icons.storefront_rounded,
                            color: Colors.white, size: 26)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: _showPhotoSheet,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _brandOrange,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _profileUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.edit,
                                size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _merchantEmail,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _merchantPhone,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(statusText,
                            style: TextStyle(
                                color: statusFg,
                                fontWeight: FontWeight.w900,
                                fontSize: 12)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_meOffline)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFEDEE),
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('YOUR OFFLINE',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: Colors.red)),
                        ),
                      if (_loadingMe)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- Smaller Business Overview cards -----------------
  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Business Overview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 74,
          ),
          itemBuilder: (_, i) {
            switch (i) {
              case 0:
                return _compactStatTile(
                  title: 'Total Items',
                  value: '$_totalItems',
                  icon: Icons.inventory_2,
                  color: _brandOrange,
                );
              case 1:
                return _compactStatTile(
                  title: 'Active Items',
                  value: '$_activeItems',
                  icon: Icons.verified_rounded,
                  color: Colors.green,
                );
              case 2:
                return _compactStatTile(
                  title: 'Sold Items',
                  value: '$_soldItems',
                  icon: Icons.shopping_bag_rounded,
                  color: Colors.blue,
                );
              default:
                return _compactStatTile(
                  title: 'Earnings',
                  value: 'MWK ${_totalEarnings.toStringAsFixed(0)}',
                  icon: Icons.payments_rounded,
                  color: Colors.green,
                );
            }
          },
        ),
      ],
    );
  }

  // ----------------- Quick actions + profile actions -----------------
  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 74,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            _QuickActionTile(
              title: 'Add Item',
              icon: Icons.add_circle_outline,
              color: _brandOrange,
              onTap: () => _marketplaceTabs.animateTo(1),
            ),
            _QuickActionTile(
              title: 'My Items',
              icon: Icons.inventory_2_outlined,
              color: _brandNavy,
              onTap: () => _marketplaceTabs.animateTo(2),
            ),
            _QuickActionTile(
              title: 'My Orders',
              icon: Icons.receipt_long,
              color: Colors.green,
              onTap: () => _openBottomSheet(const OrdersPage()),
            ),
            _QuickActionTile(
              title: 'Shipped',
              icon: Icons.local_shipping_outlined,
              color: Colors.orange,
              onTap: () => _openBottomSheet(const ToShipPage()),
            ),
            _QuickActionTile(
              title: 'Received',
              icon: Icons.move_to_inbox_outlined,
              color: Colors.blue,
              onTap: () => _openBottomSheet(const DeliveredOrdersPage()),
            ),
            _QuickActionTile(
              title: 'Refund',
              icon: Icons.replay_circle_filled_outlined,
              color: Colors.red,
              onTap: () => _openBottomSheet(const ToRefundPage()),
            ),
            ActionChip(
              avatar: const Icon(Icons.logout, size: 20),
              label: const Text('Logout'),
              onPressed: _logout,
            ),
          ],
        ),
      ],
    );
  }

  void _openBottomSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: child,
      ),
    );
  }

  // ----------------- Wallet Summary (LOCKED) -----------------
  Widget _buildWalletSummary() {
    final titleName = _displayBusinessName();
    final unlocked = _walletUnlockedNow;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (unlocked ? Colors.green : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              unlocked ? Icons.account_balance_wallet_rounded : Icons.lock_rounded,
              color: unlocked ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wallet Balance',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  unlocked ? 'MWK ${_walletBalance.toStringAsFixed(2)}' : 'MWK ••••',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: unlocked ? Colors.green : Colors.black54,
                  ),
                ),
                if (!unlocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Locked — tap Open to unlock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              final ok = await _unlockWalletWithPin();
              if (!ok || !mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: titleName,
                    serviceType: 'marketplace',
                  ),
                ),
              );
            },
            child: const Text('Open',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ----------------- Recent Sales -----------------
  Widget _buildRecentSales() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Expanded(
              child: Text('Recent Sales',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentSales.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No sales yet')),
          )
        else
          ..._recentSales.take(4).map((sale) {
            final saleMap = sale as Map<String, dynamic>;
            final orderId = (saleMap['orderId'] ?? '').toString();
            final shortId = orderId.length >= 8
                ? orderId.substring(0, 8)
                : (orderId.isEmpty ? 'N/A' : orderId);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _brandOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shopping_bag_rounded,
                      color: _brandOrange),
                ),
                title: Text('Sale #$shortId',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer: ${saleMap['customerName'] ?? 'N/A'}'),
                      Text('Items: ${saleMap['itemCount'] ?? '0'}'),
                      Text('Total: MWK ${saleMap['totalAmount'] ?? '0'}'),
                    ],
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getSaleStatusColor(saleMap['status']?.toString()),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text((saleMap['status'] ?? 'pending').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Color _getSaleStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green[100]!;
      case 'processing':
        return Colors.blue[100]!;
      case 'shipped':
        return Colors.orange[100]!;
      case 'pending':
        return Colors.yellow[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  // ----------------- “Top items” replaced: list ALL merchant items -----------------
  Widget _buildAllClientItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Items',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        if (_loadingItems)
          const _ItemsGridSkeleton(count: 6)
        else if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No items yet')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (_, i) => _ModernItemMiniCard(item: _items[i]),
          ),
      ],
    );
  }

  // ----------------- Add Item Tab -----------------
  Widget _buildAddItemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add New Item',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              const Text('Cover Image',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _cover == null
                    ? Container(
                        height: 160,
                        color: const Color(0xFFF3F4F7),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.image,
                                  size: 40, color: Colors.black26),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: _brandOrange),
                                onPressed: () => _pickCover(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Select Image'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          Image.memory(_cover!.bytes,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: InkWell(
                              onTap: () => setState(() => _cover = null),
                              child: const CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              TextField(
                  controller: _name,
                  decoration: _inputDecoration(label: 'Item Name')),
              const SizedBox(height: 10),
              TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(label: 'Price (MWK)')),
              const SizedBox(height: 10),
              TextField(
                controller: _location,
                decoration: _inputDecoration(label: 'Location').copyWith(
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.my_location),
                          onPressed: _getCurrentLocation),
                      IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: _openGoogleMap),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _category,
                items: _kCategories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c[0].toUpperCase() + c.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v),
                decoration: _inputDecoration(label: 'Category'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                minLines: 3,
                maxLines: 5,
                decoration: _inputDecoration(label: 'Description (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v)),
                  Text(_isActive ? 'Active' : 'Inactive',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const Spacer(),
                  FilledButton.icon(
                    style: _filledBtnStyle(),
                    onPressed: _submitting ? null : _create,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_rounded),
                    label: const Text('Post Item'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- My Items Tab: Search + Filter chips + Edit -----------------
  Widget _buildMyItemsTab() {
    final filtered = _filteredItems();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search items...',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        const BorderSide(color: _brandOrange, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip(
                      label: 'All Categories',
                      selected: _filterCategory == 'all',
                      onTap: () => setState(() => _filterCategory = 'all'),
                    ),
                    ..._kCategories.map((c) => _chip(
                          label: c[0].toUpperCase() + c.substring(1),
                          selected: _filterCategory == c,
                          onTap: () => setState(() => _filterCategory = c),
                        )),
                    const SizedBox(width: 10),
                    _chip(
                      label: 'All',
                      selected: _filterStatus == 'all',
                      onTap: () => setState(() => _filterStatus = 'all'),
                    ),
                    _chip(
                      label: 'Active',
                      selected: _filterStatus == 'active',
                      onTap: () => setState(() => _filterStatus = 'active'),
                    ),
                    _chip(
                      label: 'Inactive',
                      selected: _filterStatus == 'inactive',
                      onTap: () => setState(() => _filterStatus = 'inactive'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingItems
              ? const _ItemsGridSkeleton(count: 8)
              : filtered.isEmpty
                  ? const Center(child: Text('No items match your filters'))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: filtered.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemBuilder: (_, i) => _ItemCard(
                        item: filtered[i],
                        busy: _busyRow,
                        onDelete: () => _deleteItem(filtered[i]),
                        onEdit: () => _openEditItemSheet(filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _chip(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: _brandOrange.withOpacity(0.16),
        labelStyle: TextStyle(color: selected ? _brandOrange : Colors.black87),
        side: const BorderSide(color: Colors.black12),
      ),
    );
  }

  // ----------------- cover picker -----------------
  Future<void> _pickCover(ImageSource src) async {
    final x = await _picker.pickImage(
        source: src, imageQuality: 90, maxWidth: 2048);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _cover = LocalMedia(
          bytes: bytes,
          filename: x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes));
    });
  }

  // ----------------- Bottom nav -----------------
  Widget _buildMerchantNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -6))
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_rounded, 'Home', 0),
              _buildNavItem(Icons.storefront_rounded, 'Marketplace', 1),
              _buildNavItem(Icons.shopping_cart_rounded, 'Cart', 2),
              _buildNavItem(Icons.message_rounded, 'Messages', 3),
              _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _brandOrange.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isSelected ? _brandOrange : Colors.grey[600], size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? _brandOrange : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------- Quick action tile -----------------
class _QuickActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _QuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------- Skeletons -----------------
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w}) => Container(
          height: h,
          width: w ?? double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEFF3),
            borderRadius: BorderRadius.circular(16),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEFF3),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: box(74)),
            const SizedBox(width: 12),
            Expanded(child: box(74))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: box(74)),
            const SizedBox(width: 12),
            Expanded(child: box(74))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: box(74)),
            const SizedBox(width: 12),
            Expanded(child: box(74))
          ]),
          const SizedBox(height: 12),
          box(90),
          const SizedBox(height: 12),
          box(110),
          const SizedBox(height: 12),
          const _ItemsGridSkeleton(count: 6),
        ],
      ),
    );
  }
}

class _ItemsGridSkeleton extends StatelessWidget {
  final int count;
  const _ItemsGridSkeleton({required this.count});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFF3),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

// ----------------- Cards -----------------
class _ModernItemMiniCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ModernItemMiniCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final active = item['isActive'] == true;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: _ImageAny(item['image']),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (item['name'] ?? 'Unknown').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'MWK ${(item['price'] ?? 0).toString()}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, color: Colors.green),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.circle,
                        size: 10, color: active ? Colors.green : Colors.red),
                    const SizedBox(width: 6),
                    Text(active ? 'Active' : 'Inactive',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ItemCard({
    required this.item,
    required this.busy,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final active = item['isActive'] == true;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  child: SizedBox(height: 150, child: _ImageAny(item['image'])),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['name'] ?? 'Unknown').toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'MWK ${(item['price'] ?? 0).toString()}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, color: Colors.green),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (item['category'] ?? 'other').toString(),
                        style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  active ? 'Active' : 'Inactive',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: [
                  _iconBtn(
                    icon: Icons.edit,
                    color: const Color(0xFF16284C),
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 8),
                  _iconBtn(
                    icon: Icons.delete,
                    color: Colors.red,
                    onTap: busy ? null : onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12)),
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: color,
        onPressed: onTap,
      ),
    );
  }
}

// Image widget: supports http OR base64
class _ImageAny extends StatelessWidget {
  final dynamic imageData;
  const _ImageAny(this.imageData);

  @override
  Widget build(BuildContext context) {
    if (imageData is! String || imageData.isEmpty) return _placeholder();

    try {
      if (imageData.startsWith('http')) {
        return Image.network(
          imageData,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } else {
        final bytes = base64Decode(imageData);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF3F4F7),
      child: const Center(
        child: Icon(Icons.image_not_supported_rounded, color: Colors.black26),
      ),
    );
  }
}
