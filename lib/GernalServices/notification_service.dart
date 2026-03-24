// lib/services/notification_service.dart
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/Home/notifications_page.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';

/// Central service for handling Firebase Cloud Messaging (FCM) + local notifications
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static GlobalKey<NavigatorState>? _navKey;

  /// Call from main.dart after app is built: NotificationService.instance.setNavigatorKey(navKey);
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navKey = key;
  }

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _highPriorityChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Important alerts: ride updates, new messages, order status',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Action IDs for interactive notifications (reply, react)
  static const String _actionReply = 'reply';
  static const String _actionLike = 'like';

  /// Actions shown on interactive notifications: Reply (with inline text) and Like
  static List<AndroidNotificationAction> get _interactiveActions =>
      [
        AndroidNotificationAction(
          _actionReply,
          'Reply',
          cancelNotification: false,
          inputs: [
            const AndroidNotificationActionInput(
              label: 'Type a reply...',
              allowFreeFormInput: true,
            ),
          ],
        ),
        AndroidNotificationAction(
          _actionLike,
          'Like',
          cancelNotification: false,
        ),
      ];

  /// Initialize everything needed for notifications
  /// Call this once early in app startup (after Firebase.initializeApp)
  Future<void> initialize() async {
    // 1. Local notifications setup
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    // Create Android notification channel (required Android 8+)
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_highPriorityChannel);

    // Request Android 13+ notification permission (required to show notifications)
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (kDebugMode) {
        debugPrint('Android notification permission granted: $granted');
      }
    }

    // 2. Request FCM notification permissions (mainly for iOS)
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      debugPrint(
          'Notification permission: ${permission.authorizationStatus.name}');
    }

    // 3. Foreground message handler
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 4. App opened from notification (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 5. Get initial message (app launched from terminated state via notification)
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _handleInitialMessage(initial);
    }

    // 6. FCM token: register with backend (if user logged in)
    final token = await messaging.getToken();
    if (token != null) {
      if (kDebugMode) {
        // Avoid logging the raw FCM token; just log a non-sensitive summary.
        debugPrint(
            "FCM token acquired (length=${token.length}, hash=${token.hashCode})");
      }
      await _registerTokenWithBackend(token);
    }

    messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        debugPrint(
            "FCM token refreshed (length=${newToken.length}, hash=${newToken.hashCode})");
      }
      await _registerTokenWithBackend(newToken);
    });

    // Register token when user signs in (handles login after app start)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await registerTokenWithBackend();
        await NotificationStore.instance.ensureLoaded();
      } else {
        // Ensure notifications from previous account do not remain visible.
        await NotificationStore.instance.clearAll();
      }
    });

    await NotificationStore.instance.ensureLoaded();
  }

  /// Register FCM token with backend. Call this when user logs in, or it runs
  /// automatically on init/token refresh (no-op if not logged in).
  Future<void> registerTokenWithBackend() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerTokenWithBackend(token);
    }
  }

  Future<void> _registerTokenWithBackend(String fcmToken) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return;

      await ApiConfig.init();
      final uri = ApiConfig.endpoint('/api/v1/notifications/register-token');
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android');

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'token': fcmToken,
          'platform': platform,
        }),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (kDebugMode) debugPrint("FCM token registered with backend ✅");
      } else if (kDebugMode) {
        debugPrint("FCM token register failed: ${res.statusCode}");
      }
    } catch (e) {
      if (kDebugMode) debugPrint("FCM token register error");
    }
  }

  // ───────────────────────────────────────────────
  //  Handlers
  // ───────────────────────────────────────────────

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Support both "notification" payload and "data-only" messages (e.g. from FCM console)
    final notification = message.notification;
    final data = message.data;
    final title = notification?.title ?? data['title'] as String? ?? 'Vero360';
    final body = notification?.body ?? data['body'] as String? ?? 'New notification';
    if (kDebugMode) debugPrint("Foreground FCM received");

    final id = message.messageId ?? 'fcm_${message.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      NotificationStore.instance.addNotification(
        id: id,
        title: title,
        body: body,
        payload: data,
      );
    } catch (e) {
      if (kDebugMode) debugPrint("NotificationStore add failed");
    }

    final notificationId = message.hashCode.abs();
    final interactive = _isInteractivePayload(data);
    if (kDebugMode && interactive) {
      debugPrint("Showing interactive notification (Reply/Like actions). data.interactive or type triggered it.");
    }
    try {
      await _showLocalNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: jsonEncode(data),
        interactive: interactive,
      );
    } catch (e) {
      if (kDebugMode) debugPrint("Show local notification failed");
    }
  }

  /// True when the notification supports Reply / Like (comment, post, mention, or explicit flag).
  bool _isInteractivePayload(Map<String, dynamic> data) {
    if (data['interactive'] == true || data['interactive'] == 'true') return true;
    final type = (data['type'] as String?)?.toLowerCase();
    return type != null &&
        (type == 'comment' ||
            type == 'post_comment' ||
            type == 'mention' ||
            type == 'new_comment' ||
            type == 'reply');
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) debugPrint("Notification tap from background");
    _addToStoreIfNeeded(message);
    _navigateBasedOnPayload(message.data);
  }

  void _handleInitialMessage(RemoteMessage message) {
    if (kDebugMode) debugPrint("Launched from terminated via notification");
    _addToStoreIfNeeded(message);
    _navigateBasedOnPayload(message.data);
  }

  void _addToStoreIfNeeded(RemoteMessage message) {
    final n = message.notification;
    final id = message.messageId ?? 'fcm_${message.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    NotificationStore.instance.addNotification(
      id: id,
      title: n?.title ?? 'Notification',
      body: n?.body ?? '',
      payload: message.data,
    );
  }

  static void _onDidReceiveNotificationResponse(NotificationResponse response) {
    Map<String, dynamic>? data;
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        data = jsonDecode(response.payload!) as Map<String, dynamic>;
      } catch (e) {
        if (kDebugMode) debugPrint("Invalid notification payload");
      }
    }

    // User tapped an action button (Reply or Like)
    if (response.notificationResponseType ==
        NotificationResponseType.selectedNotificationAction) {
      final actionId = response.actionId;
      if (actionId == _actionReply && response.input != null) {
        instance._submitReply(data ?? {}, response.input!.trim());
        return;
      }
      if (actionId == _actionLike) {
        instance._submitReaction(data ?? {});
        return;
      }
    }

    // User tapped the notification body → navigate
    if (data != null) instance._navigateBasedOnPayload(data);
  }

  /// Send reply text to backend; backend can push to other users in real time.
  Future<void> _submitReply(Map<String, dynamic> payload, String text) async {
    if (text.isEmpty) return;
    try {
      await ApiConfig.init();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return;

      final uri = ApiConfig.endpoint('/api/v1/notifications/interactive/reply');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          ...payload,
          'text': text,
        }),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (kDebugMode) debugPrint("Notification reply sent ✅");
        _showLocalNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Reply sent',
          body: text.length > 40 ? '${text.substring(0, 40)}...' : text,
          payload: null,
        );
      } else if (kDebugMode) {
        debugPrint("Notification reply failed: ${res.statusCode}");
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Notification reply error");
    }
  }

  /// Send reaction (e.g. like) to backend; backend can update and push in real time.
  Future<void> _submitReaction(Map<String, dynamic> payload) async {
    try {
      await ApiConfig.init();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return;

      final uri = ApiConfig.endpoint('/api/v1/notifications/interactive/react');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          ...payload,
          'reaction': 'like',
        }),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (kDebugMode) debugPrint("Notification reaction sent ✅");
        _showLocalNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'Liked',
          body: 'Your reaction was sent',
          payload: null,
        );
      } else if (kDebugMode) {
        debugPrint("Notification reaction failed: ${res.statusCode}");
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Notification reaction error");
    }
  }

  // ───────────────────────────────────────────────
  //  Display local notification
  // ───────────────────────────────────────────────

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool interactive = false,
  }) async {
    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _highPriorityChannel.id,
          _highPriorityChannel.name,
          channelDescription: _highPriorityChannel.description,
          importance: _highPriorityChannel.importance,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          visibility: NotificationVisibility.public,
          actions: interactive ? _interactiveActions : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ───────────────────────────────────────────────
  //  Navigation logic (customize based on your needs)
  // ───────────────────────────────────────────────

  void _navigateBasedOnPayload(Map<String, dynamic> data) {
    final navigator = _navKey?.currentState;
    if (navigator == null) return;

    final type = (data['type'] as String?)?.toLowerCase();
 
    switch (type ?? '') {
      case 'new_ride':
      case 'ride_update':
        if (kDebugMode) debugPrint("→ Open ride");
        navigator.push(MaterialPageRoute(
          builder: (_) => const NotificationsPage(),
        ));
        break;

      case 'new_message':
        if (kDebugMode) debugPrint("→ Open chat");
        navigator.push(MaterialPageRoute(
          builder: (_) => const ChatListPage(),
        ));
        break;

      case 'order_update':
        if (kDebugMode) debugPrint("→ Open order");
        final orderId = data['orderId']?.toString();
        final orderNumber = data['orderNumber']?.toString();
        final status = data['status']?.toString();
        navigator.push(MaterialPageRoute(
          builder: (_) => OrdersPage(
            initialOrderId: orderId,
            initialOrderNumber: orderNumber,
            initialStatus: status,
          ),
        ));
        break;

      default:
        navigator.push(MaterialPageRoute(
          builder: (_) => const NotificationsPage(),
        ));
    }
  }

  /// Push / manual payloads can include `badgeRoute` for quick-action badges, e.g.
  /// `quick_my_orders`, `quick_shipped`, `quick_received`, `quick_refund`, `quick_promotions`,
  /// `quick_post_arrival` (see [NotificationStore] constants).

  /// Show a local notification manually. Set [interactive] true to show Reply + Like actions.
  Future<void> showManualNotification({
    required String title,
    required String body,
    String? payload,
    bool interactive = false,
  }) async {
    final id = 'manual_${DateTime.now().millisecondsSinceEpoch}';
    Map<String, dynamic> payloadMap = {};
    if (payload != null && payload.isNotEmpty) {
      try {
        payloadMap = jsonDecode(payload) as Map<String, dynamic>? ?? {};
      } catch (_) {}
    }
    NotificationStore.instance.addNotification(
      id: id,
      title: title,
      body: body,
      payload: payloadMap,
    );
    await _showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: payload,
      interactive: interactive,
    );
  }

  /// Sends a one-time welcome notification for a newly created account.
  Future<void> sendWelcomeNotificationIfFirstTime({
    required String uid,
    required String name,
    String? role,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'welcome_notification_sent_$cleanUid';
    if (prefs.getBool(key) == true) return;

    final safeName = name.trim().isEmpty ? 'there' : name.trim();
    final normalizedRole = (role ?? '').trim().toLowerCase();
    final title = switch (normalizedRole) {
      'merchant' => 'Welcome to Vero360 Merchant Account, $safeName!',
      'driver' => 'Welcome to Vero360 Driver Account, $safeName!',
      _ => 'Welcome to Vero360, $safeName!',
    };
    final body = switch (normalizedRole) {
      'merchant' =>
        'Start listing your products and services, manage orders, and grow your business in one app.',
      'driver' =>
        'Start accepting rides, manage trips, and track your earnings with the all-in-one Vero360 app.',
      _ =>
        'Vero360 is your all-in-one app for rides, marketplace, food, transport, accommodation, and more.',
    };
    final payloadMap = <String, dynamic>{
      'type': 'welcome',
      'uid': cleanUid,
      'role': normalizedRole,
    };

    await showManualNotification(
      title: title,
      body: body,
      payload: jsonEncode(payloadMap),
    );

    await prefs.setBool(key, true);
  }
}