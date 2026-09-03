import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Flat slide-to-go-live control. Drag or tap.
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
  static const _height = 52.0;
  static const _pad = 4.0;
  static const _thumb = 44.0;

  late final AnimationController _pulse;
  late final AnimationController _shimmer;
  late final AnimationController _snap;

  double _extent = 0;
  bool _dragging = false;
  bool _midHaptic = false;
  double _dragAccum = 0;
  VoidCallback? _snapTick;

  @override
  void initState() {
    super.initState();
    _extent = widget.isOnline ? 1 : 0;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    if (widget.isOnline) {
      _pulse.repeat(reverse: true);
    } else {
      _shimmer.repeat();
    }
  }

  @override
  void didUpdateWidget(DriverOnlineToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && !oldWidget.isOnline) {
      _shimmer.stop();
      _pulse.repeat(reverse: true);
      if (!_dragging) _animateTo(1);
    } else if (!widget.isOnline && oldWidget.isOnline) {
      _pulse
        ..stop()
        ..value = 0;
      _shimmer.repeat();
      if (!_dragging) _animateTo(0);
    } else if (!widget.busy && oldWidget.busy && !_dragging) {
      _animateTo(widget.isOnline ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _clearSnap();
    _pulse.dispose();
    _shimmer.dispose();
    _snap.dispose();
    super.dispose();
  }

  void _clearSnap() {
    if (_snapTick != null) {
      _snap.removeListener(_snapTick!);
      _snapTick = null;
    }
  }

  void _animateTo(double target) {
    _clearSnap();
    final start = _extent.clamp(0.0, 1.0);
    if ((start - target).abs() < 0.001) {
      setState(() => _extent = target);
      return;
    }
    final anim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic),
    );
    _snapTick = () {
      if (mounted) setState(() => _extent = anim.value);
    };
    _snap
      ..addListener(_snapTick!)
      ..forward(from: 0);
  }

  void _commit(bool online) {
    if (widget.busy || widget.isOnline == online) {
      _animateTo(widget.isOnline ? 1 : 0);
      return;
    }
    HapticFeedback.mediumImpact();
    _animateTo(online ? 1 : 0);
    widget.onToggle();
  }

  void _onDragStart(DragStartDetails _) {
    if (widget.busy) return;
    _clearSnap();
    _dragging = true;
    _dragAccum = 0;
    _midHaptic = _extent > 0.5;
  }

  void _onDragUpdate(DragUpdateDetails details, double travel) {
    if (widget.busy || travel <= 0) return;
    _dragAccum += details.delta.dx.abs();
    final next = (_extent + details.delta.dx / travel).clamp(0.0, 1.0);
    final crossed = (next > 0.5) != _midHaptic;
    if (crossed) {
      _midHaptic = next > 0.5;
      HapticFeedback.selectionClick();
    }
    setState(() => _extent = next);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final fling = details.velocity.pixelsPerSecond.dx;
    final tapped = _dragAccum < 10 && fling.abs() < 80;
    if (tapped) {
      _commit(!widget.isOnline);
      return;
    }
    final goOnline = fling.abs() > 420 ? fling > 0 : _extent >= 0.5;
    _commit(goOnline);
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
          ? 'You are live. Double tap to go offline.'
          : 'You are offline. Slide or double tap to go live.',
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _shimmer]),
        builder: (context, _) {
          final heat = _extent.clamp(0.0, 1.0);
          final track = Color.lerp(
            RideShareColors.surfaceContainerHigh,
            RideShareColors.primary,
            heat,
          )!;
          final label = Color.lerp(
            RideShareColors.onSurfaceVariant,
            Colors.white,
            heat,
          )!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final travel =
                  (constraints.maxWidth - _pad * 2 - _thumb).clamp(0.0, 400.0);
              final thumbLeft = _pad + heat * travel;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.busy ? null : () => _commit(!online),
                onHorizontalDragStart: widget.busy ? null : _onDragStart,
                onHorizontalDragUpdate:
                    widget.busy ? null : (d) => _onDragUpdate(d, travel),
                onHorizontalDragEnd: widget.busy ? null : _onDragEnd,
                onHorizontalDragCancel: () {
                  _dragging = false;
                  _animateTo(widget.isOnline ? 1 : 0);
                },
                child: Container(
                  height: _height,
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: _thumb + 8,
                        right: 16,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: (1 - heat * 1.4).clamp(0.0, 1.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Go live',
                                  style: TextStyle(
                                    color: label,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Opacity(
                                  opacity: 0.45 +
                                      0.45 *
                                          (0.5 -
                                                  (_shimmer.value - 0.5).abs())
                                              .clamp(0.0, 1.0) *
                                          2,
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 22,
                                    color: label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: _thumb + 8,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: ((heat - 0.38) / 0.5).clamp(0.0, 1.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.55 + _pulse.value * 0.45,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Live',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: thumbLeft,
                        top: _pad,
                        child: _FlatThumb(
                          heat: heat,
                          busy: widget.busy,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FlatThumb extends StatelessWidget {
  final double heat;
  final bool busy;

  const _FlatThumb({
    required this.heat,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final hot = heat > 0.5;
    final iconColor = Color.lerp(
      RideShareColors.onSurfaceVariant,
      RideShareColors.primaryDeep,
      heat,
    )!;
    return Container(
      width: _DriverOnlineToggleState._thumb,
      height: _DriverOnlineToggleState._thumb,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: iconColor,
                ),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  hot ? Icons.bolt_rounded : Icons.power_settings_new_rounded,
                  key: ValueKey(hot),
                  size: 22,
                  color: iconColor,
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
