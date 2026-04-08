import 'dart:convert';

import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';

class CourierService {
  const CourierService();

  Future<CourierDelivery> createDelivery(CreateCourierDeliveryDto payload) async {
    final res = await ApiClient.post(
      '/verocourier/create/deliveries',
      body: jsonEncode(payload.toJson()),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CourierDelivery.fromJson(data);
  }

  Future<List<CourierDelivery>> getAllDeliveries() async {
    final res = await ApiClient.get('/verocourier/all/deliveries');
    final data = jsonDecode(res.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(CourierDelivery.fromJson)
        .toList();
  }

  Future<List<CourierDelivery>> getMyDeliveries() async {
    final res = await ApiClient.get('/verocourier/my/deliveries');
    final data = jsonDecode(res.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(CourierDelivery.fromJson)
        .toList();
  }

  Future<CourierDelivery> getDeliveryById(int id) async {
    final res = await ApiClient.get('/verocourier/deliveries/$id');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CourierDelivery.fromJson(data);
  }

  Future<CourierDelivery> updateStatus({
    required int id,
    required CourierStatus status,
  }) async {
    final res = await ApiClient.patch(
      '/verocourier/deliveries/$id/status',
      body: jsonEncode({'status': status.value}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CourierDelivery.fromJson(data);
  }

  Future<bool> deleteDelivery(int id) async {
    final headers = <String, String>{};
    final res = await ApiClient.delete(
      '/verocourier/deliveries/$id',
      headers: headers,
      allowedStatusCodes: {200, 204},
    );
    if (res.body.trim().isEmpty) return true;
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) {
      return data['deleted'] == true;
    }
    return res.statusCode == 200 || res.statusCode == 204;
  }
}
