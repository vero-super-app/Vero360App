import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local heads-up / full-screen ride offer used when the app is not in front.
class DriverRideAlertNotifications {
  DriverRideAlertNotifications._();

  static const channelId = 'driver_ride_requests';
  static const channelName = 'Driver Ride Requests';
  static const channelDescription = 'Incoming ride offers for drivers';
  static const acceptActionId = 'ride_accept';
  static const declineActionId = 'ride_decline';
  static const _platform = MethodChannel('vero365.app/driver_alerts');

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    channelId,
    channelName,
    description: channelDescription,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> ensureChannel(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> showIncomingOffer({
    required FlutterLocalNotificationsPlugin plugin,
    required Map<String, dynamic> data,
    bool fullScreen = true,
  }) async {
    await ensureChannel(plugin);
    final rideId = (data['rideId'] ?? data['id'] ?? '').toString();
    if (rideId.isEmpty) return;

    final title = (data['title'] ?? 'New Ride Request').toString();
    final pickup = (data['pickupAddress'] ?? '').toString().trim();
    final body = (data['body'] ?? '').toString().trim().isNotEmpty
        ? data['body'].toString()
        : (pickup.isNotEmpty ? pickup : 'Tap to accept this ride');

    await plugin.show(
      rideId.hashCode.abs(),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: fullScreen,
          visibility: NotificationVisibility.public,
          ticker: 'New Vero Ride request',
          timeoutAfter: 30000,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          actions: const [
            AndroidNotificationAction(
              acceptActionId,
              'Accept',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              declineActionId,
              'Decline',
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: jsonEncode(Map<String, dynamic>.from(data)),
    );
  }

  static Future<void> cancelOffer(String rideId) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.cancel(rideId.hashCode.abs());
    } catch (_) {}
  }

  /// Android 14+: open the full-screen intent settings page if needed.
  static Future<void> requestFullScreenIntentAccess() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _platform.invokeMethod<void>('requestFullScreenIntent');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DriverRideAlert] FSI permission: $e');
      }
    }
  }

  static Future<bool> canUseFullScreenIntent() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _platform.invokeMethod<bool>('canUseFullScreenIntent') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _platform.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DriverRideAlert] battery opt: $e');
      }
    }
  }
}

@pragma('vm:entry-point')
void onDriverRideNotificationBackgroundAction(NotificationResponse response) {
  // Accept uses showsUserInterface so the main isolate opens the popup.
  // Decline only dismisses the tray while the process is dead.
}
