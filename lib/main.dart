// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// Deep links
import 'package:app_links/app_links.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';

// HTTP + prefs
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Your pages/services
import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/merchantbottomnavbar.dart';
import 'package:vero360_app/Pages/cartpage.dart';
import 'package:vero360_app/Pages/profile_from_link_page.dart';
import 'package:vero360_app/screens/login_screen.dart';
import 'package:vero360_app/screens/register_screen.dart';
import 'package:vero360_app/services/auth_guard.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/services/api_config.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort Firebase init (safe to keep if you use it)
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCQ5_4N2J_xwKqmY-lAa8-ifRxovoRTTYk",
        authDomain: "vero360app-ca423.firebaseapp.com",
        projectId: "vero360app-ca423",
        storageBucket: "vero360app-ca423.firebasestorage.app",
        messagingSenderId: " 1010595167807",
        appId: "1:1010595167807:android:f63d7c7959bdb2891dc28a",
        measurementId: "509938238",
      ),
    );
  } catch (_) {}

  await ApiConfig.useProd();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  // Which shell we’re currently showing (purely for nav correctness)
  String _currentShell =
      'customer'; // customer home is the default (Bottomnavbar)

  @override
  void initState() {
    super.initState();
    _initDeepLinks();

    // 1) Instant redirect using cached role (no spinner)
    // 2) Quick verify with server to correct if needed
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await _fastRedirectFromCache();
      unawaited(_verifyRoleFromServerInBg());
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _sub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'vero360' && uri.host == 'users' && uri.path == '/me') {
        navKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const ProfileFromLinkPage()));
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------- Shell & role helpers ----------
  Future<void> _fastRedirectFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('user_role') ?? '').toLowerCase();
    final email = prefs.getString('email') ?? '';

    if (role == 'merchant') {
      _pushMerchant(email);
    } // else keep customer home by default
  }

  Future<void> _verifyRoleFromServerInBg() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _readToken(prefs);
    if (token == null) return;

    final base = await ApiConfig.readBase();
    try {
      final resp = await http.get(Uri.parse('$base/users/me'), headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final user = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{});

        await _persistUserToPrefs(prefs, user);
        final merchant = _isMerchant(user);
        if (merchant && _currentShell != 'merchant') {
          _pushMerchant((user['email'] ?? '').toString());
        } else if (!merchant && _currentShell != 'customer') {
          _pushCustomer();
        }
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        await _clearAuth(prefs);
        // Stay on customer home (public) per your UX – do not force login
      }
    } catch (_) {/* network hiccup: keep current shell */}
  }

  String? _readToken(SharedPreferences p) =>
      p.getString('jwt_token') ??
      p.getString('token') ??
      p.getString('authToken');

  bool _isMerchant(Map<String, dynamic> u) {
    final role = (u['role'] ?? u['accountType'] ?? '').toString().toLowerCase();
    final roles = (u['roles'] is List)
        ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final flags = {
      'isMerchant': u['isMerchant'] == true,
      'merchant': u['merchant'] == true,
      'merchantId': (u['merchantId'] ?? '').toString().isNotEmpty,
    };
    return role == 'merchant' ||
        roles.contains('merchant') ||
        flags.values.any((v) => v == true);
  }

  Future<void> _persistUserToPrefs(
      SharedPreferences prefs, Map<String, dynamic> u) async {
    String _join(String? a, String? b) {
      final parts = [a, b]
          .where((x) => x != null && x!.trim().isNotEmpty)
          .map((x) => x!.trim())
          .toList();
      return parts.isEmpty ? '' : parts.join(' ');
    }

    final name = (u['name'] ?? _join(u['firstName'], u['lastName'])).toString();
    final email = (u['email'] ?? u['userEmail'] ?? '').toString();
    final phone = (u['phone'] ?? '').toString();
    final pic = (u['profilepicture'] ?? u['profilePicture'] ?? '').toString();

    await prefs.setString('fullName', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('name', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('email', email.isEmpty ? 'No Email' : email);
    await prefs.setString('phone', phone.isEmpty ? 'No Phone' : phone);
    await prefs.setString('profilepicture', pic);

    final normalizedRole = _isMerchant(u) ? 'merchant' : 'customer';
    await prefs.setString('user_role', normalizedRole);
  }

  Future<void> _clearAuth(SharedPreferences prefs) async {
    await prefs.remove('jwt_token');
    await prefs.remove('token');
    await prefs.remove('authToken');
    await prefs.remove('user_role');
  }

  void _pushMerchant(String email) {
    if (!mounted) return;
    _currentShell = 'merchant';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MerchantBottomnavbar(email: email)),
      (route) => false,
    );
  }

  void _pushCustomer() {
    if (!mounted) return;
    _currentShell = 'customer';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
      (route) => false,
    );
  }

  void _pushLogin() {
    if (!mounted) return;
    _currentShell = 'login';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ---------- App ----------
  @override
  Widget build(BuildContext context) {
    // Start on Home (customer shell) for everyone
    return MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      title: 'Vero360',
      theme: ThemeData(
          useMaterial3: true, colorSchemeSeed: const Color(0xFFFF8A00)),
      home: const Bottomnavbar(email: ''), // ✅ default home (no login gate)
      routes: {
        '/marketplace': (context) => const Bottomnavbar(email: ''),
        '/signup': (context) => const RegisterScreen(),
        '/login': (context) => const LoginScreen(),
        '/cartpage': (context) => AuthGuard(
            child: CartPage(
                cartService: CartService('https://vero-backend.onrender.com',
                    apiPrefix: ''))),
      },
    );
  }
}

/// -------- Static helpers to use from Login / Logout screens ---------------
class AuthFlow {
  /// Call this RIGHT AFTER a successful login.
  static Future<void> onLoginSuccess(BuildContext ctx, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);

    final base = await ApiConfig.readBase();
    try {
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json'
        },
      );
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final user = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{});

        // persist minimal user + role
        final role = _isMerchant(user) ? 'merchant' : 'customer';
        await prefs.setString('user_role', role);
        await prefs.setString('email', (user['email'] ?? '').toString());

        // route to correct shell
        if (role == 'merchant') {
          navKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => MerchantBottomnavbar(
                    email: (user['email'] ?? '').toString())),
            (route) => false,
          );
        } else {
          navKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
            (route) => false,
          );
        }
      } else {
        // fallback to customer shell
        navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
          (route) => false,
        );
      }
    } catch (_) {
      // network fail: still send to customer shell; user can refresh later
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
        (route) => false,
      );
    }
  }

  /// Optional: call on logout.
  static Future<void> logout(BuildContext ctx) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('jwt_token');
    await p.remove('token');
    await p.remove('authToken');
    await p.remove('user_role');
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
      (route) => false,
    );
  }

  static bool _isMerchant(Map<String, dynamic> u) {
    final role = (u['role'] ?? u['accountType'] ?? '').toString().toLowerCase();
    final roles = (u['roles'] is List)
        ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final flags = {
      'isMerchant': u['isMerchant'] == true,
      'merchant': u['merchant'] == true,
      'merchantId': (u['merchantId'] ?? '').toString().isNotEmpty,
    };
    return role == 'merchant' ||
        roles.contains('merchant') ||
        flags.values.any((v) => v == true);
  }
}
