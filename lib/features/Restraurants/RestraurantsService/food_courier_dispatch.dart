import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/features/Restraurants/Models/restaurant_model.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/restaurant_service.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/courier_city.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/vero_courier_service.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';

/// Creates a Vero Courier job when a kitchen marks a food order ready.
class FoodCourierDispatch {
  FoodCourierDispatch._();

  static const provider = 'vero_courier';
  static const methodLabel = 'Vero Courier';

  static final _courier = const CourierService();
  static final _restaurants = RestaurantService();

  /// Returns the tracking code when a job is created; null if skipped or failed.
  static Future<String?> dispatchForReadyOrder({
    required String orderId,
    required Map<String, dynamic> order,
    required String merchantPhone,
    required String merchantEmail,
    required String merchantName,
    required String merchantUid,
  }) async {
    final id = orderId.trim();
    if (id.isEmpty) return null;

    try {
      final snap =
          await FirebaseFirestore.instance.collection('food_orders').doc(id).get();
      final merged = <String, dynamic>{
        ...?snap.data(),
        ...order,
        'id': id,
      };

      final existingCode =
          '${merged['courierTrackingNumber'] ?? merged['trackingNumber'] ?? ''}'
              .trim();
      if (existingCode.isNotEmpty) return existingCode;

      final restaurant = await _loadRestaurant(merged, merchantUid);
      final pickup = _pickupLine(merged, restaurant, merchantName);
      final dropoff = _dropoffLine(merged);
      if (pickup.isEmpty || dropoff.isEmpty) {
        debugPrint(
          '[FoodCourierDispatch] skip $id: missing pickup or dropoff',
        );
        return null;
      }

      final city = _cityLabel(merged, restaurant, dropoff, pickup);
      final phone = CourierService.normalizePhone(merchantPhone);
      if (phone.isEmpty) {
        debugPrint('[FoodCourierDispatch] skip $id: merchant phone missing');
        return null;
      }

      final email = merchantEmail.trim().isNotEmpty
          ? merchantEmail.trim()
          : 'no-email@vero.local';
      final customerName = '${merged['customerName'] ?? ''}'.trim();
      final customerPhone = CourierService.normalizePhone(
        sanitizedPhoneOrEmpty(
          '${merged['customerPhone'] ?? merged['phone'] ?? ''}',
        ),
      );
      final dishSummary = _dishSummary(merged);
      final dropLat = _asDouble(merged['deliveryLat'] ?? merged['lat']);
      final dropLng = _asDouble(merged['deliveryLng'] ?? merged['lng']);
      final pickLat = _asDouble(
        merged['pickupLat'] ?? restaurant?.latitude,
      );
      final pickLng = _asDouble(
        merged['pickupLng'] ?? restaurant?.longitude,
      );

      final additional = [
        'Sender: ${merchantName.trim().isEmpty ? 'Kitchen' : merchantName.trim()}',
        if (merchantUid.trim().isNotEmpty) 'SenderUid: ${merchantUid.trim()}',
        if (customerName.isNotEmpty) 'Recipient: $customerName',
        if (customerPhone.isNotEmpty) 'Recipient Phone: $customerPhone',
        'Recipient Address: $dropoff',
        if (dropLat != null) 'DropoffLat: ${dropLat.toStringAsFixed(6)}',
        if (dropLng != null) 'DropoffLng: ${dropLng.toStringAsFixed(6)}',
        if (pickLat != null) 'PickupLat: ${pickLat.toStringAsFixed(6)}',
        if (pickLng != null) 'PickupLng: ${pickLng.toStringAsFixed(6)}',
        'FoodOrderId: $id',
        'ServiceCity: $city',
        'IntraCityOnly: yes',
      ].join(' | ');

      final created = await _courier.createDelivery(
        CreateCourierDeliveryDto(
          courierPhone: phone,
          courierEmail: email,
          courierCity: city,
          pickupLocation: pickup,
          dropoffLocation: dropoff,
          typeOfGoods: 'Food',
          descriptionOfGoods: dishSummary,
          additionalInformation: additional,
        ),
      );

      final code = created.trackingCode.trim().isNotEmpty
          ? created.trackingCode.trim()
          : (created.courierId > 0 ? '#${created.courierId}' : '');

      await FirebaseFirestore.instance.collection('food_orders').doc(id).update({
        'deliveryMethod': methodLabel,
        'courierProvider': provider,
        'courierTrackingNumber': code,
        if (created.courierId > 0) 'courierDeliveryId': created.courierId,
        'pickupAddress': pickup,
        if (pickLat != null) 'pickupLat': pickLat,
        if (pickLng != null) 'pickupLng': pickLng,
        if (dropLat != null) 'deliveryLat': dropLat,
        if (dropLng != null) 'deliveryLng': dropLng,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return code.isEmpty ? null : code;
    } on ApiException catch (e) {
      debugPrint('[FoodCourierDispatch] $id failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[FoodCourierDispatch] $id failed: $e');
      return null;
    }
  }

  static Future<RestaurantModel?> _loadRestaurant(
    Map<String, dynamic> order,
    String merchantUid,
  ) async {
    final rid = '${order['restaurantId'] ?? ''}'.trim();
    if (rid.isNotEmpty) {
      final byId = await _restaurants.fetchRestaurantById(rid);
      if (byId != null) return byId;
    }
    return _restaurants.fetchRestaurantByOwnerUid(merchantUid);
  }

  static String _pickupLine(
    Map<String, dynamic> order,
    RestaurantModel? restaurant,
    String merchantName,
  ) {
    final stored = '${order['pickupAddress'] ?? ''}'.trim();
    if (stored.isNotEmpty) return stored;
    final fromRest = (restaurant?.address ?? '').trim();
    if (fromRest.isNotEmpty) return fromRest;
    final name = (restaurant?.businessName ?? merchantName).trim();
    return name.isEmpty ? '' : name;
  }

  static String _dropoffLine(Map<String, dynamic> order) {
    return '${order['deliveryAddress'] ?? order['address'] ?? ''}'.trim();
  }

  static String _cityLabel(
    Map<String, dynamic> order,
    RestaurantModel? restaurant,
    String dropoff,
    String pickup,
  ) {
    final blob = [
      restaurant?.address,
      order['pickupAddress'],
      dropoff,
      pickup,
    ].whereType<String>().join(' ');
    final city = CourierCityHelper.resolve(blob);
    if (city != null) return CourierCityHelper.displayName(city);
    return 'Lilongwe';
  }

  static String _dishSummary(Map<String, dynamic> order) {
    final items = order['lineItems'] ?? order['items'];
    if (items is! List || items.isEmpty) {
      return 'Food order';
    }
    final names = <String>[];
    for (final e in items) {
      if (e is! Map) continue;
      final name = '${e['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final qty = e['quantity'];
      final n = qty is num ? qty.toInt() : int.tryParse('$qty') ?? 1;
      names.add(n > 1 ? '$n× $name' : name);
      if (names.length >= 4) break;
    }
    if (names.isEmpty) return 'Food order';
    return names.join(', ');
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
