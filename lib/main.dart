// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, kReleaseMode, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// Deep links
import 'package:app_links/app_links.dart';

// Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vero360_app/native/local_notifications.dart' as local_notif;

// HTTP + prefs
import 'package:http/http.dart' as http;
import 'package:vero360_app/native/biometrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pages
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Marketplace/presentation/widgets/widgets/onboarding_gate.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GeneralPages/profile_from_link_page.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';

import 'package:vero360_app/features/Accomodation/AccomodationModel/accommodation_share_link.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_deep_link.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_share_link.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/food_share_navigation.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace_share_navigation.dart';
import 'package:vero360_app/features/Restraurants/Models/food_share_link.dart';
import 'package:vero360_app/GernalServices/merchant_identity.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/app_nav_key.dart';
import 'package:vero360_app/app_shell_coordinator.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/active_ride_controller.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_request_overlay.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_alert_notifications.dart';
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
import 'package:vero360_app/GernalServices/vero_rewards_service.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vero360_app/native/android_maps.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/utils/app_version_info.dart';
import 'package:vero360_app/utils/low_ram_android.dart';
import 'package:vero360_app/utils/session_local_cache.dart';
import 'package:vero360_app/utils/firebase_bootstrap.dart';
import 'package:vero360_app/widgets/vero_launch_splash.dart';

final GlobalKey<NavigatorState> navKey = appNavKey;

/// Do NOT wrap the whole app in a reduced [MediaQuery.devicePixelRatio].
/// That breaks Google Maps / other Android platform views (blank map tiles).
/// Image-cache caps in [main] already protect low-RAM GPUs.
Widget _androidGpuSoftened(BuildContext context, Widget? child) {
  return child ?? const SizedBox.shrink();
}

Future<void> _configureAndroidGoogleMaps() => configureAndroidGoogleMaps();

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

/// Root merchant shell: one [Bottomnavbar], Dashboard tab = vertical UI.
Widget merchantDashboardFromPrefs(String email, SharedPreferences prefs) {
  final displayEmail =
      email.trim().isNotEmpty ? email : (prefs.getString('email') ?? '');
  return Bottomnavbar(email: displayEmail, initialIndex: 0);
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

  // Driver ride offer: stash payload, then raise a full-screen Accept popup
  // (data-only FCM — OS does not show a tray notification on Android).
  if (data['type'] == 'new_ride' && data['rideId'] != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pending_driver_ride_offer',
        jsonEncode(Map<String, dynamic>.from(data)),
      );
    } catch (_) {}

    if (message.notification == null) {
      try {
        final plugin = local_notif.FlutterLocalNotificationsPlugin();
        const android =
            local_notif.AndroidInitializationSettings('@mipmap/ic_launcher');
        await plugin.initialize(
          const local_notif.InitializationSettings(android: android),
        );
        await DriverRideAlertNotifications.showIncomingOffer(
          plugin: plugin,
          data: Map<String, dynamic>.from(data),
          fullScreen: true,
        );
      } catch (_) {}
    }
  }

  // Chat message: show a tray notification when payload is data-only
  // (notification+data is already displayed by the OS while killed/backgrounded).
  final chatType = data['type']?.toString();
  if ((chatType == 'new_message' || chatType == 'chat_message') &&
      message.notification == null) {
    try {
      final plugin = local_notif.FlutterLocalNotificationsPlugin();
      const android =
          local_notif.AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(
        const local_notif.InitializationSettings(android: android),
      );
      const channel = local_notif.AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'Chat and alerts',
        importance: local_notif.Importance.high,
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              local_notif.AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      final title = data['title']?.toString() ?? 'New message';
      final body = data['body']?.toString() ?? 'Sent you a message';
      final chatId = data['chatId']?.toString() ?? '';
      await plugin.show(
        chatId.isNotEmpty ? chatId.hashCode.abs() : title.hashCode.abs(),
        title,
        body,
        local_notif.NotificationDetails(
          android: local_notif.AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: local_notif.Importance.high,
            priority: local_notif.Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: jsonEncode(Map<String, dynamic>.from(data)),
      );
    } catch (_) {}
  }
}

FirebaseOptions get _kFirebaseOptions => kFirebaseOptions;

bool _fcmBackgroundHandlerRegistered = false;
Future<bool>? _firebaseHealInFlight;

/// Modern Firebase self-heal: init / verify / retry without blocking first paint.
///
/// Each attempt is timed out so a hung native init cannot stall App Store launch
/// (Guideline 2.1 — indefinite splash on iPad / cold start).
Future<bool> _ensureFirebaseHealthy({
  void Function(String msg)? log,
  bool quiet = false,
  Duration attemptTimeout = const Duration(seconds: 4),
}) async {
  if (_firebaseHealInFlight != null) return _firebaseHealInFlight!;

  _firebaseHealInFlight = () async {
    void say(String msg) {
      if (!quiet) log?.call(msg);
    }

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final ok = await ensureFirebaseApp(maxAttempts: 1)
            .timeout(attemptTimeout, onTimeout: () => false);
        if (!ok && Firebase.apps.isEmpty) {
          say('Firebase init (attempt $attempt/$maxAttempts)…');
          await Firebase.initializeApp(options: _kFirebaseOptions)
              .timeout(attemptTimeout);
        } else {
          say('Firebase already warm ✅');
        }

        // Touch core services to confirm the default app is usable.
        final _ = FirebaseAuth.instance.currentUser;
        Firebase.app();

        if (!_fcmBackgroundHandlerRegistered && !kIsWeb) {
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
bool _isFirebaseNoApp(Object error) {
  final msg = error.toString();
  return msg.contains('core/no-app') || msg.contains('No Firebase App');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    if (_isFirebaseNoApp(details.exception)) return;
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (_isFirebaseNoApp(error)) return true;
    return false;
  };

  // Android must have a DEFAULT app before Auth/Firestore widgets.
  // iPadOS can stall native init — never block first paint there.
  final isCupertino = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  if (isCupertino) {
    unawaited(ensureFirebaseApp(
      maxAttempts: 2,
      attemptTimeout: const Duration(seconds: 2),
    ));
  } else {
    try {
      await ensureFirebaseApp(
        maxAttempts: 2,
        attemptTimeout: const Duration(seconds: 2),
      ).timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {}
  }

  unawaited(AppVersionInfo.ensureLoaded());
  // Draw behind the system bars. Flutter then reports the insets so screens
  // can pad content. Bar colors are left unset; Android 15 ignores them.
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
        .timeout(const Duration(milliseconds: 400));
  } catch (_) {}

  // Release builds must not echo debug logs (PII, tokens, session JSON) to logcat.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Cap decoded-image cache — Redmi 8A / 2GB Adreno dies on GPU texture OOM.
  if (LowRamAndroid.isAndroid) {
    PaintingBinding.instance.imageCache.maximumSize = LowRamAndroid.imageCacheCount;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        LowRamAndroid.imageCacheBytes;
  } else {
    PaintingBinding.instance.imageCache.maximumSize = 60;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
  }

  // Must run before any GoogleMap widget is created.
  await _configureAndroidGoogleMaps();
  unawaited(GoogleMapsConfig.initialize());

  void launchApp() {
    // Cap decoded-image cache — Redmi 8A / 2GB Adreno dies on GPU texture OOM.
    if (LowRamAndroid.isAndroid) {
      PaintingBinding.instance.imageCache.maximumSize =
          LowRamAndroid.imageCacheCount;
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          LowRamAndroid.imageCacheBytes;
    } else {
      PaintingBinding.instance.imageCache.maximumSize = 60;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
    }

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

  if (kReleaseMode) {
    runZonedGuarded(
      launchApp,
      (error, stack) {
        if (_isFirebaseNoApp(error)) return;
        FlutterError.presentError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, ____) {},
      ),
    );
  } else {
    launchApp();
  }
}

// Icon brightness only. Bar colors call Window.setStatusBarColor, which
// Android 15 deprecates. AppBar uses this instead of painting a bar color.
const SystemUiOverlayStyle _kEdgeToEdgeOverlay = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.dark,
);

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
  bool _bootDeadlinePassed = false;
  Timer? _bootDeadlineTimer;

  /// Brand flash — keep short so home arrives in ~1s.
  static const _minLauncher = Duration(milliseconds: 400);
  /// Hard ceiling so App Review / iPad cold start never sits on splash forever.
  static const _bootDeadline = Duration(seconds: 3);
  static const _splashBg = Color(0xFFFFF8F2);

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();
    _bootDeadlineTimer = Timer(_bootDeadline, () {
      if (!mounted || _bootDeadlinePassed) return;
      setState(() => _bootDeadlinePassed = true);
      // Keep healing in background; UI must fail-open past splash.
      unawaited(_ensureFirebaseHealthy(quiet: true));
    });

    unawaited(GoogleMapsConfig.initialize());

    // Register FCM background handler as soon as Firebase is usable.
    // Must happen before process can receive background messages.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(() async {
        try {
          await _ensureFirebaseHealthy(quiet: true)
              .timeout(const Duration(seconds: 6), onTimeout: () => false);
          if (Firebase.apps.isEmpty) return;
          // Warm push path quickly (token + channels) — don't wait 2.4s.
          await NotificationService.instance.initialize();
          NotificationService.setNavigatorKey(navKey);
        } catch (_) {}
      }());
    });
  }

  @override
  void dispose() {
    _bootDeadlineTimer?.cancel();
    super.dispose();
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

      try {
        await ensureFirebaseApp(
          maxAttempts: 2,
          attemptTimeout: const Duration(seconds: 2),
        ).timeout(const Duration(seconds: 2), onTimeout: () => false);
      } catch (_) {}
      unawaited(_ensureFirebaseHealthy(quiet: true));
      unawaited(GoogleMapsConfig.initialize());

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
          if (tryFirebaseUser() != null) {
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
        final role = RoleHelper.normalizeAccountRole(
              prefs.getString('user_role') ?? prefs.getString('role'),
            ) ??
            'customer';
        if (role == 'merchant' || role == 'driver') {
          initialRole = role;
        }
        if (onboardingDone) {
          if (initialRole == 'merchant') {
            unawaited(MerchantIdentityStore.resolve(
              prefs: prefs,
              allowShopProbe: true,
            ));
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

      return _BootState(
        clearedOldCache: false,
        onboardingDone: onboardingDone,
        initialRole: initialRole,
        email: email,
        initialShell: initialShell,
      );
    } catch (_) {
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

  void _continueFirebaseInBackground() {
    if (_firebaseNudgeInFlight) return;
    _firebaseNudgeInFlight = true;
    unawaited(() async {
      try {
        await _ensureFirebaseHealthy(quiet: true);
      } catch (_) {}
      _firebaseNudgeInFlight = false;
    }());
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
        final firebaseReady = isFirebaseAppReady;
        // Leave splash when boot is done and Firebase exists. If init hangs,
        // the 3s deadline still fail-opens so iPad is never stuck.
        final ready =
            _bootDeadlinePassed || (!booting && firebaseReady);

        if (ready && _showLauncher) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _showLauncher = false);
          });
        }

        if (_showLauncher || !ready) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            color: _splashBg,
            theme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: _splashBg,
              colorSchemeSeed: const Color(0xFFFF6B00),
              appBarTheme: const AppBarTheme(
                systemOverlayStyle: _kEdgeToEdgeOverlay,
              ),
            ),
            builder: _androidGpuSoftened,
            home: VeroLaunchSplash(
              title: _bootTitle,
              message: _bootMessage,
              showSpinner: true,
            ),
          );
        }

        if (!firebaseReady) {
          _continueFirebaseInBackground();
        }

        return MyApp(
          initialRole: boot.initialRole,
          initialEmail: boot.email,
          onboardingDoneHint: boot.onboardingDone,
          initialShell: boot.initialShell ??
              Bottomnavbar(email: boot.email.isNotEmpty ? boot.email : ''),
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
    driverSessionRiverpodBump = () {
      if (!mounted) return;
      ref.read(driverSessionTickProvider.notifier).state++;
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await loadDriverStatusFromPrefs()
            .timeout(const Duration(seconds: 2));
        await ref.read(syncDriverStatusProvider.future)
            .timeout(const Duration(seconds: 4));
        await loadDriverStatusFromPrefs()
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (driverSessionRiverpodBump != null) {
      // Only clear if we still own the callback (hot restart / nested bootstraps).
      driverSessionRiverpodBump = null;
    }
    super.dispose();
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
    AppShellCoordinator.register(
      onGuestHome: () {
        if (mounted) _currentShell = 'customer';
      },
      onShellRole: (role) {
        if (!mounted) return;
        _currentShell = role == RoleHelper.merchant
            ? 'merchant'
            : (role == RoleHelper.driver ? 'driver' : 'customer');
      },
    );
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
      // Vero Coin visits for customers + merchants + drivers.
      unawaited(VeroRewardsService.recordAppOpen());
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    final prefs = await SharedPreferences.getInstance();
    final bootAt = DateTime.now().millisecondsSinceEpoch;
    final prevBoot = prefs.getInt(_dlBootAtKey) ?? 0;
    // Hot restart re-runs Dart in the same Android Activity (gap is seconds).
    final hotRestart =
        prevBoot > 0 && (bootAt - prevBoot) < _dlHotRestartWindowMs;
    await prefs.setInt(_dlBootAtKey, bootAt);

    Uri? initial;
    try {
      initial = await _appLinks.getInitialLink();
    } catch (_) {}

    if (kDebugMode) {
      debugPrint(
        '[DeepLink] boot hotRestart=$hotRestart initial=$initial',
      );
    }

    await _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen((uri) {
      unawaited(_onDeepLinkStreamEvent(
        uri: uri,
        initial: initial,
        hotRestart: hotRestart,
        bootAt: bootAt,
      ));
    }, onError: (_) {});

    if (initial == null) return;

    if (_isContentShareDeepLink(initial)) {
      if (hotRestart || await _wasContentDeepLinkRecentlyOpened(initial)) {
        if (kDebugMode) {
          debugPrint(
            '[DeepLink] skip sticky content initial: $initial',
          );
        }
        return;
      }
      await _markInitialDeepLinkHandled(initial);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dispatchDeepLink(initial!);
    });
  }

  Future<void> _onDeepLinkStreamEvent({
    required Uri uri,
    required Uri? initial,
    required bool hotRestart,
    required int bootAt,
  }) async {
    if (_isContentShareDeepLink(uri)) {
      if (hotRestart) {
        if (kDebugMode) {
          debugPrint('[DeepLink] skip content on hot restart: $uri');
        }
        return;
      }

      final ageMs = DateTime.now().millisecondsSinceEpoch - bootAt;
      // app_links re-sends getInitialLink into the stream on listen — ignore that
      // echo; getInitialLink handler already opened it on a real cold start.
      if (ageMs < 8000 &&
          initial != null &&
          _sameContentDeepLink(uri, initial)) {
        if (kDebugMode) {
          debugPrint('[DeepLink] skip stream boot echo: $uri');
        }
        return;
      }
    }

    await _markInitialDeepLinkHandled(uri);
    _dispatchDeepLink(uri);
  }

  void _dispatchDeepLink(Uri uri) {
    if (_isPasswordResetDeepLink(uri)) {
      _openPasswordResetFromDeepLink(uri);
      return;
    }
    if (uri.scheme == 'vero360' &&
        uri.host == 'users' &&
        uri.path == '/me') {
      navKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ProfileFromLinkPage()),
      );
      return;
    }
    if (uri.scheme == 'vero360' && uri.host == 'payment-complete') {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OrdersPage()),
        (route) => route.isFirst,
      );
      return;
    }
    if (isCarHireDeepLinkUri(uri)) {
      openCarHireDeepLink(uri, navKey);
      return;
    }
    if (isAccommodationShareUri(uri)) {
      _openAccommodationFromShare(uri);
      return;
    }
    if (isFoodShareUri(uri)) {
      unawaited(FoodShareNavigation.openFromUri(uri));
      return;
    }
    if (isMarketplaceProductShareUri(uri) || isMarketplaceShopShareUri(uri)) {
      unawaited(
        MarketplaceShareNavigation.openFromUri(
          uri,
          CartServiceProvider.getInstance(),
        ),
      );
    }
  }

  static const _dlHandledUriKey = 'deeplink_initial_handled_uri';
  static const _dlHandledAtKey = 'deeplink_initial_handled_at';
  static const _dlBootAtKey = 'deeplink_init_boot_at';
  static const _dlHotRestartWindowMs = 2 * 60 * 1000;
  static const _dlStickySuppressMs = 30 * 60 * 1000;

  bool _isContentShareDeepLink(Uri uri) =>
      isAccommodationShareUri(uri) ||
      isCarHireDeepLinkUri(uri) ||
      isFoodShareUri(uri) ||
      isMarketplaceProductShareUri(uri) ||
      isMarketplaceShopShareUri(uri);

  bool _sameContentDeepLink(Uri a, Uri b) {
    final shopA = marketplaceShopIdFromShareUri(a);
    final shopB = marketplaceShopIdFromShareUri(b);
    if (shopA != null && shopB != null) return shopA == shopB;
    final prodA = marketplaceProductIdFromShareUri(a);
    final prodB = marketplaceProductIdFromShareUri(b);
    if (prodA != null && prodB != null) return prodA == prodB;
    return a.scheme == b.scheme &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        a.path == b.path;
  }

  Future<bool> _wasContentDeepLinkRecentlyOpened(Uri uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUri = prefs.getString(_dlHandledUriKey);
      if (lastUri == null || lastUri.isEmpty) return false;
      if (!_sameContentDeepLink(Uri.parse(lastUri), uri)) return false;
      final lastAt = prefs.getInt(_dlHandledAtKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - lastAt;
      return age >= 0 && age < _dlStickySuppressMs;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markInitialDeepLinkHandled(Uri uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dlHandledUriKey, uri.toString());
      await prefs.setInt(
        _dlHandledAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  void _openAccommodationFromShare(Uri uri) {
    unawaited(_openAccommodationFromShareAsync(uri));
  }

  Future<void> _openAccommodationFromShareAsync(Uri uri) async {
    var id = accommodationIdFromShareUri(uri);
    final ref = accommodationRefFromShareUri(uri);
    final q = accommodationSearchQueryFromShareUri(uri);

    // Facebook posts often use Firestore room doc ids (e.g. uid_123).
    if ((id == null || id <= 0) && ref != null && ref.isNotEmpty) {
      try {
        final db = FirebaseFirestore.instance;
        DocumentSnapshot<Map<String, dynamic>>? doc;
        final room = await db.collection('accommodation_rooms').doc(ref).get();
        if (room.exists) {
          doc = room;
        } else {
          final acc = await db.collection('accommodations').doc(ref).get();
          if (acc.exists) doc = acc;
        }
        final data = doc?.data();
        if (data != null) {
          id = int.tryParse(
                '${data['accommodationId'] ?? data['sqlId'] ?? data['id'] ?? ''}',
              ) ??
              (ref.contains('_') ? int.tryParse(ref.split('_').last) : null);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AccommodationMainPage(
          focusAccommodationId: (id != null && id > 0) ? id : null,
          initialSearchQuery: q,
          openFocusedStay: id != null && id > 0,
        ),
      ),
    );
  }

  void _trimImageMemory() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _lastLifecycleState;
    _lastLifecycleState = state;

    if (state == AppLifecycleState.paused) {
      // Free decoded bitmaps while backgrounded — critical on 2GB Redmi.
      _trimImageMemory();
      // System PIN/biometric UI also pauses the activity. Do not treat that as
      // "user left the app" or the next resume will lock again after unlock.
      if (!_biometricAuthInProgress && !_showBiometricLock) {
        _biometricSessionUnlocked = false;
      }
      return;
    }

    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _trimImageMemory();
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
    final role = RoleHelper.normalizeAccountRole(
          prefs.getString('user_role') ?? prefs.getString('role'),
        ) ??
        'customer';
    final email = prefs.getString('email') ?? '';
    final token = RoleSessionService.readToken(prefs);
    final signedIn = tryFirebaseUser() != null ||
        (token != null && token.trim().isNotEmpty);
    if (!signedIn) {
      if (_currentShell != 'customer') _pushCustomer(email);
      return;
    }

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
    var token = RoleSessionService.readToken(prefs) ??
        await AuthHandler.getTokenForApi();

    if (token == null || token.trim().isEmpty) return;

    var result = await RoleSessionService.syncFromServer(
      prefs: prefs,
      token: token,
    );
    if (result == null) return;

    // One Firebase refresh before treating as logged out.
    if (result.isUnauthorized) {
      final refreshed = await AuthHandler.refreshTokenAfterUnauthorized();
      if (refreshed != null && refreshed.isNotEmpty) {
        result = await RoleSessionService.syncFromServer(
          prefs: prefs,
          token: refreshed,
        );
      }
    }
    if (result == null) return;
    if (result.isUnauthorized) {
      // Keep Firebase session; only clear stale SP tokens if Firebase is gone.
      if (tryFirebaseUser() == null) {
        await _clearAuth(prefs);
      }
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
    await RoleSessionService.clearRoleKeys(prefs);
  }

  Future<void> _pushMerchant(String email) async {
    if (!mounted) return;
    // Paint merchant shell immediately — resolve vertical in background.
    _currentShell = 'merchant';
    navKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => Bottomnavbar(email: email, initialIndex: 4),
      ),
      (route) => false,
    );
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await MerchantIdentityStore.resolve(
          prefs: prefs,
          allowShopProbe: true,
        );
      } catch (_) {}
    }());
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
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: _kEdgeToEdgeOverlay,
            ),
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
            return _androidGpuSoftened(context, content);
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
    if (isMerchant) {
      navKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => Bottomnavbar(email: email, initialIndex: 4),
        ),
        (route) => false,
      );
      unawaited(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await MerchantIdentityStore.resolve(
            prefs: prefs,
            allowShopProbe: true,
          );
        } catch (_) {}
      }());
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

        await RoleSessionService.persistUserToPrefs(prefs, user);

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
    await RoleSessionService.clearRoleKeys(p);
    await p.remove('has_driver_profile');
    resetDriverSessionCache();
    try {
      await SessionLocalCache.clearOnLogout();
    } catch (_) {}

    try {
      await tryFirebaseAuth()?.signOut();
    } catch (_) {}

    AppShellCoordinator.markGuestHome();
    openVeroMainShell(ctx, email: '', tabIndex: 0);
  }

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    final t = _readToken(p);
    final fb = tryFirebaseUser();
    return (t != null && t.trim().isNotEmpty) || fb != null;
  }
}
