/// Merchant review + summary models for `/vero/reviews` APIs.
class MerchantReviewSummary {
  final double average;
  final int count;
  final double? bayesian;
  final double? wilson;

  const MerchantReviewSummary({
    required this.average,
    required this.count,
    this.bayesian,
    this.wilson,
  });

  factory MerchantReviewSummary.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    int i(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    return MerchantReviewSummary(
      average: d(json['average'] ?? json['avg'] ?? json['averageRating']),
      count: i(json['count'] ?? json['reviewCount'] ?? json['total']),
      bayesian: _optionalDouble(json['bayesian'] ?? json['bayesianAverage']),
      wilson: _optionalDouble(json['wilson'] ?? json['wilsonScore']),
    );
  }

  static double? _optionalDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

enum ReviewReaction { none, like, dislike }

class MerchantReview {
  final String id;
  final String merchantId;
  final int? userId;
  final int? customerId;
  final String authorName;
  final String? authorAvatar;
  final int rating;
  final String comment;
  final int likes;
  final int dislikes;
  final ReviewReaction myReaction;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MerchantReview({
    required this.id,
    required this.merchantId,
    this.userId,
    this.customerId,
    required this.authorName,
    this.authorAvatar,
    required this.rating,
    required this.comment,
    this.likes = 0,
    this.dislikes = 0,
    this.myReaction = ReviewReaction.none,
    this.createdAt,
    this.updatedAt,
  });

  int? get reviewerId => customerId ?? userId;

  bool isMine(int? currentUserId) {
    if (currentUserId == null) return false;
    final rid = reviewerId;
    return rid != null && rid == currentUserId;
  }

  /// Ensures the viewer can only have one active reaction at a time.
  MerchantReview withNormalizedReaction() {
    return copyWith(myReaction: myReaction);
  }

  /// Applies a reaction tap — no-op if the same reaction is already active.
  MerchantReview withReactionTap(ReviewReaction target) {
    if (myReaction == target) return this;
    return withReactionSwitch(target);
  }

  /// Optimistic UI when switching like ↔ dislike in a single tap.
  MerchantReview withReactionSwitch(ReviewReaction target) {
    if (myReaction == target) return this;

    var likes = this.likes;
    var dislikes = this.dislikes;

    if (myReaction == ReviewReaction.like && likes > 0) likes--;
    if (myReaction == ReviewReaction.dislike && dislikes > 0) dislikes--;

    if (target == ReviewReaction.like) {
      likes++;
    } else if (target == ReviewReaction.dislike) {
      dislikes++;
    }

    return copyWith(
      likes: likes.clamp(0, 999999),
      dislikes: dislikes.clamp(0, 999999),
      myReaction: target,
    );
  }

  /// Merge a server payload after PATCH like/dislike — one reaction, correct counts.
  MerchantReview reconcileReactionResponse({
    required MerchantReview before,
    required ReviewReaction target,
  }) {
    if (before.myReaction == target) return before;
    final optimistic = before.withReactionSwitch(target);
    return copyWith(
      likes: optimistic.likes,
      dislikes: optimistic.dislikes,
      myReaction: target,
    );
  }

  MerchantReview copyWith({
    int? likes,
    int? dislikes,
    ReviewReaction? myReaction,
    int? rating,
    String? comment,
    String? authorName,
    String? authorAvatar,
  }) {
    return MerchantReview(
      id: id,
      merchantId: merchantId,
      userId: userId,
      customerId: customerId,
      authorName: authorName ?? this.authorName,
      authorAvatar: authorAvatar ?? this.authorAvatar,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      myReaction: myReaction ?? this.myReaction,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory MerchantReview.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final userMap = user is Map ? Map<String, dynamic>.from(user) : null;
    final customer = json['customer'];
    final customerMap =
        customer is Map ? Map<String, dynamic>.from(customer) : null;
    final reviewer = json['reviewer'];
    final reviewerMap =
        reviewer is Map ? Map<String, dynamic>.from(reviewer) : null;

    final authorName = _parseAuthorName(json, userMap, customerMap, reviewerMap);

    final uidRaw = json['customerId'] ??
        json['userId'] ??
        json['authorId'] ??
        customerMap?['id'] ??
        userMap?['id'] ??
        reviewerMap?['id'];
    final parsedId = uidRaw is int
        ? uidRaw
        : int.tryParse(uidRaw?.toString() ?? '');

    final customerIdRaw = json['customerId'] ?? customerMap?['id'];
    final customerId = customerIdRaw is int
        ? customerIdRaw
        : int.tryParse(customerIdRaw?.toString() ?? '');

    final reaction = _parseReaction(json);

    final avatar = _parseAvatar(json, userMap, customerMap, reviewerMap);

    return MerchantReview(
      id: '${json['id'] ?? ''}',
      merchantId: '${json['merchantId'] ?? ''}',
      userId: parsedId,
      customerId: customerId ?? parsedId,
      authorName: authorName,
      authorAvatar: avatar,
      rating: _parseRating(json['rating'] ?? json['score'] ?? json['stars']),
      comment: (json['comment'] ??
              json['body'] ??
              json['text'] ??
              json['content'] ??
              '')
          .toString()
          .trim(),
      likes: _parseInt(json['likes'] ?? json['likeCount'] ?? json['likesCount']),
      dislikes: _parseInt(
          json['dislikes'] ?? json['dislikeCount'] ?? json['dislikesCount']),
      myReaction: reaction,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    ).withNormalizedReaction();
  }

  static String _parseAuthorName(
    Map<String, dynamic> json,
    Map<String, dynamic>? userMap,
    Map<String, dynamic>? customerMap,
    Map<String, dynamic>? reviewerMap,
  ) {
    String? pick(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }

    String? fromPerson(Map<String, dynamic>? m) {
      if (m == null) return null;
      final direct = pick(m['name']) ??
          pick(m['displayName']) ??
          pick(m['fullName']) ??
          pick(m['username']);
      if (direct != null) return direct;

      final first = pick(m['firstName'] ?? m['firstname']);
      final last = pick(m['lastName'] ?? m['lastname']);
      if (first != null && last != null) return '$first $last';
      return first ?? last;
    }

    final candidates = <String?>[
      pick(json['customerName']),
      pick(json['reviewerName']),
      pick(json['userName']),
      pick(json['authorName']),
      fromPerson(customerMap),
      fromPerson(userMap),
      fromPerson(reviewerMap),
    ];

    for (final c in candidates) {
      if (c != null && c.toLowerCase() != 'customer' && c.toLowerCase() != 'user') {
        return c;
      }
    }

    for (final m in [customerMap, userMap, reviewerMap]) {
      final email = pick(m?['email']);
      if (email != null && email.contains('@')) {
        final local = email.split('@').first;
        if (local.isNotEmpty) return local;
      }
    }

    return 'Anonymous reviewer';
  }

  static String? _parseAvatar(
    Map<String, dynamic> json,
    Map<String, dynamic>? userMap,
    Map<String, dynamic>? customerMap,
    Map<String, dynamic>? reviewerMap,
  ) {
    String? pick(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty) ? s : null;
    }

    String? fromPerson(Map<String, dynamic>? m) {
      if (m == null) return null;
      return pick(m['profilePicture']) ??
          pick(m['profilepicture']) ??
          pick(m['photoUrl']) ??
          pick(m['photoURL']) ??
          pick(m['avatar']) ??
          pick(m['avatarUrl']);
    }

    return pick(json['userAvatar']) ??
        pick(json['customerAvatar']) ??
        fromPerson(customerMap) ??
        fromPerson(userMap) ??
        fromPerson(reviewerMap);
  }

  static int _parseRating(dynamic v) {
    if (v is num) return v.round().clamp(1, 5);
    return (int.tryParse(v?.toString() ?? '') ?? 5).clamp(1, 5);
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static ReviewReaction _parseReaction(Map<String, dynamic> json) {
    final raw = (json['myReaction'] ??
            json['userReaction'] ??
            json['reaction'] ??
            json['vote'] ??
            json['userVote'])
        ?.toString()
        .toLowerCase()
        .trim();

    if (raw != null && raw.isNotEmpty) {
      if (raw == 'like' || raw == 'liked' || raw == 'up') {
        return ReviewReaction.like;
      }
      if (raw == 'dislike' || raw == 'disliked' || raw == 'down') {
        return ReviewReaction.dislike;
      }
      if (raw == 'none' || raw == 'null' || raw == 'neutral') {
        return ReviewReaction.none;
      }
    }

    final liked = json['liked'] == true || json['isLiked'] == true;
    final disliked = json['disliked'] == true || json['isDisliked'] == true;

    // Never allow both — treat as unknown if the API sends conflicting flags.
    if (liked && disliked) return ReviewReaction.none;
    if (disliked) return ReviewReaction.dislike;
    if (liked) return ReviewReaction.like;

    return ReviewReaction.none;
  }
}
