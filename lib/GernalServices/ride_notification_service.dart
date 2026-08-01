import 'package:cloud_functions/cloud_functions.dart';

class RideNotificationService {
  static final _functions = FirebaseFunctions.instance;

  /// Send ride request notification to available drivers
  /// This should be called after a ride request is created
  static Future<void> notifyDriversOfNewRide({
    required String rideId,
    required String passengerId,
    required String passengerName,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required String pickupAddress,
    required String dropoffAddress,
    required double estimatedFare,
    required int estimatedTime,
    required double estimatedDistance,
  }) async {
    try {
      // Call Cloud Function to send notifications to drivers
      final result = await _functions
          .httpsCallable('notifyDriversOfNewRide')
          .call({
        'rideId': rideId,
        'passengerId': passengerId,
        'passengerName': passengerName,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'pickupAddress': pickupAddress,
        'dropoffAddress': dropoffAddress,
        'estimatedFare': estimatedFare,
        'estimatedTime': estimatedTime,
        'estimatedDistance': estimatedDistance,
      });

      print('Notification sent to drivers: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      print('Error calling Cloud Function: ${e.code} ${e.message}');
      // Don't throw - ride was already created successfully
      // Notification failure shouldn't prevent ride creation
    } catch (e) {
      print('Error notifying drivers: $e');
      // Don't throw - ride was already created successfully
    }
  }

  /// Send notification to specific driver
  /// Used for driver-specific messages during an active ride
  static Future<void> notifyDriver({
    required String driverId,
    required String title,
    required String message,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _functions.httpsCallable('notifyDriver').call({
        'driverId': driverId,
        'title': title,
        'message': message,
        'data': data,
      });

      print('Notification sent to driver: $driverId');
    } catch (e) {
      print('Error notifying driver: $e');
    }
  }

  /// Send notification to passenger
  static Future<void> notifyPassenger({
    required String passengerId,
    required String title,
    required String message,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _functions.httpsCallable('notifyPassenger').call({
        'passengerId': passengerId,
        'title': title,
        'message': message,
        'data': data,
      });

      print('Notification sent to passenger: $passengerId');
    } catch (e) {
      print('Error notifying passenger: $e');
    }
  }

  /// Send ride status update notification
  /// Called when ride status changes (accepted, arrived, completed, etc)
  static Future<void> sendRideStatusUpdate({
    required String passengerId,
    required String rideId,
    required String status,
    required String statusMessage,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _functions.httpsCallable('sendRideStatusUpdate').call({
        'passengerId': passengerId,
        'rideId': rideId,
        'status': status,
        'statusMessage': statusMessage,
        'data': additionalData ?? {},
      });

      print('Status update sent to passenger: $status');
    } catch (e) {
      print('Error sending status update: $e');
    }
  }
}
