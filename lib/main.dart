// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';


// Deep links
import 'package:app_links/app_links.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  runApp(const AppBootstrap());
}

/// ----------------- ✅ SELF-HEAL BOOTSTRAP (NO nested MaterialApp navigation) -----------------
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<_BootState> _bootFuture;

  final ValueNotifier<List<String>> _logs = ValueNotifier<List<String>>(<String>[]);
  bool _goMain = false;
  bool _scheduled = false;

  void _log(String msg) {
    final t = DateTime.now().toIso8601String().substring(11, 19); // HH:mm:ss
    final next = List<String>.from(_logs.value)..add("[$t] $msg");
    _logs.value = next.length > 150 ? next.sublist(next.length - 150) : next;
  }

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();
  }

  Future<_BootState> _boot() async {
    bool firebaseOk = false;
    bool clearedOldCache = false;

    _log("Starting Vero360App…");
    _log("Initializing Firebase…");

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
      firebaseOk = true;
      _log("Firebase OK ✅");
    } catch (e) {
      _log("Firebase init failed (continuing): $e");
    }

    if (firebaseOk) {
      _log("Checking local Firestore cache…");
      clearedOldCache = await FirestoreSelfHeal.configureSafeMode(
        disablePersistence: true, // ✅ prevents SQLite CursorWindow crash
        clearOldPersistenceOnce: true, // ✅ clears corrupted cache once
        log: _log,
      );
      _log("Firestore offline cache: OFF (safe mode)");
    }

    _log("Configuring API…");
    await ApiConfig.useProd();
    _log("API config OK ✅");
    _log("Launch ready 🚀");

    return _BootState(firebaseOk: firebaseOk, clearedOldCache: clearedOldCache);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootState>(
      future: _bootFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SelfHealPage(
              title: 'Starting…',
              message: 'Preparing and optimizing your app.',
              showSpinner: true,
              logs: _logs,
            ),
          );
        }

        if (snap.hasError || !snap.hasData) {
          _log("Boot failed: ${snap.error}");
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SelfHealPage(
              title: 'Could not start',
              message: 'Tap retry to start again.',
              showSpinner: false,
              logs: _logs,
              actionLabel: 'Retry',
              onAction: () {
                setState(() {
                  _goMain = false;
                  _scheduled = false;
                  _bootFuture = _boot();
                });
              },
            ),
          );
        }

        final state = snap.data!;

        // ✅ show repair message briefly, then rebuild into MyApp (no navigation)
        if (state.clearedOldCache && !_goMain) {
          if (!_scheduled) {
            _scheduled = true;
            Future.delayed(const Duration(milliseconds: 1100), () {
              if (!mounted) return;
              setState(() => _goMain = true);
            });
          }

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SelfHealPage(
              title: 'Repair completed',
              message: 'We repaired local data to prevent crashes. Launching…',
              showSpinner: true,
              logs: _logs,
            ),
          );
        }

        // ✅ main app
        return const MyApp();
      },
    );
  }
}

class _BootState {
  final bool firebaseOk;
  final bool clearedOldCache;
  const _BootState({required this.firebaseOk, required this.clearedOldCache});
}

/// ----------------- ✅ FIRESTORE SELF-HEAL -----------------
class FirestoreSelfHeal {
  static const _clearedKey = 'fs_cleared_persistence_v1';

  static Future<bool> configureSafeMode({
    required bool disablePersistence,
    required bool clearOldPersistenceOnce,
    void Function(String msg)? log,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    bool didClear = false;

    if (clearOldPersistenceOnce && !(prefs.getBool(_clearedKey) ?? false)) {
      log?.call("First run repair: terminating Firestore…");
      try {
        await FirebaseFirestore.instance.terminate();
        log?.call("Firestore terminated ✅");
      } catch (e) {
        log?.call("Terminate skipped: $e");
      }

      log?.call("Clearing Firestore local persistence…");
      try {
        await FirebaseFirestore.instance.clearPersistence();
        didClear = true;
        log?.call("Local persistence cleared ✅");
      } catch (e) {
        log?.call("Clear persistence failed (continuing): $e");
      }

      await prefs.setBool(_clearedKey, true);
      log?.call("Repair flag saved ✅");
    } else {
      log?.call("No repair needed (already repaired before).");
    }

    // Apply settings BEFORE any Firestore usage elsewhere
    try {
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: !disablePersistence,
      );
      log?.call("Firestore settings applied ✅");
    } catch (e) {
      log?.call("Failed to apply Firestore settings: $e");
    }

    return didClear;
  }
}

/// ----------------- ✅ BRANDED HEALING PAGE (motion + log) -----------------
class SelfHealPage extends StatefulWidget {
  final String title;
  final String message;
  final bool showSpinner;

  final ValueListenable<List<String>>? logs;

  final String? actionLabel;
  final VoidCallback? onAction;

  const SelfHealPage({
    super.key,
    required this.title,
    required this.message,
    required this.showSpinner,
    this.logs,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<SelfHealPage> createState() => _SelfHealPageState();
}

class _SelfHealPageState extends State<SelfHealPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _pulse;
  final ScrollController _scroll = ScrollController();

  final _slogans = const [
    "Buy anything, anytime",
    "Fast • Reliable • Local",
    "Vero360App",
  ];
  int _sloganIndex = 0;
  Timer? _sloganTimer;
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _c, curve: Curves.easeInOut);

    _sloganTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _sloganIndex = (_sloganIndex + 1) % _slogans.length);
    });

    widget.logs?.addListener(_autoScrollLogs);
  }

  void _autoScrollLogs() {
    if (!_showLogs) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.logs?.removeListener(_autoScrollLogs);
    _sloganTimer?.cancel();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFF3E6),
          Color(0xFFFFFFFF),
        ],
      ),
    );

    return Scaffold(
      body: Container(
        decoration: bg,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) {
                        final s = 1.0 + (_pulse.value * 0.06);
                        return Transform.scale(
                          scale: s,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.shopping_bag_outlined, size: 30, color: Color(0xFFFF8A00)),
                                SizedBox(width: 10),
                                Text(
                                  "Vero360App",
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _slogans[_sloganIndex],
                        key: ValueKey(_sloganIndex),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),

                    const SizedBox(height: 16),

                    if (widget.showSpinner)
                      const SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),

                    if (!widget.showSpinner && widget.actionLabel != null && widget.onAction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: widget.onAction,
                            child: Text(widget.actionLabel!),
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    if (widget.logs != null)
                      TextButton(
                        onPressed: () => setState(() => _showLogs = !_showLogs),
                        child: Text(_showLogs ? "" : ""),
                      ),

                    if (_showLogs && widget.logs != null)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black.withOpacity(0.06)),
                          ),
                          child: ValueListenableBuilder<List<String>>(
                            valueListenable: widget.logs!,
                            builder: (_, lines, __) {
                              final text = lines.isEmpty ? "No logs yet…" : lines.join("\n");
                              return SingleChildScrollView(
                                controller: _scroll,
                                child: SelectableText(
                                  text,
                                  style: const TextStyle(fontSize: 12, height: 1.25),
                                ),
                              );
                            },
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

/// ----------------- ✅ MAIN APP (your original logic preserved) -----------------
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

  /// Fix emulator localhost:
  /// Android emulator: 127.0.0.1 = emulator itself. Use 10.0.2.2 for host machine.
  String _fixLocalhostIfNeeded(String base) {
    if (kIsWeb) return base;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return base.replaceFirst('https://heflexitservice.co.za', 'https://heflexitservice.co.za').replaceFirst('localhost', 'https://heflexitservice.co.za');
    }
    return base;
  }

  Future<void> _verifyRoleFromServerInBg() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _readToken(prefs);

    if (token == null || token.trim().isEmpty) return;

    var base = await ApiConfig.readBase();
    base = _fixLocalhostIfNeeded(base);

    try {
      final resp = await http
          .get(
            Uri.parse('$base/users/me'),
            headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));

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
    // Use same cart service config as your Bottomnavbar (kept)
    final cartSvc = CartService('https://heflexitservice.co.za', apiPrefix: 'vero');

    return MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      title: 'Vero360',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFFF8A00)),

      // ✅ keep public home
      home: const Bottomnavbar(email: ''),

      // ✅ restrict named routes too
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

  static String _fixLocalhostIfNeeded(String base) {
    if (kIsWeb) return base;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return base.replaceFirst('https://heflexitservice.co.za', 'https://heflexitservice.co.za').replaceFirst('localhost', 'https://heflexitservice.co.za');
    }
    return base;
  }

  static Future<void> onLoginSuccess(BuildContext ctx, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);

    var base = await ApiConfig.readBase();
    base = _fixLocalhostIfNeeded(base);

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
    } catch (e) {
      debugPrint("onLoginSuccess error: $e");
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
        (_) => false,
      );
    }
  }

  static Future<void> logout(BuildContext ctx) async {
    final p = await SharedPreferences.getInstance();

    await p.remove('jwt_token');
    await p.remove('token');
    await p.remove('authToken');
    await p.remove('user_role');
    await p.remove('role');

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
