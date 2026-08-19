import 'package:flutter/material.dart';
import 'package:vero360_app/utils/kyc_gate.dart';

/// Compact KYC status row for merchant dashboards.
class KycStatusCard extends StatelessWidget {
  const KycStatusCard({
    super.key,
    required this.snapshot,
    this.onTap,
  });

  final KycStatusSnapshot snapshot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    late final String title;
    late final String subtitle;
    late final String badge;
    late final IconData icon;
    late final Color accent;
    late final Color wash;

    if (snapshot.verified) {
      title = 'Identity verified';
      subtitle = 'Your KYC check is complete.';
      badge = 'Verified';
      icon = Icons.verified_user_rounded;
      accent = const Color(0xFF1B8F3E);
      wash = const Color(0xFFF4FBF6);
    } else if (snapshot.pending) {
      title = 'Verification in progress';
      subtitle = 'We are reviewing your Didit submission.';
      badge = 'In review';
      icon = Icons.hourglass_top_rounded;
      accent = const Color(0xFFE86F00);
      wash = const Color(0xFFFFFBF7);
    } else if (snapshot.rejected) {
      title = 'Verification needs attention';
      subtitle = snapshot.rejectionReason.isNotEmpty
          ? snapshot.rejectionReason
          : 'Your previous attempt was declined. Try again.';
      badge = 'Action needed';
      icon = Icons.gpp_bad_rounded;
      accent = const Color(0xFFD14343);
      wash = const Color(0xFFFFF8F7);
    } else {
      title = 'Verify your identity';
      subtitle =
          'Food merchants must complete KYC before posting dishes and receiving payouts.';
      badge = 'Required';
      icon = Icons.badge_outlined;
      accent = const Color(0xFFFF8A00);
      wash = const Color(0xFFFFFBF7);
    }

    final canStart = !snapshot.verified;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: canStart ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: wash,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'KYC verification',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Color(0xFF141414),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.28)),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B6B6B),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (canStart) ...[
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
