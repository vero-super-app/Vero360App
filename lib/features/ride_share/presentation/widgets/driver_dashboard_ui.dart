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
                color:
                    isOnline ? Colors.white : RideShareColors.onSurfaceVariant,
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
  final String todayAmountLabel;
  final int todayTrips;
  final String weekAmountLabel;
  final int weekTrips;
  final bool loading;

  const DriverEarningsSummaryCard({
    required this.todayAmountLabel,
    required this.todayTrips,
    required this.weekAmountLabel,
    required this.weekTrips,
    this.loading = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RideShareColors.primary,
            RideShareColors.primaryDeep,
            RideShareColors.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -20,
            child: Icon(
              Icons.account_balance_wallet_rounded,
              size: 110,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "TODAY'S EARNINGS",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.75),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (loading)
                Container(
                  height: 36,
                  width: 140,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              else
                Text(
                  todayAmountLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                loading
                    ? 'Loading…'
                    : todayTrips == 0
                        ? 'No trips completed today'
                        : '$todayTrips trip${todayTrips == 1 ? '' : 's'} today',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _miniStat(
                        'This week',
                        loading ? '—' : weekAmountLabel,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    Expanded(
                      child: _miniStat(
                        'Week trips',
                        loading ? '—' : '$weekTrips',
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Motivational daily trip target — progress uses real completed trips.
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
    final remaining = (target - trips).clamp(0, target);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RideShareColors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DAILY TRIP GOAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: RideShareColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$trips',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: RideShareColors.titleText,
                          height: 1,
                        ),
                      ),
                      TextSpan(
                        text: ' / $target',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: RideShareColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress >= 1
                      ? 'Goal reached — great work!'
                      : remaining == 1
                          ? '1 more trip to hit today’s goal'
                          : '$remaining more trips to hit today’s goal',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
    final radius = (size.shortestSide / 2) - 5;
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
      -3.1415926535 / 2,
      2 * 3.1415926535 * progress,
      false,
      prog,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.progressColor != progressColor;
}

/// Motivational weekly earnings target — earned value is real API data.
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Weekly earnings goal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: RideShareColors.titleText,
                  ),
                ),
              ),
              Icon(
                Icons.emoji_events_rounded,
                color: RideShareColors.primary.withValues(alpha: 0.9),
                size: 26,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MK ${money.format(earned)} of MK ${money.format(goal)}',
            style: const TextStyle(
              color: RideShareColors.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
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
          Text(
            progress >= 1
                ? 'Goal crushed — new stretch target unlocked'
                : '$pct% there — keep driving to hit this week’s goal',
            style: TextStyle(
              color: progress >= 1
                  ? RideShareColors.primaryDeep
                  : RideShareColors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
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

  const DriverRatingCard({
    required this.rating,
    required this.totalRides,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filled = rating.floor().clamp(0, 5);
    final half = (rating - filled) >= 0.4;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RideShareColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: RideShareColors.primaryDeep,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your rating',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: RideShareColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
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
                        size: 18,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      rating > 0 ? rating.toStringAsFixed(1) : '—',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: RideShareColors.titleText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            totalRides == 0 ? 'No trips yet' : '$totalRides trips',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: RideShareColors.onSurfaceVariant,
            ),
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
          label:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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
