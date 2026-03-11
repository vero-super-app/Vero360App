import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'dart:async';

/// Notification state for incoming ride request
class RideNotification {
  final String id;
  final DriverRideRequest rideRequest;
  final DateTime receivedAt;
  final bool isViewed;

  RideNotification({
    required this.id,
    required this.rideRequest,
    required this.receivedAt,
    this.isViewed = false,
  });

  RideNotification copyWith({
    String? id,
    DriverRideRequest? rideRequest,
    DateTime? receivedAt,
    bool? isViewed,
  }) {
    return RideNotification(
      id: id ?? this.id,
      rideRequest: rideRequest ?? this.rideRequest,
      receivedAt: receivedAt ?? this.receivedAt,
      isViewed: isViewed ?? this.isViewed,
    );
  }
}

/// Service managing ride notifications
class RideNotificationService {
  final _notificationsController = StreamController<List<RideNotification>>.broadcast();
  final Map<String, RideNotification> _notifications = {};
  
  Stream<List<RideNotification>> get notificationsStream => _notificationsController.stream;
  List<RideNotification> get notifications => _notifications.values.toList();

  void addNotification(DriverRideRequest request) {
    final notification = RideNotification(
      id: request.id,
      rideRequest: request,
      receivedAt: DateTime.now(),
    );
    _notifications[request.id] = notification;
    _notificationsController.add(notifications);
    
    // Auto-remove after 30 seconds if not interacted
    Future.delayed(const Duration(seconds: 30), () {
      if (_notifications.containsKey(request.id)) {
        removeNotification(request.id);
      }
    });
  }

  void markAsViewed(String rideId) {
    if (_notifications.containsKey(rideId)) {
      _notifications[rideId] = _notifications[rideId]!.copyWith(isViewed: true);
      _notificationsController.add(notifications);
    }
  }

  void removeNotification(String rideId) {
    _notifications.remove(rideId);
    _notificationsController.add(notifications);
  }

  void clearAll() {
    _notifications.clear();
    _notificationsController.add([]);
  }

  void dispose() {
    _notificationsController.close();
  }
}

// Global singleton instance
final _rideNotificationServiceProvider = Provider<RideNotificationService>((ref) {
  return RideNotificationService();
});

/// Stream of all ride notifications
final rideNotificationsStreamProvider = StreamProvider<List<RideNotification>>((ref) {
  final service = ref.watch(_rideNotificationServiceProvider);
  return service.notificationsStream;
});

/// Get notification service
final rideNotificationServiceProvider = Provider<RideNotificationService>((ref) {
  return ref.watch(_rideNotificationServiceProvider);
});
