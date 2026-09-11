import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/features/Restraurants/Models/food_order_number.dart';

class FoodOrderLineItem {
  final String menuItemId;
  final String name;
  final double unitPriceMwk;
  final int quantity;
  final String? variant;
  final String? notes;
  /// Selected add-on names (e.g. "Extra cheese"). Empty on legacy lines.
  final List<String> addOns;
  final String? imageUrl;

  const FoodOrderLineItem({
    required this.menuItemId,
    required this.name,
    required this.unitPriceMwk,
    required this.quantity,
    this.variant,
    this.notes,
    this.addOns = const [],
    this.imageUrl,
  });

  factory FoodOrderLineItem.fromJson(Map<String, dynamic> json) {
    int safeInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    double safeDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    String str(dynamic v) => (v == null) ? '' : v.toString();

    String? optStr(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    final qty = safeInt(json['quantity'], fallback: 1);
    final addOns = <String>[];
    final rawAddOns = json['addOns'] ?? json['addons'];
    if (rawAddOns is List) {
      for (final e in rawAddOns) {
        final s = e.toString().trim();
        if (s.isNotEmpty) addOns.add(s);
      }
    }
    return FoodOrderLineItem(
      menuItemId: optStr(json['menuItemId']) ?? optStr(json['id']) ?? '',
      name: str(json['name']).trim().isNotEmpty
          ? str(json['name']).trim()
          : str(json['FoodName']).trim(),
      unitPriceMwk: safeDouble(
        json['unitPriceMwk'] ?? json['price'] ?? json['unitPrice'],
      ),
      quantity: qty < 1 ? 1 : qty,
      variant: optStr(json['variant']),
      notes: optStr(json['notes']),
      addOns: addOns,
      imageUrl: optStr(
        json['imageUrl'] ??
            json['image'] ??
            json['FoodImage'] ??
            json['photo'] ??
            json['coverImage'] ??
            json['coverImageUrl'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'menuItemId': menuItemId,
        'name': name,
        'unitPriceMwk': unitPriceMwk,
        'quantity': quantity,
        if (variant != null) 'variant': variant,
        if (notes != null) 'notes': notes,
        if (addOns.isNotEmpty) 'addOns': addOns,
        if (imageUrl != null && imageUrl!.trim().isNotEmpty)
          'imageUrl': imageUrl!.trim(),
      };

  double get lineTotalMwk => unitPriceMwk * quantity;
}

class FoodOrder {
  static const statuses = <String>{
    'pending',
    'preparing',
    'ready',
    'delivered',
    'cancelled',
  };

  final String id;
  /// Public reference shown to buyer and merchant (VeroF…).
  final String orderNumber;
  final String restaurantId;
  final String merchantId;
  final String customerUid;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final List<FoodOrderLineItem> lineItems;
  final double subtotalMwk;
  final double deliveryFeeMwk;
  final double serviceFeeMwk;
  final double totalMwk;
  final String status;
  final String paymentTxRef;
  final String paymentStatus;
  /// Denormalized kitchen name so customer lists skip a restaurants lookup.
  final String restaurantName;
  /// Always Vero Courier for food. Legacy orders may be empty.
  final String deliveryMethod;
  final String courierProvider;
  final String courierTrackingNumber;
  final int? courierDeliveryId;
  final String pickupAddress;
  /// Denormalized cover photo for order lists (first dish image).
  final String? coverImageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FoodOrder({
    required this.id,
    this.orderNumber = '',
    required this.restaurantId,
    required this.merchantId,
    required this.customerUid,
    this.customerName = '',
    this.customerPhone = '',
    this.customerEmail = '',
    this.deliveryAddress = '',
    this.deliveryLat,
    this.deliveryLng,
    this.lineItems = const [],
    this.subtotalMwk = 0,
    this.deliveryFeeMwk = 0,
    this.serviceFeeMwk = 0,
    this.totalMwk = 0,
    this.status = 'pending',
    this.paymentTxRef = '',
    this.paymentStatus = '',
    this.restaurantName = '',
    this.deliveryMethod = 'Vero Courier',
    this.courierProvider = 'vero_courier',
    this.courierTrackingNumber = '',
    this.courierDeliveryId,
    this.pickupAddress = '',
    this.coverImageUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory FoodOrder.fromJson(Map<String, dynamic> json) {
    double safeDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    double? optDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    String str(dynamic v) => (v == null) ? '' : v.toString();

    String? optStr(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          v > 9999999999 ? v : v * 1000,
        );
      }
      return DateTime.tryParse(v.toString());
    }

    String normalizeStatus(dynamic v) {
      final s = str(v).trim().toLowerCase();
      if (s == 'completed') return 'delivered';
      if (statuses.contains(s)) return s;
      return 'pending';
    }

    int? courierId;
    final rawCourierId = json['courierDeliveryId'];
    if (rawCourierId is int) {
      courierId = rawCourierId;
    } else if (rawCourierId is num) {
      courierId = rawCourierId.toInt();
    } else {
      courierId = int.tryParse(rawCourierId?.toString() ?? '');
    }

    final rawItems = json['lineItems'] ?? json['items'] ?? json['cartItems'];
    final items = <FoodOrderLineItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(
            FoodOrderLineItem.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    _backfillLineImages(items, json['items']);

    return FoodOrder(
      id: optStr(json['id']) ?? '',
      orderNumber: formatVeroFoodOrderNumber(
        optStr(json['orderNumber']) ??
            optStr(json['orderId']) ??
            optStr(json['id']),
      ),
      restaurantId: optStr(json['restaurantId']) ?? '',
      merchantId: optStr(json['merchantId']) ?? '',
      customerUid: optStr(json['customerUid']) ??
          optStr(json['userId']) ??
          optStr(json['customerId']) ??
          '',
      customerName: str(json['customerName']),
      customerPhone: str(json['customerPhone'] ?? json['phone']),
      customerEmail: str(json['customerEmail'] ?? json['email']),
      deliveryAddress: str(
        json['deliveryAddress'] ?? json['address'] ?? json['listingLocation'],
      ),
      deliveryLat: optDouble(json['deliveryLat'] ?? json['lat']),
      deliveryLng: optDouble(json['deliveryLng'] ?? json['lng']),
      lineItems: items,
      subtotalMwk: safeDouble(json['subtotalMwk'] ?? json['subtotal']),
      deliveryFeeMwk: safeDouble(json['deliveryFeeMwk'] ?? json['deliveryFee']),
      serviceFeeMwk: safeDouble(json['serviceFeeMwk'] ?? json['serviceFee']),
      totalMwk: safeDouble(
        json['totalMwk'] ?? json['totalAmount'] ?? json['total'],
      ),
      status: normalizeStatus(json['status']),
      paymentTxRef: str(json['paymentTxRef'] ?? json['txRef'] ?? json['tx_ref']),
      paymentStatus: str(json['paymentStatus']),
      restaurantName: str(json['restaurantName']).trim().isNotEmpty
          ? str(json['restaurantName']).trim()
          : str(json['businessName']).trim().isNotEmpty
              ? str(json['businessName']).trim()
              : str(json['merchantName']).trim(),
      deliveryMethod: str(json['deliveryMethod']).trim().isNotEmpty
          ? str(json['deliveryMethod']).trim()
          : 'Vero Courier',
      courierProvider: str(json['courierProvider']).trim().isNotEmpty
          ? str(json['courierProvider']).trim()
          : 'vero_courier',
      courierTrackingNumber: str(
        json['courierTrackingNumber'] ?? json['trackingNumber'],
      ).trim(),
      courierDeliveryId: courierId,
      pickupAddress: str(json['pickupAddress']),
      coverImageUrl: optStr(
        json['foodImageUrl'] ??
            json['coverImageUrl'] ??
            json['foodImage'] ??
            json['coverImage'],
      ),
      createdAt: asDate(json['createdAt']),
      updatedAt: asDate(json['updatedAt']),
    );
  }

  factory FoodOrder.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return FoodOrder.fromJson({...data, 'id': doc.id});
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (orderNumber.trim().isNotEmpty) 'orderNumber': orderNumber.trim(),
        'restaurantId': restaurantId,
        'merchantId': merchantId,
        'customerUid': customerUid,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail,
        'deliveryAddress': deliveryAddress,
        if (deliveryLat != null) 'deliveryLat': deliveryLat,
        if (deliveryLng != null) 'deliveryLng': deliveryLng,
        'lineItems': lineItems.map((e) => e.toJson()).toList(),
        'subtotalMwk': subtotalMwk,
        'deliveryFeeMwk': deliveryFeeMwk,
        'serviceFeeMwk': serviceFeeMwk,
        'totalMwk': totalMwk,
        'status': status,
        'paymentTxRef': paymentTxRef,
        'paymentStatus': paymentStatus,
        if (restaurantName.trim().isNotEmpty) 'restaurantName': restaurantName,
        if (restaurantName.trim().isNotEmpty) 'businessName': restaurantName,
        'deliveryMethod': deliveryMethod.trim().isEmpty
            ? 'Vero Courier'
            : deliveryMethod,
        'courierProvider': courierProvider.trim().isEmpty
            ? 'vero_courier'
            : courierProvider,
        if (courierTrackingNumber.trim().isNotEmpty)
          'courierTrackingNumber': courierTrackingNumber.trim(),
        if (courierDeliveryId != null) 'courierDeliveryId': courierDeliveryId,
        if (pickupAddress.trim().isNotEmpty) 'pickupAddress': pickupAddress.trim(),
        if (coverImageUrl != null && coverImageUrl!.trim().isNotEmpty)
          'foodImageUrl': coverImageUrl!.trim(),
        if (coverImageUrl != null && coverImageUrl!.trim().isNotEmpty)
          'coverImageUrl': coverImageUrl!.trim(),
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  /// Order ref for UI — prefers [orderNumber], falls back to document id.
  String get displayOrderNumber {
    final n = orderNumber.trim();
    if (n.isNotEmpty) return n;
    return formatVeroFoodOrderNumber(id);
  }

  FoodOrderLineItem? get primaryLineItem =>
      lineItems.isNotEmpty ? lineItems.first : null;

  String get headerFoodTitle {
    if (lineItems.isEmpty) return 'Food order';
    if (lineItems.length == 1) {
      final line = lineItems.first;
      final v = line.variant?.trim() ?? '';
      if (v.isNotEmpty) return '${line.name} ($v)';
      return line.name;
    }
    return '${lineItems.length} dishes';
  }

  String? get headerFoodImageUrl {
    final cover = coverImageUrl?.trim() ?? '';
    if (cover.isNotEmpty) return cover;
    for (final line in lineItems) {
      final img = line.imageUrl?.trim() ?? '';
      if (img.isNotEmpty) return img;
    }
    return null;
  }
}

void _backfillLineImages(
  List<FoodOrderLineItem> items,
  dynamic legacyItems,
) {
  if (items.isEmpty || legacyItems is! List) return;
  for (var i = 0; i < items.length; i++) {
    if ((items[i].imageUrl ?? '').trim().isNotEmpty) continue;
    if (i >= legacyItems.length) break;
    final raw = legacyItems[i];
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    String? url;
    for (final key in ['imageUrl', 'image', 'FoodImage', 'photo', 'coverImage']) {
      final v = map[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) {
        url = v;
        break;
      }
    }
    if (url == null) continue;
    final line = items[i];
    items[i] = FoodOrderLineItem(
      menuItemId: line.menuItemId,
      name: line.name,
      unitPriceMwk: line.unitPriceMwk,
      quantity: line.quantity,
      variant: line.variant,
      notes: line.notes,
      addOns: line.addOns,
      imageUrl: url,
    );
  }
}
