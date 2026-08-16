import 'package:cloud_firestore/cloud_firestore.dart';

class FoodOrderLineItem {
  final String menuItemId;
  final String name;
  final double unitPriceMwk;
  final int quantity;
  final String? variant;
  final String? notes;
  /// Selected add-on names (e.g. "Extra cheese"). Empty on legacy lines.
  final List<String> addOns;

  const FoodOrderLineItem({
    required this.menuItemId,
    required this.name,
    required this.unitPriceMwk,
    required this.quantity,
    this.variant,
    this.notes,
    this.addOns = const [],
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FoodOrder({
    required this.id,
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

    return FoodOrder(
      id: optStr(json['id']) ?? '',
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
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
