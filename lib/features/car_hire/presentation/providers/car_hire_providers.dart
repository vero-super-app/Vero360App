import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

final carHireApiProvider = Provider<CarHireApi>((ref) => CarHireApi());

// ---------------------------------------------------------------------------
// Browse query
// ---------------------------------------------------------------------------

class CarHireSearchQuery {
  const CarHireSearchQuery({
    this.pickupArea = '',
    this.startAt,
    this.endAt,
  });

  final String pickupArea;
  final DateTime? startAt;
  final DateTime? endAt;

  bool get hasDates => startAt != null && endAt != null;

  bool get isDateRangeValid {
    final from = startAt;
    final to = endAt;
    return from != null && to != null && to.isAfter(from);
  }

  CarHireSearchQuery copyWith({
    String? pickupArea,
    DateTime? startAt,
    DateTime? endAt,
  }) {
    return CarHireSearchQuery(
      pickupArea: pickupArea ?? this.pickupArea,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CarHireSearchQuery &&
        other.pickupArea == pickupArea &&
        other.startAt == startAt &&
        other.endAt == endAt;
  }

  @override
  int get hashCode => Object.hash(pickupArea, startAt, endAt);
}

class CarHireSearchNotifier extends Notifier<CarHireSearchQuery> {
  @override
  CarHireSearchQuery build() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9)
        .add(const Duration(days: 1));
    final end = DateTime(start.year, start.month, start.day + 3, 17);
    return CarHireSearchQuery(startAt: start, endAt: end);
  }

  void setPickupArea(String value) {
    final next = value.trim();
    if (next == state.pickupArea) return;
    state = state.copyWith(pickupArea: next);
  }

  void setStartAt(DateTime value) {
    state = state.copyWith(startAt: value);
  }

  void setEndAt(DateTime value) {
    state = state.copyWith(endAt: value);
  }

  void setDates({required DateTime startAt, required DateTime endAt}) {
    state = CarHireSearchQuery(
      pickupArea: state.pickupArea,
      startAt: startAt,
      endAt: endAt,
    );
  }

  void reset() {
    state = build();
  }
}

final carHireSearchProvider =
    NotifierProvider<CarHireSearchNotifier, CarHireSearchQuery>(
  CarHireSearchNotifier.new,
);

/// Public search results. Availability comes from the server; the client never
/// computes it.
final carHireResultsProvider = FutureProvider<CarHireSearchResult>((ref) async {
  final query = ref.watch(carHireSearchProvider);

  if (!query.hasDates) {
    throw const CarHireApiException(
      message: 'Choose a pick-up and return date to see available cars.',
      kind: CarHireErrorKind.validation,
    );
  }
  if (!query.isDateRangeValid) {
    throw const CarHireApiException(
      message: 'The return date must be after the pick-up date.',
      kind: CarHireErrorKind.validation,
    );
  }

  final api = ref.watch(carHireApiProvider);
  return api.searchCars(
    pickupArea: query.pickupArea,
    startAt: query.startAt,
    endAt: query.endAt,
    page: 1,
    limit: 20,
  );
});

// ---------------------------------------------------------------------------
// Detail + bookings
// ---------------------------------------------------------------------------

final carHireDetailProvider =
    FutureProvider.family<CarListing, int>((ref, carId) async {
  final api = ref.watch(carHireApiProvider);
  return api.getCar(carId);
});

final myCarHireBookingsProvider =
    FutureProvider<List<CarHireBooking>>((ref) async {
  final api = ref.watch(carHireApiProvider);
  final page = await api.getMyBookings();
  return page.data;
});

final carHireBookingDetailProvider =
    FutureProvider.family<CarHireBooking, int>((ref, bookingId) async {
  final api = ref.watch(carHireApiProvider);
  return api.getBooking(bookingId);
});

// ---------------------------------------------------------------------------
// Quote controller
// ---------------------------------------------------------------------------

class CarHireQuoteRequest {
  const CarHireQuoteRequest({
    required this.carId,
    required this.startAt,
    required this.endAt,
  });

  final int carId;
  final DateTime startAt;
  final DateTime endAt;

  @override
  bool operator ==(Object other) {
    return other is CarHireQuoteRequest &&
        other.carId == carId &&
        other.startAt == startAt &&
        other.endAt == endAt;
  }

  @override
  int get hashCode => Object.hash(carId, startAt, endAt);
}

class CarHireQuoteState {
  const CarHireQuoteState({
    this.loading = false,
    this.quote,
    this.error,
    this.request,
  });

  final bool loading;
  final RentalQuote? quote;
  final CarHireApiException? error;
  final CarHireQuoteRequest? request;

  bool get hasQuote => quote != null;

  bool get isExpired => quote?.isExpired ?? false;
}

class CarHireQuoteController extends Notifier<CarHireQuoteState> {
  @override
  CarHireQuoteState build() => const CarHireQuoteState();

  Future<RentalQuote?> requestQuote({
    required int carId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final request = CarHireQuoteRequest(
      carId: carId,
      startAt: startAt,
      endAt: endAt,
    );
    state = CarHireQuoteState(loading: true, request: request);

    try {
      final quote = await ref.read(carHireApiProvider).createQuote(
            carId: request.carId,
            startAt: request.startAt,
            endAt: request.endAt,
          );
      state = CarHireQuoteState(quote: quote, request: request);
      return quote;
    } on CarHireApiException catch (error) {
      state = CarHireQuoteState(error: error, request: request);
      return null;
    } catch (error) {
      state = CarHireQuoteState(
        error: CarHireApiException(message: UserFacingError.from(error)),
        request: request,
      );
      return null;
    }
  }

  Future<RentalQuote?> refresh() {
    final request = state.request;
    if (request == null) return Future<RentalQuote?>.value(null);
    return requestQuote(
      carId: request.carId,
      startAt: request.startAt,
      endAt: request.endAt,
    );
  }

  void reset() {
    state = const CarHireQuoteState();
  }
}

final quoteControllerProvider =
    NotifierProvider<CarHireQuoteController, CarHireQuoteState>(
  CarHireQuoteController.new,
);

// ---------------------------------------------------------------------------
// Booking submission controller
// ---------------------------------------------------------------------------

class CarHireBookingSubmissionState {
  const CarHireBookingSubmissionState({
    this.submitting = false,
    this.booking,
    this.error,
    this.idempotencyKey,
  });

  final bool submitting;
  final CarHireBooking? booking;
  final CarHireApiException? error;

  /// Reused across retries so the backend can de-duplicate submissions.
  final String? idempotencyKey;

  bool get hasBooking => booking != null;
}

class CarHireBookingSubmissionController
    extends Notifier<CarHireBookingSubmissionState> {
  @override
  CarHireBookingSubmissionState build() =>
      const CarHireBookingSubmissionState();

  Future<CarHireBooking?> submit({
    String? quoteId,
    int? carId,
    DateTime? startDate,
    DateTime? endDate,
    String? renterNotes,
    String? driverName,
  }) async {
    if (state.submitting) return state.booking;

    final key = state.idempotencyKey ?? const Uuid().v4();
    state = CarHireBookingSubmissionState(
      submitting: true,
      idempotencyKey: key,
    );

    try {
      final booking = await ref.read(carHireApiProvider).createBooking(
            quoteId: quoteId,
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            renterNotes: renterNotes,
            driverName: driverName,
            idempotencyKey: key,
          );
      state = CarHireBookingSubmissionState(
        booking: booking,
        idempotencyKey: key,
      );
      ref.invalidate(myCarHireBookingsProvider);
      return booking;
    } on CarHireApiException catch (error) {
      state = CarHireBookingSubmissionState(
        error: error,
        idempotencyKey: key,
      );
      return null;
    } catch (error) {
      state = CarHireBookingSubmissionState(
        error: CarHireApiException(message: UserFacingError.from(error)),
        idempotencyKey: key,
      );
      return null;
    }
  }

  /// Applies a server-refreshed snapshot (for example after a payment return).
  void updateBooking(CarHireBooking booking) {
    state = CarHireBookingSubmissionState(
      booking: booking,
      idempotencyKey: state.idempotencyKey,
    );
    ref.invalidate(myCarHireBookingsProvider);
    ref.invalidate(carHireBookingDetailProvider(booking.id));
  }

  void reset() {
    state = const CarHireBookingSubmissionState();
  }
}

final bookingSubmissionProvider =
    NotifierProvider<CarHireBookingSubmissionController,
        CarHireBookingSubmissionState>(
  CarHireBookingSubmissionController.new,
);

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

final verificationProvider = FutureProvider<CarHireVerification>((ref) async {
  final api = ref.watch(carHireApiProvider);
  return api.getVerificationStatus();
});
