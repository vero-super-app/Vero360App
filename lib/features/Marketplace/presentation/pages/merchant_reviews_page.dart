import 'package:flutter/material.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Merchant reviews screen — wire up review APIs here later.
class MerchantReviewsPage extends StatelessWidget {
  static const _brandOrange = Color(0xFFFF8A00);
  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFECEEF2);

  final String merchantId;
  final String merchantName;
  final String? logoUrl;
  final double? rating;

  const MerchantReviewsPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
    this.logoUrl,
    this.rating,
  });

  @override
  Widget build(BuildContext context) {
    final score = (rating ?? 0).clamp(0, 5).toDouble();
    final displayScore = score == score.truncateToDouble()
        ? score.toStringAsFixed(0)
        : score.toStringAsFixed(1);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
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
            color: _ink,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _summaryCard(displayScore, score),
          const SizedBox(height: 16),
          _sectionHeader('Customer reviews'),
          const SizedBox(height: 10),
          _emptyReviewsCard(),
          const SizedBox(height: 20),
          _writeReviewButton(context),
        ],
      ),
    );
  }

  Widget _summaryCard(String displayScore, double score) {
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Row(
        children: [
          _merchantAvatar(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchantName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _starRow(score),
                    const SizedBox(width: 8),
                    Text(
                      displayScore,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      ' / 5',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '0 reviews',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _merchantAvatar() {
    final url = (logoUrl ?? '').trim();
    if (url.isEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFFFFF4E5),
        child: Icon(Icons.storefront_rounded, color: _brandOrange, size: 28),
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

  Widget _starRow(double rating) {
    final filled = rating.floor();
    final hasHalf = (rating - filled) >= 0.5 && filled < 5;
    final empty = 5 - filled - (hasHalf ? 1 : 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < filled; i++)
          const Icon(Icons.star_rounded, size: 18, color: _brandOrange),
        if (hasHalf)
          const Icon(Icons.star_half_rounded, size: 18, color: _brandOrange),
        for (var i = 0; i < empty; i++)
          Icon(Icons.star_outline_rounded, size: 18, color: Colors.grey.shade400),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _ink,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _emptyReviewsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rate_review_outlined,
              size: 28,
              color: _brandOrange,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Be the first to share your experience with $merchantName.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _writeReviewButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Review submission coming soon.'),
            ),
          );
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write a review'),
        style: FilledButton.styleFrom(
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
