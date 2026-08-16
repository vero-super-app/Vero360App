// lib/models/cart_model.dart
import 'dart:convert';

class CartModel {
  final String userId;
  final int item;
  final int quantity;
  final String image;
  final String name;
  final double price;
  final String description;
  final String? comment;
  final String merchantId;
  final String merchantName;
  final String serviceType;
  /// Supplier stock cap (null = unknown / legacy unlimited).
  final int? availableStock;
  /// Firestore `restaurants` id for food cart lines. Null for marketplace/legacy.
  final String? restaurantId;
  /// Size / option label for a dish (e.g. "Large").
  final String? variant;
  /// Kitchen notes for this line (food). Distinct from [comment] which marketplace uses.
  final String? notes;
  /// Selected add-on names for this food line. Empty for marketplace / legacy.
  final List<String> addOns;

  CartModel({
    required this.userId,
    required this.item,
    required this.quantity,
    required this.image,
    required this.name,
    required this.price,
    required this.description,
    this.comment,
    required this.merchantId,
    required this.merchantName,
    required this.serviceType,
    this.availableStock,
    this.restaurantId,
    this.variant,
    this.notes,
    this.addOns = const [],
  });

  factory CartModel.fromJson(Map<String, dynamic> json) {
    int safeInt(Object? v, {int def = 0}) {
      if (v is int) return v;
      return int.tryParse('${v ?? ''}') ?? def;
    }

    double safeDouble(Object? v, {double def = 0}) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? def;
    }

    String str(Object? v) => (v ?? '').toString();

    String? optStr(Object? v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return CartModel(
      userId: str(json['userId'] ?? json['user_id']),
      item: safeInt(json['item']),
      quantity: safeInt(json['quantity'], def: 1),
      image: str(json['image']),
      name: str(json['name']),
      price: safeDouble(json['price']),
      description: str(json['description']),
      comment: json['comment'] == null ? null : str(json['comment']),
      merchantId: str(json['merchantId'] ?? json['merchant_id'] ?? 'unknown'),
      merchantName: str(json['merchantName'] ?? json['merchant_name'] ?? 'Unknown Merchant'),
      serviceType: str(json['serviceType'] ?? json['service_type'] ?? 'marketplace'),
      availableStock: json['availableStock'] == null && json['stockQuantity'] == null
          ? null
          : safeInt(json['availableStock'] ?? json['stockQuantity'], def: 0),
      restaurantId: optStr(json['restaurantId'] ?? json['restaurant_id']),
      variant: optStr(json['variant']),
      notes: optStr(json['notes']),
      addOns: parseAddOnNames(json['addOns'] ?? json['addons']),
    );
  }

  static List<String> parseAddOnNames(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'item': item,
    'quantity': quantity,
    'image': image,
    'name': name,
    'price': price,
    'description': description,
    'merchantId': merchantId,
    'merchantName': merchantName,
    'serviceType': serviceType,
    if (comment != null) 'comment': comment,
    if (availableStock != null) 'availableStock': availableStock,
    if (availableStock != null) 'stockQuantity': availableStock,
    if (restaurantId != null && restaurantId!.isNotEmpty)
      'restaurantId': restaurantId,
    if (variant != null && variant!.isNotEmpty) 'variant': variant,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    if (addOns.isNotEmpty) 'addOns': addOns,
  };

  CartModel copyWith({
    String? userId,
    int? item,
    int? quantity,
    String? image,
    String? name,
    double? price,
    String? description,
    String? comment,
    String? merchantId,
    String? merchantName,
    String? serviceType,
    int? availableStock,
    String? restaurantId,
    String? variant,
    String? notes,
    List<String>? addOns,
  }) {
    return CartModel(
      userId: userId ?? this.userId,
      item: item ?? this.item,
      quantity: quantity ?? this.quantity,
      image: image ?? this.image,
      name: name ?? this.name,
      price: price ?? this.price,
      description: description ?? this.description,
      comment: comment ?? this.comment,
      merchantId: merchantId ?? this.merchantId,
      merchantName: merchantName ?? this.merchantName,
      serviceType: serviceType ?? this.serviceType,
      availableStock: availableStock ?? this.availableStock,
      restaurantId: restaurantId ?? this.restaurantId,
      variant: variant ?? this.variant,
      notes: notes ?? this.notes,
      addOns: addOns ?? this.addOns,
    );
  }

  /// Stable key so Small vs Large (or different add-ons) stay separate cart rows.
  String get lineConfigKey {
    final v = (variant ?? '').trim().toLowerCase();
    final a = addOns
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    if (v.isEmpty && a.isEmpty) return '';
    return '$v|${a.join(',')}';
  }

  /// Firestore backup_carts doc id. Legacy lines (no variant/add-ons) keep
  /// `{item}_{merchantId}` so existing carts still match.
  String get firestoreDocId {
    final base = '${item}_$merchantId';
    final cfg = lineConfigKey;
    if (cfg.isEmpty) return base;
    return '${base}_${cfg.hashCode.abs()}';
  }

  bool get isFood => serviceType.trim().toLowerCase() == 'food';

  /// Kitchen identity for single-restaurant carts. Prefers restaurantId, then merchantId, then name.
  String get kitchenKey {
    final rid = restaurantId?.trim();
    if (rid != null && rid.isNotEmpty) return 'r:$rid';
    final mid = merchantId.trim();
    if (mid.isNotEmpty && mid != 'unknown') return 'm:$mid';
    return 'n:${merchantName.trim().toLowerCase()}';
  }

  int get maxOrderQty =>
      availableStock == null ? 99999 : availableStock!.clamp(0, 99999);

  double get total => price * quantity;
  
  bool get hasValidMerchant => 
      merchantId.isNotEmpty && merchantId != 'unknown' && 
      merchantName.isNotEmpty && merchantName != 'Unknown Merchant';

  @override
  String toString() {
    return 'CartModel{item: $item, name: $name, price: $price, merchantId: $merchantId, merchantName: $merchantName}';
  }
}