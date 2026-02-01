import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GeneralModels/car_model.dart';
import 'package:vero360_app/GeneralModels/car_booking_model.dart';
import 'package:vero360_app/GeneralModels/merchant_model.dart';
import 'package:vero360_app/dto/create_car_dto.dart';
import 'package:vero360_app/dto/update_car_dto.dart';
import 'package:vero360_app/dto/geofence_dto.dart';

class MerchantService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Get merchant profile
  Future<MerchantModel> getMerchantProfile() async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/merchant/profile',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final merchant = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return MerchantModel.fromJson(merchant as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  /// Get pending booking requests
  Future<List<CarBookingModel>> getPendingBookings() async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/merchant/bookings/pending',
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
      throw MerchantException(e.message);
    }
  }

  /// Get active rentals for merchant
  Future<List<CarBookingModel>> getActiveRentals() async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/merchant/rentals/active',
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
      throw MerchantException(e.message);
    }
  }

  /// Confirm/approve booking request
  Future<CarBookingModel> confirmBooking(int bookingId) async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      final res = await ApiClient.post(
        '/car-rental/bookings/$bookingId/confirm',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({}),
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final booking = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return CarBookingModel.fromJson(booking as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  /// Reject booking with reason
  Future<void> rejectBooking(int bookingId, String reason) async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      await ApiClient.post(
        '/car-rental/bookings/$bookingId/reject',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({'reason': reason}),
        timeout: _timeout,
      );
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  /// Complete rental with final details
  Future<CarBookingModel> completeRental(int bookingId, {
    required double finalOdometerReading,
    String? damageReport,
    List<String>? damagePhotos,
    double? additionalCharges,
    String? notes,
  }) async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      final res = await ApiClient.post(
        '/car-rental/bookings/$bookingId/complete',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'finalOdometerReading': finalOdometerReading,
          'damageReport': damageReport,
          'damagePhotos': damagePhotos ?? [],
          'additionalCharges': additionalCharges ?? 0,
          'notes': notes,
        }),
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final booking = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return CarBookingModel.fromJson(booking as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  /// Set pricing model for a car
  Future<void> setPricingModel(int carId, {
    required double dailyRate,
    double? hourlyRate,
    double? distanceRate,
    Map<String, dynamic>? surcharges,
  }) async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      await ApiClient.post(
        '/car-rental/cars/$carId/pricing',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'dailyRate': dailyRate,
          'hourlyRate': hourlyRate,
          'distanceRate': distanceRate,
          'surcharges': surcharges ?? {},
        }),
        timeout: _timeout,
      );
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  /// Configure geofence for a car
  Future<void> configureGeofence(int carId, GeofenceDto geofenceDto) async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      await ApiClient.post(
        '/car-rental/cars/$carId/geofence',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode(geofenceDto.toJson()),
        timeout: _timeout,
      );
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  /// Get all geofences for merchant
  Future<List<Map<String, dynamic>>> getGeofences() async {
    final token = await _getToken();
    if (token == null) throw MerchantException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/merchant/geofences',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      throw MerchantException(e.message);
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }
}

class MerchantException implements Exception {
  final String message;
  MerchantException(this.message);

  @override
  String toString() => message;
}
