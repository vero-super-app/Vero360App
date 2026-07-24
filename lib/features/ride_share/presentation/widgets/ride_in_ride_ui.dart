import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Progress 0–1 for in-ride UI (shared passenger/driver).
double rideStatusProgress(String status) {
  switch (status) {
    case RideStatus.requested:
      return 0.15;
    case RideStatus.accepted:
      return 0.35;
    case RideStatus.driverArrived:
      return 0.55;
    case RideStatus.inProgress:
      return 0.78;
    case RideStatus.completed:
      return 1.0;
    default:
      return 0.2;
  }
}

String rideStatusBadge(String status) {
  switch (status) {
    case RideStatus.requested:
      return 'Searching';
    case RideStatus.accepted:
      return 'On the way';
    case RideStatus.driverArrived:
      return 'Arrived';
    case RideStatus.inProgress:
      return 'On trip';
    case RideStatus.completed:
      return 'Done';
    default:
      return 'Active';
  }
}

/// Full-bleed in-ride shell: map + optional top/header overlays + bottom sheet.
class RideInRideShell extends StatelessWidget {
  final Widget map;
  final Widget? topOverlay;
  final Widget? floatingActions;
  final Widget bottomSheet;

  const RideInRideShell({
    required this.map,
    required this.bottomSheet,
    this.topOverlay,
    this.floatingActions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: map),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * 0.18,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      RideShareColors.primaryContainer.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (topOverlay != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: topOverlay!,
            ),
          if (floatingActions != null) floatingActions!,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: bottomSheet,
          ),
        ],
      ),
    );
  }
}

/// Frosted top bar used on passenger in-ride.
class RideGlassTopBar extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const RideGlassTopBar({
    required this.title,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: RideShareColors.background.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: RideShareColors.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: RideShareColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_taxi,
                      color: RideShareColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: RideShareColors.titleText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact navy status chip over the map (driver next-step banner).
class RideNavBanner extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? trailing;
  final IconData icon;

  const RideNavBanner({
    required this.eyebrow,
    required this.title,
    this.trailing,
    this.icon = Icons.navigation,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RideShareColors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: RideShareColors.primaryContainer.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Navy bottom sheet used by both passenger and driver in-ride UIs.
class RideNavySheet extends StatelessWidget {
  final Widget child;

  const RideNavySheet({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.58,
        ),
        decoration: BoxDecoration(
          color: RideShareColors.primaryContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 32,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RideStatusHeadline extends StatelessWidget {
  final String title;
  final String badge;
  final String? subtitle;
  final IconData? subtitleIcon;

  const RideStatusHeadline({
    required this.title,
    required this.badge,
    this.subtitle,
    this.subtitleIcon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: RideShareColors.primarySoft,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                subtitleIcon ?? Icons.location_on,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class RideTripProgressBar extends StatelessWidget {
  final double progress;
  final String? leftLabel;
  final String? rightLabel;

  const RideTripProgressBar({
    required this.progress,
    this.leftLabel,
    this.rightLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: Colors.white.withValues(alpha: 0.12)),
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: Container(color: RideShareColors.primary),
                ),
              ],
            ),
          ),
        ),
        if (leftLabel != null || rightLabel != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                leftLabel ?? '',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
              Text(
                rightLabel ?? '',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class RidePersonCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? meta;
  final double? rating;
  final String? avatarUrl;
  final String? initials;
  final List<Widget>? actions;

  const RidePersonCard({
    required this.name,
    this.subtitle,
    this.meta,
    this.rating,
    this.avatarUrl,
    this.initials,
    this.actions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: RideShareColors.primary.withValues(alpha: 0.25),
                  image: avatarUrl != null && avatarUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: avatarUrl == null || avatarUrl!.isEmpty
                    ? Center(
                        child: Text(
                          (initials ?? name).isNotEmpty
                              ? (initials ?? name)[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : null,
              ),
              if (rating != null)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: RideShareColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 12, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta!,
                    style: const TextStyle(
                      color: RideShareColors.primarySoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

class RideCircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const RideCircleIconButton({
    required this.icon,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class RideQuickActionsRow extends StatelessWidget {
  final VoidCallback? onMessage;
  final VoidCallback? onCall;
  final VoidCallback? onSafety;

  const RideQuickActionsRow({
    this.onMessage,
    this.onCall,
    this.onSafety,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          _Action(
            icon: Icons.chat_bubble_outline,
            label: 'Message',
            onTap: onMessage,
            showDivider: true,
          ),
          _Action(
            icon: Icons.shield_outlined,
            label: 'Safety',
            onTap: onSafety,
            showDivider: true,
          ),
          _Action(
            icon: Icons.call_outlined,
            label: 'Call',
            onTap: onCall,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool showDivider;

  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RideMetricRow extends StatelessWidget {
  final String distanceLabel;
  final String fareLabel;

  const RideMetricRow({
    required this.distanceLabel,
    required this.fareLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricChip(label: 'Distance', value: distanceLabel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricChip(label: 'Fare', value: fareLabel),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class RidePrimaryCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const RidePrimaryCta({
    required this.label,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: RideShareColors.primary,
          disabledBackgroundColor:
              RideShareColors.primary.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}

class RideSecondaryCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const RideSecondaryCta({
    required this.label,
    required this.icon,
    this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Swipe-to-complete control for driver in-progress state.
class RideSwipeToComplete extends StatefulWidget {
  final String label;
  final VoidCallback onCompleted;
  final bool enabled;

  const RideSwipeToComplete({
    required this.label,
    required this.onCompleted,
    this.enabled = true,
    super.key,
  });

  @override
  State<RideSwipeToComplete> createState() => _RideSwipeToCompleteState();
}

class _RideSwipeToCompleteState extends State<RideSwipeToComplete> {
  double _dx = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDx = (constraints.maxWidth - 60).clamp(0.0, 400.0);
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: _done
                ? RideShareColors.primary
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Text(
                  _done ? 'Completed' : widget.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: _done ? 1 : 0.7),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontSize: 12,
                  ),
                ),
              ),
              if (!_done)
                Positioned(
                  left: 4 + _dx,
                  child: GestureDetector(
                    onHorizontalDragUpdate: widget.enabled
                        ? (d) {
                            setState(() {
                              _dx = (_dx + d.delta.dx).clamp(0.0, maxDx);
                            });
                            if (_dx >= maxDx * 0.92) {
                              setState(() {
                                _dx = maxDx;
                                _done = true;
                              });
                              widget.onCompleted();
                            }
                          }
                        : null,
                    onHorizontalDragEnd: widget.enabled
                        ? (_) {
                            if (!_done) setState(() => _dx = 0);
                          }
                        : null,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: RideShareColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _done ? Icons.check : Icons.chevron_right,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class RideMapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const RideMapFab({required this.icon, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: RideShareColors.primaryContainer),
        ),
      ),
    );
  }
}

void showRideSafetySheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Safety tools',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your trip is being tracked. If you feel unsafe, end the ride or contact support.',
              style: TextStyle(color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sos, color: RideShareColors.primary),
              title: const Text('Emergency contacts'),
              subtitle: const Text('Call local emergency services if needed'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.share_location,
                  color: RideShareColors.primaryContainer),
              title: const Text('Share trip status'),
              subtitle: const Text('Let someone know you are on a Vero Ride'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}
