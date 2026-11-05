// lib/services/notification_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:vero360_app/native/local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/chat_notification_service.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/engagement_notification_service.dart';
import 'package:vero360_app/utils/description_contact_mask.dart';
import 'package:vero360_app/GeneralPages/Toreceive.dart';
import 'package:vero360_app/GeneralPages/ToRefund.dart';
import 'package:vero360_app/GeneralPages/Toship.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/Home/notifications_page.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Reels/reels_notification_routes.dart';
import 'package:vero360_app/GernalScreens/vero_team_chat_page.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_my_orders_page.dart';
import 'package:vero360_app/features/DigitalServices/presentation/digital_my_orders_page.dart';
import 'package:vero360_app/features/DigitalServices/presentation/digital_service_order_service.dart';
import 'package:vero360_app/features/Promotions/presentation/promotions_page.dart';
import 'package:vero360_app/features/Promotions/presentation/promo_detail_page.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as market;
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/LatestArrival_page.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/driver_incoming_ride_from_notification_page.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_alert_notifications.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_offer_inbox.dart';
import 'package:vero360_app/utils/app_update_checker.dart';
import 'package:vero360_app/utils/firebase_bootstrap.dart';

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

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _partyAlertSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatAlertSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _digitalOrderSub;
  final Map<String, String> _digitalFulfillSeen = {};
  final Map<String, String> _digitalStatusSeen = {};
  bool _digitalStatusPrimed = false;

  static const AndroidNotificationChannel _highPriorityChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Important alerts: ride updates, new messages, order status',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _rideRequestChannel =
      DriverRideAlertNotifications.channel;

  static const String _actionReply = 'reply';
  static const String _actionLike = 'like';
  static String? _openedRideOfferId;
  static DateTime? _openedRideOfferAt;

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
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Local notifications setup.
    // Do NOT request iOS alert permission here. A permission sheet over the
    // launch splash (or a sheet that never appears on iPadOS) looks like an
    // infinite load — App Store Guideline 2.1.
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            onDriverRideNotificationBackgroundAction,
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}

    // Create Android notification channel (required Android 8+)
    try {
      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_highPriorityChannel);
      await androidImpl?.createNotificationChannel(_rideRequestChannel);
    } catch (_) {}

    var launchedFromLocal = false;
    try {
      final launchDetails = await _localNotifications
          .getNotificationAppLaunchDetails()
          .timeout(const Duration(seconds: 2));
      final launchResponse = launchDetails?.notificationResponse;
      launchedFromLocal = launchResponse != null &&
          launchDetails?.didNotificationLaunchApp == true;
      if (launchedFromLocal && launchResponse != null) {
        _onDidReceiveNotificationResponse(launchResponse);
      }
    } catch (_) {}

    // Android 13+ can prompt in-app; never block iOS launch on a sheet.
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      unawaited(androidPlugin?.requestNotificationsPermission());
    } catch (_) {}

    if (!isFirebaseAppReady) return;

    FirebaseMessaging? messaging;
    try {
      messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    if (messaging == null) return;

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    try {
      final initial = await messaging.getInitialMessage()
          .timeout(const Duration(seconds: 2));
      if (initial != null) {
        _handleInitialMessage(initial);
      } else if (!launchedFromLocal) {
        unawaited(_consumePendingDriverRideOffer());
      }
    } catch (_) {
      if (!launchedFromLocal) {
        unawaited(_consumePendingDriverRideOffer());
      }
    }

    unawaited(registerTokenWithBackend(retries: 3));

    messaging.onTokenRefresh.listen((newToken) async {
      await _registerTokenWithBackend(newToken);
    });

    tryFirebaseAuth()?.authStateChanges().listen((user) async {
      if (user != null) {
        unawaited(_ensurePushPermissionAfterLogin());
        await NotificationStore.instance.switchToUser(user.uid);
        await registerTokenWithBackend(retries: 4);
        _syncOrderPartyAlertListener(user);
        _syncChatAlertListener(user);
        _syncDigitalOrderFulfillmentListener(user);
        await EngagementNotificationService.instance.syncTopicSubscription();
        unawaited(
          Future<void>.delayed(const Duration(seconds: 8), () {
            unawaited(
              EngagementNotificationService.instance.maybeSendDailyDigest(),
            );
          }),
        );
      } else {
        _syncOrderPartyAlertListener(null);
        _syncChatAlertListener(null);
        _syncDigitalOrderFulfillmentListener(null);
        await NotificationStore.instance.clearForLogout();
        try {
          await _localNotifications.cancelAll();
        } catch (_) {}
        await EngagementNotificationService.instance.syncTopicSubscription();
      }
    });

    unawaited(
      NotificationStore.instance.ensureLoaded().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      ),
    );
    final current = tryFirebaseUser();
    _syncOrderPartyAlertListener(current);
    _syncChatAlertListener(current);
    _syncDigitalOrderFulfillmentListener(current);
    unawaited(EngagementNotificationService.instance.syncTopicSubscription());
    if (current != null) {
      unawaited(_ensurePushPermissionAfterLogin());
      unawaited(
        Future<void>.delayed(const Duration(seconds: 12), () {
          unawaited(
            EngagementNotificationService.instance.maybeSendDailyDigest(),
          );
        }),
      );
    }
  }

  bool _pushPermissionAsked = false;

  /// Ask for notification permission after the first UI is on screen, and only
  /// when a signed-in user actually needs push (not during App Review launch).
  Future<void> _ensurePushPermissionAfterLogin() async {
    if (_pushPermissionAsked) return;
    _pushPermissionAsked = true;
    try {
      final iosPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin
          ?.requestPermissions(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      if (!isFirebaseAppReady) return;
      final settingsPermission = await FirebaseMessaging.instance
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          )
          .timeout(const Duration(seconds: 8));
      if (kDebugMode) {
        debugPrint(
          '[NotificationService] iOS/FCM permission: ${settingsPermission.authorizationStatus}',
        );
      }
    } catch (_) {}
  }

  /// Listens for [OrderPartyNotificationService] docs. Tips appear in the
  /// Vero360 Team chat; here we only bump the notification badge count
  /// (no system/local notification banner).
  void _syncOrderPartyAlertListener(User? user) {
    _partyAlertSub?.cancel();
    _partyAlertSub = null;
    if (user == null) return;

    // Single-field query avoids requiring a composite index; filter counted locally.
    _partyAlertSub = FirebaseFirestore.instance
        .collection(OrderPartyNotificationService.collectionName)
        .where('toUid', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) {
          continue;
        }
        final d = change.doc.data();
        if (d == null) continue;
        if (d['notifCounted'] == true) continue;
        final title = (d['title'] ?? 'Vero360 Team').toString();
        final body = (d['body'] ?? '').toString();
        Map<String, dynamic> payloadMap = {};
        final rawPayload = d['payload'];
        if (rawPayload is Map) {
          try {
            payloadMap = Map<String, dynamic>.from(
              rawPayload.map((k, v) => MapEntry(k.toString(), v)),
            );
          } catch (_) {}
        }
        final type = (payloadMap['type'] ?? '').toString().toLowerCase();
        final isServiceAlert = type.contains('order') ||
            type.contains('food') ||
            type.contains('digital') ||
            type.contains('subscription') ||
            type.contains('courier') ||
            type.contains('booking') ||
            type.contains('refund') ||
            type.contains('fulfillment') ||
            type.contains('stay');
        await NotificationStore.instance.addNotification(
          id: 'party_${change.doc.id}',
          title: title,
          body: body.isEmpty
              ? (isServiceAlert
                  ? 'New order update'
                  : 'New message from Vero360 Team')
              : body,
          payload: {
            ...payloadMap,
            if (!isServiceAlert) 'openChat': 'vero360_team',
          },
        );
        try {
          await change.doc.reference.update({'notifCounted': true});
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[NotificationService] party alert count failed: $e');
          }
        }
      }
    }, onError: (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] party alert listener error: $e');
      }
    });
  }

  /// Incoming chat messages published by [ChatNotificationService] for this user.
  ///
  /// Consume + refresh only â€” do not show a second local banner here.
  /// Foreground banners come from WebSocket; background/killed from FCM
  /// (`onChatMessageAlertCreated`). Showing here duplicated those paths.
  void _syncChatAlertListener(User? user) {
    _chatAlertSub?.cancel();
    _chatAlertSub = null;
    if (user == null) return;

    _chatAlertSub = FirebaseFirestore.instance
        .collection(ChatNotificationService.collectionName)
        .where('toUid', isEqualTo: user.uid)
        .where('consumed', isEqualTo: false)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc.data();
        if (d == null) continue;

        final fromUid = (d['fromUid'] ?? '').toString();
        if (fromUid == user.uid) continue;

        final payload = d['payload'];
        final chatId = payload is Map
            ? (payload['chatId'] ?? '').toString().trim()
            : '';

        final active = (BackendChatService.activeChatId ?? '').trim();
        if (chatId.isNotEmpty && active.isNotEmpty && chatId == active) {
          try {
            await change.doc.reference.update({'consumed': true});
          } catch (_) {}
          continue;
        }

        BackendChatService.refreshThreads();
        try {
          await change.doc.reference.update({'consumed': true});
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[NotificationService] chat alert consume failed: $e');
          }
        }
      }
    });
  }

  /// When admin writes card/login details onto the buyer's digital order,
  /// surface it in the in-app inbox (app open). Background/killed devices
  /// get the same alert from [onDigitalServiceOrderUpdated] → order_party_alerts.
  void _syncDigitalOrderFulfillmentListener(User? user) {
    _digitalOrderSub?.cancel();
    _digitalOrderSub = null;
    _digitalFulfillSeen.clear();
    _digitalStatusSeen.clear();
    _digitalStatusPrimed = false;
    if (user == null || user.isAnonymous) return;

    _digitalOrderSub = FirebaseFirestore.instance
        .collection(kDigitalServiceOrdersCollection)
        .where('buyerUid', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) async {
      if (!_digitalStatusPrimed) {
        for (final doc in snap.docs) {
          final order = DigitalServiceOrder.fromDoc(doc);
          _digitalStatusSeen[order.id] = order.status.toLowerCase();
          _digitalFulfillSeen[order.id] = order.fulfillment.copyAllText;
        }
        _digitalStatusPrimed = true;
        return;
      }
      for (final change in snap.docChanges) {
        final order = DigitalServiceOrder.fromDoc(change.doc);
        final fp = order.fulfillment.copyAllText;
        final prevFulfill = _digitalFulfillSeen[order.id];
        _digitalFulfillSeen[order.id] = fp;
        final status = order.status.toLowerCase();
        final prevStatus = _digitalStatusSeen[order.id];
        _digitalStatusSeen[order.id] = status;

        Future<void> banner({
          required String id,
          required String type,
          required String title,
          required String body,
          bool addToInbox = true,
        }) async {
          if (addToInbox) {
            await NotificationStore.instance.addNotification(
              id: id,
              title: title,
              body: body,
              payload: {
                'type': type,
                'orderId': order.id,
                'productName': order.productName,
                NotificationStore.kPayloadBadgeRoute:
                    NotificationStore.kBadgeDigitalOrders,
              },
            );
          }
          try {
            await _showLocalNotification(
              id: id.hashCode.abs() % 100000000,
              title: title,
              body: body,
              payload: jsonEncode({
                'type': type,
                'orderId': order.id,
                'productName': order.productName,
                NotificationStore.kPayloadBadgeRoute:
                    NotificationStore.kBadgeDigitalOrders,
              }),
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[NotificationService] digital status notify: $e');
            }
          }
        }

        if (order.isPaid &&
            prevStatus != null &&
            prevStatus != 'paid' &&
            prevStatus != 'fulfilled' &&
            prevStatus != 'completed') {
          await banner(
            id: 'digital_paid_${order.id}',
            type: 'digital_order',
            title: 'We received your order · ${order.productName}',
            body:
                'We have received your ${order.productName} payment. We are processing your order now — you will get your details in My Digital Orders.',
            addToInbox: false,
          );
        }

        if (change.type != DocumentChangeType.modified) continue;
        if (!order.fulfillment.hasContent) continue;
        if (prevFulfill == fp) continue;

        await banner(
          id: 'digital_fulfill_${order.id}',
          type: 'digital_fulfillment',
          title: 'Your ${order.productName} details are ready',
          body:
              'Open My Digital Orders to copy your code, login, or joining link.',
        );
      }
    }, onError: (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] digital order listener error: $e');
      }
    });
  }

  /// Register FCM token with backend. Call this when user logs in, or it runs
  /// automatically on init/token refresh (no-op if not logged in).
  Future<void> registerTokenWithBackend({int retries = 1}) async {
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        // iOS: FCM token is unavailable until APNs token is set.
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          final apns = await _waitForApnsToken(
            attempts: attempt == 0 ? 8 : 4,
          );
          if (apns == null && kDebugMode) {
            debugPrint(
              '[NotificationService] APNs token not ready (attempt ${attempt + 1})',
            );
          }
        }
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await _registerTokenWithBackend(token);
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FCM getToken attempt ${attempt + 1} failed: $e');
        }
      }
      if (attempt < retries - 1) {
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    if (kDebugMode) {
      debugPrint('FCM token unavailable after $retries attempts');
    }
  }

  /// Wait until iOS has an APNs device token (required before FCM getToken).
  Future<String?> _waitForApnsToken({int attempts = 8}) async {
    final messaging = FirebaseMessaging.instance;
    for (var i = 0; i < attempts; i++) {
      try {
        final token = await messaging.getAPNSToken();
        if (token != null && token.isNotEmpty) return token;
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 400 + (i * 200)));
    }
    try {
      return await messaging.getAPNSToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _consumePendingDriverRideOffer() async {
    final pending = await DriverRideOfferInbox.instance.takePendingOffer();
    if (pending == null) return;
    // Delay until navigator is ready after cold start.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _navigateBasedOnPayload(pending);
  }

  Future<void> _registerTokenWithBackend(String fcmToken) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Persist token for Cloud Functions (marketplace moderation push, etc.).
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': fcmToken,
          'fcmTokens': FieldValue.arrayUnion([fcmToken]),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FCM token Firestore save failed: $e');
        }
      }

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
        // Success â€” no console log (avoids leaking push-registration state).
      } else if (res.statusCode == 409) {
        // Already registered â€” silent.
      } else if (kDebugMode) {
        debugPrint('FCM token register failed: ${res.statusCode}');
      }
    } catch (_) {
      // Silent â€” avoid leaking auth/network details to logcat.
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  Handlers
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Call **before** FirebaseAuth.signOut so we can remove this device's FCM
  /// token from the leaving account. Prevents pushes for account A arriving
  /// while account B is logged in on the same phone.
  Future<void> clearSessionOnLogout() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    _syncOrderPartyAlertListener(null);
    _syncChatAlertListener(null);
    _syncDigitalOrderFulfillmentListener(null);

    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    if (user != null && fcmToken != null && fcmToken.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': FieldValue.delete(),
          'fcmTokens': FieldValue.arrayRemove([fcmToken]),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[NotificationService] FCM token remove on logout failed: $e');
        }
      }
    }

    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] FCM deleteToken on logout failed: $e');
      }
    }

    try {
      await _localNotifications.cancelAll();
    } catch (_) {}

    await NotificationStore.instance.clearForLogout(uid: uid);
    try {
      await EngagementNotificationService.instance.syncTopicSubscription();
    } catch (_) {}
  }

  /// Returns false when the push names a Firebase recipient that is not the signed-in user.
  bool _payloadBelongsToCurrentUser(Map<String, dynamic> data) {
    final current = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (current.isEmpty) return false;

    final targets = <String>{};
    for (final key in const ['toUid', 'recipientUid', 'targetUid']) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) targets.add(v);
    }
    // `uid` is often Firebase UID; skip pure numeric Nest/user ids.
    final uidField = (data['uid'] ?? '').toString().trim();
    if (uidField.isNotEmpty && int.tryParse(uidField) == null) {
      targets.add(uidField);
    }

    // No explicit Firebase recipient â€” accept only while store is bound to current user.
    if (targets.isEmpty) {
      final bound = (NotificationStore.instance.boundUid ?? '').trim();
      return bound.isEmpty || bound == current;
    }
    return targets.contains(current);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Support both "notification" payload and "data-only" messages (e.g. from FCM console)
    final notification = message.notification;
    final data = message.data;
    if (!_payloadBelongsToCurrentUser(data)) {
      if (kDebugMode) {
        debugPrint('Foreground FCM ignored (wrong account / signed out)');
      }
      return;
    }
    final type = (data['type'] as String?)?.toLowerCase() ?? '';
    final title = notification?.title ?? data['title'] as String? ?? 'Vero360';
    final body = notification?.body ?? data['body'] as String? ?? 'New notification';
    if (kDebugMode) debugPrint("Foreground FCM received");

    // Driver ride offers: feed the same overlay path as WebSocket.
    if (type == 'new_ride') {
      unawaited(DriverRideOfferInbox.instance.ingestFcm(Map<String, dynamic>.from(data)));
      try {
        await DriverRideAlertNotifications.showIncomingOffer(
          plugin: _localNotifications,
          data: Map<String, dynamic>.from(data),
          fullScreen: false,
        );
      } catch (e) {
        if (kDebugMode) debugPrint("Show ride local notification failed");
      }
      return;
    }

    final id = message.messageId ?? 'fcm_${message.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    // Chat alerts: WS shows the foreground tray banner; FCM notification payload
    // already drives the iOS system banner when presentation options are on.
    // Showing another local here doubles banners (especially on iOS).
    if (type == 'new_message') {
      BackendChatService.refreshThreads();
      final chatId = (data['chatId'] ?? data['chat_id'] ?? '').toString().trim();
      final active = (BackendChatService.activeChatId ?? '').trim();
      if (chatId.isNotEmpty && active.isNotEmpty && chatId == active) {
        return;
      }
      // iOS: OS already displayed the FCM `notification` payload.
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          notification != null) {
        return;
      }
      try {
        await showNewChatMessageNotification(
          senderName: title,
          body: body,
          chatId: chatId.isEmpty ? id : chatId,
          peerUserId: int.tryParse(
            (data['peerUserId'] ?? data['senderId'] ?? '').toString(),
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Chat FCM notify failed: $e');
      }
      return;
    }

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
    if (!_payloadBelongsToCurrentUser(message.data)) return;
    final n = message.notification;
    final data = message.data;
    final type = (data['type'] as String?)?.toLowerCase() ?? '';
    final title = n?.title ?? data['title'] as String? ?? 'Notification';
    final body = n?.body ?? data['body'] as String? ?? '';
    if (type == 'new_message') {
      final chatId = (data['chatId'] ?? data['chat_id'] ?? '').toString().trim();
      unawaited(showNewChatMessageNotification(
        senderName: title,
        body: body.isEmpty ? 'Sent you a message' : body,
        chatId: chatId.isEmpty
            ? (message.messageId ?? 'chat')
            : chatId,
        peerUserId: int.tryParse(
          (data['peerUserId'] ?? data['senderId'] ?? '').toString(),
        ),
      ));
      return;
    }
    final id = message.messageId ?? 'fcm_${message.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    NotificationStore.instance.addNotification(
      id: id,
      title: title,
      body: body,
      payload: data,
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
      if (actionId == DriverRideAlertNotifications.acceptActionId) {
        if (data != null) instance._navigateBasedOnPayload(data);
        return;
      }
      if (actionId == DriverRideAlertNotifications.declineActionId) {
        final rideId = (data?['rideId'] ?? data?['id'] ?? '').toString();
        if (rideId.isNotEmpty) {
          unawaited(DriverRideAlertNotifications.cancelOffer(rideId));
        }
        return;
      }
      if (actionId == _actionReply && response.input != null) {
        instance._submitReply(data ?? {}, response.input!.trim());
        return;
      }
      if (actionId == _actionLike) {
        instance._submitReaction(data ?? {});
        return;
      }
    }

    // User tapped the notification body â†’ navigate
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
        if (kDebugMode) debugPrint("Notification reply sent âœ…");
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
        if (kDebugMode) debugPrint("Notification reaction sent âœ…");
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  Display local notification
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool interactive = false,
    bool rideRequest = false,
  }) async {
    final channel = rideRequest ? _rideRequestChannel : _highPriorityChannel;
    final safeTitle = DescriptionContactMask.mask(title);
    final safeBody = DescriptionContactMask.mask(body);
    await _localNotifications.show(
      id,
      safeTitle,
      safeBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          visibility: NotificationVisibility.public,
          category: rideRequest ? AndroidNotificationCategory.call : null,
          fullScreenIntent: rideRequest,
          actions: interactive ? _interactiveActions : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: payload,
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  Navigation logic (customize based on your needs)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Routes the user from an in-app or push notification payload.
  static void navigateFromPayload(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    instance._navigateWithNavigator(Navigator.of(context), data);
  }

  void _navigateBasedOnPayload(Map<String, dynamic> data) {
    final navigator = _navKey?.currentState;
    if (navigator == null) return;
    _navigateWithNavigator(navigator, data);
  }

  void _openChatThread(
    NavigatorState navigator,
    Map<String, dynamic> data,
    String chatId,
  ) {
    var peerName = (data['senderName'] ??
            data['peerName'] ??
            data['title'] ??
            '')
        .toString()
        .trim();
    var avatarRaw =
        (data['peerAvatarUrl'] ?? data['avatarUrl'] ?? '').toString().trim();
    final merchantRaw =
        (data['peerMerchantId'] ?? data['merchantId'] ?? '').toString().trim();
    var peerUserId = int.tryParse(
      (data['peerUserId'] ?? data['senderId'] ?? '').toString().trim(),
    );

    // Notification-centre payloads often lack the name â€” resolve from inbox cache.
    final cached = BackendChatService.findCachedThreadById(chatId);
    if (cached != null) {
      final resolved = BackendChatService.cachedPeerLabelForChat(chatId);
      if (_isPlaceholderChatPeerName(peerName) &&
          resolved != null &&
          !_isPlaceholderChatPeerName(resolved.name)) {
        peerName = resolved.name;
      }
      if (avatarRaw.isEmpty && resolved != null && resolved.avatarUrl.isNotEmpty) {
        avatarRaw = resolved.avatarUrl;
      }
      if ((peerUserId == null || peerUserId <= 0) &&
          resolved != null &&
          (resolved.peerUserId ?? 0) > 0) {
        peerUserId = resolved.peerUserId;
      }
    }

    BackendChatService.setActiveChatId(chatId);
    unawaited(BackendMessagingSocket.connect().catchError((_) {}));
    navigator
        .push(
      MaterialPageRoute(
        builder: (_) => MessagePageBackendApi(
          peerId: chatId,
          peerName: _isPlaceholderChatPeerName(peerName) ? 'Chat' : peerName,
          peerAvatarUrl: avatarRaw.isEmpty ? null : avatarRaw,
          peerMerchantId: merchantRaw.isEmpty ? null : merchantRaw,
          peerUserId: peerUserId,
        ),
      ),
    )
        .then((_) {
      BackendChatService.clearThreadUnread(chatId);
      BackendChatService.setActiveChatId(null);
      BackendChatService.refreshThreads();
    });
  }

  static bool _isPlaceholderChatPeerName(String raw) =>
      ChatParticipant.isPlaceholderName(raw);

  bool _tryNavigateFromBadgeRoute(
    NavigatorState navigator,
    String? badgeRoute,
    Map<String, dynamic> data,
  ) {
    final route = (badgeRoute ?? '').trim().toLowerCase();
    if (route.isEmpty) return false;

    switch (route) {
      case NotificationStore.kBadgeRefund:
        navigator.push(
          MaterialPageRoute(builder: (_) => const ToRefundPage()),
        );
        return true;
      case NotificationStore.kBadgeReceived:
        navigator.push(
          MaterialPageRoute(builder: (_) => const DeliveredOrdersPage()),
        );
        return true;
      case NotificationStore.kBadgeShipped:
        navigator.push(
          MaterialPageRoute(builder: (_) => const ToShipPage()),
        );
        return true;
      case NotificationStore.kBadgeMyOrders:
        navigator.push(
          MaterialPageRoute(
            builder: (_) => OrdersPage(
              initialOrderId: data['orderId']?.toString(),
              initialOrderNumber: data['orderNumber']?.toString(),
              initialStatus: data['status']?.toString(),
            ),
          ),
        );
        return true;
      case NotificationStore.kBadgeDigitalOrders:
        _openDigitalMyOrders(navigator, data);
        return true;
      case NotificationStore.kBadgePromotions:
        unawaited(_openPromotionTarget(navigator, data));
        return true;
      case NotificationStore.kBadgePostArrival:
        unawaited(_openArrivalTarget(navigator, data));
        return true;
      case NotificationStore.kBadgeAppUpdate:
      case 'quick_app_update':
      case 'store_update':
        unawaited(_openAppStoreUpdate());
        return true;
      case NotificationStore.kBadgeVeroTeam:
      case 'vero360_team':
        return false; // handled via openChat / type in _navigateWithNavigator
      default:
        return false;
    }
  }

  static bool _isDigitalServicesPayload(Map<String, dynamic> data) {
    String s(dynamic v) => (v ?? '').toString().trim().toLowerCase();
    final type = s(data['type']);
    final badge = s(
      data['badgeRoute'] ?? data[NotificationStore.kPayloadBadgeRoute],
    );
    if (badge == NotificationStore.kBadgeDigitalOrders) return true;
    if (type.contains('digital')) return true;
    if (s(data['collection']).contains('digital_service')) return true;
    if (s(data['digitalOrderId']).isNotEmpty) return true;
    final productKey = s(data['productKey']);
    if (productKey.startsWith('netflix') ||
        productKey.startsWith('chatgpt') ||
        productKey.contains('digital')) {
      return true;
    }
    final hay = '${s(data['title'])} ${s(data['body'])} ${s(data['productName'])}';
    if (hay.contains('digital order') ||
        hay.contains('my digital') ||
        hay.contains('digital service')) {
      return true;
    }
    return false;
  }

  void _openDigitalMyOrders(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) {
    final orderId = (data['orderId'] ?? data['digitalOrderId'] ?? '')
        .toString()
        .trim();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => DigitalMyOrdersPage(
          initialOrderId: orderId.isEmpty ? null : orderId,
        ),
      ),
    );
  }

  void _navigateWithNavigator(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) {
    final type = (data['type'] ?? '').toString().toLowerCase();
    final badgeRoute = (data['badgeRoute'] ??
            data[NotificationStore.kPayloadBadgeRoute] ??
            '')
        .toString()
        .toLowerCase();
    final openChat = (data['openChat'] ?? '').toString().trim().toLowerCase();

    if (_isDigitalServicesPayload(data)) {
      if (kDebugMode) debugPrint('→ Open My Digital Orders');
      _openDigitalMyOrders(navigator, data);
      return;
    }

    switch (type) {
      case 'reel_live':
        unawaited(openLiveFromNotification(navigator, data));
        return;
      case 'reel_posted':
        unawaited(openReelFromNotification(navigator, data));
        return;
      case 'new_ride':
        final rideId = (data['rideId'] ?? data['id'] ?? '').toString().trim();
        if (rideId.isEmpty) {
          if (kDebugMode) debugPrint("â†’ new_ride missing rideId");
          break;
        }
        if (_openedRideOfferId == rideId &&
            _openedRideOfferAt != null &&
            DateTime.now().difference(_openedRideOfferAt!) <
                const Duration(seconds: 4)) {
          break;
        }
        _openedRideOfferId = rideId;
        _openedRideOfferAt = DateTime.now();
        if (kDebugMode) debugPrint("â†’ Open driver ride accept ($rideId)");
        navigator.push(MaterialPageRoute(
          builder: (_) => DriverIncomingRideFromNotificationPage(
            rideId: rideId,
            fcmData: Map<String, dynamic>.from(data),
          ),
        ));
        break;

      case 'ride_update':
        if (kDebugMode) debugPrint("â†’ Open ride notifications");
        navigator.push(MaterialPageRoute(
          builder: (_) => const NotificationsPage(),
        ));
        break;

      case 'new_message':
      case 'chat_message':
        final chatId =
            (data['chatId'] ?? data['threadId'] ?? '').toString().trim();
        if (chatId.isNotEmpty) {
          if (kDebugMode) debugPrint('â†’ Open chat thread ($chatId)');
          _openChatThread(navigator, data, chatId);
        } else {
          if (kDebugMode) debugPrint('â†’ Open chat list');
          navigator.push(
            MaterialPageRoute(builder: (_) => const ChatListPage()),
          );
        }
        break;

      case 'refund_request':
      case 'refund_update':
        if (kDebugMode) debugPrint('â†’ Open refund');
        final refundOrderId = data['orderId']?.toString();
        if (refundOrderId != null && refundOrderId.trim().isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => OrdersPage(
                initialOrderId: refundOrderId,
                initialOrderNumber: data['orderNumber']?.toString(),
                initialStatus: data['status']?.toString(),
              ),
            ),
          );
        } else {
          navigator.push(
            MaterialPageRoute(builder: (_) => const ToRefundPage()),
          );
        }
        break;

      case 'order_update':
        if (kDebugMode) debugPrint("â†’ Open order");
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

      case 'food_order_placed':
      case 'food_sent':
        if (kDebugMode) debugPrint('â†’ Open food my orders');
        navigator.push(
          MaterialPageRoute(builder: (_) => const FoodMyOrdersPage()),
        );
        break;

      case 'food_order':
      case 'new_food_order':
        if (kDebugMode) debugPrint("â†’ Open food merchant dashboard");
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        openVeroMainShell(navigator.context, email: email, tabIndex: 4);
        break;

      case 'story_posted':
      case 'story_liked':
        if (kDebugMode) debugPrint('â†’ Open home for story');
        final storyEmail = FirebaseAuth.instance.currentUser?.email ?? '';
        openVeroMainShell(navigator.context, email: storyEmail, tabIndex: 0);
        break;

      case 'new_review':
        if (kDebugMode) debugPrint('â†’ Open merchant reviews / dashboard');
        final reviewEmail = FirebaseAuth.instance.currentUser?.email ?? '';
        openVeroMainShell(navigator.context, email: reviewEmail, tabIndex: 4);
        break;

      case 'marketplace_moderation':
        if (kDebugMode) debugPrint('â†’ Open marketplace listing (moderation)');
        final modStatus =
            (data['status'] ?? '').toString().trim().toLowerCase();
        final modTitle =
            (data['title'] ?? '').toString().trim().toLowerCase();
        final modBody =
            (data['body'] ?? '').toString().trim().toLowerCase();
        final isRejected = modStatus == 'rejected' ||
            modTitle.contains('not approved') ||
            modBody.contains('not approved') ||
            modBody.contains('rejected');
        if (isRejected) {
          final email = FirebaseAuth.instance.currentUser?.email ?? '';
          navigator.push(
            MaterialPageRoute(
              builder: (_) => MarketplaceMerchantDashboard(
                email: email,
                merchantUid: FirebaseAuth.instance.currentUser?.uid,
                onBackToHomeTab: () {},
              ),
            ),
          );
        } else {
          unawaited(_openMarketplaceTarget(navigator, data));
        }
        break;

      case 'accommodation_booking':
        if (kDebugMode) debugPrint('â†’ Open stay bookings');
        navigator.push(
          MaterialPageRoute(
            builder: (_) => const AccommodationMainPage(initialTabIndex: 1),
          ),
        );
        break;

      case 'promo_digest':
      case 'promotion':
      case 'promotions':
        if (kDebugMode) debugPrint("â†’ Open promotions");
        unawaited(_openPromotionTarget(navigator, data));
        break;

      case 'arrivals_digest':
      case 'latest_arrivals':
      case 'todays_arrivals':
        if (kDebugMode) debugPrint("â†’ Open today's arrivals");
        unawaited(_openArrivalTarget(navigator, data));
        break;

      case 'marketplace_digest':
      case 'marketplace':
      case 'new_product':
        if (kDebugMode) debugPrint("â†’ Open marketplace");
        unawaited(_openMarketplaceTarget(navigator, data));
        break;

      case 'admin_broadcast':
      case 'admin':
        if (badgeRoute == NotificationStore.kBadgeAppUpdate ||
            badgeRoute == 'quick_app_update' ||
            badgeRoute == 'store_update') {
          unawaited(_openAppStoreUpdate());
        } else if ((data['promoId']?.toString() ?? '').trim().isNotEmpty ||
            badgeRoute == NotificationStore.kBadgePromotions) {
          unawaited(_openPromotionTarget(navigator, data));
        } else if ((data['arrivalId']?.toString() ?? '').trim().isNotEmpty ||
            badgeRoute == NotificationStore.kBadgePostArrival) {
          unawaited(_openArrivalTarget(navigator, data));
        } else if (badgeRoute == 'marketplace' ||
            badgeRoute == 'quick_marketplace') {
          unawaited(_openMarketplaceTarget(navigator, data));
        } else {
          navigator.push(
            MaterialPageRoute(builder: (_) => const NotificationsPage()),
          );
        }
        break;

      case 'app_update':
      case 'store_update':
        if (kDebugMode) debugPrint('â†’ Open store for app update');
        unawaited(_openAppStoreUpdate());
        break;

      case 'vero_team':
      case 'vero360_team':
        if (kDebugMode) debugPrint('â†’ Open Vero360 Team chat');
        navigator.push(
          MaterialPageRoute(builder: (_) => const VeroTeamChatPage()),
        );
        break;

      case 'engagement':
        // Generic keep-alive â€” route by badge / ids if present.
        if ((data['promoId']?.toString() ?? '').trim().isNotEmpty ||
            badgeRoute == NotificationStore.kBadgePromotions) {
          unawaited(_openPromotionTarget(navigator, data));
        } else if ((data['arrivalId']?.toString() ?? '').trim().isNotEmpty ||
            badgeRoute == NotificationStore.kBadgePostArrival) {
          unawaited(_openArrivalTarget(navigator, data));
        } else {
          unawaited(_openMarketplaceTarget(navigator, data));
        }
        break;

      default:
        if (_tryNavigateFromBadgeRoute(navigator, badgeRoute, data)) {
          break;
        }
        if ((data['orderId']?.toString() ?? '').trim().isNotEmpty ||
            (data['orderNumber']?.toString() ?? '').trim().isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => OrdersPage(
                initialOrderId: data['orderId']?.toString(),
                initialOrderNumber: data['orderNumber']?.toString(),
                initialStatus: data['status']?.toString(),
              ),
            ),
          );
          break;
        }
        final chatId =
            (data['chatId'] ?? data['threadId'] ?? '').toString().trim();
        if (chatId.isNotEmpty) {
          _openChatThread(navigator, data, chatId);
          break;
        }
        if ((data['promoId']?.toString() ?? '').trim().isNotEmpty ||
            badgeRoute == NotificationStore.kBadgePromotions) {
          unawaited(_openPromotionTarget(navigator, data));
        } else if ((data['arrivalId']?.toString() ?? '').trim().isNotEmpty ||
            badgeRoute == NotificationStore.kBadgePostArrival) {
          unawaited(_openArrivalTarget(navigator, data));
        } else if ((data['marketplaceItemId']?.toString() ?? '')
            .trim()
            .isNotEmpty) {
          unawaited(_openMarketplaceTarget(navigator, data));
        } else if (openChat == 'vero360_team' ||
            openChat == VeroTeamChatPage.threadId) {
          navigator.push(
            MaterialPageRoute(builder: (_) => const VeroTeamChatPage()),
          );
        } else if (kDebugMode) {
          debugPrint('â†’ No route for notification type=$type');
        }
    }
  }

  /// Open Play Store (Android) or App Store (iOS) when an update push is tapped.
  Future<void> _openAppStoreUpdate() async {
    try {
      final ok = await AppUpdateChecker.openStoreForThisPlatform();
      if (!ok && kDebugMode) {
        debugPrint('â†’ Could not open store for app update');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('â†’ openStoreForThisPlatform failed: $e');
    }
  }

  Future<void> _openPromotionTarget(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    if (!navigator.mounted) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => const PromotionsPage(),
    ));

    final rawId = (data['promoId'] ?? data['id'] ?? '').toString().trim();
    final promoId = int.tryParse(rawId);
    if (promoId == null || promoId <= 0) return;

    try {
      final promos = await PromoService().fetchActivePromos();
      PromoModel? match;
      for (final p in promos) {
        if (p.id == promoId) {
          match = p;
          break;
        }
      }
      if (match != null && navigator.mounted) {
        navigator.push(MaterialPageRoute(
          builder: (_) => PromoDetailPage(promo: match!),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Open promo target failed: $e');
    }
  }

  Future<void> _openArrivalTarget(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    final arrivalId = (data['arrivalId'] ?? data['id'] ?? '').toString().trim();
    if (!navigator.mounted) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text("Today's arrivals")),
        body: LatestArrivalsSection(
          initialArrivalId: arrivalId.isEmpty ? null : arrivalId,
          autoOpenInitial: arrivalId.isNotEmpty,
        ),
      ),
    ));
  }

  Future<void> _openMarketplaceTarget(
    NavigatorState navigator,
    Map<String, dynamic> data,
  ) async {
    final docId =
        (data['marketplaceItemId'] ?? data['itemId'] ?? data['id'] ?? '')
            .toString()
            .trim();
    final cart = CartServiceProvider.getInstance();
    if (!navigator.mounted) return;

    if (docId.isEmpty) {
      navigator.push(MaterialPageRoute(
        builder: (_) => MarketPage(cartService: cart),
      ));
      return;
    }

    final open = await _resolveMarketplaceOpen(docId);
    if (!navigator.mounted) return;

    if (open.kind == _MarketplaceOpenKind.sellerManage) {
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      navigator.push(
        MaterialPageRoute(
          builder: (_) => MarketplaceMerchantDashboard(
            email: email,
            merchantUid: FirebaseAuth.instance.currentUser?.uid,
            onBackToHomeTab: () {},
          ),
        ),
      );
      return;
    }

    if (open.kind == _MarketplaceOpenKind.unavailable) {
      ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
        const SnackBar(content: Text('This listing is no longer available.')),
      );
      navigator.push(MaterialPageRoute(
        builder: (_) => MarketPage(cartService: cart),
      ));
      return;
    }

    navigator.push(MaterialPageRoute(
      builder: (_) => _MarketplaceNotificationDestination(
        cartService: cart,
        resolveFuture: Future.value(open.item),
      ),
    ));
  }

  Future<_MarketplaceOpenResult> _resolveMarketplaceOpen(String docId) async {
    final sqlId = int.tryParse(docId);
    if (sqlId != null && sqlId > 0) {
      try {
        final item = await MarketplaceService().getItemDetails(sqlId);
        if (item != null) {
          return _MarketplaceOpenResult.item(item);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Resolve marketplace SQL item failed: $e');
      }
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .doc(docId)
          .get();
      if (!doc.exists) return const _MarketplaceOpenResult.unavailable();
      final data = doc.data() ?? <String, dynamic>{};
      final review =
          (data['reviewStatus'] ?? '').toString().trim().toLowerCase();
      final inactive = data['isActive'] == false;
      final blocked = review == 'pending' || review == 'rejected' || inactive;
      if (blocked) {
        if (_isCurrentUserMarketplaceSeller(data)) {
          return const _MarketplaceOpenResult.sellerManage();
        }
        // Rejected/pending must not open as a public product page.
        return const _MarketplaceOpenResult.unavailable();
      }
      return _MarketplaceOpenResult.item(_marketplaceItemFromFirestore(doc));
    } catch (e) {
      if (kDebugMode) debugPrint('Resolve marketplace Firestore item failed: $e');
    }
    return const _MarketplaceOpenResult.unavailable();
  }

  bool _isCurrentUserMarketplaceSeller(Map<String, dynamic> data) {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return false;
    for (final key in const [
      'sellerUserId',
      'merchantId',
      'firebaseUid',
      'ownerId',
      'uid',
    ]) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty && v == uid) return true;
    }
    return false;
  }

  market.MarketplaceDetailModel _marketplaceItemFromFirestore(
    DocumentSnapshot doc,
  ) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    int? sqlId;
    final rawSql = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'];
    if (rawSql is int) {
      sqlId = rawSql;
    } else if (rawSql != null) {
      sqlId = int.tryParse(rawSql.toString());
    }
    final id = sqlId ?? doc.id.hashCode.abs();
    final image = (data['imageUrl'] ?? data['image'] ?? data['photo'] ?? '')
        .toString()
        .trim();
    List<String> gallery = const [];
    final g = data['galleryUrls'] ?? data['gallery'];
    if (g is List) {
      gallery = g.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    double price = 0;
    final p = data['price'];
    if (p is num) {
      price = p.toDouble();
    } else if (p != null) {
      price = double.tryParse(p.toString()) ?? 0;
    }
    DateTime? created;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) created = createdRaw.toDate();

    return market.MarketplaceDetailModel(
      id: id,
      name: (data['name'] ?? data['title'] ?? data['productName'] ?? 'Item')
          .toString(),
      image: image,
      price: price,
      description: (data['description'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      gallery: gallery,
      merchantId: (data['merchantId'] ?? '').toString(),
      merchantName: (data['merchantName'] ?? '').toString(),
      sellerUserId: (data['sellerUserId'] ?? '').toString(),
      serviceProviderId: (data['serviceProviderId'] ?? '').toString(),
      serviceType: (data['serviceType'] ?? 'marketplace').toString(),
      firestoreDocId: doc.id,
      createdAt: created,
    );
  }

  /// Push / manual payloads can include `badgeRoute` for quick-action badges, e.g.
  /// `quick_my_orders`, `quick_shipped`, `quick_received`, `quick_refund`, `quick_promotions`,
  /// `quick_post_arrival` (see [NotificationStore] constants).

  /// Push / in-app alert when a new chat message arrives (WebSocket / Firestore / FCM).
  Future<void> showNewChatMessageNotification({
    required String senderName,
    required String body,
    required String chatId,
    int? peerUserId,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final safeChatId = chatId.trim().isEmpty ? 'chat' : chatId.trim();
    final rawSender =
        senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final safeSender = DescriptionContactMask.mask(rawSender);
    final safeBody = DescriptionContactMask.mask(body);
    final payloadMap = <String, dynamic>{
      'type': 'new_message',
      'chatId': safeChatId,
      'badgeRoute': 'messages',
      // Keep name in payload so notification-centre / tray taps open with title.
      'senderName': safeSender,
      'title': safeSender,
      if (peerUserId != null && peerUserId > 0) 'peerUserId': peerUserId,
    };
    final payload = jsonEncode(payloadMap);
    // Stable-enough id so rapid WS+Firestore+FCM copies collapse in the store.
    final id =
        'chat_${safeChatId}_${safeSender.hashCode}_${safeBody.trim().hashCode}';
    final added = await NotificationStore.instance.addNotification(
      id: id,
      title: safeSender,
      body: safeBody,
      payload: payloadMap,
    );
    // Skip second tray banner when WS/Firestore/FCM all fire for the same message.
    if (!added) return;
    await _showLocalNotification(
      id: safeChatId.hashCode.abs(),
      title: safeSender,
      body: safeBody,
      payload: payload,
    );
  }

  /// Show a local notification manually. Set [interactive] true to show Reply + Like actions.
  Future<void> showManualNotification({
    required String title,
    required String body,
    String? payload,
    bool interactive = false,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final id = 'manual_${DateTime.now().millisecondsSinceEpoch}';
    Map<String, dynamic> payloadMap = {};
    if (payload != null && payload.isNotEmpty) {
      try {
        payloadMap = jsonDecode(payload) as Map<String, dynamic>? ?? {};
      } catch (_) {}
    }
    if (payloadMap.isNotEmpty && !_payloadBelongsToCurrentUser(payloadMap)) {
      return;
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
  /// [merchantService] refines copy for merchants (e.g. `accommodation`).
  Future<void> sendWelcomeNotificationIfFirstTime({
    required String uid,
    required String name,
    String? role,
    String? merchantService,
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'welcome_notification_sent_$cleanUid';
    if (prefs.getBool(key) == true) return;

    final safeName = name.trim().isEmpty ? 'there' : name.trim();
    final normalizedRole = (role ?? '').trim().toLowerCase();
    final normalizedService = (merchantService ?? '').trim().toLowerCase();

    late final String title;
    late final String body;
    if (normalizedRole == 'merchant' && normalizedService == 'accommodation') {
      title = 'Welcome to Vero accommodation, $safeName!';
      body =
          'Your merchant account is ready. List your property, manage guest bookings, '
          'handle payments, and grow your stay business â€” all from this app.';
    } else if (normalizedRole == 'merchant' && normalizedService == 'food') {
      title = 'Welcome to Vero food & restaurant, $safeName!';
      body =
          'Set up your restaurant, post food, manage orders, and accept payments â€” '
          'all from this app.';
    } else if (normalizedRole == 'merchant') {
      title = 'Welcome to Vero360 Merchant Account, $safeName!';
      body =
          'Start listing your products and services, manage orders, and grow your business in one app.';
    } else if (normalizedRole == 'driver') {
      title = 'Welcome to Vero360 Driver Account, $safeName!';
      body =
          'Start accepting rides, manage trips, and track your earnings with the all-in-one Vero360 app.';
    } else {
      title = 'Welcome to Vero360, $safeName!';
      body =
          'Vero360 is your all-in-one app for rides, marketplace, food, transport, accommodation, and more.';
    }

    final payloadMap = <String, dynamic>{
      'type': 'welcome',
      'uid': cleanUid,
      'role': normalizedRole,
      if (normalizedService.isNotEmpty) 'merchantService': normalizedService,
    };

    await showManualNotification(
      title: title,
      body: body,
      payload: jsonEncode(payloadMap),
    );

    await prefs.setBool(key, true);
  }

  /// After PawaPay success: notify the guest on this device and queue a Firestore
  /// alert for the host (same [OrderPartyNotificationService] pipe as marketplace escrow).
  Future<void> notifyAccommodationBookingForGuestAndHost({
    required String propertyName,
    required String bookingRef,
    String? hostMerchantUid,
    String? guestDisplayLine,
    String? guestEmail,
    String? checkInLabel,
    /// Prefer this (e.g. "2 nights", "1 day", "1 month") over raw [nights].
    String? staySummary,
    int? nights,
  }) async {
    final prop =
        propertyName.trim().isEmpty ? 'your stay' : propertyName.trim();
    final ref = bookingRef.trim();
    if (ref.isEmpty) return;
    final displayRef = formatVeroAccommodationBookingRef(ref);

    final cin = (checkInLabel ?? '').trim();
    final summary = (staySummary ?? '').trim();
    final n = nights ?? 0;
    final durationLabel = summary.isNotEmpty
        ? summary
        : (n > 0 ? '$n night${n == 1 ? '' : 's'}' : '');
    final stayBits = <String>[
      if (cin.isNotEmpty) 'Check-in $cin',
      if (durationLabel.isNotEmpty) durationLabel,
    ];
    final staySeg = stayBits.isEmpty ? '' : ' ${stayBits.join(' Â· ')}.';

    await showManualNotification(
      title: 'Stay booked',
      body: displayRef.isEmpty
          ? 'Your booking at $prop is confirmed.$staySeg'
          : 'Your booking at $prop is confirmed.$staySeg Ref $displayRef.',
      payload: jsonEncode({
        'type': 'accommodation_booking',
        'bookingRef': displayRef.isEmpty ? ref : displayRef,
        'role': 'guest',
      }),
    );

    final host = hostMerchantUid?.trim() ?? '';
    if (host.isNotEmpty) {
      await OrderPartyNotificationService.publishAccommodationBookingToHost(
        hostUid: host,
        propertyName: prop,
        bookingRef: displayRef.isEmpty ? ref : displayRef,
        guestLine: guestDisplayLine,
        guestEmail: guestEmail,
        checkInLabel: checkInLabel,
        staySummary: staySummary,
        nights: nights,
        fromUid: FirebaseAuth.instance.currentUser?.uid,
      );
    } else if (kDebugMode) {
      debugPrint(
        '[NotificationService] No hostMerchantUid on listing â€” host will not get '
        'Firestore booking alert. Expose host Firebase UID on GET /vero/accommodations.',
      );
    }
  }
}

/// Shows a loading screen immediately, then product detail or marketplace home.
class _MarketplaceNotificationDestination extends StatelessWidget {
  const _MarketplaceNotificationDestination({
    required this.cartService,
    required this.resolveFuture,
  });

  final CartService cartService;
  final Future<market.MarketplaceDetailModel?> resolveFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<market.MarketplaceDetailModel?>(
      future: resolveFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Marketplace')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final item = snap.data;
        if (item != null) {
          return DetailsPage(item: item, cartService: cartService);
        }
        return MarketPage(cartService: cartService);
      },
    );
  }
}

enum _MarketplaceOpenKind { item, sellerManage, unavailable }

class _MarketplaceOpenResult {
  final _MarketplaceOpenKind kind;
  final market.MarketplaceDetailModel? item;

  const _MarketplaceOpenResult._(this.kind, this.item);

  const _MarketplaceOpenResult.unavailable()
      : this._(_MarketplaceOpenKind.unavailable, null);

  const _MarketplaceOpenResult.sellerManage()
      : this._(_MarketplaceOpenKind.sellerManage, null);

  factory _MarketplaceOpenResult.item(market.MarketplaceDetailModel item) =>
      _MarketplaceOpenResult._(_MarketplaceOpenKind.item, item);
}