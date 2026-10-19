import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_booking_detail_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_bookings_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_browse_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_checkout_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_detail_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_inspection_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_report_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_verification_page.dart';

/// Navigation helpers for the additive car-hire renter journey.
class CarHireRoutes {
  CarHireRoutes._();

  static Future<void> openBrowse(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CarHireBrowsePage()),
    );
  }

  static Future<void> openDetail(
    BuildContext context, {
    required CarListing car,
    DateTime? startAt,
    DateTime? endAt,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CarHireDetailPage(
          carId: car.id,
          initialCar: car,
          initialStartAt: startAt,
          initialEndAt: endAt,
        ),
      ),
    );
  }

  static Future<void> openCheckout(
    BuildContext context, {
    required CarListing car,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CarHireCheckoutPage(
          car: car,
          startAt: startAt,
          endAt: endAt,
        ),
      ),
    );
  }

  static Future<void> openBookings(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CarHireBookingsPage()),
    );
  }

  static Future<void> openBookingDetail(
    BuildContext context, {
    required int bookingId,
    CarHireBooking? initialBooking,
    bool replace = false,
  }) {
    final route = MaterialPageRoute<void>(
      builder: (_) => CarHireBookingDetailPage(
        bookingId: bookingId,
        initialBooking: initialBooking,
      ),
    );
    if (replace) {
      return Navigator.of(context).pushReplacement(route);
    }
    return Navigator.of(context).push(route);
  }

  static Future<void> openVerification(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CarHireVerificationPage(),
      ),
    );
  }

  static Future<void> openInspection(
    BuildContext context, {
    required int bookingId,
    required InspectionType type,
    CarHireBooking? booking,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CarHireInspectionPage(
          bookingId: bookingId,
          type: type,
          booking: booking,
        ),
      ),
    );
  }

  static Future<void> openReport(
    BuildContext context, {
    required int bookingId,
    int initialTab = 0,
    String? bookingNumber,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CarHireReportPage(
          bookingId: bookingId,
          initialTab: initialTab,
          bookingNumber: bookingNumber,
        ),
      ),
    );
  }
}
