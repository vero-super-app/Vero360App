// lib/services/notification_service.dart
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

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
      if (kDebugMode) debugPrint("FCM Token: $token");
      await _registerTokenWithBackend(token);
    }

    messaging.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) debugPrint("FCM token refreshed: $newToken");
      await _registerTokenWithBackend(newToken);
    });

    // Register token when user signs in (handles login after app start)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await registerTokenWithBackend();
      }
    });
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
        debugPrint("FCM token register failed: ${res.statusCode} ${res.body}");
      }
    } catch (e) {
      if (kDebugMode) debugPrint("FCM token register error: $e");
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
    debugPrint("Foreground FCM: $title / $body");

    final id = message.messageId ?? 'fcm_${message.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      NotificationStore.instance.addNotification(
        id: id,
        title: title,
        body: body,
        payload: data,
      );
    } catch (e) {
      debugPrint("NotificationStore add failed: $e");
    }

    final notificationId = message.hashCode.abs();
    try {
      await _showLocalNotification(
        id: notificationId,
        title: title,
        body: body,
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint("Show local notification failed: $e");
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint("Notification tap from background: ${message.messageId}");
    _addToStoreIfNeeded(message);
    _navigateBasedOnPayload(message.data);
  }

  void _handleInitialMessage(RemoteMessage message) {
    debugPrint("Launched from terminated via notification: ${message.messageId}");
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
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      instance._navigateBasedOnPayload(data);
    } catch (e) {
      debugPrint("Invalid notification payload: $e");
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
    final rideId = data['rideId'] as String?;
    final chatId = data['chatId'] as String?;
    final orderId = data['orderId'] as String?;

    switch (type ?? '') {
      case 'new_ride':
      case 'ride_update':
        debugPrint("→ Open ride: $rideId");
        navigator.push(MaterialPageRoute(
          builder: (_) => const NotificationsPage(),
        ));
        break;

      case 'new_message':
        debugPrint("→ Open chat: $chatId");
        navigator.push(MaterialPageRoute(
          builder: (_) => const ChatListPage(),
        ));
        break;

      case 'order_update':
        debugPrint("→ Open order: $orderId");
        navigator.push(MaterialPageRoute(
          builder: (_) => const OrdersPage(),
        ));
        break;

      default:
        navigator.push(MaterialPageRoute(
          builder: (_) => const NotificationsPage(),
        ));
    }
  }

  // Public method to show a local notification manually (e.g. from other parts of app)
  Future<void> showManualNotification({
    required String title,
    required String body,
    String? payload,
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
    );
  }
}