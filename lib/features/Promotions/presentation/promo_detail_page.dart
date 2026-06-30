import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';
import 'package:vero360_app/features/Promotions/presentation/promo_checkout_page.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Offer details before checkout.
class PromoDetailPage extends StatelessWidget {
  const PromoDetailPage({super.key, required this.promo});

  final PromoModel promo;

  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);

  void _continue(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PromoCheckoutPage(promo: promo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        color: const Color(0xFFE8F8F1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            PhosphorIconsBold.sparkle,
                            size: 16,
                            color: Color(0xFF047857),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Free trial until ${_fmtDate(promo.freeTrialEndsAt!)}',
                            style: const TextStyle(
                              color: Color(0xFF047857),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  _BenefitTile(
                    icon: PhosphorIconsBold.shieldCheck,
                    title: 'Verified merchant offer',
                    subtitle: 'Promotions are published by Vero360 partners.',
                  ),
                  const SizedBox(height: 10),
                  _BenefitTile(
                    icon: PhosphorIconsBold.creditCard,
                    title: promo.isFree ? 'No payment required' : 'Secure checkout',
                    subtitle: promo.isFree
                        ? 'Claim instantly with your Vero360 account.'
                        : 'Pay with mobile money or card via PayChangu.',
                  ),
                  const SizedBox(height: 10),
                  _BenefitTile(
                    icon: PhosphorIconsBold.bell,
                    title: 'Instant activation',
                    subtitle: 'Get confirmation as soon as your claim is complete.',
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
              onPressed: () => _continue(context),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                promo.isFree
                    ? PhosphorIconsBold.gift
                    : PhosphorIconsBold.arrowRight,
              ),
              label: Text(
                promo.isFree ? 'Claim for free' : 'Continue to checkout',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.promo});

  final PromoModel promo;

  @override
  Widget build(BuildContext context) {
    final free = promo.isFree;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: free ? const Color(0xFFE8F8F1) : const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        promo.formattedPrice,
        style: TextStyle(
          color: free ? const Color(0xFF047857) : const Color(0xFFFF6B00),
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
