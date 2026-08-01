import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared UI tokens for ride-share screens — uses Vero brand colors.
abstract final class RideShareColors {
  static const primary = Color(0xFFFF8A00);
  static const primaryDeep = Color(0xFFD94F00);
  static const background = Color(0xFFFFFBF6);
  static const surface = Colors.white;
  static const titleText = Color(0xFF111111);
  static const bodyText = Color(0xFF666666);
  static const outline = Color(0xFFE0E0E0);
  static const outlineVariant = Color(0xFFC4C6CF);
  static const surfaceContainer = Color(0xFFF0EDED);
  static const surfaceContainerLow = Color(0xFFF6F3F2);
  static const onSurfaceVariant = Color(0xFF43474E);
  static const primaryContainer = Color(0xFF16284C);
  static const primarySoft = Color(0xFFFFE8CC);
}

/// Frosted-glass panel used on the home bottom sheet.
class RideShareGlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;

  const RideShareGlassPanel({
    required this.child,
    this.borderRadius,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ??
          const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RideShareColors.background.withValues(alpha: 0.92),
            borderRadius: borderRadius ??
                const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: RideShareColors.primaryContainer.withValues(alpha: 0.12),
                blurRadius: 40,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
