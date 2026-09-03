import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Full-width Online / Offline control with a sliding thumb and live pulse.
class DriverOnlineToggle extends StatefulWidget {
  final bool isOnline;
  final VoidCallback onToggle;
  final bool busy;

  const DriverOnlineToggle({
    required this.isOnline,
    required this.onToggle,
    this.busy = false,
    super.key,
  });

  @override
  State<DriverOnlineToggle> createState() => _DriverOnlineToggleState();
}

class _DriverOnlineToggleState extends State<DriverOnlineToggle>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scale = Tween<double>(begin: 1, end: 0.97).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
    if (widget.isOnline) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(DriverOnlineToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && !oldWidget.isOnline) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isOnline && oldWidget.isOnline) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _press.dispose();
    super.dispose();
  }

  void _onSelect(bool online) {
    if (widget.busy || widget.isOnline == online) return;
    HapticFeedback.mediumImpact();
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.isOnline;
    return Semantics(
      button: true,
      toggled: online,
      enabled: !widget.busy,
      onTap: widget.busy ? null : widget.onToggle,
      label: online
          ? 'You are online. Double tap to go offline.'
          : 'You are offline. Double tap to go online.',
      child: Listener(
        onPointerDown:
            widget.busy ? null : (_) => _press.forward(),
        onPointerUp: (_) => _press.reverse(),
        onPointerCancel: (_) => _press.reverse(),
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulse, _scale]),
          builder: (context, _) {
            final glow = online ? 0.22 + (_pulse.value * 0.2) : 0.0;
            return Transform.scale(
              scale: _scale.value,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                height: 56,
                decoration: BoxDecoration(
                  color: online
                      ? const Color(0xFFFFF1E0)
                      : RideShareColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: online
                        ? RideShareColors.primary.withValues(alpha: 0.55)
                        : RideShareColors.outlineVariant,
                    width: 1.2,
                  ),
                  boxShadow: [
                    if (online)
                      BoxShadow(
                        color: RideShareColors.primary.withValues(alpha: glow),
                        blurRadius: 18 + (_pulse.value * 10),
                        spreadRadius: 0.5,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final thumbWidth = constraints.maxWidth / 2;
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutCubic,
                            left: online ? thumbWidth : 0,
                            top: 0,
                            bottom: 0,
                            width: thumbWidth,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: online
                                      ? const [
                                          RideShareColors.primary,
                                          RideShareColors.primaryDeep,
                                        ]
                                      : const [
                                          Color(0xFF5C5A59),
                                          Color(0xFF3D3C3C),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: (online
                                            ? RideShareColors.primaryDeep
                                            : Colors.black)
                                        .withValues(alpha: 0.22),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _AvailabilitySegment(
                                  label: 'Offline',
                                  icon: Icons.pause_rounded,
                                  selected: !online,
                                  busy: widget.busy && online,
                                  onTap: () => _onSelect(false),
                                ),
                              ),
                              Expanded(
                                child: _AvailabilitySegment(
                                  label: 'Online',
                                  icon: Icons.bolt_rounded,
                                  selected: online,
                                  busy: widget.busy && !online,
                                  pulse: online ? _pulse.value : 0,
                                  onTap: () => _onSelect(true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AvailabilitySegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool busy;
  final double pulse;
  final VoidCallback onTap;

  const _AvailabilitySegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.busy = false,
    this.pulse = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Colors.white
        : RideShareColors.onSurfaceVariant.withValues(alpha: 0.78);
    return ExcludeSemantics(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: selected ? 0.2 : 0,
              color: color,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  AnimatedScale(
                    scale: selected ? 1 : 0.92,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(
                      icon,
                      size: 20,
                      color: color.withValues(
                        alpha: selected ? 0.95 + (pulse * 0.05) : 0.7,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DriverEarningsSummaryCard extends StatelessWidget {
  final String todayAmountLabel;
  final int todayTrips;
  final bool loading;

  const DriverEarningsSummaryCard({
    required this.todayAmountLabel,
    required this.todayTrips,
    this.loading = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tripsLabel = loading
        ? 'Loading…'
        : todayTrips == 0
            ? 'No trips yet'
            : '$todayTrips trip${todayTrips == 1 ? '' : 's'}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            RideShareColors.primary,
            RideShareColors.primaryDeep,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: RideShareColors.primary.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TODAY'S EARNINGS",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                if (loading)
                  Container(
                    height: 26,
                    width: 112,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                else
                  Text(
                    todayAmountLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tripsLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withValues(alpha: 0.8),
            size: 22,
          ),
        ],
      ),
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
