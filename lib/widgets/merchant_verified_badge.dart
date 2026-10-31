import 'package:flutter/material.dart';

/// True when a merchant passed KYC / admin verification.
class MerchantVerification {
  MerchantVerification._();

  static const _ok = {'verified', 'approved'};

  static bool isVerifiedFromData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    if (data['kycVerified'] == true ||
        data['verified'] == true ||
        data['isVerified'] == true) {
      return true;
    }
    for (final key in ['kycStatus', 'verificationStatus']) {
      final v = (data[key] ?? '').toString().trim().toLowerCase();
      if (_ok.contains(v)) return true;
    }
    return false;
  }
}

/// Green check used next to a verified merchant name.
class MerchantVerifiedBadge extends StatelessWidget {
  const MerchantVerifiedBadge({
    super.key,
    this.showLabel = true,
    this.size = 16,
  });

  final bool showLabel;
  final double size;

  static const Color green = Color(0xFF16A34A);
  static const Color soft = Color(0xFFDCFCE7);

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.verified_rounded, size: size, color: green);
    if (!showLabel) {
      return Tooltip(message: 'Verified merchant', child: icon);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          const Text(
            'Verified',
            style: TextStyle(
              color: green,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Merchant name with an optional green verified chip.
class MerchantNameWithBadge extends StatelessWidget {
  const MerchantNameWithBadge({
    super.key,
    required this.name,
    required this.verified,
    this.style,
    this.maxLines = 1,
    this.showLabel = true,
    this.badgeSize = 16,
  });

  final String name;
  final bool verified;
  final TextStyle? style;
  final int maxLines;
  final bool showLabel;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 6),
          MerchantVerifiedBadge(showLabel: showLabel, size: badgeSize),
        ],
      ],
    );
  }
}
