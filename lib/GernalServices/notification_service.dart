// lib/services/notification_service.dart
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'package:vero360_app/config/api_config.dart';

/// Central service for handling Firebase Cloud Messaging (FCM) + local notifications
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _highPriorityChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Important alerts: ride updates, new messages, order status',
    importance: Importance.max,
    playSound: true,
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

    // 2. Request notification permissions
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

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint("Foreground FCM: ${message.notification?.title ?? 'no title'}");

    final notification = message.notification;
    if (notification == null) return;

    _showLocalNotification(
      id: notification.hashCode,
      title: notification.title ?? 'Vero360',
      body: notification.body ?? '',
      payload: jsonEncode(message.data),
    );
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint("Notification tap from background: ${message.messageId}");
    _navigateBasedOnPayload(message.data);
  }

  void _handleInitialMessage(RemoteMessage message) {
    debugPrint("Launched from terminated via notification: ${message.messageId}");
    _navigateBasedOnPayload(message.data);
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
    final type = data['type'] as String?;
    final rideId = data['rideId'] as String?;
    final chatId = data['chatId'] as String?;
    final orderId = data['orderId'] as String?;

    if (type == null) return;

    switch (type.toLowerCase()) {
      case 'new_ride':
      case 'ride_update':
        // TODO: Navigate to ride details screen
        debugPrint("→ Open ride: $rideId");
        // navKey.currentState?.push(...);
        break;

      case 'new_message':
        // TODO: Open chat screen
        debugPrint("→ Open chat: $chatId");
        break;

      case 'order_update':
        // TODO: Open order details or My Orders
        debugPrint("→ Open order: $orderId");
        break;

      default:
        debugPrint("Unhandled notification type: $type");
    }
  }

  // Public method to show a local notification manually (e.g. from other parts of app)
  Future<void> showManualNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: payload,
    );
  }
}