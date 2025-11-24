import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/models/car_booking_model.dart';
import 'package:vero360_app/models/merchant_model.dart';
import 'package:vero360_app/models/analytics_model.dart';
import 'package:vero360_app/services/car_rental_service.dart';
import 'package:vero360_app/services/merchant_service.dart';
import 'package:vero360_app/services/analytics_service.dart';

// Services
final carRentalServiceProvider = Provider<CarRentalService>((ref) {
  return CarRentalService();
});

final merchantServiceProvider = Provider<MerchantService>((ref) {
  return MerchantService();
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

// Merchant Cars
final myCarsFutureProvider = FutureProvider<List<CarModel>>((ref) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getMyCars();
});

// Merchant Bookings
final pendingBookingsFutureProvider = FutureProvider<List<CarBookingModel>>((ref) async {
  final service = ref.watch(merchantServiceProvider);
  return service.getPendingBookings();
});

final activeRentalsFutureProvider = FutureProvider<List<CarBookingModel>>((ref) async {
  final service = ref.watch(merchantServiceProvider);
  return service.getActiveRentals();
});

// Car Bookings by Car ID
final carBookingsFutureProvider = FutureProvider.family<List<CarBookingModel>, int>((ref, carId) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getMyCarBookings(carId);
});

// Rental History
final rentalHistoryFutureProvider = FutureProvider.family<List<CarBookingModel>, int>((ref, carId) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getRentalHistory(carId);
});

// Analytics
final merchantAnalyticsFutureProvider = FutureProvider<MerchantAnalytics>((ref) async {
  final service = ref.watch(carRentalServiceProvider);
  return service.getAnalytics();
});

final merchantProfileFutureProvider = FutureProvider<MerchantModel>((ref) async {
  final service = ref.watch(merchantServiceProvider);
  return service.getMerchantProfile();
});

// State Management for Form
final newCarFormProvider = StateNotifierProvider<NewCarFormNotifier, NewCarFormState>((ref) {
  return NewCarFormNotifier();
});

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

  NewCarFormState({
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

class NewCarFormNotifier extends StateNotifier<NewCarFormState> {
  NewCarFormNotifier() : super(NewCarFormState());

  void updateMake(String value) => state = state.copyWith(make: value);
  void updateModel(String value) => state = state.copyWith(model: value);
  void updateYear(int value) => state = state.copyWith(year: value);
  void updateLicensePlate(String value) => state = state.copyWith(licensePlate: value);
  void updateColor(String value) => state = state.copyWith(color: value);
  void updateDailyRate(double value) => state = state.copyWith(dailyRate: value);
  void updateDescription(String value) => state = state.copyWith(description: value);
  void updateSeats(int value) => state = state.copyWith(seats: value);
  void updateFuelType(String value) => state = state.copyWith(fuelType: value);
  void reset() => state = NewCarFormState();
}
