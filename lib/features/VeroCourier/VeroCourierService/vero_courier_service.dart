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

  Future<CourierDelivery> getDeliveryByTrackingNumber(String trackingNumber) async {
    final code = trackingNumber.trim();
    final encoded = Uri.encodeComponent(code);
    final res = await ApiClient.get('/verocourier/track/$encoded');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CourierDelivery.fromJson(data);
  }

  static bool _matchesTrackingQuery(CourierDelivery delivery, String query) {
    final q = query.trim();
    if (q.isEmpty) return false;
    final code = delivery.trackingCode.trim();
    if (code.isNotEmpty && code.toUpperCase() == q.toUpperCase()) return true;
    if (delivery.courierId.toString() == q) return true;
    final bare = q.startsWith('#') ? q.substring(1) : q;
    if (delivery.courierId.toString() == bare) return true;
    return false;
  }

  /// Track by backend code (`VC506683`) or numeric delivery id.
  Future<CourierDelivery> getMyDeliveryByTrackingOrId(
    String query, {
    required String senderPhone,
    String? senderEmail,
  }) async {
    final raw = query.trim();
    if (raw.isEmpty) {
      throw const ApiException(message: 'Enter your tracking number (e.g. VC506683).');
    }

    try {
      final mine = await getMyDeliveries();
      for (final delivery in mine) {
        if (_matchesTrackingQuery(delivery, raw)) return delivery;
      }
    } catch (_) {
      // Fall through to public track / id lookup.
    }

    final looksLikeVc = RegExp(r'^VC\d+$', caseSensitive: false).hasMatch(raw);
    if (looksLikeVc) {
      try {
        final delivery = await getDeliveryByTrackingNumber(raw);
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
      } on ApiException {
        rethrow;
      } catch (_) {
        // Older backends may not expose /track — try all list match.
      }
    }

    try {
      final all = await getAllDeliveries();
      for (final delivery in all) {
        if (!_matchesTrackingQuery(delivery, raw)) continue;
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
    } catch (e) {
      if (e is ApiException) rethrow;
    }

    final id = int.tryParse(raw.startsWith('#') ? raw.substring(1) : raw);
    if (id != null) {
      return getMyDeliveryById(
        id,
        senderPhone: senderPhone,
        senderEmail: senderEmail,
      );
    }

    throw const ApiException(
      message: 'Delivery not found. Check your tracking number (e.g. VC506683).',
    );
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
    // Auth-scoped endpoint is the source of truth. Only filter when we have a
    // usable phone/email AND that filter still returns matches.
    final phone = senderPhone.trim();
    final email = (senderEmail ?? '').trim();
    if (phone.isEmpty && email.isEmpty) return data;

    final filtered = data
        .where(
          (d) => deliveryBelongsToSender(
            d,
            senderPhone: phone,
            senderEmail: email.isEmpty ? null : email,
          ),
        )
        .toList();
    if (filtered.isEmpty && data.isNotEmpty) return data;
    return filtered;
  }

  Future<CourierDelivery> updateStatus({
    required int id,
    required CourierStatus status,
    String? cancelReason,
  }) async {
    final body = <String, dynamic>{'status': status.value};
    final reason = (cancelReason ?? '').trim();
    if (status == CourierStatus.cancelled && reason.isNotEmpty) {
      body['cancelReason'] = reason;
    }
    final res = await ApiClient.patch(
      '/verocourier/deliveries/$id/status',
      body: jsonEncode(body),
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
