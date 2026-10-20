import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

/// Changes whenever the Firebase login changes, so account-scoped providers
/// refetch after sign-in, sign-out or switching accounts.
final carHireLoginProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

/// The login's single car hire account. Renters, signed-out users and any
/// lookup the server refuses resolve to [CarHireAccount.none].
final carHireAccountProvider = FutureProvider<CarHireAccount>((ref) async {
  ref.watch(carHireLoginProvider);
  try {
    return await ref.watch(carHireApiProvider).getCarHireAccount();
  } on CarHireApiException catch (error) {
    final status = error.statusCode;
    if (status == 401 || status == 403 || status == 404) {
      return CarHireAccount.none;
    }
    rethrow;
  }
});

/// Company memberships of the signed-in user. Signed-out users and renters
/// without a company simply get no access; company mode stays hidden.
final companyAccessProvider = FutureProvider<CompanyAccess>((ref) async {
  ref.watch(carHireLoginProvider);
  try {
    final memberships = await ref.watch(carHireApiProvider).getMyCompanies();
    return CompanyAccess(memberships);
  } on CarHireApiException catch (error) {
    final status = error.statusCode;
    if (status == 401 || status == 403 || status == 404) {
      return const CompanyAccess(<CompanyMembership>[]);
    }
    rethrow;
  }
});

/// Dispatch board for one local day (`YYYY-MM-DD`).
final companyDispatchProvider =
    FutureProvider.family<DispatchBoard, String>((ref, date) async {
  return ref.watch(carHireApiProvider).getDispatchBoard(date: date);
});

/// Company bookings, optionally filtered by status (empty string = all).
final companyBookingsProvider =
    FutureProvider.family<List<CarHireBooking>, String>((ref, status) async {
  return ref
      .watch(carHireApiProvider)
      .getCompanyBookings(status: status.isEmpty ? null : status);
});

final companyFleetProvider = FutureProvider<List<FleetUnit>>((ref) async {
  return ref.watch(carHireApiProvider).getCompanyFleet();
});

/// Company performance for the last 30 days; null when not permitted.
final companyAnalyticsProvider = FutureProvider<CompanyAnalytics?>((ref) async {
  final now = DateTime.now();
  return ref.watch(carHireApiProvider).getCompanyAnalytics(
        from: now.subtract(const Duration(days: 30)),
        to: now,
      );
});

final bookingUnitOptionsProvider =
    FutureProvider.family<List<BookingUnitOption>, int>((ref, bookingId) async {
  return ref.watch(carHireApiProvider).getBookingUnitOptions(bookingId);
});

String companyDateKey(DateTime value) {
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${pad(value.month)}-${pad(value.day)}';
}

/// Runs one company write action and refreshes every company view after it.
class CompanyActionController extends Notifier<CarHireMutationState> {
  @override
  CarHireMutationState build() => const CarHireMutationState();

  Future<bool> run(
    Future<void> Function(CarHireApi api) action, {
    int? bookingId,
  }) async {
    if (state.submitting) return false;
    state = const CarHireMutationState(submitting: true);
    try {
      await action(ref.read(carHireApiProvider));
      state = const CarHireMutationState(succeeded: true);
      ref.invalidate(companyDispatchProvider);
      ref.invalidate(companyBookingsProvider);
      ref.invalidate(companyFleetProvider);
      if (bookingId != null) {
        ref.invalidate(carHireBookingDetailProvider(bookingId));
        ref.invalidate(bookingUnitOptionsProvider(bookingId));
        ref.invalidate(bookingExtensionsProvider(bookingId));
        ref.invalidate(bookingIncidentsProvider(bookingId));
      }
      return true;
    } on CarHireApiException catch (error) {
      state = CarHireMutationState(error: error);
      return false;
    } catch (error) {
      state = CarHireMutationState(
        error: CarHireApiException(message: UserFacingError.from(error)),
      );
      return false;
    }
  }
}

final companyActionProvider =
    NotifierProvider<CompanyActionController, CarHireMutationState>(
  CompanyActionController.new,
);
