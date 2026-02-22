import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

/// Facade service that uses RideShareHttpService for all operations
/// This maintains backward compatibility with existing code
class RideShareService {
  final RideShareHttpService _httpService = RideShareHttpService();

  /// Estimate fare for a trip
  Future<Map<String, dynamic>> estimateFare({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String vehicleClass,
  }) async {
    try {
      final fareEstimate = await _httpService.estimateFare(
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        dropoffLatitude: dropoffLatitude,
        dropoffLongitude: dropoffLongitude,
        vehicleClass: vehicleClass,
      );
      return fareEstimate.toJson();
    } catch (e) {
      print('Error estimating fare: $e');
      rethrow;
    }
  }



  /// Request a new ride
  Future<Map<String, dynamic>> requestRide({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String vehicleClass,
    String? pickupAddress,
    String? dropoffAddress,
    String? notes,
  }) async {
    try {
      final ride = await _httpService.requestRide(
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        dropoffLatitude: dropoffLatitude,
        dropoffLongitude: dropoffLongitude,
        vehicleClass: vehicleClass,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        notes: notes,
      );
      return ride.toJson();
    } catch (e) {
      print('Error requesting ride: $e');
      rethrow;
    }
  }

  /// Get ride details
  Future<Map<String, dynamic>> getRideDetails(int rideId) async {
    try {
      final ride = await _httpService.getRideDetails(rideId);
      return ride.toJson();
    } catch (e) {
      print('Error getting ride: $e');
      rethrow;
    }
  }

  /// Cancel a ride
  Future<Map<String, dynamic>> cancelRide(int rideId, {String? reason}) async {
    try {
      final ride = await _httpService.cancelRide(rideId, reason: reason);
      return ride.toJson();
    } catch (e) {
      print('Error cancelling ride: $e');
      rethrow;
    }
  }

  /// Subscribe to passenger ride tracking
  void subscribeToRideTracking(int rideId) {
    _httpService.subscribeToRideTracking(rideId);
  }

  /// Unsubscribe from ride tracking
  void unsubscribeFromRideTracking() {
    _httpService.unsubscribeFromRideTracking();
  }

  /// Listen to driver location updates
  void onDriverLocationUpdated(Function(Map<String, dynamic>) callback) {
    _httpService.onDriverLocationUpdated(callback);
  }

  /// Listen to ride status changes
  void onRideStatusUpdated(Function(Map<String, dynamic>) callback) {
    _httpService.onRideStatusUpdated(callback);
  }

  /// Get connection status stream
  Stream<String> get connectionStatusStream =>
      _httpService.connectionStatusStream;

  /// Get driver location stream
  Stream<Map<String, dynamic>> get driverLocationStream =>
      _httpService.driverLocationStream;

  /// Get ride status stream
  Stream<Map<String, dynamic>> get rideStatusStream =>
      _httpService.rideStatusStream;

  /// Get ride update stream (with Ride objects)
  Stream<Ride> get rideUpdateStream => _httpService.rideUpdateStream;

  /// Disconnect socket
  void disconnect() {
    _httpService.disconnect();
  }

  /// Reconnect websocket with retry logic
  Future<void> reconnectWebSocket() async {
    await _httpService.reconnectWebSocket();
  }

  /// Dispose resources
  void dispose() {
    _httpService.dispose();
  }
}
