import 'package:cloud_firestore/cloud_firestore.dart';

/// Someone who has posted reels, with totals across their recent reels.
class ReelCreator {
  final String id;
  final String name;
  final String photo;
  final bool isMerchant;
  int reelCount = 0;
  int viewCount = 0;
  int likeCount = 0;

  ReelCreator({
    required this.id,
    required this.name,
    this.photo = '',
    this.isMerchant = false,
  });
}

/// A marketplace product a merchant tagged on their reel.
class ReelProduct {
  final String id;
  final String name;
  final String image;

  const ReelProduct({required this.id, required this.name, this.image = ''});

  static ReelProduct? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    return ReelProduct(
      id: id,
      name: (raw['name'] ?? '').toString().trim(),
      image: (raw['image'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (image.isNotEmpty) 'image': image,
      };
}

/// Header details for a reels profile page.
class ReelProfile {
  final String bio;
  final String location;
  final String shopName;
  final bool isMerchant;
  final int followingCount;
  final int followerCount;

  const ReelProfile({
    this.bio = '',
    this.location = '',
    this.shopName = '',
    this.isMerchant = false,
    this.followingCount = 0,
    this.followerCount = 0,
  });
}

/// A Spotify song tagged on a reel. Shown as a label that opens Spotify;
/// Spotify's terms don't allow playing it over the video.
class ReelMusic {
  final String id;
  final String name;
  final String artist;
  final String image;
  final String url;

  const ReelMusic({
    required this.id,
    required this.name,
    required this.artist,
    this.image = '',
    required this.url,
  });

  String get label => artist.isEmpty ? name : '$name · $artist';

  static ReelMusic? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString().trim();
    final name = (raw['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) return null;
    final url = (raw['url'] ?? '').toString().trim();
    return ReelMusic(
      id: id,
      name: name,
      artist: (raw['artist'] ?? '').toString().trim(),
      image: (raw['image'] ?? '').toString().trim(),
      url: url.startsWith('https://') ? url : 'https://open.spotify.com/track/$id',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'artist': artist,
        if (image.isNotEmpty) 'image': image,
        'url': url,
        'source': 'spotify',
      };
}

class Reel {
  final String id;
  final String ownerId;
  final String ownerName;
  final String ownerPhoto;
  final bool ownerIsMerchant;
  final String videoUrl;
  final String storagePath;
  final String caption;
  final int durationMs;
  final ReelProduct? product;
  final ReelMusic? music;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final int shareCount;
  final int reportCount;
  final bool hidden;
  final DateTime createdAt;

  const Reel({
    this.music,
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhoto,
    required this.ownerIsMerchant,
    required this.videoUrl,
    required this.storagePath,
    required this.caption,
    required this.durationMs,
    required this.product,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.shareCount,
    required this.reportCount,
    required this.hidden,
    required this.createdAt,
  });

  factory Reel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final ts = d['createdAt'];
    return Reel(
      id: doc.id,
      ownerId: (d['ownerId'] ?? '').toString(),
      ownerName: (d['ownerName'] ?? '').toString().trim().isEmpty
          ? 'Vero360 member'
          : (d['ownerName'] ?? '').toString().trim(),
      ownerPhoto: (d['ownerPhoto'] ?? '').toString().trim(),
      ownerIsMerchant: d['ownerIsMerchant'] == true,
      videoUrl: (d['videoUrl'] ?? '').toString().trim(),
      storagePath: (d['storagePath'] ?? '').toString(),
      caption: (d['caption'] ?? '').toString(),
      durationMs: n(d['durationMs']),
      product: ReelProduct.fromMap(d['product']),
      music: ReelMusic.fromMap(d['music']),
      likeCount: n(d['likeCount']),
      commentCount: n(d['commentCount']),
      viewCount: n(d['viewCount']),
      shareCount: n(d['shareCount']),
      reportCount: n(d['reportCount']),
      hidden: d['hidden'] == true,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  Reel copyWith({int? likeCount, int? commentCount, int? shareCount}) => Reel(
        id: id,
        ownerId: ownerId,
        ownerName: ownerName,
        ownerPhoto: ownerPhoto,
        ownerIsMerchant: ownerIsMerchant,
        videoUrl: videoUrl,
        storagePath: storagePath,
        caption: caption,
        durationMs: durationMs,
        product: product,
        music: music,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        viewCount: viewCount,
        shareCount: shareCount ?? this.shareCount,
        reportCount: reportCount,
        hidden: hidden,
        createdAt: createdAt,
      );
}

class ReelComment {
  final String id;
  final String uid;
  final String name;
  final String photo;
  final String text;
  final DateTime createdAt;
  /// Top-level comment this replies to; null for top-level comments.
  final String? parentId;
  /// Name of the person being answered, shown as "@name".
  final String? replyToName;
  final List<String> likedBy;
  final List<String> dislikedBy;
  final int replyCount;
  /// Removed by its author but kept so its replies stay readable.
  final bool deleted;

  const ReelComment({
    required this.id,
    required this.uid,
    required this.name,
    required this.photo,
    required this.text,
    required this.createdAt,
    this.parentId,
    this.replyToName,
    this.likedBy = const [],
    this.dislikedBy = const [],
    this.replyCount = 0,
    this.deleted = false,
  });

  bool get isReply => parentId != null;
  int get likeCount => likedBy.length;
  int get dislikeCount => dislikedBy.length;

  factory ReelComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['createdAt'];
    List<String> ids(Object? v) =>
        v is List ? v.map((e) => e.toString()).toList() : const <String>[];
    final parent = (d['parentId'] ?? '').toString().trim();
    final replyTo = (d['replyToName'] ?? '').toString().trim();
    final rc = d['replyCount'];
    return ReelComment(
      id: doc.id,
      uid: (d['uid'] ?? '').toString(),
      name: (d['name'] ?? 'Vero360 member').toString(),
      photo: (d['photo'] ?? '').toString(),
      text: (d['text'] ?? '').toString(),
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      parentId: parent.isEmpty ? null : parent,
      replyToName: replyTo.isEmpty ? null : replyTo,
      likedBy: ids(d['likedBy']),
      dislikedBy: ids(d['dislikedBy']),
      replyCount: rc is num ? rc.toInt() : 0,
      deleted: d['deleted'] == true,
    );
  }
}
