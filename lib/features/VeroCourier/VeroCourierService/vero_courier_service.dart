import 'dart:convert';

import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class CourierService {
  const CourierService();

  static String normalizePhone(String raw) {
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  static bool phonesMatch(String a, String b) {
    final left = normalizePhone(a);
    final right = normalizePhone(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    if (left.length >= 9 && right.length >= 9) {
      return left.endsWith(right.substring(right.length - 9)) ||
          right.endsWith(left.substring(left.length - 9));
    }
    return false;
  }

  /// True when [delivery] was created with this sender's phone or email.
  static bool deliveryBelongsToSender(
    CourierDelivery delivery, {
    required String senderPhone,
    String? senderEmail,
  }) {
    if (phonesMatch(delivery.courierPhone, senderPhone)) return true;

    final email = (senderEmail ?? '').trim().toLowerCase();
    final onDelivery = delivery.courierEmail.trim().toLowerCase();
    if (email.isNotEmpty &&
        onDelivery.isNotEmpty &&
        onDelivery != 'no-email@vero.local' &&
        onDelivery == email) {
      return true;
    }
    return false;
  }

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

  /// Returns a delivery only if it belongs to the current sender.
  Future<CourierDelivery> getMyDeliveryById(
    int id, {
    required String senderPhone,
    String? senderEmail,
  }) async {
    try {
      final mine = await getMyDeliveries();
      for (final delivery in mine) {
        if (delivery.courierId == id) return delivery;
      }
    } catch (_) {
      // Fall back to id lookup + client ownership check.
    }

    final delivery = await getDeliveryById(id);
    if (!deliveryBelongsToSender(
      delivery,
      senderPhone: senderPhone,
      senderEmail: senderEmail,
    )) {
      throw const ApiException(
        message: 'Delivery not found. You can only track your own parcels.',
      );
    }
    return delivery;
  }

  Future<List<CourierDelivery>> getMyDeliveriesForSender({
    required String senderPhone,
    String? senderEmail,
  }) async {
    final data = await getMyDeliveries();
    return data
        .where(
          (d) => deliveryBelongsToSender(
            d,
            senderPhone: senderPhone,
            senderEmail: senderEmail,
          ),
        )
        .toList();
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
