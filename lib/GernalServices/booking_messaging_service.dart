import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class BookingMessagingService {
  final Dio _dio;
  final String _baseUrl;

  BookingMessagingService({
    required Dio dio,
    required String baseUrl,
  })  : _dio = dio,
        _baseUrl = baseUrl;

  /// Notify booking status change
  Future<Map<String, dynamic>> notifyBookingStatusChange({
    required int bookingId,
    required String bookingNumber,
    required String status,
    required int customerId,
    required int ownerId,
    required int accommodationId,
    required double price,
    required DateTime checkInDate,
    DateTime? checkOutDate,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/notify-status',
        data: {
          'bookingNumber': bookingNumber,
          'status': status,
          'customerId': customerId,
          'ownerId': ownerId,
          'accommodationId': accommodationId,
          'price': price,
          'checkInDate': checkInDate.toIso8601String(),
          'checkOutDate': checkOutDate?.toIso8601String(),
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error notifying booking status: $e');
      rethrow;
    }
  }

  /// Send pre-arrival information to customer
  Future<Map<String, dynamic>> sendPreArrivalInfo({
    required int bookingId,
    required int ownerId,
    required String information,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/pre-arrival',
        data: {
          'ownerId': ownerId,
          'information': information,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error sending pre-arrival info: $e');
      rethrow;
    }
  }

  /// Send check-in reminder
  Future<Map<String, dynamic>> sendCheckInReminder(int bookingId) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/check-in-reminder',
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error sending check-in reminder: $e');
      rethrow;
    }
  }

  /// Send checkout instructions
  Future<Map<String, dynamic>> sendCheckoutInstructions(
      int bookingId) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/checkout',
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error sending checkout instructions: $e');
      rethrow;
    }
  }

  /// Request review from customer
  Future<Map<String, dynamic>> requestReview(int bookingId) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/request-review',
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error requesting review: $e');
      rethrow;
    }
  }

  /// Get booking analytics
  Future<Map<String, dynamic>> getBookingAnalytics(int bookingId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/analytics',
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error getting booking analytics: $e');
      rethrow;
    }
  }

  /// Notify special offers
  Future<Map<String, dynamic>> notifySpecialOffers({
    required int bookingId,
    required String offersText,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/messaging/integrations/bookings/$bookingId/offers',
        data: {
          'offersText': offersText,
        },
      );
      return response.data ?? {};
    } catch (e) {
      debugPrint('Error notifying special offers: $e');
      rethrow;
    }
  }
}
