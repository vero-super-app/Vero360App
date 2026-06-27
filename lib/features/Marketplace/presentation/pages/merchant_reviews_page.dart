import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/widgets/modern_confirm_dialog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class MerchantReviewsPage extends StatefulWidget {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFECEEF2);
  static const _bg = Color(0xFFF7F8FA);

  final String merchantId;
  final String merchantName;
  final String? logoUrl;
  final double? rating;
  final String? serviceProviderId;
  final String? sellerUserId;
  final int? merchantBackendId;

  const MerchantReviewsPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.logoUrl,
    this.rating,
    this.serviceProviderId,
    this.sellerUserId,
    this.merchantBackendId,
  });

  @override
  State<MerchantReviewsPage> createState() => _MerchantReviewsPageState();
}

class _MerchantReviewsPageState extends State<MerchantReviewsPage> {
  static const _service = MerchantReviewService();

  bool _loading = true;
  bool _refreshing = false;
  bool _isLoggedIn = false;
  String? _error;
  int? _myUserId;
  int? _resolvedMerchantId;
  String _myDisplayName = '';
  String? _myAvatarUrl;
  MerchantReviewSummary? _summary;
  List<MerchantReview> _reviews = const [];
  final Set<String> _reactingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }

    try {
      final loggedIn = await AuthHandler.isAuthenticated();
      final prefs = await SharedPreferences.getInstance();
      final myId = loggedIn
          ? (prefs.getInt('userId') ?? prefs.getInt('user_id'))
          : null;
      final myName = loggedIn
          ? (prefs.getString('fullName') ?? prefs.getString('name') ?? '')
          : '';
      final myAvatar =
          loggedIn ? prefs.getString('profilepicture') : null;

      final merchantBackendId = await MerchantReviewIdResolver.resolveMerchantId(
        merchantRef: widget.merchantId,
        serviceProviderId: widget.serviceProviderId,
        sellerUserId: widget.sellerUserId,
        preResolvedBackendId: widget.merchantBackendId,
      );

      final results = await Future.wait([
        _service.getMerchantSummary(merchantBackendId),
        _service.getMerchantReviews(merchantBackendId),
      ]);

      if (!mounted) return;
      setState(() {
        _isLoggedIn = loggedIn;
        _myUserId = myId;
        _myDisplayName = myName.trim();
        _myAvatarUrl = myAvatar?.trim();
        _resolvedMerchantId = merchantBackendId;
        _summary = results[0] as MerchantReviewSummary;
        _reviews = (results[1] as List<MerchantReview>)
            .map((r) => _enrichReview(r.withNormalizedReaction()))
            .toList();
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e is ApiException ? e.message : 'Could not load reviews.';
      });
    }
  }

  double get _displayRating {
    final s = _summary;
    if (s != null && s.average > 0) return s.average.clamp(0, 5);
    return (widget.rating ?? 0).clamp(0, 5);
  }

  int get _reviewCount => _summary?.count ?? _reviews.length;

  MerchantReview? get _myExistingReview {
    final me = _myUserId;
    if (me == null) return null;
    for (final r in _reviews) {
      if (r.isMine(me)) return r;
    }
    return null;
  }

  bool _isGenericName(String name) {
    final n = name.trim().toLowerCase();
    return n.isEmpty ||
        n == 'customer' ||
        n == 'user' ||
        n == 'anonymous reviewer' ||
        n == 'anonymous';
  }

  String _reviewerDisplayName(MerchantReview review) {
    if (review.isMine(_myUserId) && _myDisplayName.isNotEmpty) {
      return _myDisplayName;
    }
    if (!_isGenericName(review.authorName)) return review.authorName;
    return 'Anonymous reviewer';
  }

  String? _reviewerAvatarUrl(MerchantReview review) {
    if (review.isMine(_myUserId) &&
        _myAvatarUrl != null &&
        _myAvatarUrl!.isNotEmpty) {
      return _myAvatarUrl;
    }
    final url = review.authorAvatar?.trim();
    return (url != null && url.isNotEmpty) ? url : null;
  }

  MerchantReview _enrichReview(MerchantReview review) {
    if (!review.isMine(_myUserId)) return review;
    var r = review;
    if (_myDisplayName.isNotEmpty && _isGenericName(r.authorName)) {
      r = r.copyWith(authorName: _myDisplayName);
    }
    if (_myAvatarUrl != null &&
        _myAvatarUrl!.isNotEmpty &&
        (r.authorAvatar == null || r.authorAvatar!.trim().isEmpty)) {
      r = r.copyWith(authorAvatar: _myAvatarUrl);
    }
    return r;
  }

  String _reviewerInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'R';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<bool> _requireLogin() async {
    if (await AuthHandler.isAuthenticated()) return true;
    _toast('Please sign in to continue.', error: true);
    return false;
  }

  Future<void> _openReviewEditor({MerchantReview? existing}) async {
    if (!await _requireLogin()) return;

    final result = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewEditorSheet(
        merchantName: widget.merchantName,
        initialRating: existing?.rating ?? 5,
        initialComment: existing?.comment ?? '',
        isEditing: existing != null,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final merchantId = _resolvedMerchantId ??
          await MerchantReviewIdResolver.resolveMerchantId(
            merchantRef: widget.merchantId,
            serviceProviderId: widget.serviceProviderId,
            sellerUserId: widget.sellerUserId,
            preResolvedBackendId: widget.merchantBackendId,
          );
      final customerId = await MerchantReviewIdResolver.resolveCustomerId();

      if (existing != null) {
        await _service.updateReview(
          reviewId: existing.id,
          rating: result.rating,
          comment: result.comment,
        );
        _toast('Review updated');
      } else {
        await _service.createReview(
          merchantId: merchantId,
          customerId: customerId,
          rating: result.rating,
          comment: result.comment,
        );
        _toast('Review posted — thank you!');
      }
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(
        e is ApiException ? e.message : 'Could not save review.',
        error: true,
      );
    }
  }

  Future<void> _deleteReview(MerchantReview review) async {
    if (!await _requireLogin()) return;

    final ok = await showModernConfirmDialog(
      context,
      title: 'Delete review?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;

    try {
      await _service.deleteReview(review.id);
      _toast('Review deleted');
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(
        e is ApiException ? e.message : 'Could not delete review.',
        error: true,
      );
    }
  }

  Future<void> _toggleReaction(MerchantReview review, ReviewReaction target) async {
    if (!await _requireLogin()) return;
    if (_reactingIds.contains(review.id)) return;
    if (review.myReaction == target) return;

    final previous = review;
    final optimistic = review.withReactionTap(target);

    setState(() {
      _reactingIds.add(review.id);
      final idx = _reviews.indexWhere((r) => r.id == review.id);
      if (idx >= 0) _reviews = List.of(_reviews)..[idx] = optimistic;
    });

    try {
      final updated = target == ReviewReaction.like
          ? await _service.likeReview(review.id)
          : await _service.dislikeReview(review.id);

      if (!mounted) return;
      setState(() {
        final idx = _reviews.indexWhere((r) => r.id == review.id);
        if (idx >= 0) {
          final reconciled = _enrichReview(
            updated.reconcileReactionResponse(
              before: previous,
              target: target,
            ),
          );
          _reviews = List.of(_reviews)..[idx] = reconciled;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _reviews.indexWhere((r) => r.id == review.id);
        if (idx >= 0) _reviews = List.of(_reviews)..[idx] = previous;
      });
      _toast(
        e is ApiException ? e.message : 'Could not update reaction.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _reactingIds.remove(review.id));
    }
  }

  void _onReactionTap(MerchantReview review, ReviewReaction tap) {
    if (_reactingIds.contains(review.id)) return;
    if (review.myReaction == tap) return;
    _toggleReaction(review, tap);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MerchantReviewsPage._bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text(
          'Reviews & Ratings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: MerchantReviewsPage._ink,
            letterSpacing: -0.2,
          ),
        ),
      ),
      floatingActionButton: _loading || !_isLoggedIn
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final mine = _myExistingReview;
                if (mine != null) {
                  _openReviewEditor(existing: mine);
                } else {
                  _openReviewEditor();
                }
              },
              backgroundColor: MerchantReviewsPage._brandOrange,
              foregroundColor: Colors.white,
              icon: Icon(
                _myExistingReview != null
                    ? Icons.edit_outlined
                    : Icons.rate_review_outlined,
              ),
              label: Text(
                _myExistingReview != null ? 'Edit your review' : 'Write review',
              ),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: MerchantReviewsPage._brandOrange),
      );
    }

    if (_error != null && _reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: MerchantReviewsPage._muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MerchantReviewsPage._ink,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(
                  backgroundColor: MerchantReviewsPage._brandOrange,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: MerchantReviewsPage._brandOrange,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          _summaryCard(),
          const SizedBox(height: 20),
          _sectionHeader('Customer reviews'),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: MerchantReviewsPage._brandOrange,
              ),
            ),
          const SizedBox(height: 10),
          if (_reviews.isEmpty) _emptyCard() else ..._reviews.map(_reviewCard),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final score = _displayRating;
    final displayScore = score == score.truncateToDouble()
        ? score.toStringAsFixed(0)
        : score.toStringAsFixed(1);
    final s = _summary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MerchantReviewsPage._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _merchantAvatar(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.merchantName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: MerchantReviewsPage._ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _starRow(score, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      displayScore,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: MerchantReviewsPage._ink,
                      ),
                    ),
                    Text(
                      ' / 5',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$_reviewCount review${_reviewCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if (s != null && (s.bayesian != null || s.wilson != null)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (s.bayesian != null)
                        _statChip('Bayesian', s.bayesian!.toStringAsFixed(1)),
                      if (s.wilson != null)
                        _statChip('Wilson', s.wilson!.toStringAsFixed(1)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: MerchantReviewsPage._brandOrange,
        ),
      ),
    );
  }

  Widget _merchantAvatar() {
    final url = (widget.logoUrl ?? '').trim();
    if (url.isEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFFFFF4E5),
        child: const Icon(
          Icons.storefront_rounded,
          color: MerchantReviewsPage._brandOrange,
          size: 28,
        ),
      );
    }
    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFFF0F2F5),
      child: ClipOval(
        child: ResilientCachedNetworkImage(
          url: url,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: MerchantReviewsPage._ink,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MerchantReviewsPage._border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF4E5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rate_review_outlined,
              size: 28,
              color: MerchantReviewsPage._brandOrange,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: MerchantReviewsPage._ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Be the first to share your experience with ${widget.merchantName}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: MerchantReviewsPage._muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(MerchantReview review) {
    final isMine = review.isMine(_myUserId);
    final displayName = _reviewerDisplayName(review);
    final avatarUrl = _reviewerAvatarUrl(review);
    final date = review.createdAt;
    final dateLabel = date != null
        ? DateFormat('d MMM yyyy').format(date.toLocal())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine
              ? MerchantReviewsPage._brandOrange.withValues(alpha: 0.35)
              : MerchantReviewsPage._border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reviewerAvatar(displayName, avatarUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: MerchantReviewsPage._ink,
                            ),
                          ),
                        ),
                        if (isMine)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: MerchantReviewsPage._brandOrange,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _starRow(review.rating.toDouble(), size: 14),
                        if (dateLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isMine)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, color: Colors.grey.shade600),
                  onSelected: (v) {
                    if (v == 'edit') _openReviewEditor(existing: review);
                    if (v == 'delete') _deleteReview(review);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit review')),
                    PopupMenuItem(value: 'delete', child: Text('Delete review')),
                  ],
                ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.comment,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: MerchantReviewsPage._ink,
              ),
            ),
          ],
          if (!isMine) ...[
            const SizedBox(height: 12),
            _reactionRow(review, readOnly: !_isLoggedIn),
          ],
        ],
      ),
    );
  }

  Widget _reviewerAvatar(String name, String? url) {
    const size = 40.0;
    final initials = _reviewerInitials(name);
    final hash = name.hashCode.abs();

    if (url != null && url.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MerchantReviewsPage._border),
        ),
        child: ClipOval(
          child: ResilientCachedNetworkImage(
            url: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    const palettes = <List<Color>>[
      [Color(0xFFE8ECF4), Color(0xFFD4DAE8)],
      [Color(0xFFFFF4E5), Color(0xFFFFE4CC)],
      [Color(0xFFEAF4FF), Color(0xFFD6E8FF)],
      [Color(0xFFF3E8FF), Color(0xFFE4D4FF)],
    ];
    final gradient = palettes[hash % palettes.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        border: Border.all(color: MerchantReviewsPage._border),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: MerchantReviewsPage._ink,
          ),
        ),
      ),
    );
  }

  Widget _reactionRow(MerchantReview review, {bool readOnly = false}) {
    final busy = _reactingIds.contains(review.id);
    final liked = review.myReaction == ReviewReaction.like;
    final disliked = review.myReaction == ReviewReaction.dislike;

    return Row(
      children: [
        _reactionButton(
          icon: liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
          label: '${review.likes}',
          active: liked,
          activeColor: const Color(0xFF2563EB),
          readOnly: readOnly,
          onTap: readOnly || busy
              ? null
              : liked
                  ? null
                  : () => _onReactionTap(review, ReviewReaction.like),
        ),
        const SizedBox(width: 8),
        _reactionButton(
          icon: disliked ? Icons.thumb_down_rounded : Icons.thumb_down_outlined,
          label: '${review.dislikes}',
          active: disliked,
          activeColor: const Color(0xFFDC2626),
          readOnly: readOnly,
          onTap: readOnly || busy
              ? null
              : disliked
                  ? null
                  : () => _onReactionTap(review, ReviewReaction.dislike),
        ),
        if (busy) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }

  Widget _reactionButton({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return Material(
      color: readOnly
          ? const Color(0xFFF7F8FA)
          : active
              ? activeColor.withValues(alpha: 0.1)
              : const Color(0xFFF3F4F7),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: readOnly
                    ? MerchantReviewsPage._muted
                    : active
                        ? activeColor
                        : MerchantReviewsPage._muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: readOnly
                      ? MerchantReviewsPage._muted
                      : active
                          ? activeColor
                          : MerchantReviewsPage._muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _starRow(double rating, {double size = 16}) {
    final filled = rating.floor();
    final hasHalf = (rating - filled) >= 0.5 && filled < 5;
    final empty = 5 - filled - (hasHalf ? 1 : 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < filled; i++)
          Icon(Icons.star_rounded, size: size, color: MerchantReviewsPage._brandOrange),
        if (hasHalf)
          Icon(Icons.star_half_rounded, size: size, color: MerchantReviewsPage._brandOrange),
        for (var i = 0; i < empty; i++)
          Icon(Icons.star_outline_rounded, size: size, color: Colors.grey.shade400),
      ],
    );
  }
}

class _ReviewDraft {
  final int rating;
  final String comment;
  const _ReviewDraft({required this.rating, required this.comment});
}

class _ReviewEditorSheet extends StatefulWidget {
  final String merchantName;
  final int initialRating;
  final String initialComment;
  final bool isEditing;

  const _ReviewEditorSheet({
    required this.merchantName,
    required this.initialRating,
    required this.initialComment,
    required this.isEditing,
  });

  @override
  State<_ReviewEditorSheet> createState() => _ReviewEditorSheetState();
}

class _ReviewEditorSheetState extends State<_ReviewEditorSheet> {
  late int _rating;
  late final TextEditingController _commentCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating.clamp(1, 5);
    _commentCtrl = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.isEditing ? 'Edit your review' : 'Write a review',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: MerchantReviewsPage._ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.merchantName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: MerchantReviewsPage._muted,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Your rating',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MerchantReviewsPage._muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    final filled = star <= _rating;
                    return IconButton(
                      onPressed: () => setState(() => _rating = star),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 36,
                        color: filled
                            ? MerchantReviewsPage._brandOrange
                            : Colors.grey.shade400,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 5,
                  minLines: 3,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Share your experience…',
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: MerchantReviewsPage._brandOrange,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting
                      ? null
                      : () {
                          final text = _commentCtrl.text.trim();
                          if (text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please write a short review.'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(
                            context,
                            _ReviewDraft(rating: _rating, comment: text),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: MerchantReviewsPage._brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    widget.isEditing ? 'Save changes' : 'Post review',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
