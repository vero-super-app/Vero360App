// Merchant story model — 24h stories (Firebase Spark: Firestore + Storage)

class MerchantStoryItem {
  final String storyId;
  final String merchantId;
  final String merchantName;
  final String? merchantImageUrl;
  /// marketplace | accommodation | food | courier | ride | taxi | ...
  final String? serviceType;
  /// Optional product/service details shown in story details bottom sheet.
  final String? title;
  final String? description;
  final num? price;
  final String mediaUrl;
  /// When Storage fails, image can be stored as base64 in Firestore. Use [displayImageBytes] to show.
  final String? imageBase64;
  final String mediaType;
  final DateTime createdAt;
  final DateTime expiresAt;

  const MerchantStoryItem({
    required this.storyId,
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
    this.serviceType,
    this.title,
    this.description,
    this.price,
    required this.mediaUrl,
    this.imageBase64,
    this.mediaType = 'image',
    required this.createdAt,
    required this.expiresAt,
  });

  /// True if the image is stored in Firestore (base64) instead of Storage URL.
  bool get hasInlineImage => imageBase64 != null && imageBase64!.isNotEmpty;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class MerchantStoryGroup {
  final String merchantId;
  final String merchantName;
  final String? merchantImageUrl;
  final List<MerchantStoryItem> items;

  const MerchantStoryGroup({
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
    required this.items,
  });

  MerchantStoryItem? get latestItem =>
      items.isEmpty ? null : items.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
}
