import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_booking_model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class BookingService {
  static const String _bookingPath = '/accomodation/create';
  static const String _paymentPath = '/payments/pay';

  // Step 1: Create a booking
  Future<Map<String, dynamic>> createBooking(
    BookingRequest bookingRequest,
  ) async {
    try {
      final response = await ApiClient.post(
        _bookingPath,
        body: jsonEncode(bookingRequest.toJson()),
      );

      if (kDebugMode) {
        // Debug only, no URL shown, just path is logged in ApiClient
        // but here we can log structured data if needed
        print('Parsed Booking Response: ${response.body}');
      }

      final responseBody = jsonDecode(response.body);

      if (responseBody['BookingNumber'] != null) {
        return {
          'status': 'success',
          'bookingDetails': responseBody,
        };
      } else {
        throw const ApiException(
          message: 'Booking failed. Please try again.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Booking failed. Please try again.',
      );
    }
  }

  // Step 2: Initiate payment
  Future<Map<String, dynamic>> initiatePayment({
    required String amount,
    required String currency,
    required String email,
    required String txRef,
    required String phoneNumber,
    required String name,
  }) async {
    try {
      final response = await ApiClient.post(
        _paymentPath,
        headers: {
          'accept': '*/*',
        },
        body: jsonEncode({
          'amount': amount,
          'currency': currency,
          'email': email,
          'tx_ref': txRef,
          'phone_number': phoneNumber,
          'name': name,
        }),
      );

      if (kDebugMode) {
        print('Parsed Payment Response: ${response.body}');
      }

      final responseBody = jsonDecode(response.body);

      if (responseBody['statusCode'] == 200 &&
          responseBody['data'] != null &&
          responseBody['data']['checkout_url'] != null) {
        return {
          'status': 'success',
          'checkout_url': responseBody['data']['checkout_url'],
        };
      } else {
        throw const ApiException(
          message: 'Payment initiation failed. Please try again.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Payment initiation failed. Please try again.',
      );
    }
  }

  Future<void> cancelOrDelete(String id) async {
    // implement when backend route exists
  }
}
