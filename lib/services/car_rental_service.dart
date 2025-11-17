import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/models/car_booking_model.dart';
import 'package:vero360_app/models/car_model.dart';

class CarRentalService {
  static const Duration _timeout = Duration(seconds: 30);

  // ────── GET Endpoints ──────
  /// Fetch all available cars for booking
  Future<List<CarModel>> getAvailableCars({
    String? location,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final res = await ApiClient.get(
        '/car-rental/cars/available',
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list.map<CarModel>((e) => CarModel.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      throw CarRentalException(e.message);
    }
  }

  /// Get single car details
  Future<CarModel> getCarDetails(int carId) async {
    try {
      final res = await ApiClient.get(
        '/car-rental/cars/$carId',
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final car = data is Map
          ? data
          : (data is Map && data['data'] is Map
              ? data['data']
              : <String, dynamic>{});

      return CarModel.fromJson(car as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw CarRentalException(e.message);
    }
  }

  /// Get user's active and past bookings
  Future<List<CarBookingModel>> getUserBookings() async {
    final token = await _getToken();
    if (token == null) throw CarRentalException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/bookings/my-bookings',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list
          .map<CarBookingModel>(
              (e) => CarBookingModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw CarRentalException(e.message);
    }
  }

  /// Get specific booking details
  Future<CarBookingModel> getBooking(int bookingId) async {
    final token = await _getToken();
    if (token == null) throw CarRentalException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/bookings/$bookingId',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final booking = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return CarBookingModel.fromJson(booking as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw CarRentalException(e.message);
    }
  }

  // ────── POST Endpoints ──────
  /// Create new booking
  Future<CarBookingModel> createBooking({
    required int carId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final token = await _getToken();
    if (token == null) throw CarRentalException('Not authenticated');

    try {
      final res = await ApiClient.post(
        '/car-rental/bookings',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'carId': carId,
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
        }),
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final booking = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return CarBookingModel.fromJson(booking as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw CarRentalException(e.message);
    }
  }

  // ────── PUT Endpoints (Status transitions) ──────
  /// Confirm booking (PENDING → CONFIRMED)
  Future<CarBookingModel> confirmBooking(int bookingId) async {
    return _updateBookingStatus(bookingId, 'CONFIRMED');
  }

  /// Start rental (CONFIRMED → ACTIVE)
  /// Called when user picks up car - GPS tracking begins here
  Future<CarBookingModel> startRental(int bookingId) async {
    return _updateBookingStatus(bookingId, 'ACTIVE');
  }

  /// Complete rental (ACTIVE → COMPLETED)
  /// Called when car is returned
  Future<CarBookingModel> completeRental(int bookingId) async {
    return _updateBookingStatus(bookingId, 'COMPLETED');
  }

  Future<CarBookingModel> _updateBookingStatus(
    int bookingId,
    String status,
  ) async {
    final token = await _getToken();
    if (token == null) throw CarRentalException('Not authenticated');

    try {
      final res = await ApiClient.put(
        '/car-rental/bookings/$bookingId/status',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({'status': status}),
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final booking = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return CarBookingModel.fromJson(booking as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw CarRentalException(e.message);
    }
  }

  // ────── Cache ──────
  Future<void> cacheActiveBooking(CarBookingModel booking) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_car_booking', jsonEncode(booking.toJson()));
  }

  Future<CarBookingModel?> getCachedActiveBooking() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('active_car_booking');
    if (cached == null) return null;

    try {
      final json = jsonDecode(cached);
      return CarBookingModel.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCachedBooking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_car_booking');
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }
}

class CarRentalException implements Exception {
  final String message;
  CarRentalException(this.message);

  @override
  String toString() => message;
}
