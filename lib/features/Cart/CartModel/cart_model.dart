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
  });

  factory CartModel.fromJson(Map<String, dynamic> json) {
    int _int(Object? v, {int def = 0}) {
      if (v is int) return v;
      return int.tryParse('${v ?? ''}') ?? def;
    }

    double _double(Object? v, {double def = 0}) {
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? def;
    }

    String _str(Object? v) => (v ?? '').toString();

    return CartModel(
      userId: _str(json['userId'] ?? json['user_id']),
      item: _int(json['item']),
      quantity: _int(json['quantity'], def: 1),
      image: _str(json['image']),
      name: _str(json['name']),
      price: _double(json['price']),
      description: _str(json['description']),
      comment: json['comment'] == null ? null : _str(json['comment']),
      merchantId: _str(json['merchantId'] ?? json['merchant_id'] ?? 'unknown'),
      merchantName: _str(json['merchantName'] ?? json['merchant_name'] ?? 'Unknown Merchant'),
      serviceType: _str(json['serviceType'] ?? json['service_type'] ?? 'marketplace'),
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
    );
  }

  double get total => price * quantity;
  
  bool get hasValidMerchant => 
      merchantId.isNotEmpty && merchantId != 'unknown' && 
      merchantName.isNotEmpty && merchantName != 'Unknown Merchant';

  @override
  String toString() {
    return 'CartModel{item: $item, name: $name, price: $price, merchantId: $merchantId, merchantName: $merchantName}';
  }
}