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
            top: 0,
            height: MediaQuery.of(context).size.height * 0.22,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      RideShareColors.background.withValues(alpha: 0.8),
                      RideShareColors.background.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                      RideShareColors.primaryContainer.withValues(alpha: 0.1),
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
  final VoidCallback? onMenu;

  const RideGlassTopBar({
    required this.title,
    this.trailing,
    this.onMenu,
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: RideShareColors.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: RideShareColors.outlineVariant.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onMenu ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.menu),
                    color: RideShareColors.titleText,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: RideShareColors.primaryContainer,
                        letterSpacing: -0.3,
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

/// Frosted light status banner over the map (driver next-step).
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: RideShareColors.outlineVariant.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: RideShareColors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: RideShareColors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: RideShareColors.titleText,
                            height: 1.2,
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
                        color: RideShareColors.primaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Light bottom sheet used by both passenger and driver in-ride UIs.
class RideLightSheet extends StatelessWidget {
  final Widget child;
  final bool floating;
  final bool showHandle;
  final EdgeInsetsGeometry? contentPadding;

  const RideLightSheet({
    required this.child,
    this.floating = false,
    this.showHandle = true,
    this.contentPadding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final radius = floating
        ? BorderRadius.circular(24)
        : const BorderRadius.vertical(top: Radius.circular(32));

    final sheet = Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      decoration: BoxDecoration(
        color: RideShareColors.background,
        borderRadius: radius,
        border: Border.all(
          color: RideShareColors.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHandle && !floating) ...[
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: RideShareColors.titleText.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
          Flexible(
            child: SingleChildScrollView(
              padding: contentPadding ??
                  EdgeInsets.fromLTRB(16, floating ? 20 : 16, 16, 20),
              child: child,
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: floating
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: sheet,
            )
          : sheet,
    );
  }
}

/// Backward-compatible alias for callers still naming the navy sheet.
typedef RideNavySheet = RideLightSheet;

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
                  color: RideShareColors.titleText,
                  height: 1.25,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: RideShareColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: RideShareColors.primaryDeep,
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
                size: 18,
                color: RideShareColors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: RideShareColors.onSurfaceVariant,
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
                Container(color: RideShareColors.surfaceContainerHigh),
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: Container(
                    decoration: BoxDecoration(
                      color: RideShareColors.primary,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: RideShareColors.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: RideShareColors.onSurfaceVariant,
                ),
              ),
              Text(
                rightLabel ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: RideShareColors.onSurfaceVariant,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RideShareColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: RideShareColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: RideShareColors.primaryContainer.withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                            color: RideShareColors.primaryContainer,
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
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
                            fontSize: 12,
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
                    color: RideShareColors.titleText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: RideShareColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                if (meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta!,
                    style: const TextStyle(
                      color: RideShareColors.primaryDeep,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
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
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: RideShareColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(icon, color: RideShareColors.onSurfaceVariant, size: 20),
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
          top: BorderSide(
            color: RideShareColors.outlineVariant.withValues(alpha: 0.25),
          ),
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
                      color:
                          RideShareColors.outlineVariant.withValues(alpha: 0.25),
                    ),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: RideShareColors.primaryContainer),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: RideShareColors.titleText,
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
        color: RideShareColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: RideShareColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: RideShareColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: RideShareColors.titleText,
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
          elevation: 2,
          shadowColor: RideShareColors.primary.withValues(alpha: 0.4),
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
          foregroundColor: RideShareColors.titleText,
          backgroundColor: RideShareColors.surfaceContainerHigh,
          side: BorderSide(
            color: RideShareColors.outlineVariant.withValues(alpha: 0.3),
          ),
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

/// Two-column Safety + Share actions matching passenger mockup.
class RidePassengerActionGrid extends StatelessWidget {
  final VoidCallback? onSafety;
  final VoidCallback? onShare;

  const RidePassengerActionGrid({
    this.onSafety,
    this.onShare,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: onSafety,
              style: ElevatedButton.styleFrom(
                backgroundColor: RideShareColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: RideShareColors.primary.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.emergency_share, size: 20),
              label: const Text(
                'Safety/SOS',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: onShare,
              style: OutlinedButton.styleFrom(
                foregroundColor: RideShareColors.titleText,
                backgroundColor: RideShareColors.surfaceContainerHigh,
                side: BorderSide(
                  color: RideShareColors.outlineVariant.withValues(alpha: 0.3),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text(
                'Share Trip',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact passenger avatar card for driver destination row.
class RidePassengerMiniCard extends StatelessWidget {
  final String name;
  final double? rating;
  final String? avatarUrl;

  const RidePassengerMiniCard({
    required this.name,
    this.rating,
    this.avatarUrl,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RideShareColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: RideShareColors.outlineVariant.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RideShareColors.primaryContainer.withValues(alpha: 0.12),
              border: Border.all(color: RideShareColors.primary, width: 2),
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
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: RideShareColors.primaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 72,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RideShareColors.titleText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (rating != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 12, color: RideShareColors.primary),
                const SizedBox(width: 2),
                Text(
                  rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 11,
                    color: RideShareColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
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
          height: 64,
          decoration: BoxDecoration(
            color: _done
                ? RideShareColors.primary
                : RideShareColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: RideShareColors.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (_dx > 0 && !_done)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        colors: [
                          RideShareColors.primary.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              Center(
                child: Text(
                  _done ? 'Ride Completed' : widget.label.toUpperCase(),
                  style: TextStyle(
                    color: _done
                        ? Colors.white
                        : RideShareColors.titleText.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
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
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: RideShareColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                RideShareColors.primary.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _done ? Icons.check : Icons.chevron_right,
                        color: Colors.white,
                        size: 28,
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
          child: Icon(icon, color: RideShareColors.titleText),
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
