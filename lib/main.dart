// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// Deep links
import 'package:app_links/app_links.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// HTTP + prefs
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pages
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/onboarding/presentation/widgets/onboarding_gate.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GeneralPages/profile_from_link_page.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';

import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:vero360_app/app_nav_key.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/active_ride_controller.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_request_overlay.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/reset_password_screen.dart';

// Services
import 'package:vero360_app/features/Auth/AuthServices/auth_guard.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/backend_messaging_cache.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/GernalServices/engagement_notification_service.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/utils/session_local_cache.dart';
import 'package:vero360_app/widgets/vero_launch_splash.dart';

final GlobalKey<NavigatorState> navKey = appNavKey;

bool _isPasswordResetDeepLink(Uri uri) {
  final oobCode = uri.queryParameters['oobCode'];
  if (oobCode == null || oobCode.isEmpty) return false;
  if (uri.scheme == 'vero360' && uri.host == 'reset-password') return true;
  if (uri.queryParameters['mode'] == 'resetPassword') return true;
  if (uri.path.contains('/__/auth/action')) return true;
  return false;
}

void _openPasswordResetFromDeepLink(Uri uri) {
  final oobCode = uri.queryParameters['oobCode'];
  if (oobCode == null || oobCode.isEmpty) return;
  navKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => ResetPasswordScreen(oobCode: oobCode),
    ),
  );
}

/// Root merchant shell: must match [Bottomnavbar] / auth screens (prefs `merchant_service`).
Widget merchantDashboardFromPrefs(String email, SharedPreferences prefs) {
  final displayEmail =
      email.trim().isNotEmpty ? email : (prefs.getString('email') ?? '');
  final key = normalizeMerchantServiceKey(prefs.getString('merchant_service')) ??
      'marketplace';
  return switch (key) {
    'food' => FoodMerchantDashboard(email: displayEmail),
    'accommodation' => AccommodationMerchantDashboard(email: displayEmail),
    'courier' => CourierMerchantDashboard(email: displayEmail),
    _ => MarketplaceMerchantDashboard(
        email: displayEmail,
        onBackToHomeTab: () {},
      ),
  };
}

/// Set in [MyApp] initState; used by [OnboardingGate] to re-run role-based shell redirect.
void Function()? _onOnboardingGateCompletedHook;

// ───────────────────────────────────────────────
//  BACKGROUND MESSAGE HANDLER - must be top-level
// ───────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebaseHealthy(quiet: true);

  final data = message.data;
  if (data['type'] == 'ride_status' && data['rideId'] != null) {
    final rideId = int.tryParse(data['rideId'].toString());
    final status = data['status']?.toString() ?? '';
    if (rideId != null &&
        status.isNotEmpty &&
        status != 'COMPLETED' &&
        status != 'CANCELLED') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_ride_id', rideId);
      await prefs.setString('active_ride_role', 'passenger');
      await prefs.setString('active_ride_status', status);
    }
  }
}

const FirebaseOptions _kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCQ5_4N2J_xwKqmY-lAa8-ifRxovoRTTYk',
  authDomain: 'vero360app-ca423.firebaseapp.com',
  projectId: 'vero360app-ca423',
  storageBucket: 'vero360app-ca423.firebasestorage.app',
  messagingSenderId: '1010595167807',
  appId: '1:1010595167807:android:87af3098cda575fd1dc28a',
);

bool _fcmBackgroundHandlerRegistered = false;
Future<bool>? _firebaseHealInFlight;

/// Modern Firebase self-heal: init / verify / retry without blocking first paint.
Future<bool> _ensureFirebaseHealthy({
  void Function(String msg)? log,
  bool quiet = false,
}) async {
  if (_firebaseHealInFlight != null) return _firebaseHealInFlight!;

  _firebaseHealInFlight = () async {
    void say(String msg) {
      if (!quiet) log?.call(msg);
    }

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (Firebase.apps.isEmpty) {
          say('Firebase init (attempt $attempt/$maxAttempts)…');
          await Firebase.initializeApp(options: _kFirebaseOptions);
        } else {
          say('Firebase already warm ✅');
        }

        // Touch core services to confirm the default app is usable.
        final _ = FirebaseAuth.instance.currentUser;
        Firebase.app();

        if (!_fcmBackgroundHandlerRegistered) {
          FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler,
          );
          _fcmBackgroundHandlerRegistered = true;
        }

        say('Firebase healthy ✅');
        return true;
      } catch (e) {
        say('Firebase heal failed ($attempt): $e');
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 180 * attempt));
        }
      }
    }
    return false;
  }();

  final ok = await _firebaseHealInFlight!;
  // Allow launcher Retry to run a fresh heal after a hard failure.
  if (!ok) _firebaseHealInFlight = null;
  return ok;
}

// ───────────────────────────────────────────────
//  MAIN — paint launcher first, heal Firebase after
// ───────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Low-RAM phones: cap decoded image memory so product grids don't OOM.
  // Default Flutter cache can hold ~100MB+ of full-res bitmaps.
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20; // 40 MB

  // Start Firebase self-heal immediately, but do not block first paint.
  unawaited(_ensureFirebaseHealthy(quiet: true));

  runApp(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) => ColoredBox(
        color: const Color(0xFFFFFBF6),
        child: child ?? const AppBootstrap(),
      ),
      child: const AppBootstrap(),
    ),
  );
}

// ───────────────────────────────────────────────
//  AppBootstrap — launcher + Firebase self-heal
// ───────────────────────────────────────────────
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<_BootState> _bootFuture;
  String _bootTitle = 'Starting…';
  String _bootMessage = 'Opening Vero360…';
  bool _showLauncher = true;
  bool _firebaseNudgeInFlight = false;

  /// Brand flash — keep short so home arrives in ~1s.
  static const _minLauncher = Duration(milliseconds: 450);
  static const _splashBg = Color(0xFFFFFBF6);

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();

    // Defer heavier, non-blocking services until after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(() async {
        try {
          await GoogleMapsConfig.initialize();
        } catch (_) {}
        try {
          await NotificationService.instance.initialize();
          NotificationService.setNavigatorKey(navKey);
        } catch (_) {}
      }());
    });
  }

  Future<_BootState> _boot() async {
    final started = DateTime.now();

    try {
      final prefsWarm = SharedPreferences.getInstance();
      unawaited(Future(() async {
        try {
          await loadDriverStatusFromPrefs();
        } catch (_) {}
      }));

      // Cart / Auth / Firestore need the DEFAULT app. Init is local (fast) —
      // await it here so MyApp never mounts without Firebase. No failure UI.
      await _ensureFirebaseHealthy(quiet: true);
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(options: _kFirebaseOptions);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _bootTitle = 'Almost ready…';
          _bootMessage = 'Loading your home…';
        });
      }

      // Never block homepage on API / messaging.
      unawaited(Future(() async {
        try {
          await ApiConfig.useProd();
        } catch (_) {}
      }));
      unawaited(Future(() async {
        try {
          if (Firebase.apps.isEmpty) return;
          if (FirebaseAuth.instance.currentUser != null) {
            await BackendMessagingCache.initialize();
            await BackendMessagingSocket.connect();
          }
        } catch (_) {}
      }));

      // Resolve shell from cache so MyApp can open home immediately.
      String initialRole = 'customer';
      String email = '';
      var onboardingDone = false;
      Widget? initialShell;
      try {
        final prefs =
            await prefsWarm.timeout(const Duration(milliseconds: 200));
        onboardingDone = prefs.getBool('onboarding_completed_v1') ?? false;
        email = prefs.getString('email') ?? '';
        final role =
            (prefs.getString('user_role') ?? prefs.getString('role') ?? '')
                .toLowerCase()
                .trim();
        if (role == 'merchant' || role == 'driver') {
          initialRole = role;
        }
        if (onboardingDone) {
          if (initialRole == 'merchant') {
            unawaited(hydrateMerchantServiceFromFirestore(prefs));
            initialShell = merchantDashboardFromPrefs(email, prefs);
          } else {
            initialShell = Bottomnavbar(email: email);
          }
        }
      } catch (_) {
        onboardingDone = true;
        initialShell = Bottomnavbar(email: email);
      }

      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minLauncher) {
        await Future<void>.delayed(_minLauncher - elapsed);
      }

      // Last-resort: still no app → keep trying briefly on splash (no red screen).
      if (Firebase.apps.isEmpty) {
        for (var i = 0; i < 3 && Firebase.apps.isEmpty; i++) {
          try {
            await Firebase.initializeApp(options: _kFirebaseOptions);
          } catch (_) {
            await Future<void>.delayed(Duration(milliseconds: 120 * (i + 1)));
          }
        }
      }

      return _BootState(
        clearedOldCache: false,
        onboardingDone: onboardingDone,
        initialRole: initialRole,
        email: email,
        initialShell: initialShell,
      );
    } catch (_) {
      // Still try to stand up Firebase before MyApp (avoids red [core/no-app]).
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: _kFirebaseOptions);
        }
      } catch (_) {}
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minLauncher) {
        await Future<void>.delayed(_minLauncher - elapsed);
      }
      return const _BootState(
        clearedOldCache: false,
        onboardingDone: true,
        initialRole: 'customer',
        email: '',
        initialShell: null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootState>(
      future: _bootFuture,
      builder: (context, snap) {
        final booting = snap.connectionState != ConnectionState.done;
        final boot = snap.data ??
            const _BootState(
              clearedOldCache: false,
              onboardingDone: true,
              initialShell: null,
            );
        // Do not open MyApp until Firebase DEFAULT exists (CartService needs it).
        final firebaseReady = Firebase.apps.isNotEmpty;
        final ready = !booting && firebaseReady;

        if (ready && _showLauncher) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _showLauncher = false);
          });
        }

        // Keep branded splash — never a Firebase failure / retry screen.
        if (_showLauncher || !ready) {
          // If boot finished but Firebase still missing, nudge init once more.
          if (!booting && !firebaseReady && !_firebaseNudgeInFlight) {
            _firebaseNudgeInFlight = true;
            unawaited(() async {
              try {
                await Firebase.initializeApp(options: _kFirebaseOptions);
              } catch (_) {}
              _firebaseNudgeInFlight = false;
              if (mounted) setState(() {});
            }());
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            color: _splashBg,
            theme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: _splashBg,
              colorSchemeSeed: const Color(0xFFFF6B00),
            ),
            home: VeroLaunchSplash(
              title: _bootTitle,
              message: _bootMessage,
              showSpinner: true,
            ),
          );
        }

        return MyApp(
          initialRole: boot.initialRole,
          initialEmail: boot.email,
          onboardingDoneHint: boot.onboardingDone,
          initialShell: boot.initialShell ??
              Bottomnavbar(email: boot.email),
        );
      },
    );
  }
}

class _BootState {
  final bool clearedOldCache;
  final bool onboardingDone;
  final String initialRole;
  final String email;
  final Widget? initialShell;
  const _BootState({
    required this.clearedOldCache,
    this.onboardingDone = false,
    this.initialRole = 'customer',
    this.email = '',
    this.initialShell,
  });
}

/// Back-compat alias used by older call sites / mental model.
typedef SelfHealPage = VeroLaunchSplash;

/// Loads driver prefs locally and triggers a background sync **under** [ProviderScope].
class _DriverStatusBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  const _DriverStatusBootstrap({required this.child});

  @override
  ConsumerState<_DriverStatusBootstrap> createState() =>
      _DriverStatusBootstrapState();
}

class _DriverStatusBootstrapState
    extends ConsumerState<_DriverStatusBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadDriverStatusFromPrefs();
      await ref.read(syncDriverStatusProvider.future);
      await loadDriverStatusFromPrefs();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ----------------- ✅ MAIN APP (your original logic preserved) -----------------
class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.initialRole = 'customer',
    this.initialEmail = '',
    this.onboardingDoneHint = false,
    this.initialShell,
  });

  /// Cached role from bootstrap (`customer` / `merchant` / `driver`).
  final String initialRole;
  final String initialEmail;
  /// When true, [OnboardingGate] skips its prefs round-trip + splash.
  final bool onboardingDoneHint;
  /// Pre-built home shell so we never show a second branded loader.
  final Widget? initialShell;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  /// Empty until first cached-role redirect. Prevents remounting the same shell
  /// mid-session (which blinked Home / disposed merchant dashboards).
  String _currentShell = '';

  bool _showBiometricLock = false;
  /// True after a successful unlock until the user truly backgrounds the app
  /// (not while the system PIN / biometric sheet is open).
  bool _biometricSessionUnlocked = false;
  bool _biometricAuthInProgress = false;
  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();
    // Bootstrap already mounted the right shell — skip remount flash.
    if (widget.onboardingDoneHint && widget.initialShell != null) {
      _currentShell = widget.initialRole == 'merchant'
          ? 'merchant'
          : (widget.initialRole == 'driver' ? 'driver' : 'customer');
    }
    _onOnboardingGateCompletedHook = () {
      if (!mounted) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        unawaited(_fastRedirectFromCache());
      });
    };
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      // Only push when bootstrap could not resolve a shell (e.g. first onboarding).
      if (_currentShell.isEmpty) {
        await _fastRedirectFromCache();
      }
      unawaited(_verifyRoleFromServerInBg());
      unawaited(() async {
        try {
          if (Firebase.apps.isEmpty) return;
          await OrderEscrowService.processDueAutoReleasesForSignedInUser();
        } catch (_) {}
      }());
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _sub = _appLinks.uriLinkStream.listen((uri) {
      if (_isPasswordResetDeepLink(uri)) {
        _openPasswordResetFromDeepLink(uri);
      } else if (uri.scheme == 'vero360' &&
          uri.host == 'users' &&
          uri.path == '/me') {
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

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && _isPasswordResetDeepLink(initial)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openPasswordResetFromDeepLink(initial);
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _lastLifecycleState;
    _lastLifecycleState = state;

    if (state == AppLifecycleState.paused) {
      // Free decoded bitmaps while backgrounded — big win on 2–3GB phones.
      PaintingBinding.instance.imageCache.clear();
      // System PIN/biometric UI also pauses the activity. Do not treat that as
      // "user left the app" or the next resume will lock again after unlock.
      if (!_biometricAuthInProgress && !_showBiometricLock) {
        _biometricSessionUnlocked = false;
      }
      return;
    }

    if (state == AppLifecycleState.resumed &&
        previous == AppLifecycleState.paused) {
      _checkBiometricLockOnResume();
      unawaited(OrderEscrowService.processDueAutoReleasesForSignedInUser());
      unawaited(EngagementNotificationService.instance.maybeSendDailyDigest());
    }
  }

  @override
  void didHaveMemoryPressure() {
    // OS asked us to free RAM — drop image cache immediately.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> _checkBiometricLockOnResume() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) return;
    // Already locked, mid-auth (PIN sheet), or unlocked this session.
    if (_showBiometricLock ||
        _biometricAuthInProgress ||
        _biometricSessionUnlocked) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('pref_biometric_lock') ?? false;
      if (!enabled || !mounted) return;
      if (_showBiometricLock ||
          _biometricAuthInProgress ||
          _biometricSessionUnlocked) {
        return;
      }
      final auth = LocalAuthentication();
      final isSupported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!isSupported && !canCheck) return;
      if (mounted) setState(() => _showBiometricLock = true);
    } catch (_) {}
  }

  void _onBiometricUnlockSuccess() {
    _biometricSessionUnlocked = true;
    _biometricAuthInProgress = false;
    if (mounted) setState(() => _showBiometricLock = false);
  }

  void _onBiometricAuthStarted() {
    _biometricAuthInProgress = true;
  }

  void _onBiometricAuthEnded() {
    _biometricAuthInProgress = false;
  }

  @override
  void dispose() {
    _onOnboardingGateCompletedHook = null;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  // ---------- Shell & role helpers ----------
  Future<void> _fastRedirectFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_completed_v1') ?? false;
    if (!onboardingDone) return;
    final role = (prefs.getString('user_role') ?? prefs.getString('role') ?? '')
        .toLowerCase();
    final email = prefs.getString('email') ?? '';

    // First launch: _currentShell is '' so we push once. Later calls skip when
    // already on the right shell (avoids Home blink / tab reset).
    if (role == 'merchant') {
      if (_currentShell != 'merchant') await _pushMerchant(email);
    } else if (role == 'driver') {
      if (_currentShell != 'driver') _pushDriver(email);
    } else {
      // customer, empty, or unknown — main customer shell
      if (_currentShell != 'customer') _pushCustomer(email);
    }
  }

  Future<void> _verifyRoleFromServerInBg() async {
    final prefs = await SharedPreferences.getInstance();
    final token = RoleSessionService.readToken(prefs);

    if (token == null || token.trim().isEmpty) return;

    final result = await RoleSessionService.syncFromServer(
      prefs: prefs,
      token: token,
    );
    if (result == null) return;
    if (result.isUnauthorized) {
      await _clearAuth(prefs);
      return;
    }

    if (result.isMerchant && _currentShell != 'merchant') {
      await _pushMerchant(result.email);
    } else if (!result.isMerchant &&
        result.isDriver &&
        _currentShell != 'driver') {
      _pushDriver(result.email);
    } else if (!result.isMerchant &&
        !result.isDriver &&
        _currentShell != 'customer') {
      _pushCustomer(result.email);
    }
    await loadDriverStatusFromPrefs();
  }

  Future<void> _clearAuth(SharedPreferences prefs) async {
    await prefs.remove('jwt_token');
    await prefs.remove('token');
    await prefs.remove('authToken');
    await prefs.remove('user_role');
    await prefs.remove('role');
  }

  Future<void> _pushMerchant(String email) async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await hydrateMerchantServiceFromFirestore(prefs);
    if (!mounted) return;
    _currentShell = 'merchant';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => merchantDashboardFromPrefs(email, prefs),
      ),
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

  void _pushDriver(String email) {
    if (!mounted) return;
    _currentShell = 'driver';
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
      child: ActiveRideResumeListener(
        child: _DriverStatusBootstrap(
          child: MaterialApp(
            navigatorKey: appNavKey,
          debugShowCheckedModeBanner: false,
          title: 'Vero360',
          color: const Color(0xFFFFFBF6),
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFFFFBF6),
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
                  _BiometricLockOverlay(
                    onUnlock: _onBiometricUnlockSuccess,
                    onAuthStarted: _onBiometricAuthStarted,
                    onAuthEnded: _onBiometricAuthEnded,
                  ),
                ],
              );
            }
            return content;
          },

          // Bootstrap resolves role → home. Fallback cream only if shell unknown.
          home: OnboardingGate(
            onboardingDoneHint: widget.onboardingDoneHint,
            onCompleted: () => _onOnboardingGateCompletedHook?.call(),
            child: widget.initialShell ??
                const ColoredBox(color: Color(0xFFFFFBF6)),
          ),

          // ✅ restrict named routes too
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/login':
                return MaterialPageRoute(builder: (_) => const LoginScreen());

              case '/signup':
                return MaterialPageRoute(
                  builder: (_) => const RegisterScreen(),
                );

              case '/marketplace':
                return MaterialPageRoute(
                  builder: (_) => OnboardingGate(
                    onboardingDoneHint: true,
                    onCompleted: () => _onOnboardingGateCompletedHook?.call(),
                    child: Bottomnavbar(email: widget.initialEmail),
                  ),
                );

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
      ),
      ),
    );
  }
}

/// Full-screen overlay shown when app lock (Face ID / fingerprint) is enabled and user returns to app.
class _BiometricLockOverlay extends StatefulWidget {
  final VoidCallback onUnlock;
  final VoidCallback onAuthStarted;
  final VoidCallback onAuthEnded;

  const _BiometricLockOverlay({
    required this.onUnlock,
    required this.onAuthStarted,
    required this.onAuthEnded,
  });

  @override
  State<_BiometricLockOverlay> createState() => _BiometricLockOverlayState();
}

class _BiometricLockOverlayState extends State<_BiometricLockOverlay> {
  String _label = 'Unlock';
  bool _authenticating = false;

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    widget.onAuthStarted();
    try {
      final auth = LocalAuthentication();
      final isSupported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      final available = await auth.getAvailableBiometrics();
      if (!isSupported && !canCheck) {
        widget.onAuthEnded();
        if (mounted) {
          setState(() {
            _label = 'Biometrics unavailable';
            _authenticating = false;
          });
        }
        return;
      }
      final isFace = available.contains(BiometricType.face);
      final isFinger = available.contains(BiometricType.fingerprint);
      final reason = isFace && isFinger
          ? 'Unlock Vero360 with Face ID or fingerprint'
          : isFace
              ? 'Unlock Vero360 with Face ID'
              : isFinger
                  ? 'Unlock Vero360 with fingerprint'
                  : 'Unlock Vero360';
      final success = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: true,
          biometricOnly: false,
        ),
      );
      if (success && mounted) {
        widget.onUnlock();
      } else {
        widget.onAuthEnded();
        if (mounted) setState(() => _label = 'Try again');
      }
    } catch (_) {
      widget.onAuthEnded();
      if (mounted) setState(() => _label = 'Try again');
    }
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
  static Future<void> _navigateByRole(
      String email, bool isMerchant, bool isDriver) async {
    final prefs = await SharedPreferences.getInstance();
    if (isMerchant) {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => merchantDashboardFromPrefs(email, prefs),
        ),
        (route) => false,
      );
    } else if (isDriver) {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => Bottomnavbar(email: email)),
        (route) => false,
      );
    } else {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => Bottomnavbar(email: email)),
        (route) => false,
      );
    }
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
      ).timeout(const Duration(seconds: 15));

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
          await persistMerchantServiceFromApi(
            prefs,
            user['merchantService']?.toString() ??
                user['serviceType']?.toString() ??
                user['merchant_service']?.toString(),
          );
        } else if (isDriver) {
          await prefs.setString('user_role', 'driver');
          await prefs.setString('role', 'driver');
        } else {
          await prefs.setString('user_role', 'customer');
          await prefs.setString('role', 'customer');
        }

        await loadDriverStatusFromPrefs();

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
    await p.remove('has_driver_profile');
    resetDriverSessionCache();
    try {
      await SessionLocalCache.clearOnLogout();
    } catch (_) {}

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
