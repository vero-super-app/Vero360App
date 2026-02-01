class LatestArrivalModels {
  final String id;
  final String name;
  final String imageUrl;
  final int price; // store MWK as whole number

  LatestArrivalModels({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
  });

  factory LatestArrivalModels.fromJson(Map<String, dynamic> j) {
    int parsePrice(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.round();
      final s = v.toString().replaceAll(RegExp(r'[^\d]'), '');
      return int.tryParse(s) ?? 0;
    }

    return LatestArrivalModels(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      name: (j['name'] ?? j['title'] ?? 'Unnamed').toString(),
      imageUrl: (j['image'] ?? j['imageUrl'] ?? j['thumbnail'] ?? '').toString(),
      price: parsePrice(j['price']),
    );
  }
}


class LatestArrivalModel {
  final int id;
  final String image;
  final String name;
  final double price;
  final DateTime? createdAt;

  LatestArrivalModel({
    required this.id,
    required this.image,
    required this.name,
    required this.price,
    this.createdAt,
  });

  factory LatestArrivalModel.fromJson(Map<String, dynamic> j) {
    return LatestArrivalModel(
      id: (j['id'] ?? 0) as int,
      image: (j['image'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      price: double.tryParse(j['price']?.toString() ?? '0') ?? 0,
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'image': image,
    'name': name,
    'price': price,
  };
}
