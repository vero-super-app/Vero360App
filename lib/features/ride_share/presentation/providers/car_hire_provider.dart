import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/car_model.dart';
import 'package:vero360_app/GeneralModels/car_booking_model.dart';
import 'package:vero360_app/GeneralModels/merchant_model.dart';
import 'package:vero360_app/GeneralModels/analytics_model.dart';
import 'package:vero360_app/GernalServices/car_rental_service.dart';
import 'package:vero360_app/GernalServices/merchant_service.dart';
import 'package:vero360_app/GernalServices/analytics_service.dart';

// -------------------- Services --------------------

final carRentalServiceProvider = Provider<CarRentalService>((ref) {
  return CarRentalService();
});

final merchantServiceProvider = Provider<MerchantService>((ref) {
  return MerchantService();
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

// -------------------- Merchant Cars --------------------

final myCarsFutureProvider = FutureProvider<List<CarModel>>((ref) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getMyCars();
});

// -------------------- Merchant Bookings --------------------

final pendingBookingsFutureProvider = FutureProvider<List<CarBookingModel>>((ref) async {
  final service = ref.watch(merchantServiceProvider);
  return service.getPendingBookings();
});

final activeRentalsFutureProvider = FutureProvider<List<CarBookingModel>>((ref) async {
  final service = ref.watch(merchantServiceProvider);
  return service.getActiveRentals();
});

// -------------------- Bookings by Car ID --------------------

final carBookingsFutureProvider =
    FutureProvider.family<List<CarBookingModel>, int>((ref, carId) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getMyCarBookings(carId);
});

final rentalHistoryFutureProvider =
    FutureProvider.family<List<CarBookingModel>, int>((ref, carId) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getRentalHistory(carId);
});

// -------------------- Analytics --------------------

final merchantAnalyticsFutureProvider = FutureProvider<MerchantAnalytics>((ref) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getAnalytics();
});

final merchantProfileFutureProvider = FutureProvider<MerchantModel>((ref) async {
  final service = ref.watch(merchantServiceProvider);
  return service.getMerchantProfile();
});

// -------------------- New Car Form (Notifier) --------------------

final newCarFormProvider =
    NotifierProvider<NewCarFormNotifier, NewCarFormState>(NewCarFormNotifier.new);

class NewCarFormState {
  final String make;
  final String model;
  final int year;
  final String licensePlate;
  final String color;
  final double dailyRate;
  final String description;
  final int seats;
  final String fuelType;
  final bool isLoading;
  final String? error;

  const NewCarFormState({
    this.make = '',
    this.model = '',
    this.year = 0,
    this.licensePlate = '',
    this.color = '',
    this.dailyRate = 0,
    this.description = '',
    this.seats = 5,
    this.fuelType = 'Petrol',
    this.isLoading = false,
    this.error,
  });

  NewCarFormState copyWith({
    String? make,
    String? model,
    int? year,
    String? licensePlate,
    String? color,
    double? dailyRate,
    String? description,
    int? seats,
    String? fuelType,
    bool? isLoading,
    String? error,
  }) {
    return NewCarFormState(
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      licensePlate: licensePlate ?? this.licensePlate,
      color: color ?? this.color,
      dailyRate: dailyRate ?? this.dailyRate,
      description: description ?? this.description,
      seats: seats ?? this.seats,
      fuelType: fuelType ?? this.fuelType,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class NewCarFormNotifier extends Notifier<NewCarFormState> {
  @override
  NewCarFormState build() => const NewCarFormState();

  void updateMake(String v) => state = state.copyWith(make: v);
  void updateModel(String v) => state = state.copyWith(model: v);
  void updateYear(int v) => state = state.copyWith(year: v);
  void updateLicensePlate(String v) => state = state.copyWith(licensePlate: v);
  void updateColor(String v) => state = state.copyWith(color: v);
  void updateDailyRate(double v) => state = state.copyWith(dailyRate: v);
  void updateDescription(String v) => state = state.copyWith(description: v);
  void updateSeats(int v) => state = state.copyWith(seats: v);
  void updateFuelType(String v) => state = state.copyWith(fuelType: v);

  void setLoading(bool v) => state = state.copyWith(isLoading: v, error: null);
  void setError(String? e) => state = state.copyWith(isLoading: false, error: e);

  void reset() => state = const NewCarFormState();
}
