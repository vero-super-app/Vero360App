import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Provider, FutureProvider;
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifierProvider, StateProvider;
import 'package:state_notifier/state_notifier.dart';

import 'package:vero360_app/models/car_booking_model.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/services/car_rental_service.dart';

// Get available cars
final availableCarsFutureProvider = FutureProvider<List<CarModel>>((ref) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getAvailableCars();
});

final carRentalServiceProvider = Provider<CarRentalService>((ref) {
  return CarRentalService();
});

// Get car details
final carDetailsFutureProvider =
    FutureProvider.family<CarModel, int>((ref, carId) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getCarDetails(carId);
});

// Get user bookings
final userBookingsFutureProvider =
    FutureProvider<List<CarBookingModel>>((ref) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getUserBookings();
});

// Get specific booking
final bookingDetailsFutureProvider =
    FutureProvider.family<CarBookingModel, int>((ref, bookingId) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getBooking(bookingId);
});

// Booking form state
final bookingFormProvider =
    StateNotifierProvider<BookingFormNotifier, BookingFormState>((ref) {
  return BookingFormNotifier();
});

class BookingFormState {
  final int carId;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? pickupLocation;
  final String? returnLocation;
  final bool includeInsurance;
  final List<String> extras;
  final String? promoCode;
  final bool isLoading;
  final String? error;
  final double estimatedCost;

  BookingFormState({
    required this.carId,
    this.startDate,
    this.endDate,
    this.pickupLocation,
    this.returnLocation,
    this.includeInsurance = false,
    this.extras = const [],
    this.promoCode,
    this.isLoading = false,
    this.error,
    this.estimatedCost = 0,
  });

  BookingFormState copyWith({
    int? carId,
    DateTime? startDate,
    DateTime? endDate,
    String? pickupLocation,
    String? returnLocation,
    bool? includeInsurance,
    List<String>? extras,
    String? promoCode,
    bool? isLoading,
    String? error,
    double? estimatedCost,
  }) {
    return BookingFormState(
      carId: carId ?? this.carId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      returnLocation: returnLocation ?? this.returnLocation,
      includeInsurance: includeInsurance ?? this.includeInsurance,
      extras: extras ?? this.extras,
      promoCode: promoCode ?? this.promoCode,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      estimatedCost: estimatedCost ?? this.estimatedCost,
    );
  }
}

class BookingFormNotifier extends StateNotifier<BookingFormState> {
  BookingFormNotifier() : super(BookingFormState(carId: 0));

  void setCarId(int carId) => state = state.copyWith(carId: carId);
  void setStartDate(DateTime date) => state = state.copyWith(startDate: date);
  void setEndDate(DateTime date) => state = state.copyWith(endDate: date);
  void setPickupLocation(String location) =>
      state = state.copyWith(pickupLocation: location);
  void setReturnLocation(String location) =>
      state = state.copyWith(returnLocation: location);
  void toggleInsurance() =>
      state = state.copyWith(includeInsurance: !state.includeInsurance);
  void addExtra(String extra) =>
      state = state.copyWith(extras: [...state.extras, extra]);
  void removeExtra(String extra) => state =
      state.copyWith(extras: state.extras.where((e) => e != extra).toList());
  void setPromoCode(String code) => state = state.copyWith(promoCode: code);
  void setEstimatedCost(double cost) =>
      state = state.copyWith(estimatedCost: cost);
  void reset() => state = BookingFormState(carId: 0);
}

// Booking status filter
final bookingStatusFilterProvider =
    StateProvider<BookingStatus?>((ref) => null);

// Filtered bookings
final filteredBookingsFutureProvider =
    FutureProvider<List<CarBookingModel>>((ref) async {
  final bookings = await ref.watch(userBookingsFutureProvider.future);
  final filter = ref.watch(bookingStatusFilterProvider);

  if (filter == null) return bookings;
  return bookings.where((b) => b.status == filter).toList();
});
