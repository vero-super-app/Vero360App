import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/services/driver_request_service.dart';

class DriverPushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Initialize FCM and set up message handlers
  static Future<void> initializeMessaging(BuildContext context) async {
    // Request permission for notifications
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Handle when app is terminated and opened from notification
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? remoteMessage) {
      if (remoteMessage != null) {
        _handleNotification(remoteMessage, context);
      }
    });

    // Handle when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage remoteMessage) {
      _handleNotification(remoteMessage, context);
    });

    // Handle when app is in background and notification is tapped
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage remoteMessage) {
      _handleNotification(remoteMessage, context);
    });
  }

  /// Handle incoming notifications
  static Future<void> _handleNotification(
    RemoteMessage message,
    BuildContext context,
  ) async {
    try {
      final rideId = message.data['rideId'];

      if (rideId == null) {
        print('Invalid notification: missing rideId');
        return;
      }

      // Fetch ride request details
      final ride = await DriverRequestService.getRideRequest(rideId);

      if (ride == null) {
        print('Ride request not found: $rideId');
        return;
      }

      // Show notification dialog if still pending
      if (ride.status == 'pending' && context.mounted) {
        _showRequestNotificationDialog(context, ride);
      }
    } catch (e) {
      print('Error handling notification: $e');
    }
  }

  /// Show modal dialog when notification arrives
  static void _showRequestNotificationDialog(
    BuildContext context,
    DriverRideRequest ride,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('New Ride Request'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDialogRow('Passenger', ride.passengerName),
              const SizedBox(height: 12),
              _buildDialogRow('Pickup', ride.pickupAddress),
              const SizedBox(height: 12),
              _buildDialogRow('Dropoff', ride.dropoffAddress),
              const SizedBox(height: 12),
              _buildDialogRow(
                'Fare',
                'MWK${ride.estimatedFare.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 8),
              _buildDialogRow('Time', '${ride.estimatedTime} mins'),
              const SizedBox(height: 8),
              _buildDialogRow(
                'Distance',
                '${ride.estimatedDistance.toStringAsFixed(1)} km',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to driver request screen or accept directly
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  /// Get and store FCM token for driver
  static Future<String?> getAndStoreToken(String driverId) async {
    try {
      final token = await _messaging.getToken();

      if (token != null) {
        // Store token in driver's profile
        await _db
            .ref()
            .child('drivers')
            .child(driverId)
            .update({
          'fcmToken': token,
          'tokenUpdatedAt': DateTime.now().millisecondsSinceEpoch,
        });

        print('FCM Token stored: $token');

        // Subscribe to topics
        await _subscribeToTopics(driverId);
      }

      return token;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe driver to FCM topics
  static Future<void> _subscribeToTopics(String driverId) async {
    try {
      // Subscribe to all drivers topic (for broadcast announcements)
      await _messaging.subscribeToTopic('allDrivers');

      // Subscribe to driver-specific topic for personalized notifications
      await _messaging.subscribeToTopic('driver_$driverId');

      print('Subscribed to FCM topics');
    } catch (e) {
      print('Error subscribing to topics: $e');
    }
  }

  /// Unsubscribe driver from FCM topics
  static Future<void> unsubscribeFromTopics(String driverId) async {
    try {
      await _messaging.unsubscribeFromTopic('allDrivers');
      await _messaging.unsubscribeFromTopic('driver_$driverId');
      print('Unsubscribed from FCM topics');
    } catch (e) {
      print('Error unsubscribing from topics: $e');
    }
  }

  /// Listen for token refresh (Firebase rotates tokens periodically)
  static void listenToTokenRefresh() {
    _messaging.onTokenRefresh.listen((String token) {
      print('FCM Token refreshed: $token');
      // Update token in database if needed
    });
  }

  /// Send test notification (for testing)
  static Future<void> sendTestNotification(String driverId) async {
    try {
      // In production, this would be called from your backend
      // For now, just log that it would be sent
      print('Test notification would be sent to driver: $driverId');
    } catch (e) {
      print('Error sending test notification: $e');
    }
  }
}

/// Data model for notification payload
class DriverNotificationPayload {
  final String rideId;
  final String passengerId;
  final String passengerName;
  final String pickupAddress;
  final String dropoffAddress;
  final double estimatedFare;
  final int estimatedTime;

  DriverNotificationPayload({
    required this.rideId,
    required this.passengerId,
    required this.passengerName,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.estimatedFare,
    required this.estimatedTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'rideId': rideId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'estimatedFare': estimatedFare,
      'estimatedTime': estimatedTime,
    };
  }

  factory DriverNotificationPayload.fromMap(Map<String, dynamic> map) {
    return DriverNotificationPayload(
      rideId: map['rideId'] ?? '',
      passengerId: map['passengerId'] ?? '',
      passengerName: map['passengerName'] ?? 'Unknown',
      pickupAddress: map['pickupAddress'] ?? '',
      dropoffAddress: map['dropoffAddress'] ?? '',
      estimatedFare: (map['estimatedFare'] as num?)?.toDouble() ?? 0.0,
      estimatedTime: map['estimatedTime'] ?? 0,
    );
  }
}

Widget _buildDialogRow(String label, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}
