import 'package:flutter/cupertino.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_account_pages.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_booking_detail_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_bookings_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_browse_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_checkout_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_add_vehicle_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_booking_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_bookings_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_fleet_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_unit_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_detail_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_inspection_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_report_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_verification_page.dart';
import 'package:vero360_app/settings/Settings.dart' show PolicyPage;

/// Navigation helpers for the additive car-hire renter journey.
class CarHireRoutes {
  CarHireRoutes._();

  /// Car hire entry: company home for a live car hire account, otherwise the
  /// renter marketplace.
  static Future<void> openHome(BuildContext context) {
    return Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => const CarHireHomePage()));
  }

  static Future<void> openBrowse(BuildContext context) {
    return Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => const CarHireBrowsePage()));
  }

  static Future<void> openApply(
    BuildContext context, {
    CarHireAccount? existing,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CarHireApplyPage(existing: existing),
      ),
    );
  }

  static Future<void> openAccountStatus(BuildContext context) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => const CarHireAccountStatusPage(),
      ),
    );
  }

  static Future<void> openDetail(
    BuildContext context, {
    required CarListing car,
    DateTime? startAt,
    DateTime? endAt,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
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
      CupertinoPageRoute<void>(
        builder: (_) =>
            CarHireCheckoutPage(car: car, startAt: startAt, endAt: endAt),
      ),
    );
  }

  static Future<void> openBookings(BuildContext context) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const CarHireBookingsPage()),
    );
  }

  static Future<void> openBookingDetail(
    BuildContext context, {
    required int bookingId,
    CarHireBooking? initialBooking,
    bool replace = false,
  }) {
    final route = CupertinoPageRoute<void>(
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
      CupertinoPageRoute<void>(builder: (_) => const CarHireVerificationPage()),
    );
  }

  /// Opens Terms & Privacy with the car hire section first. Resolves to
  /// `true` when the user taps "Agree & Continue".
  static Future<bool> openTerms(BuildContext context) async {
    final agreed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (_) => const PolicyPage(focusCarHire: true),
      ),
    );
    return agreed == true;
  }

  static Future<void> openInspection(
    BuildContext context, {
    required int bookingId,
    required InspectionType type,
    CarHireBooking? booking,
    bool asCompany = false,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CarHireInspectionPage(
          bookingId: bookingId,
          type: type,
          booking: booking,
          asCompany: asCompany,
        ),
      ),
    );
  }

  static Future<void> openCompany(BuildContext context) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const CarHireCompanyPage()),
    );
  }

  static Future<void> openCompanyBookings(BuildContext context) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => const CarHireCompanyBookingsPage(),
      ),
    );
  }

  static Future<void> openCompanyFleet(BuildContext context) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const CarHireCompanyFleetPage()),
    );
  }

  /// The single-vehicle workspace: status, live rental, rates and documents.
  static Future<void> openCompanyUnit(
    BuildContext context, {
    required FleetUnit unit,
    required CompanyAccess access,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CarHireCompanyUnitPage(unit: unit, access: access),
      ),
    );
  }

  /// Add-vehicle flow. Resolves to the created unit, or null when cancelled.
  static Future<FleetUnit?> openCompanyAddVehicle(
    BuildContext context, {
    required CompanyAccess access,
  }) {
    return Navigator.of(context).push<FleetUnit>(
      CupertinoPageRoute<FleetUnit>(
        builder: (_) => CarHireCompanyAddVehiclePage(access: access),
      ),
    );
  }

  static Future<void> openCompanyBooking(
    BuildContext context, {
    required int bookingId,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CarHireCompanyBookingPage(bookingId: bookingId),
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
      CupertinoPageRoute<void>(
        builder: (_) => CarHireReportPage(
          bookingId: bookingId,
          initialTab: initialTab,
          bookingNumber: bookingNumber,
        ),
      ),
    );
  }
}
