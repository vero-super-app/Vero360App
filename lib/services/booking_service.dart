import 'package:http/http.dart' as http;

import 'dart:convert';

import 'package:vero360_app/models/booking_model.dart';

class BookingService {
  static const String _bookingUrl = 'https://unimatherapyapplication.com/vero/accomodation/create';
  static const String _paymentUrl = 'https://unimatherapyapplication.com/vero/payments/pay';

  // Step 1: Create a booking
  Future<Map<String, dynamic>> createBooking(BookingRequest bookingRequest) async {
    try {
      // Send the booking request to the backend
      final response = await http.post(
        Uri.parse(_bookingUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bookingRequest.toJson()),
      );

      // Log the raw response for debugging
      print('Raw Booking Response: ${response.body}');

      // Check if the request was successful
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = json.decode(response.body);

        // Log the parsed response for debugging
        print('Parsed Booking Response: $responseBody');

        // Validate the response structure
        if (responseBody['BookingNumber'] != null) {
          // If the booking is successful, return the booking details
          return {
            'status': 'success',
            'bookingDetails': responseBody,
          };
        } else {
          throw Exception('Booking failed: Invalid response structure');
        }
      } else {
        // Handle server errors
        print('Failed to book: ${response.body}');
        throw Exception('Failed to create booking: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      // Handle any exceptions
      print('Error: $e');
      throw Exception('Error: $e');
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
      // Send the payment request to the backend
      final response = await http.post(
        Uri.parse(_paymentUrl),
        headers: {
          'accept': '*/*',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'amount': amount,
          'currency': currency,
          'email': email,
          'tx_ref': txRef,
          'phone_number': phoneNumber,
          'name': name,
        }),
      );

      // Log the raw response for debugging
      print('Raw Payment Response: ${response.body}');

      // Check if the request was successful
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = json.decode(response.body);

        // Log the parsed response for debugging
        print('Parsed Payment Response: $responseBody');

        // Validate the response structure
        if (responseBody['statusCode'] == 200 && responseBody['data'] != null) {
          final checkoutUrl = responseBody['data']['checkout_url'];

          // Ensure the checkout URL is present
          if (checkoutUrl != null) {
            return {
              'status': 'success',
              'checkout_url': checkoutUrl,
            };
          } else {
            throw Exception('Payment initiation failed: Checkout URL missing');
          }
        } else {
          throw Exception('Payment initiation failed: Invalid response structure');
        }
      } else {
        // Handle server errors
        print('Failed to initiate payment: ${response.body}');
        throw Exception('Failed to initiate payment: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      // Handle any exceptions
      print('Error: $e');
      throw Exception('Error: $e');
    }
  }

  Future cancelOrDelete(String id) async {}
}