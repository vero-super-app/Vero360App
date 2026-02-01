import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class RideShareMessagingService {
  final Dio _dio;
  final String _baseUrl;

  RideShareMessagingService({
    required Dio dio,
    required String baseUrl,
  })  : _dio = dio,
        _baseUrl = baseUrl;

  /// Notify ride status change
  Future<Map<String, dynamic>> notifyRideStatusChange({
    required int rideId,
    required String status,
    required int passengerId,
    required int driverId,
    required String pickupAddress,
    required String dropoffAddress,
    required double estimatedFare,
    int? estimatedDuration,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/rides/$rideId/notify-status',
        data: {
          'status': status,
          'passengerId': passengerId,
          'driverId': driverId,
          'pickupAddress': pickupAddress,
          'dropoffAddress': dropoffAddress,
          'estimatedFare': estimatedFare,
          'estimatedDuration': estimatedDuration,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error notifying ride status: $e');
      rethrow;
    }
  }

  /// Send driver location update
  Future<Map<String, dynamic>> sendDriverLocation({
    required int rideId,
    required int driverId,
    required double latitude,
    required double longitude,
    required int etaMinutes,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/rides/$rideId/driver-location',
        data: {
          'driverId': driverId,
          'latitude': latitude,
          'longitude': longitude,
          'etaMinutes': etaMinutes,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error sending driver location: $e');
      rethrow;
    }
  }

  /// Send emergency alert
  Future<Map<String, dynamic>> sendEmergencyAlert({
    required int rideId,
    required int userId,
    required String alertMessage,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/rides/$rideId/emergency',
        data: {
          'userId': userId,
          'alertMessage': alertMessage,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error sending emergency alert: $e');
      rethrow;
    }
  }

  /// Send trip summary after ride completion
  Future<Map<String, dynamic>> sendTripSummary({
    required int rideId,
    required double actualDistance,
    required double actualFare,
    required int durationMinutes,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/rides/$rideId/trip-summary',
        data: {
          'actualDistance': actualDistance,
          'actualFare': actualFare,
          'durationMinutes': durationMinutes,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error sending trip summary: $e');
      rethrow;
    }
  }

  /// Request driver rating from passenger
  Future<Map<String, dynamic>> requestRating(int rideId) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/rides/$rideId/request-rating',
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error requesting rating: $e');
      rethrow;
    }
  }

  /// Cancel ride
  Future<Map<String, dynamic>> cancelRide({
    required int rideId,
    required String cancelledBy,
    required String reason,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/rides/$rideId/cancel',
        data: {
          'cancelledBy': cancelledBy,
          'reason': reason,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error cancelling ride: $e');
      rethrow;
    }
  }

  /// Get ride analytics
  Future<Map<String, dynamic>> getRideAnalytics(int rideId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/messaging/integrations/rides/$rideId/analytics',
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error getting ride analytics: $e');
      rethrow;
    }
  }
}
