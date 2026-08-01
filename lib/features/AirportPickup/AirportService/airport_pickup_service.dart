// lib/features/AirportPickup/AirportService/airport_pickup_service.dart
import 'dart:convert';
import 'package:vero360_app/features/AirportPickup/AirportModels/Airport_pickup.models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class AirportPickupService {
  const AirportPickupService();

  static const String _base = '/vero/verocourier/airport-pickups';

  Map<String, String> _authHeaders(String? authToken) => {
        if (authToken != null && authToken.isNotEmpty)
          'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static AirportPickupBooking _parseBooking(dynamic data) {
    final map = data is Map<String, dynamic> ? data : (jsonDecode(data.toString()) as Map<String, dynamic>);
    return AirportPickupBooking.fromJson(map);
  }

  /// Create airport pickup (login optional).
  Future<AirportPickupBooking> createBooking(
    AirportPickupRequestPayload payload, {
    String? authToken,
  }) async {
    final res = await ApiClient.post(
      _base,
      headers: _authHeaders(authToken),
      body: jsonEncode(payload.toJson()),
    );
    try {
      final data = jsonDecode(res.body);
      final booking = data is Map && data['data'] != null ? data['data'] : data;
      return _parseBooking(booking);
    } catch (e) {
      throw const ApiException(
        message: 'Unexpected response from server. Please try again.',
      );
    }
  }

  /// Get my airport pickup bookings (auth required). Newest first.
  Future<List<AirportPickupBooking>> getMyBookings({required String authToken}) async {
    final res = await ApiClient.get(
      '$_base/me',
      headers: _authHeaders(authToken),
      allowedStatusCodes: {200},
    );
    try {
      final data = jsonDecode(res.body);
      final list = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : <dynamic>[]);
      return list.map((e) => _parseBooking(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get single booking by ID.
  Future<AirportPickupBooking?> getBookingById(int id, {String? authToken}) async {
    final res = await ApiClient.get(
      '$_base/$id',
      headers: _authHeaders(authToken),
      allowedStatusCodes: {200, 404},
    );
    if (res.statusCode == 404) return null;
    try {
      final data = jsonDecode(res.body);
      final booking = data is Map && data['data'] != null ? data['data'] : data;
      return _parseBooking(booking);
    } catch (e) {
      return null;
    }
  }

  /// Update booking (e.g. status). Optional auth.
  Future<AirportPickupBooking> updateBooking(
    int id,
    Map<String, dynamic> body, {
    String? authToken,
  }) async {
    final res = await ApiClient.patch(
      '$_base/$id',
      headers: _authHeaders(authToken),
      body: jsonEncode(body),
      allowedStatusCodes: {200},
    );
    try {
      final data = jsonDecode(res.body);
      final booking = data is Map && data['data'] != null ? data['data'] : data;
      return _parseBooking(booking);
    } catch (e) {
      throw const ApiException(
        message: 'Failed to update booking. Please try again.',
      );
    }
  }

  /// Cancel my airport pickup (auth required).
  Future<AirportPickupBooking> cancelBooking(
    int id, {
    required String authToken,
  }) async {
    final res = await ApiClient.patch(
      '$_base/$id/cancel',
      headers: _authHeaders(authToken),
      allowedStatusCodes: {200},
    );
    try {
      final data = jsonDecode(res.body);
      final booking = data is Map && data['data'] != null ? data['data'] : data;
      return _parseBooking(booking);
    } catch (e) {
      throw const ApiException(
        message: 'Failed to cancel. Please try again.',
      );
    }
  }

  /// Hard delete (admin). Use with care.
  Future<void> deleteBookingById(int id, {String? authToken}) async {
    await ApiClient.delete(
      '$_base/$id',
      headers: _authHeaders(authToken),
      allowedStatusCodes: {200, 204},
    );
  }
}
