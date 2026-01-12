import 'package:flutter/material.dart';
import 'package:vero360_app/services/driver_push_notification_service.dart';

/// Widget to initialize push notifications when driver app loads
class PushNotificationInitializer extends StatefulWidget {
  final String driverId;
  final Widget child;

  const PushNotificationInitializer({
    Key? key,
    required this.driverId,
    required this.child,
  }) : super(key: key);

  @override
  State<PushNotificationInitializer> createState() =>
      _PushNotificationInitializerState();
}

class _PushNotificationInitializerState
    extends State<PushNotificationInitializer> {
  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    try {
      // Initialize FCM message handlers
      await DriverPushNotificationService.initializeMessaging(context);

      // Get and store FCM token
      await DriverPushNotificationService.getAndStoreToken(widget.driverId);

      // Listen for token refresh
      DriverPushNotificationService.listenToTokenRefresh();

      print('Push notifications initialized for driver: ${widget.driverId}');
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
