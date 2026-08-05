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
    );
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
    );
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