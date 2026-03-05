// Merchant story model — 24h stories (Firebase Spark: Firestore + Storage)

/// Single viewer record for story insights.
class StoryViewerInfo {
  final String viewerId;
  final String viewerName;
  final DateTime viewedAt;
  /// Optional profile picture URL (e.g. from Firebase Auth photoURL).
  final String? viewerProfileImageUrl;

  const StoryViewerInfo({
    required this.viewerId,
    required this.viewerName,
    required this.viewedAt,
    this.viewerProfileImageUrl,
  });
}

class MerchantStoryItem {
  final String storyId;
  final String merchantId;
  final String merchantName;
  final String? merchantImageUrl;
  final String mediaUrl;
  /// When Storage fails, image can be stored as base64 in Firestore. Use [displayImageBytes] to show.
  final String? imageBase64;
  final String mediaType;
  /// Optional caption for this story slide.
  final String? caption;
  /// Optional music track (e.g. Spotify track id or name) for Instagram-style music.
  final String? musicTrackId;
  final String? musicTrackName;
  final DateTime createdAt;
  final DateTime expiresAt;
  /// Number of viewers (from Firestore). May be 0 if not fetched.
  final int viewerCount;

  const MerchantStoryItem({
    required this.storyId,
    required this.merchantId,
    required this.merchantName,
    this.merchantImageUrl,
    required this.mediaUrl,
    this.imageBase64,
    this.mediaType = 'image',
    this.caption,
    this.musicTrackId,
    this.musicTrackName,
    required this.createdAt,
    required this.expiresAt,
    this.viewerCount = 0,
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

  /// Total viewer count across all items (unique viewers).
  int get totalViewerCount => items.fold<int>(0, (sum, i) => sum + i.viewerCount);
}
