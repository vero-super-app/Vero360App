import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class MerchantFollowerRow {
  const MerchantFollowerRow({
    required this.uid,
    required this.name,
    this.email,
    this.photoUrl,
    this.followedAt,
    this.backendUserId,
    this.shopReview,
  });

  final String uid;
  final String name;
  final String? email;
  final String? photoUrl;
  final DateTime? followedAt;
  final int? backendUserId;
  final MerchantReview? shopReview;
}

/// Modern list of people who follow a shop — profile, name, and their review.
class MerchantFollowersPage extends StatefulWidget {
  const MerchantFollowersPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.merchantLogoUrl,
    this.merchantBackendId,
    this.initialFollowerCount = 0,
  });

  final String merchantId;
  final String merchantName;
  final String? merchantLogoUrl;
  final int? merchantBackendId;
  final int initialFollowerCount;

  static const _orange = Color(0xFFFF8A00);
  static const _navy = Color(0xFF16284C);
  static const _bg = Color(0xFFF5F6FA);
  static const _ink = Color(0xFF1A1D26);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E8F0);

  @override
  State<MerchantFollowersPage> createState() => _MerchantFollowersPageState();
}

class _MerchantFollowersPageState extends State<MerchantFollowersPage> {
  final _db = FirebaseFirestore.instance;
  final _reviewService = const MerchantReviewService();

  bool _loading = true;
  String? _error;
  List<MerchantFollowerRow> _followers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final mid = widget.merchantId.trim();
      QuerySnapshot<Map<String, dynamic>> docs;
      try {
        docs = await _db
            .collection('merchant_followers')
            .doc(mid)
            .collection('followers')
            .orderBy('followedAt', descending: true)
            .limit(200)
            .get();
      } catch (_) {
        docs = await _db
            .collection('merchant_followers')
            .doc(mid)
            .collection('followers')
            .limit(200)
            .get();
      }

      final reviews = await _loadShopReviews();

      final rows = <MerchantFollowerRow>[];
      // Batch-load user profiles (chunks of 10 for whereIn, or parallel gets).
      final uids = docs.docs
          .map((d) {
            final data = d.data();
            final uid = (data['uid'] ?? d.id).toString().trim();
            return uid;
          })
          .where((u) => u.isNotEmpty)
          .toList();

      final profiles = await _loadUserProfiles(uids);

      for (final doc in docs.docs) {
        final data = doc.data();
        final uid = (data['uid'] ?? doc.id).toString().trim();
        if (uid.isEmpty) continue;

        final profile = profiles[uid] ?? const <String, dynamic>{};
        final name = _pickName(data, profile) ?? 'Vero360 member';
        final photo = _pickPhoto(data, profile);
        final email = _pickEmail(data, profile);
        final backendId = _pickBackendId(profile);
        final followedAt = _parseDate(data['followedAt']);
        final review = _matchReview(
          reviews: reviews,
          name: name,
          email: email,
          backendUserId: backendId,
        );

        rows.add(
          MerchantFollowerRow(
            uid: uid,
            name: name,
            email: email,
            photoUrl: photo,
            followedAt: followedAt,
            backendUserId: backendId,
            shopReview: review,
          ),
        );
      }

      rows.sort((a, b) {
        final at = a.followedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.followedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      if (!mounted) return;
      setState(() {
        _followers = rows;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load followers failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load followers. Please try again.';
        _loading = false;
      });
    }
  }

  Future<List<MerchantReview>> _loadShopReviews() async {
    try {
      var backendId = widget.merchantBackendId;
      backendId ??= await MerchantReviewIdResolver.resolveMerchantId(
        merchantRef: widget.merchantId,
        preResolvedBackendId: widget.merchantBackendId,
      );
      if (backendId <= 0) return const [];
      final cached = MerchantReviewService.peekCache(backendId);
      if (cached != null) return cached.reviews;
      return await _reviewService.getMerchantReviews(backendId);
    } catch (e) {
      debugPrint('Followers reviews load: $e');
      return const [];
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadUserProfiles(
    List<String> uids,
  ) async {
    final out = <String, Map<String, dynamic>>{};
    if (uids.isEmpty) return out;

    // Parallel individual gets — reliable for Firebase UIDs.
    await Future.wait(
      uids.map((uid) async {
        try {
          final doc = await _db.collection('users').doc(uid).get();
          if (doc.exists) {
            out[uid] = doc.data() ?? <String, dynamic>{};
          }
        } catch (_) {}
      }),
    );
    return out;
  }

  String? _pickName(Map<String, dynamic> follow, Map<String, dynamic> user) {
    for (final key in [
      'displayName',
      'fullName',
      'name',
      'userName',
      'username',
    ]) {
      final fromFollow = (follow[key] ?? '').toString().trim();
      if (fromFollow.isNotEmpty) return fromFollow;
      final fromUser = (user[key] ?? '').toString().trim();
      if (fromUser.isNotEmpty) return fromUser;
    }
    final first = (user['firstName'] ?? '').toString().trim();
    final last = (user['lastName'] ?? '').toString().trim();
    final combined = '$first $last'.trim();
    if (combined.isNotEmpty) return combined;
    return null;
  }

  String? _pickPhoto(Map<String, dynamic> follow, Map<String, dynamic> user) {
    for (final map in [follow, user]) {
      for (final key in [
        'photoUrl',
        'photoURL',
        'profilePicture',
        'profilepicture',
        'avatar',
        'avatarUrl',
      ]) {
        final v = (map[key] ?? '').toString().trim();
        if (v.startsWith('http://') || v.startsWith('https://')) return v;
      }
    }
    return null;
  }

  String? _pickEmail(Map<String, dynamic> follow, Map<String, dynamic> user) {
    for (final map in [follow, user]) {
      final v = (map['email'] ?? '').toString().trim();
      if (v.contains('@')) return v;
    }
    return null;
  }

  int? _pickBackendId(Map<String, dynamic> user) {
    for (final key in [
      'backendUserId',
      'sqlUserId',
      'userId',
      'id',
      'backendId',
    ]) {
      final raw = user[key];
      if (raw is int && raw > 0) return raw;
      final n = int.tryParse('${raw ?? ''}');
      if (n != null && n > 0) return n;
    }
    return null;
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  MerchantReview? _matchReview({
    required List<MerchantReview> reviews,
    required String name,
    String? email,
    int? backendUserId,
  }) {
    if (reviews.isEmpty) return null;

    if (backendUserId != null && backendUserId > 0) {
      for (final r in reviews) {
        if (r.reviewerId == backendUserId) return r;
      }
    }

    final nameKey = name.trim().toLowerCase();
    if (nameKey.isNotEmpty && nameKey != 'vero360 member') {
      for (final r in reviews) {
        if (r.authorName.trim().toLowerCase() == nameKey) return r;
      }
    }

    final mail = (email ?? '').trim().toLowerCase();
    if (mail.isNotEmpty) {
      final local = mail.split('@').first;
      for (final r in reviews) {
        final a = r.authorName.trim().toLowerCase();
        if (a == mail || (local.length > 2 && a.contains(local))) return r;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final countLabel = _loading
        ? (widget.initialFollowerCount > 0
            ? '${widget.initialFollowerCount}'
            : '…')
        : '${_followers.length}';

    return Scaffold(
      backgroundColor: MerchantFollowersPage._bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: MerchantFollowersPage._ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Followers',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              widget.merchantName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MerchantFollowersPage._muted,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: MerchantFollowersPage._orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  countLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MerchantFollowersPage._orange,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: MerchantFollowersPage._orange,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: 6,
        itemBuilder: (_, __) => const _FollowerSkeleton(),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: MerchantFollowersPage._muted,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: MerchantFollowersPage._orange,
              ),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_followers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 56),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MerchantFollowersPage._orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              size: 36,
              color: MerchantFollowersPage._orange,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No followers yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: MerchantFollowersPage._ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When people follow ${widget.merchantName}, they’ll show up here with their profile and shop reviews.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: MerchantFollowersPage._muted,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: _followers.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _HeaderBanner(
            merchantName: widget.merchantName,
            logoUrl: widget.merchantLogoUrl,
            count: _followers.length,
          );
        }
        return _FollowerCard(row: _followers[index - 1]);
      },
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.merchantName,
    required this.count,
    this.logoUrl,
  });

  final String merchantName;
  final String? logoUrl;
  final int count;

  @override
  Widget build(BuildContext context) {
    final url = (logoUrl ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16284C), Color(0xFF1F3A66)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: url.startsWith('http')
                ? ResilientCachedNetworkImage(
                    url: url,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: Colors.white.withValues(alpha: 0.12),
                    child: const Icon(Icons.storefront_rounded,
                        color: Colors.white),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  count == 1
                      ? '1 person follows this shop'
                      : '$count people follow this shop',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowerCard extends StatelessWidget {
  const _FollowerCard({required this.row});

  final MerchantFollowerRow row;

  @override
  Widget build(BuildContext context) {
    final review = row.shopReview;
    final followed = row.followedAt == null
        ? null
        : DateFormat('d MMM yyyy').format(row.followedAt!);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MerchantFollowersPage._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: row.name, photoUrl: row.photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                          color: MerchantFollowersPage._ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if ((row.email ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.email!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MerchantFollowersPage._muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (followed != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Followed $followed',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (review != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          '${review.rating}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (review != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: MerchantFollowersPage._border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ...List.generate(5, (i) {
                          final filled = i < review.rating;
                          return Icon(
                            filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 15,
                            color: filled
                                ? const Color(0xFFF59E0B)
                                : Colors.grey.shade400,
                          );
                        }),
                        const SizedBox(width: 8),
                        const Text(
                          'Review on this shop',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: MerchantFollowersPage._navy,
                          ),
                        ),
                      ],
                    ),
                    if (review.comment.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        review.comment.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else
              Text(
                'No review on this shop yet',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: MerchantFollowersPage._orange.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: url.startsWith('http')
            ? ResilientCachedNetworkImage(
                url: url,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                memCacheWidth: 104,
              )
            : Container(
                color: const Color(0xFFFFE8CC),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: MerchantFollowersPage._orange,
                  ),
                ),
              ),
      ),
    );
  }
}

class _FollowerSkeleton extends StatelessWidget {
  const _FollowerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MerchantFollowersPage._border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 12,
                  width: 140,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 90,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
