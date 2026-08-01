import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_reviews_page.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Offer details with seller info before checkout.
class PromoDetailPage extends StatefulWidget {
  const PromoDetailPage({super.key, required this.promo});

  final PromoModel promo;

  @override
  State<PromoDetailPage> createState() => _PromoDetailPageState();
}

class _PromoDetailPageState extends State<PromoDetailPage> {
  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);

  final _svc = PromoService();
  late PromoModel _promo;
  Future<PromoMerchantInfo>? _merchantFuture;

  @override
  void initState() {
    super.initState();
    _promo = widget.promo;
    _merchantFuture = PromoService.resolvePromoMerchant(_promo);
    _refreshPromoFromApi();
  }

  Future<void> _refreshPromoFromApi() async {
    try {
      final items = await _svc.fetchActivePromos();
      final fresh = items.cast<PromoModel?>().firstWhere(
            (p) => p?.id == widget.promo.id,
            orElse: () => null,
          );
      if (fresh == null || !mounted) return;
      setState(() {
        _promo = fresh;
        _merchantFuture = PromoService.resolvePromoMerchant(fresh);
      });
    } catch (_) {}
  }

  Future<void> _continue() async {
    if (_promo.displayPrice <= 0) {
      ToastHelper.showCustomToast(
        context,
        'This promotion is not available for purchase yet.',
        isSuccess: false,
        errorMessage: 'Price not set',
      );
      return;
    }

    final merchant = await _merchantFuture;
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          item: _promo.toCheckoutItem(merchant: merchant),
          promoSubscribeId: _promo.id,
        ),
      ),
    );
  }

  void _openMerchantReviews(PromoMerchantInfo merchant) {
    final merchantId = RegExp(r'^[A-Za-z0-9_-]{20,}$')
            .hasMatch(merchant.merchantRef.trim())
        ? merchant.merchantRef.trim()
        : (merchant.serviceProviderId?.trim().isNotEmpty == true
            ? merchant.serviceProviderId!.trim()
            : merchant.backendMerchantId.toString());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantReviewsPage(
          merchantId: merchantId,
          merchantName: merchant.displayName,
          logoUrl: merchant.logoUrl,
          rating: merchant.rating,
          serviceProviderId: merchant.serviceProviderId,
          sellerUserId: merchant.sellerUserId,
          merchantBackendId: merchant.backendMerchantId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final promo = _promo;
    final imageUrl = promo.resolvedImageUrl;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: imageUrl != null ? 260 : 120,
            pinned: true,
            stretch: true,
            backgroundColor: _orange,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: imageUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ResilientCachedNetworkImage(
                          url: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFD94F00), _orange],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          PhosphorIconsBold.tag,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          promo.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                            letterSpacing: -0.3,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _PriceBadge(promo: promo),
                    ],
                  ),
                  if (promo.hasFreeTrial) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            PhosphorIconsBold.calendarBlank,
                            size: 16,
                            color: Color(0xFFFF6B00),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Offer ends ${promo.formattedPromoEnd}',
                            style: const TextStyle(
                              color: Color(0xFFD97706),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _PromoPeriodCard(promo: promo),
                  const SizedBox(height: 20),
                  const Text(
                    'About this offer',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (promo.description ?? '').trim().isNotEmpty
                        ? promo.description!.trim()
                        : 'Exclusive promotion from a Vero360 merchant. Claim now to unlock the offer.',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Seller',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<PromoMerchantInfo>(
                    future: _merchantFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const _SellerCardSkeleton();
                      }
                      final merchant = snap.data;
                      if (merchant == null) {
                        return const _SellerCardEmpty();
                      }
                      return _PromoSellerCard(
                        merchant: merchant,
                        onOpenReviews: () => _openMerchantReviews(merchant),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _BenefitTile(
                    icon: PhosphorIconsBold.shieldCheck,
                    title: 'Verified merchant offer',
                    subtitle: 'Promotions are published by Vero360 partners.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _continue,
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(PhosphorIconsBold.arrowRight),
              label: Text(
                'Buy now · ${promo.formattedPrice}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoSellerCard extends StatelessWidget {
  const _PromoSellerCard({
    required this.merchant,
    required this.onOpenReviews,
  });

  final PromoMerchantInfo merchant;
  final VoidCallback onOpenReviews;

  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFECEEF2);
  static const _orange = Color(0xFFFF6B00);

  @override
  Widget build(BuildContext context) {
    final status = (merchant.status ?? '').trim();
    final businessDesc = (merchant.description ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _merchantAvatar(merchant.logoUrl, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: _ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _ratingStars(merchant.rating),
                          const SizedBox(width: 8),
                          Text(
                            merchant.reviewCount > 0
                                ? '${merchant.reviewCount} review${merchant.reviewCount == 1 ? '' : 's'}'
                                : 'No reviews yet',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _statusChip(merchant.status),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _detailRow(
                    icon: Icons.badge_outlined,
                    label: 'Business name',
                    value: merchant.businessName ?? merchant.displayName,
                  ),
                  const SizedBox(height: 8),
                  _detailRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Status',
                    value: status.isEmpty ? '—' : status.toUpperCase(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Business description',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              businessDesc.isNotEmpty ? businessDesc : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _ink,
                height: 1.4,
              ),
            ),
            if (merchant.recentReviews.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Recent reviews',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 8),
              ...merchant.recentReviews.map(_recentReviewTile),
            ],
            const SizedBox(height: 14),
            Material(
              color: const Color(0xFFFFF8F0),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpenReviews,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _orange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.rate_review_outlined, color: _orange, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reviews & Ratings',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'See what customers are saying',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: _muted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentReviewTile(MerchantReview review) {
    final comment = review.comment.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.authorName.trim().isEmpty
                      ? 'Customer'
                      : review.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _ink,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: Colors.amber,
                  );
                }),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4B5563),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ratingStars(double? rating) {
    final rr = ((rating ?? 0).clamp(0, 5)).toDouble();
    final filled = rr.floor();
    final hasHalf = (rr - filled) >= 0.5 && filled < 5;
    final empty = 5 - filled - (hasHalf ? 1 : 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < filled; i++)
          const Icon(Icons.star, size: 16, color: Colors.amber),
        if (hasHalf)
          const Icon(Icons.star_half, size: 16, color: Colors.amber),
        for (int i = 0; i < empty; i++)
          const Icon(Icons.star_border, size: 16, color: Colors.amber),
      ],
    );
  }

  Widget _statusChip(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    Color bg = Colors.grey.shade200;
    Color fg = Colors.black87;
    var isPending = false;
    if (s == 'open') {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    } else if (s == 'closed') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
    } else if (s == 'busy') {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
    } else if (s == 'pending') {
      isPending = true;
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
    } else if (s.contains('verified') || s.contains('approved')) {
      bg = const Color(0xFFE8F8F1);
      fg = const Color(0xFF047857);
    }
    return Chip(
      label: Text((status ?? '—').toUpperCase()),
      backgroundColor: bg,
      labelStyle: TextStyle(
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: isPending ? 11 : 12,
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _merchantAvatar(String? raw, {double size = 36}) {
    final s = (raw ?? '').trim();
    Widget child;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: ResilientCachedNetworkImage(
          url: s,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    } else if (s.isNotEmpty) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        child = ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {
        child = Icon(Icons.storefront_rounded, color: _orange, size: size * 0.5);
      }
    } else {
      child = Icon(Icons.storefront_rounded, color: _orange, size: size * 0.5);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Center(child: child),
    );
  }
}

class _SellerCardSkeleton extends StatelessWidget {
  const _SellerCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF2)),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B00)),
      ),
    );
  }
}

class _SellerCardEmpty extends StatelessWidget {
  const _SellerCardEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEEF2)),
      ),
      child: const Text(
        'Merchant details will appear here when available.',
        style: TextStyle(color: Color(0xFF6B7280)),
      ),
    );
  }
}

class _PromoPeriodCard extends StatelessWidget {
  const _PromoPeriodCard({required this.promo});

  final PromoModel promo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECEEF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              PhosphorIconsBold.calendarBlank,
              color: Color(0xFFFF6B00),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Promotion period',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF101010),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Starts on ${promo.formattedPromoStart}',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  promo.promoEnd != null
                      ? 'Ends on ${promo.formattedPromoEnd}'
                      : 'End date not set',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    height: 1.35,
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

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.promo});

  final PromoModel promo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        promo.formattedPrice,
        style: const TextStyle(
          color: Color(0xFFFF6B00),
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECEEF2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFFF6B00), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF101010),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                    height: 1.35,
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
