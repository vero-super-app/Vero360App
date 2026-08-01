import 'package:flutter/material.dart';

/// Widget to initialize messaging when driver app loads
/// Note: Push notifications are now handled via WebSocket messaging (driver_messaging_service)
class PushNotificationInitializer extends StatefulWidget {
  final String driverId;
  final Widget child;

  const PushNotificationInitializer({
    super.key,
    required this.driverId,
    required this.child,
  });

  @override
  State<PushNotificationInitializer> createState() =>
      _PushNotificationInitializerState();
}

class _PushNotificationInitializerState
    extends State<PushNotificationInitializer> {
  @override
  void initState() {
    super.initState();
    _initializeMessaging();
  }

  Future<void> _initializeMessaging() async {
    try {
      // Messaging is now handled via WebSocket connection
      // The WebSocket service will handle incoming messages and notifications
      print('Messaging initialized for driver: ${widget.driverId}');
    } catch (e) {
      print('Error initializing messaging: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
