class LatestArrivalModels {
  final String id;
  final String name;
  final String imageUrl;
  final int price; // store MWK as whole number
  // When this latest arrival was created (server time), if provided.
  final DateTime? createdAt;
  final String? merchantId;
  final String? merchantName;
  final String? sellerUserId;
  final String? serviceProviderId;
  final int? merchantBackendId;
  /// Units the merchant posted (null = older post without a quantity).
  final int? quantity;

  LatestArrivalModels({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    this.createdAt,
    this.merchantId,
    this.merchantName,
    this.sellerUserId,
    this.serviceProviderId,
    this.merchantBackendId,
    this.quantity,
  });

  LatestArrivalModels copyWith({
    String? id,
    String? name,
    String? imageUrl,
    int? price,
    DateTime? createdAt,
    String? merchantId,
    String? merchantName,
    String? sellerUserId,
    String? serviceProviderId,
    int? merchantBackendId,
    int? quantity,
  }) {
    return LatestArrivalModels(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
      merchantId: merchantId ?? this.merchantId,
      merchantName: merchantName ?? this.merchantName,
      sellerUserId: sellerUserId ?? this.sellerUserId,
      serviceProviderId: serviceProviderId ?? this.serviceProviderId,
      merchantBackendId: merchantBackendId ?? this.merchantBackendId,
      quantity: quantity ?? this.quantity,
    );
  }

  String get sellerDisplayName {
    final n = (merchantName ?? '').trim();
    return n.isNotEmpty ? n : 'Seller';
  }

  String? get resolvedMerchantRef {
    final mid = (merchantId ?? '').trim();
    if (mid.isNotEmpty) return mid;
    final sid = (sellerUserId ?? '').trim();
    if (sid.isNotEmpty) return sid;
    final sp = (serviceProviderId ?? '').trim();
    if (sp.isNotEmpty) return sp;
    return null;
  }

  factory LatestArrivalModels.fromJson(Map<String, dynamic> j) {
    int parsePrice(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.round();
      // Allow decimals/commas but keep the numeric value correct.
      // e.g. "1,000.00" -> 1000 (not 100000)
      var s = v.toString().trim();
      // Remove currency symbols / letters, keep digits, dots and commas
      s = s.replaceAll(RegExp(r'[^0-9\.,]'), '');
      // Normalise: "1,000.50" -> "1000.50"
      s = s.replaceAll(',', '');
      final d = double.tryParse(s) ?? 0;
      return d.round();
    }

    String? pickStr(List<dynamic> keys) {
      for (final k in keys) {
        final v = j[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      final merchant = j['merchant'];
      if (merchant is Map) {
        for (final k in keys) {
          final v = merchant[k]?.toString().trim();
          if (v != null && v.isNotEmpty) return v;
        }
      }
      return null;
    }

    int? pickInt(List<dynamic> keys) {
      for (final k in keys) {
        final raw = j[k];
        if (raw is num) return raw.toInt();
        final parsed = int.tryParse(raw?.toString().trim() ?? '');
        if (parsed != null) return parsed;
      }
      final merchant = j['merchant'];
      if (merchant is Map) {
        for (final k in keys) {
          final raw = merchant[k];
          if (raw is num) return raw.toInt();
          final parsed = int.tryParse(raw?.toString().trim() ?? '');
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return LatestArrivalModels(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      name: (j['name'] ?? j['title'] ?? 'Unnamed').toString(),
      imageUrl:
          (j['image'] ?? j['imageUrl'] ?? j['thumbnail'] ?? '').toString(),
      price: parsePrice(j['price']),
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'].toString())
          : null,
      merchantId: pickStr([
        'merchantId',
        'merchantUid',
        'firebaseUid',
        'sellerFirebaseUid',
      ]),
      merchantName: pickStr([
        'merchantName',
        'businessName',
        'sellerBusinessName',
        'sellerName',
        'shopName',
      ]),
      sellerUserId: pickStr([
        'sellerUserId',
        'ownerId',
        'userId',
      ]),
      serviceProviderId: pickStr(['serviceProviderId']),
      merchantBackendId: pickInt([
        'merchantBackendId',
        'backendMerchantId',
        'merchantUserId',
        'userId',
      ]),
      quantity: _parseQuantity(j['quantity'] ?? j['stockQuantity']),
    );
  }
}

int? _parseQuantity(dynamic v) {
  if (v == null) return null;
  final n = v is num ? v.toInt() : int.tryParse(v.toString().trim());
  return n == null || n < 0 ? null : n;
}


class LatestArrivalModel {
  final int id;
  final String image;
  final String name;
  final double price;
  final DateTime? createdAt;
  final int? quantity;

  LatestArrivalModel({
    required this.id,
    required this.image,
    required this.name,
    required this.price,
    this.createdAt,
    this.quantity,
  });

  factory LatestArrivalModel.fromJson(Map<String, dynamic> j) {
    final rawId = j['id'] ?? j['_id'] ?? 0;
    final id = rawId is int
        ? rawId
        : int.tryParse(rawId.toString()) ?? 0;
    return LatestArrivalModel(
      id: id,
      image: (j['image'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      price: () {
        final raw = (j['price']?.toString() ?? '0').replaceAll(',', '').trim();
        return double.tryParse(raw) ?? 0;
      }(),
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'].toString()) : null,
      quantity: _parseQuantity(j['quantity'] ?? j['stockQuantity']),
    );
  }

  Map<String, dynamic> toJson() => {
    'image': image,
    'name': name,
    'price': price,
    if (quantity != null) 'quantity': quantity,
  };
}
