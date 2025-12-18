// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// Deep links
import 'package:app_links/app_links.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// HTTP + prefs
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Pages
import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/cartpage.dart';
import 'package:vero360_app/Pages/profile_from_link_page.dart';
import 'package:vero360_app/Pages/Home/Profilepage.dart';
import 'package:vero360_app/screens/chat_list_page.dart';

import 'package:vero360_app/Pages/MerchantDashboards/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/screens/login_screen.dart';
import 'package:vero360_app/screens/register_screen.dart';

// Services
import 'package:vero360_app/services/auth_guard.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/services/api_config.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Best-effort Firebase init
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCQ5_4N2J_xwKqmY-lAa8-ifRxovoRTTYk",
        authDomain: "vero360app-ca423.firebaseapp.com",
        projectId: "vero360app-ca423",
        storageBucket: "vero360app-ca423.firebasestorage.app",
        messagingSenderId: "1010595167807",
        appId: "1:1010595167807:android:f63d7c7959bdb2891dc28a",
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

  // Which shell we’re currently showing
  String _currentShell = 'customer';

  @override
  void initState() {
    super.initState();
    _initDeepLinks();

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
          MaterialPageRoute(builder: (_) => const ProfileFromLinkPage()),
        );
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
    }
  }

  Future<void> _verifyRoleFromServerInBg() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _readToken(prefs);

    // If no token, still allow app, but customer shell only
    if (token == null || token.trim().isEmpty) return;

    final base = await ApiConfig.readBase();
    try {
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final user = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{});

        await _persistUserToPrefs(prefs, user);

        final merchant = _isMerchant(user);
        if (merchant && _currentShell != 'merchant') {
          _pushMerchant((user['email'] ?? '').toString());
        } else if (!merchant && _currentShell != 'customer') {
          _pushCustomer((user['email'] ?? '').toString());
        }
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        await _clearAuth(prefs);
        // keep customer home (public)
      }
    } catch (_) {
      // network hiccup: keep current shell
    }
  }

  String? _readToken(SharedPreferences p) =>
      p.getString('jwt_token') ?? p.getString('token') ?? p.getString('authToken');

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
    return role == 'merchant' || roles.contains('merchant') || flags.values.any((v) => v == true);
  }

  Future<void> _persistUserToPrefs(SharedPreferences prefs, Map<String, dynamic> u) async {
    String join(String? a, String? b) {
      final parts = [a, b]
          .where((x) => x != null && x!.trim().isNotEmpty)
          .map((x) => x!.trim())
          .toList();
      return parts.isEmpty ? '' : parts.join(' ');
    }

    final name = (u['name'] ?? join(u['firstName'], u['lastName'])).toString();
    final email = (u['email'] ?? u['userEmail'] ?? '').toString();
    final phone = (u['phone'] ?? '').toString();
    final pic = (u['profilepicture'] ?? u['profilePicture'] ?? '').toString();

    await prefs.setString('fullName', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('name', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('email', email);
    await prefs.setString('phone', phone);
    await prefs.setString('profilepicture', pic);

    final normalizedRole = _isMerchant(u) ? 'merchant' : 'customer';
    await prefs.setString('user_role', normalizedRole);
  }

  Future<void> _clearAuth(SharedPreferences prefs) async {
    await prefs.remove('jwt_token');
    await prefs.remove('token');
    await prefs.remove('authToken');
    await prefs.remove('user_role');
    await prefs.remove('role');
  }

  void _pushMerchant(String email) {
    if (!mounted) return;
    _currentShell = 'merchant';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MarketplaceMerchantDashboard(email: email)),
      (_) => false,
    );
  }

  void _pushCustomer(String email) {
    if (!mounted) return;
    _currentShell = 'customer';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => Bottomnavbar(email: email)),
      (_) => false,
    );
  }

  // ---------- App ----------
  @override
  Widget build(BuildContext context) {
    // Use same cart service config as your Bottomnavbar
    final cartSvc = CartService('https://heflexitservice.co.za', apiPrefix: 'vero');

    return MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      title: 'Vero360',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFFF8A00)),

      // ✅ keep public home
      home: const Bottomnavbar(email: ''),

      // ✅ restrict named routes too (cart/messages/dashboard)
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginScreen());

          case '/signup':
            return MaterialPageRoute(builder: (_) => const RegisterScreen());

          case '/marketplace':
            return MaterialPageRoute(builder: (_) => const Bottomnavbar(email: ''));

          case '/cartpage':
            return MaterialPageRoute(
              builder: (_) => AuthGuard(
                featureName: 'Cart',
                child: CartPage(cartService: cartSvc),
              ),
            );

          case '/messages':
            return MaterialPageRoute(
              builder: (_) => const AuthGuard(
                featureName: 'Messages',
                child: ChatListPage(),
              ),
            );

          case '/dashboard':
            return MaterialPageRoute(
              builder: (_) => const AuthGuard(
                featureName: 'Dashboard',
                child: ProfilePage(),
              ),
            );

          default:
            return null;
        }
      },
    );
  }
}

/// -------- Helpers to call from Login / Logout screens ---------------
class AuthFlow {
  static String? _readToken(SharedPreferences p) =>
      p.getString('jwt_token') ?? p.getString('token') ?? p.getString('authToken');

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
    return role == 'merchant' || roles.contains('merchant') || flags.values.any((v) => v == true);
  }

  static Future<void> onLoginSuccess(BuildContext ctx, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);

    final base = await ApiConfig.readBase();
    try {
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );

      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final user = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{});

        final role = _isMerchant(user) ? 'merchant' : 'customer';
        await prefs.setString('user_role', role);
        final email = (user['email'] ?? '').toString();
        await prefs.setString('email', email);

        if (role == 'merchant') {
          navKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => MarketplaceMerchantDashboard(email: email)),
            (_) => false,
          );
        } else {
          navKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => Bottomnavbar(email: email)),
            (_) => false,
          );
        }
      } else {
        navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
          (_) => false,
        );
      }
    } catch (_) {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
        (_) => false,
      );
    }
  }

  static Future<void> logout(BuildContext ctx) async {
    final p = await SharedPreferences.getInstance();

    // clear API tokens
    await p.remove('jwt_token');
    await p.remove('token');
    await p.remove('authToken');
    await p.remove('user_role');
    await p.remove('role');

    // ✅ clear Firebase too (important so AuthGuard blocks properly)
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
      (_) => false,
    );
  }

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    final t = _readToken(p);
    final fb = FirebaseAuth.instance.currentUser;
    return (t != null && t.trim().isNotEmpty) || fb != null;
  }
}
