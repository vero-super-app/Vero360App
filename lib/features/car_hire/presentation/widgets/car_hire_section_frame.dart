import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';

/// A titled block on a car-hire page. Every remote section renders inside one
/// of these so a failure or a skeleton stays inside its own boundaries.
class CarHireSectionFrame extends StatelessWidget {
  const CarHireSectionFrame({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.headerPadding = const EdgeInsets.fromLTRB(16, 16, 16, 10),
  });

  final String? title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context) {
    final heading = title?.trim() ?? '';
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading.isNotEmpty)
            CarHireSectionHeader(
              title: heading,
              subtitle: subtitle,
              action: action,
              padding: headerPadding,
            ),
          child,
        ],
      ),
    );
  }
}

/// Quiet inline failure for one section. The rest of the page keeps working.
class CarHireSectionErrorStrip extends StatelessWidget {
  const CarHireSectionErrorStrip({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon = Icons.cloud_off_rounded,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 12),
  });

  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final heading = title?.trim() ?? '';
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: CarHirePalette.warningSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: CarHirePalette.warning.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: CarHirePalette.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (heading.isNotEmpty) ...[
                    Text(
                      heading,
                      style: const TextStyle(
                        color: CarHirePalette.warning,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    style: const TextStyle(
                      color: CarHirePalette.onSurfaceVariant,
                      fontSize: 11.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  foregroundColor: CarHirePalette.warning,
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(retryLabel),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown above last-good content when a refresh failed.
class CarHireSectionStaleStrip extends StatelessWidget {
  const CarHireSectionStaleStrip({
    super.key,
    this.message = 'Showing earlier results.',
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 10),
  });

  final String message;
  final VoidCallback? onRefresh;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 7, 6, 7),
        decoration: BoxDecoration(
          color: CarHirePalette.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CarHirePalette.hairline),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 15,
              color: CarHirePalette.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: CarHireType.labelSmall.copyWith(fontSize: 11),
              ),
            ),
            if (onRefresh != null)
              TextButton(
                onPressed: onRefresh,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  foregroundColor: CarHirePalette.accent,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Refresh'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Thin "still working" hint above content that is already on screen.
class CarHireSectionUpdatingStrip extends StatelessWidget {
  const CarHireSectionUpdatingStrip({
    super.key,
    this.message = 'Updating…',
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 10),
  });

  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: CarHirePalette.accent,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            message,
            style: CarHireType.labelSmall.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
