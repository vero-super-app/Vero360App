import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_rental_service.dart';
import 'package:vero360_app/services/payment_service.dart';
import 'package:vero360_app/services/merchant_service.dart';
import 'package:vero360_app/services/analytics_service.dart';

class CarHireErrorHandler {
  static String getErrorMessage(Exception e) {
    if (e is CarRentalException) {
      return e.message;
    } else if (e is PaymentException) {
      return e.message;
    } else if (e is MerchantException) {
      return e.message;
    } else if (e is AnalyticsException) {
      return e.message;
    } else {
      return e.toString();
    }
  }

  static void showErrorDialog(BuildContext context, Exception e) {
    final message = getErrorMessage(e);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showErrorSnackbar(BuildContext context, Exception e) {
    final message = getErrorMessage(e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.red,
      ),
    );
  }

  static String getUserFriendlyMessage(String errorCode) {
    switch (errorCode) {
      case 'NOT_AUTHENTICATED':
        return 'Please sign in to continue';
      case 'CAR_NOT_AVAILABLE':
        return 'This car is not available for the selected dates';
      case 'BOOKING_CONFLICT':
        return 'These dates conflict with existing bookings';
      case 'PAYMENT_FAILED':
        return 'Payment could not be processed. Please try again';
      case 'INVALID_GEOFENCE':
        return 'Invalid geofence coordinates';
      case 'CAR_IN_USE':
        return 'This car is currently in use';
      case 'UNAUTHORIZED':
        return 'You do not have permission to perform this action';
      default:
        return 'An error occurred. Please try again';
    }
  }
}
