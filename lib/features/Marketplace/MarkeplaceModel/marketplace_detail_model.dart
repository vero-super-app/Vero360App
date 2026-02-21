import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// --------------------
/// Local marketplace model (Firestore)
/// --------------------
class MarketplaceDetailModel {
  final String id;              // Firestore doc id
  final int? sqlItemId;         // 👈 numeric id from your Nest/SQL backend
  final String name;
  final String category;
  final double price;
  final String image;           // raw string from Firestore (base64 or URL)
  final Uint8List? imageBytes;  // decoded image if base64
  final String? description;
  final String? location;
  final bool isActive;
  final DateTime? createdAt;

  MarketplaceDetailModel({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.image,
    this.sqlItemId,
    this.imageBytes,
    this.description,
    this.location,
    this.isActive = true,
    this.createdAt,
  });

  /// ✅ True only if we have a real numeric backend id > 0
  bool get hasValidSqlItemId => sqlItemId != null && sqlItemId! > 0;

  factory MarketplaceDetailModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    // Image: base64 → bytes (from your sample)
    final rawImage = (data['image'] ?? '').toString();
    Uint8List? bytes;
    if (rawImage.isNotEmpty) {
      try {
        bytes = base64Decode(rawImage);
      } catch (_) {
        bytes = null; // if it's actually a URL, decoding will fail
      }
    }

    // createdAt: Timestamp → DateTime
    DateTime? created;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) {
      created = createdRaw.toDate();
    } else if (createdRaw is DateTime) {
      created = createdRaw;
    }

    // price
    double price = 0;
    final p = data['price'];
    if (p is num) {
      price = p.toDouble();
    } else if (p != null) {
      price = double.tryParse(p.toString()) ?? 0;
    }

    // 👇 Parse numeric backend id from Firestore
    int? sqlId;
    final rawSql = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'];
    if (rawSql is int) {
      sqlId = rawSql;
    } else if (rawSql != null) {
      sqlId = int.tryParse(rawSql.toString());
    }

    final cat = (data['category'] ?? '').toString().toLowerCase();

    return MarketplaceDetailModel(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      category: cat,
      price: price,
      image: rawImage,
      imageBytes: bytes,
      description:
          data['description']?.toString(),
      location: data['location']?.toString(),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      createdAt: created,
      sqlItemId: sqlId, // 👈 set here
    );
  }
}
