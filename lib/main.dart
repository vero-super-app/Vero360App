// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show
        kIsWeb,
        defaultTargetPlatform,
        TargetPlatform,
        debugPrint,
        ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// Deep links
import 'package:app_links/app_links.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// HTTP + prefs
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pages
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GeneralPages/profile_from_link_page.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';

import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_dashboard.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_request_overlay.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';

// Services
import 'package:vero360_app/features/Auth/AuthServices/auth_guard.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/messaging_initialization_service.dart';
import 'package:vero360_app/GernalServices/websocket_messaging_service.dart';
import 'package:vero360_app/GernalServices/websocket_manager.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

// ───────────────────────────────────────────────
//  BACKGROUND MESSAGE HANDLER - must be top-level
// ───────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // debugPrint("Background/terminated FCM message: ${message.messageId}");

  // You can add minimal logic here (e.g. update local storage)
  // Full display logic is already in NotificationService
}

// ───────────────────────────────────────────────
//  MAIN
// ───────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Keep only absolutely critical init work here so the first frame appears fast.
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
    // debugPrint("Firebase initialized ✅");

    // Register background handler FIRST (important for FCM)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    // debugPrint("Firebase init error: $e");
  }

  runApp(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) => child ?? const AppBootstrap(),
      child: const AppBootstrap(),
    ),
  );
}

// ───────────────────────────────────────────────
//  AppBootstrap (self-healing bootstrap) - unchanged
// ───────────────────────────────────────────────
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<_BootState> _bootFuture;

  final ValueNotifier<List<String>> _logs =
      ValueNotifier<List<String>>(<String>[]);
  bool _goMain = false;
  bool _scheduled = false;

  void _log(String msg) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    final next = List<String>.from(_logs.value)..add("[$t] $msg");
    _logs.value = next.length > 150 ? next.sublist(next.length - 150) : next;
  }

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();

    // Defer heavier, non-blocking services until after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Google Maps config (reads .env, sets up API keys). Safe to skip if offline.
      try {
        await GoogleMapsConfig.initialize();
      } catch (e) {
        // debugPrint("GoogleMapsConfig init warning (offline?): $e");
      }

      // Push notifications (channels, permissions, listeners)
      try {
        await NotificationService.instance.initialize();
        NotificationService.setNavigatorKey(navKey);
        // debugPrint("NotificationService initialized ✅");
      } catch (e) {
        // debugPrint("NotificationService init error: $e");
      }
    });
  }

  Future<_BootState> _boot() async {
    bool firebaseOk = false;
    bool clearedOldCache = false;

    _log("Starting Vero360App…");
    _log("Firebase already initialized in main()");

    firebaseOk = true; // since we did it in main()

    // Keep boot work as light as possible so we hit the home UI quickly.
    // _log("Configuring API…");
    try {
      await ApiConfig.useProd();
      // _log("API config OK ✅");
    } catch (e) {
      // If this fails (e.g., no internet), continue in a degraded/offline mode.
      // _log("API config warning (using offline/defaults): $e");
    }

    // Run heavier messaging initialization in the background so it
    // does not block the user from seeing the home screen.
    _log("Scheduling messaging services init in background…");
    unawaited(Future(() async {
      try {
        await MessagingInitializationService.initialize();
        // _log("Messaging services initialized ✅");
      } catch (e) {
        // _log("Messaging init warning: $e");
      }
    }));

    // _log("Launch ready 🚀");

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
              // logs: _logs,
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
              // logs: _logs,
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
              // logs: _logs,
            ),
          );
        }

        return const _RideSharePreloader(child: MyApp());
      },
    );
  }
}

class _BootState {
  final bool firebaseOk;
  final bool clearedOldCache;
  const _BootState({required this.firebaseOk, required this.clearedOldCache});
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

/// ✅ Logo mark that starts small then scales up (modern feel)
class AnimatedLogoMark extends StatefulWidget {
  const AnimatedLogoMark({super.key, this.size = 30});

  final double size;

  @override
  State<AnimatedLogoMark> createState() => _AnimatedLogoMarkState();
}

class _AnimatedLogoMarkState extends State<AnimatedLogoMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack, // subtle overshoot
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    // small delay feels more premium
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Image.asset(
          'assets/logo_mark.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _SelfHealPageState extends State<SelfHealPage>
    with SingleTickerProviderStateMixin {
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

    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
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
                                // ✅ replaced icon with animated logo
                                AnimatedLogoMark(size: 30),
                                SizedBox(width: 10),
                                Text(
                                  "Vero360App",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
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
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        _slogans[_sloganIndex],
                        key: ValueKey(_sloganIndex),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
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
                    if (!widget.showSpinner &&
                        widget.actionLabel != null &&
                        widget.onAction != null)
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
                        // (keep blank if you want hidden button)
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
                            border: Border.all(
                              color: Colors.black.withOpacity(0.06),
                            ),
                          ),
                          child: ValueListenableBuilder<List<String>>(
                            valueListenable: widget.logs!,
                            builder: (_, lines, __) {
                              final text = lines.isEmpty
                                  ? "No logs yet…"
                                  : lines.join("\n");
                              return SingleChildScrollView(
                                controller: _scroll,
                                child: SelectableText(
                                  text,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
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

/// ====== RIDE SHARE DATA PRELOADER ======
/// Loads driver status from local cache on app start
class _RideSharePreloader extends ConsumerWidget {
  final Widget child;
  const _RideSharePreloader({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Load driver status from SharedPreferences (local, no network call)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadDriverStatusFromPrefs();

      // Optional: Sync with backend in background (fire and forget)
      Future.delayed(const Duration(seconds: 2), () {
        ref.read(syncDriverStatusProvider);
      });
    });

    return child;
  }
}

/// ----------------- ✅ MAIN APP (your original logic preserved) -----------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  // Which shell we’re currently showing
  String _currentShell = 'customer';

  bool _showBiometricLock = false;
  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      } else if (uri.scheme == 'vero360' && uri.host == 'payment-complete') {
        // PayChangu redirects here after payment – go to My Orders; keep root so back stays in app
        navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OrdersPage()),
          (route) => route.isFirst,
        );
      }
    }, onError: (_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasInBackground = _lastLifecycleState == AppLifecycleState.paused ||
        _lastLifecycleState == AppLifecycleState.inactive;
    _lastLifecycleState = state;
    if (state == AppLifecycleState.resumed && wasInBackground) {
      _checkBiometricLockOnResume();
    }
  }

  Future<void> _checkBiometricLockOnResume() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('pref_biometric_lock') ?? false;
      if (!enabled || !mounted) return;
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      final hasBiometrics = await auth.getAvailableBiometrics();
      if (!canCheck || hasBiometrics.isEmpty) return;
      if (mounted) setState(() => _showBiometricLock = true);
    } catch (_) {}
  }

  void _onBiometricUnlockSuccess() {
    if (mounted) setState(() => _showBiometricLock = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    } else if (role == 'driver') {
      _pushDriver();
    } else if (role == 'customer') {
      _pushCustomer(email);
    }
  }

  void _pushDriver() {
    if (!mounted) return;
    _currentShell = 'driver';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DriverDashboard()),
      (route) => false,
    );
  }

  /// Fix emulator localhost:
  /// Android emulator: 127.0.0.1 = emulator itself. Use 10.0.2.2 for host machine.
  String _fixLocalhostIfNeeded(String base) {
    if (kIsWeb) return base;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return base.replaceFirst(
          'localhost', 'https://vero-backend-2.onrender.com');
    }
    return base;
  }

  Future<void> _verifyRoleFromServerInBg() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _readToken(prefs);

    if (token == null || token.trim().isEmpty) return;

    try {
      final resp = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json'
        },
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        final user = (decoded is Map && decoded['data'] is Map)
            ? Map<String, dynamic>.from(decoded['data'])
            : (decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{});

        final backendRole = (user['role'] ?? '').toString().toLowerCase();
        final cachedRole = (prefs.getString('user_role') ?? '').toLowerCase();

        // Case 1: cached role says driver/merchant but backend says customer
        // -> re-sync cached role to backend
        if (cachedRole.isNotEmpty &&
            cachedRole != 'customer' &&
            backendRole == 'customer') {
          await _resyncRoleToBackend(prefs, token, cachedRole);
          return;
        }

        // Case 2: both cached and backend say customer, but Firestore
        // (the registration source of truth) says driver/merchant.
        // This happens when SharedPreferences was overwritten by a previous
        // backend fetch before the re-sync could fix it.
        if (backendRole == 'customer') {
          final firestoreRole = await _getRoleFromFirestore();
          if (firestoreRole != null &&
              firestoreRole != 'customer' &&
              firestoreRole != backendRole) {
            // debugPrint(
            //     '⚠️ Firestore says "$firestoreRole" but backend says "$backendRole". Re-syncing…');
            await prefs.setString('user_role', firestoreRole);
            await prefs.setString('role', firestoreRole);
            await _resyncRoleToBackend(prefs, token, firestoreRole);
            return;
          }
        }

        await _persistUserToPrefs(prefs, user);

        final merchant = _isMerchant(user);
        final driver = _isDriver(user);
        
        if (merchant && _currentShell != 'merchant') {
          _pushMerchant((user['email'] ?? '').toString());
        } else if (!merchant && driver && _currentShell != 'driver') {
          _pushDriver();
        } else if (!merchant && !driver && _currentShell != 'customer') {
          _pushCustomer((user['email'] ?? '').toString());
        }
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        await _clearAuth(prefs);
      }
    } catch (_) {
      // network hiccup: keep current shell
    }
  }

  /// Read the user's role from Firestore (registration source of truth).
  Future<String?> _getRoleFromFirestore() async {
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) return null;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(fbUser.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['role'] ?? '').toString().toLowerCase();
      }
    } catch (_) {}
    return null;
  }

  /// Backend has the wrong role (e.g. 'customer' when it should be 'driver').
  /// Send PUT /users/me to correct it, then re-verify.
  Future<void> _resyncRoleToBackend(
      SharedPreferences prefs, String token, String correctRole) async {
    try {
      final body = json.encode({'role': correctRole});
      final putResp = await http.put(
        ApiConfig.endpoint('/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 6));

      if (putResp.statusCode >= 200 && putResp.statusCode < 300) {
        debugPrint('✅ Re-synced role to backend: $correctRole');
        // Re-read the updated user from backend
        final getResp = await http.get(
          ApiConfig.endpoint('/users/me'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 6));
        if (getResp.statusCode == 200) {
          final decoded = json.decode(getResp.body);
          final user = (decoded is Map && decoded['data'] is Map)
              ? Map<String, dynamic>.from(decoded['data'])
              : (decoded is Map
                  ? Map<String, dynamic>.from(decoded)
                  : <String, dynamic>{});
          await _persistUserToPrefs(prefs, user);

          final merchant = _isMerchant(user);
          final driver = _isDriver(user);
          if (merchant && _currentShell != 'merchant') {
            _pushMerchant((user['email'] ?? '').toString());
          } else if (!merchant && driver && _currentShell != 'driver') {
            _pushDriver();
          } else if (!merchant && !driver && _currentShell != 'customer') {
            _pushCustomer((user['email'] ?? '').toString());
          }
        }
      }
    } catch (e) {
      // debugPrint('⚠️ Role re-sync failed: $e');
    }
  }

  String? _readToken(SharedPreferences p) =>
      p.getString('jwt_token') ??
      p.getString('token') ??
      p.getString('authToken');

  bool _isMerchant(Map<String, dynamic> u) => RoleHelper.isMerchant(u);

  bool _isDriver(Map<String, dynamic> u) => RoleHelper.isDriver(u);

  Future<void> _persistUserToPrefs(
      SharedPreferences prefs, Map<String, dynamic> u) async {
    String join(String? a, String? b) {
      final parts = [a, b]
          .where((x) => x != null && x.trim().isNotEmpty)
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

    // Determine role with proper priority: merchant > driver > customer
    // Keep both 'role' and 'user_role' in sync so BottomNavbar and others stay correct after hot restart.
    bool isMerchant = _isMerchant(u);
    bool isDriver = !isMerchant && _isDriver(u);
    
    if (isMerchant) {
      await prefs.setString('user_role', 'merchant');
      await prefs.setString('role', 'merchant');
    } else if (isDriver) {
      await prefs.setString('user_role', 'driver');
      await prefs.setString('role', 'driver');
    } else {
      await prefs.setString('user_role', 'customer');
      await prefs.setString('role', 'customer');
    }
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
      MaterialPageRoute(
          builder: (_) => MarketplaceMerchantDashboard(
                email: email,
                onBackToHomeTab: () {},
              )),
      (route) => false,
    );
  }

  void _pushCustomer(String email) {
    if (!mounted) return;
    _currentShell = 'customer';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => Bottomnavbar(email: email)),
      (route) => false,
    );
  }

  // ---------- App ----------
  @override
  Widget build(BuildContext context) {
    // ✅ Use CartService singleton from provider
    final cartSvc = CartServiceProvider.getInstance();

    return ProviderScope(
      child: MaterialApp(
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        title: 'Vero360',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFFF8A00),
        ),

        // ✅ Wrap app shell with RideRequestOverlay; show biometric lock when enabled and returning to app
        builder: (context, child) {
          Widget content = RideRequestOverlay(
            child: child ?? const SizedBox.shrink(),
          );
          if (_showBiometricLock) {
            content = Stack(
              children: [
                content,
                _BiometricLockOverlay(onUnlock: _onBiometricUnlockSuccess),
              ],
            );
          }
          return content;
        },

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
              return MaterialPageRoute(
                  builder: (_) => const Bottomnavbar(email: ''));

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
      ),
    );
  }
}

/// Full-screen overlay shown when app lock (Face ID / fingerprint) is enabled and user returns to app.
class _BiometricLockOverlay extends StatefulWidget {
  final VoidCallback onUnlock;

  const _BiometricLockOverlay({required this.onUnlock});

  @override
  State<_BiometricLockOverlay> createState() => _BiometricLockOverlayState();
}

class _BiometricLockOverlayState extends State<_BiometricLockOverlay> {
  String _label = 'Unlock';
  bool _authenticating = false;

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    try {
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      final available = await auth.getAvailableBiometrics();
      if (!canCheck || available.isEmpty) {
        if (mounted) setState(() => _authenticating = false);
        return;
      }
      final isFace = available.contains(BiometricType.face);
      final isFinger = available.contains(BiometricType.fingerprint);
      final reason = isFace && isFinger
          ? 'Unlock Vero360 with Face ID or fingerprint'
          : isFace
              ? 'Unlock Vero360 with Face ID'
              : 'Unlock Vero360 with fingerprint';
      final success = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (success && mounted) widget.onUnlock();
    } catch (_) {}
    if (mounted) setState(() => _authenticating = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'App locked',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use Face ID or fingerprint to unlock',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _authenticating ? null : _authenticate,
                  icon: _authenticating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(_authenticating ? 'Checking…' : _label),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
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

/// -------- Helpers to call from Login / Logout screens ---------------
class AuthFlow {
  static String? _readToken(SharedPreferences p) =>
      p.getString('jwt_token') ??
      p.getString('token') ??
      p.getString('authToken');

  // Extract common nav logic
  static Future<void> _navigateByRole(String email, bool isMerchant, bool isDriver) async {
    if (isMerchant) {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => MarketplaceMerchantDashboard(
                  email: email,
                  onBackToHomeTab: () {},
                )),
        (route) => false,
      );
    } else if (isDriver) {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverDashboard()),
        (route) => false,
      );
    } else {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => Bottomnavbar(email: email)),
        (route) => false,
      );
    }
  }

  static String _fixLocalhostIfNeeded(String base) {
    if (kIsWeb) return base;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return base.replaceFirst(
          'localhost', 'https://vero-backend-2.onrender.com');
    }
    return base;
  }

  static Future<void> onLoginSuccess(BuildContext ctx, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);

    try {
      final resp = await http.get(
        ApiConfig.endpoint('/users/me'),
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

        final email = (user['email'] ?? '').toString();
        await prefs.setString('email', email);

        // Determine role (priority: merchant > driver > customer)
        final isMerchant = RoleHelper.isMerchant(user);
        final isDriver = !isMerchant && RoleHelper.isDriver(user);

        // Persist role to preferences
        if (isMerchant) {
          await prefs.setString('user_role', 'merchant');
          await prefs.setString('role', 'merchant');
        } else if (isDriver) {
          await prefs.setString('user_role', 'driver');
          await prefs.setString('role', 'driver');
        } else {
          await prefs.setString('user_role', 'customer');
          await prefs.setString('role', 'customer');
        }

        // debugPrint("✅ Login: email=$email, role=${isMerchant ? 'merchant' : (isDriver ? 'driver' : 'customer')}");

        // Navigate based on role
        await _navigateByRole(email, isMerchant, isDriver);
      } else {
        navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
          (route) => false,
        );
      }
    } catch (e) {
      // debugPrint("❌ onLoginSuccess error: $e");
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
        (route) => false,
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
      (route) => false,
    );
  }

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    final t = _readToken(p);
    final fb = FirebaseAuth.instance.currentUser;
    return (t != null && t.trim().isNotEmpty) || fb != null;
  }

}
