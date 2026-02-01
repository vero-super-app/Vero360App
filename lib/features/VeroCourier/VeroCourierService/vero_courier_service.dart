// lib/services/courier_service.dart

import 'dart:convert';

import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';

class CourierService {
  const CourierService();

  /// POST /courier/local
  Future<CourierDeliveryBooking> createLocalDelivery(
    CourierLocalRequestPayload payload, {
    String? authToken,
  }) async {
    final headers = <String, String>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    final res = await ApiClient.post(
      '/courier/local',
      headers: headers,
      body: jsonEncode(payload.toJson()),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CourierDeliveryBooking.fromJson(data);
  }

  /// POST /courier/intercity
  Future<CourierDeliveryBooking> createIntercityDelivery(
    CourierIntercityRequestPayload payload, {
    String? authToken,
  }) async {
    final headers = <String, String>{};
    if (authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }

    final res = await ApiClient.post(
      '/courier/intercity',
      headers: headers,
      body: jsonEncode(payload.toJson()),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CourierDeliveryBooking.fromJson(data);
  }
}
