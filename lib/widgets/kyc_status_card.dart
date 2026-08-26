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
          'Complete KYC to unlock wallet withdrawals and receive payouts.';
      badge = 'For payouts';
      icon = Icons.badge_outlined;
      accent = const Color(0xFFFF8A00);
      wash = const Color(0xFFFFFBF7);
    }

    final canStart = !snapshot.verified;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: canStart ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: wash,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withValues(alpha: 0.85), accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
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
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Color(0xFF141414),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
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
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canStart) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    color: accent.withValues(alpha: 0.8)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
