// lib/services/airport_pickup_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vero360_app/models/Airport_pickup.models.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';

class AirportPickupService {
  const AirportPickupService();

  Future<AirportPickupBooking> createBooking(
    AirportPickupRequestPayload payload, {
    String? authToken,
  }) async {
    final res = await ApiClient.post(
      '/verocourier/airport-pickups',
      headers: {
        if (authToken != null && authToken.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(payload.toJson()),
    );

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return AirportPickupBooking.fromJson(data);
    } catch (e) {
      throw const ApiException(
        message: 'Unexpected response from server. Please try again.',
      );
    }
  }

  // 🔹 New: cancel booking by id
  Future<AirportPickupBooking> cancelBooking(
    int id, {
    String? authToken,
  }) async {
    final res = await ApiClient.patch(
      '/verocourier/airport-pickups/$id/cancel',
      headers: {
        if (authToken != null && authToken.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      },
      allowedStatusCodes: {200},
    );

    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return AirportPickupBooking.fromJson(data);
    } catch (e) {
      throw const ApiException(
        message: 'Unexpected response from server. Please try again.',
      );
    }
  }
}
