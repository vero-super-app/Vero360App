import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Online / Offline pill toggle for the driver header.
class DriverOnlineToggle extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onToggle;

  const DriverOnlineToggle({
    required this.isOnline,
    required this.onToggle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: 52,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isOnline
                  ? RideShareColors.primary
                  : RideShareColors.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline
                    ? RideShareColors.primaryDeep
                    : RideShareColors.outlineVariant,
              ),
            ),
            alignment: isOnline ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isOnline ? Colors.white : RideShareColors.onSurfaceVariant,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isOnline ? FontWeight.w800 : FontWeight.w600,
              color: isOnline
                  ? RideShareColors.primaryDeep
                  : RideShareColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class DriverEarningsSummaryCard extends StatelessWidget {
  final String amountLabel;
  final String? trendLabel;

  const DriverEarningsSummaryCard({
    required this.amountLabel,
    this.trendLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RideShareColors.primaryContainer,
            Color(0xFF0E1A33),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primaryContainer.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -24,
            child: Icon(
              Icons.payments_outlined,
              size: 120,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TODAY'S EARNINGS",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                amountLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              if (trendLabel != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 16,
                      color: RideShareColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        trendLabel!,
                        style: const TextStyle(
                          color: RideShareColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class DriverTripsProgressCard extends StatelessWidget {
  final int trips;
  final int target;

  const DriverTripsProgressCard({
    required this.trips,
    this.target = 15,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target <= 0 ? 0.0 : (trips / target).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RideShareColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primaryContainer.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TRIPS COMPLETED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: RideShareColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$trips',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: RideShareColors.titleText,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Target: $target trips',
                  style: const TextStyle(
                    fontSize: 12,
                    color: RideShareColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                trackColor: RideShareColors.surfaceContainer,
                progressColor: RideShareColors.primary,
              ),
              child: Center(
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: RideShareColors.titleText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 5;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final prog = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      prog,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class DriverWeeklyGoalCard extends StatelessWidget {
  final double earned;
  final double goal;
  final NumberFormat money;

  const DriverWeeklyGoalCard({
    required this.earned,
    required this.goal,
    required this.money,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal <= 0 ? 0.0 : (earned / goal).clamp(0.0, 1.0);
    final pct = (progress * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RideShareColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primaryContainer.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Weekly Goal',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: RideShareColors.titleText,
                  ),
                ),
              ),
              Icon(
                Icons.emoji_events_rounded,
                color: RideShareColors.primary.withValues(alpha: 0.9),
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MK ${money.format(earned)} / MK ${money.format(goal)}',
            style: const TextStyle(
              color: RideShareColors.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: RideShareColors.surfaceContainer,
              color: RideShareColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$pct% Complete',
                  style: const TextStyle(
                    color: RideShareColors.primaryDeep,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                TextSpan(
                  text: progress >= 1
                      ? ' — Goal crushed!'
                      : ' — Keep going for your bonus',
                  style: const TextStyle(
                    color: RideShareColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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

class DriverRatingCard extends StatelessWidget {
  final double rating;
  final int totalRides;
  final bool isVerified;

  const DriverRatingCard({
    required this.rating,
    required this.totalRides,
    this.isVerified = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filled = rating.floor().clamp(0, 5);
    final half = (rating - filled) >= 0.4;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RideShareColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primaryContainer.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Driver Rating',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: RideShareColors.titleText,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Icon(
                        i < filled
                            ? Icons.star_rounded
                            : (i == filled && half
                                ? Icons.star_half_rounded
                                : Icons.star_outline_rounded),
                        color: RideShareColors.primary,
                        size: 22,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      rating > 0 ? rating.toStringAsFixed(2) : '—',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: RideShareColors.titleText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  totalRides > 0
                      ? 'Across $totalRides trips on Vero Ride'
                      : 'Complete trips to build your rating',
                  style: const TextStyle(
                    fontSize: 12,
                    color: RideShareColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isVerified ? 'Verified' : 'Rising',
                style: const TextStyle(
                  fontSize: 11,
                  color: RideShareColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rating >= 4.8
                    ? 'Gold Tier'
                    : rating >= 4.5
                        ? 'Silver Tier'
                        : 'Starter',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: RideShareColors.titleText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DriverRecentActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amountLabel;
  final String? metaLeft;
  final String? metaRight;
  final String? badge;
  final VoidCallback? onTap;

  const DriverRecentActivityTile({
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    this.metaLeft,
    this.metaRight,
    this.badge,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RideShareColors.outlineVariant),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: RideShareColors.surfaceContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_car_outlined,
                        color: RideShareColors.primaryContainer,
                      ),
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
                              color: RideShareColors.titleText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: RideShareColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      amountLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: RideShareColors.titleText,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      color: RideShareColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (metaLeft != null || metaRight != null || badge != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: RideShareColors.surfaceContainerLow,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(15),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (metaLeft != null) ...[
                        const Icon(
                          Icons.straighten,
                          size: 14,
                          color: RideShareColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          metaLeft!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: RideShareColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (metaRight != null) ...[
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.schedule,
                          size: 14,
                          color: RideShareColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          metaRight!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: RideShareColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: RideShareColors.primarySoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: RideShareColors.primaryDeep,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverGlassChip extends StatelessWidget {
  final Widget child;

  const DriverGlassChip({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: RideShareColors.primaryContainer.withValues(alpha: 0.08),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class DriverQuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool outlined;

  const DriverQuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
    this.outlined = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
