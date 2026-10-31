import 'package:universal_io/io.dart' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:vero360_app/native/local_notifications.dart';
import 'package:vero360_app/features/ride_share/presentation/services/driver_ride_alert_notifications.dart';

/// Prompt for notification / lock-screen / battery settings when going online.
/// Failures never block going online.
class DriverOnlineAlertPermissions {
  DriverOnlineAlertPermissions._();

  static Future<void> ensure(BuildContext context) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}

    if (kIsWeb || !Platform.isAndroid) return;
    await DriverRideAlertNotifications.requestFullScreenIntentAccess();
    await DriverRideAlertNotifications.requestIgnoreBatteryOptimizations();
  }
}
