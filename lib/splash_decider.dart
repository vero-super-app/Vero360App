// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// Deep links (v6+ API: the stream emits initial + subsequent links)
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

  // Initialize Firebase (replace options with your own if needed)
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCWFa4tCHalRUqPkmfxVtrAbcXkC9negA8",
        authDomain: "superapp-c7cdb.firebaseapp.com",
        projectId: "superapp-c7cdb",
        storageBucket: "superapp-c7cdb.appspot.com",
        messagingSenderId: "802147518690",
        appId: "1:802147518690:android:a2d203d3708083dfc8f6bb",
        measurementId: "",
      ),
    );
  } catch (_) {
    // swallow init errors; app can still run
  }

  // Initialize API base once (auto-picks local vs prod; persists)
  await ApiConfig.init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  // Track what shell we think we're on to avoid nav loops
  String _currentShell = 'bottom'; // 'bottom' | 'merchant' | 'login'
  bool _didFastRedirect = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    // Run the role check in the FIRST frame so initialRoute shows instantly.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _fastRedirectFromCache(); // instant, no network
      _verifyRoleFromServerInBg(); // short network check; may correct
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks(); // singleton
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        if (uri != null) _routeFor(uri);
      },
      onError: (_) {},
    );
  }

  void _routeFor(Uri uri) {
    // Handle: vero360://users/me  -> open a page that calls /users/me
    if (uri.scheme == 'vero360' && uri.host == 'users' && uri.path == '/me') {
      navKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ProfileFromLinkPage()),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---- Fast redirect using cached role (no spinner) ----
  Future<void> _fastRedirectFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = (prefs.getString('user_role') ?? '').toLowerCase();
    final email = prefs.getString('email') ?? '';

    if (cachedRole == 'merchant') {
      // Initial route shows Bottomnavbar; replace it immediately with Merchant.
      _pushMerchant(email);
      _didFastRedirect = true;
    } else if (cachedRole == 'customer') {
      // Stay on Bottomnavbar (already initialRoute)
      _currentShell = 'bottom';
    } else {
      // Unknown: if no token, optionally send to login (commented to keep your UX)
      final token = prefs.getString('jwt_token') ??
          prefs.getString('token') ??
          prefs.getString('authToken') ??
          '';
      if (token == '') {
        // _pushLogin();  // enable if you want login-first UX
      }
    }
  }

  // ---- Verify with server quickly; correct shell if needed ----
  Future<void> _verifyRoleFromServerInBg() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        '';

    if (token.isEmpty) return;

    final base = ApiConfig.prod ?? 'https://vero-backend.onrender.com';

    try {
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json'
        },
      ).timeout(const Duration(seconds: 5)); // be snappy

      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final user = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{});

        // Persist normalized fields so profile page sees correct values
        await _persistUserToPrefs(prefs, user);

        final wantMerchant = _isMerchant(user);
        final wantShell = wantMerchant ? 'merchant' : 'bottom';

        if (_currentShell != wantShell) {
          // Correct the shell if cache was wrong or we haven't redirected yet
          if (wantMerchant) {
            _pushMerchant((user['email'] ?? '').toString());
          } else {
            _pushBottom();
          }
        }
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        await _clearAuth(prefs);
        _pushLogin();
      }
    } catch (_) {
      // Offline/DNS: keep whatever we showed from cache
    }
  }

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

    final applicationStatus =
        (u['applicationStatus'] ?? '').toString().toLowerCase();
    final kycStatus = (u['kycStatus'] ?? '').toString().toLowerCase();
    final isVerified =
        (u['isVerified'] == true) || (u['merchantVerified'] == true);

    await prefs.setString('fullName', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('name', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('email', email.isEmpty ? 'No Email' : email);
    await prefs.setString('phone', phone.isEmpty ? 'No Phone' : phone);
    await prefs.setString('profilepicture', pic);
    await prefs.setString('applicationStatus', applicationStatus);
    await prefs.setString('kycStatus', kycStatus);
    await prefs.setBool('merchant_verified', isVerified);

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

  void _pushBottom() {
    if (!mounted) return;
    _currentShell = 'bottom';
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      title: 'Vero360',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFFF8A00),
      ),
      // ✅ Keep your original initial route for instant boot
      initialRoute: '/Bottomnavbar',
      routes: {
        '/Bottomnavbar': (context) => const Bottomnavbar(email: ''),
        '/marketplace': (context) => const Bottomnavbar(email: ''),
        '/signup': (context) => const RegisterScreen(),
        '/login': (context) => const LoginScreen(),
        '/cartpage': (context) => _authGuard(
            context,
            CartPage(
                cartService: CartService('https://vero-backend.onrender.com',
                    apiPrefix: ''))),
      },
    );
  }
}

/// Ensures restricted pages require login (wrap target page in your AuthGuard)
Widget _authGuard(BuildContext context, Widget page) {
  return AuthGuard(child: page);
}
