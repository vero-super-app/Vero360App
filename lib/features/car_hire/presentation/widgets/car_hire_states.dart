import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

/// Compact inline error used under forms and action cards.
class CarHireInlineError extends StatelessWidget {
  const CarHireInlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: CarHirePalette.errorSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: CarHirePalette.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              UserFacingError.sanitize(message),
              style: const TextStyle(
                color: CarHirePalette.error,
                fontSize: 11.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                foregroundColor: CarHirePalette.error,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(retryLabel),
            ),
        ],
      ),
    );
  }
}

/// A quiet informational strip for the journey-wide guarantees.
class CarHireInfoBanner extends StatelessWidget {
  const CarHireInfoBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = CarHireInfoTone.neutral,
  });

  final IconData icon;
  final String title;
  final String message;
  final CarHireInfoTone tone;

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final Color foreground;
    switch (tone) {
      case CarHireInfoTone.neutral:
        background = CarHirePalette.surface;
        foreground = CarHirePalette.onSurface;
        break;
      case CarHireInfoTone.accent:
        background = CarHirePalette.accentPale;
        foreground = CarHirePalette.onAccentSoft;
        break;
      case CarHireInfoTone.success:
        background = CarHirePalette.successSoft;
        foreground = CarHirePalette.success;
        break;
      case CarHireInfoTone.warning:
        background = CarHirePalette.warningSoft;
        foreground = CarHirePalette.warning;
        break;
      case CarHireInfoTone.error:
        background = CarHirePalette.errorSoft;
        foreground = CarHirePalette.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tone == CarHireInfoTone.neutral
              ? CarHirePalette.hairline
              : foreground.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tone == CarHireInfoTone.neutral
                        ? CarHirePalette.onSurface
                        : foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    color: tone == CarHireInfoTone.neutral
                        ? CarHirePalette.onSurfaceVariant
                        : foreground.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    height: 1.5,
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

enum CarHireInfoTone { neutral, accent, success, warning, error }

class CarHireLoadingState extends StatelessWidget {
  const CarHireLoadingState({
    super.key,
    this.message = 'Loading cars…',
    this.padding = const EdgeInsets.all(32),
  });

  final String message;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: CarHirePalette.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: CarHireType.bodySmall.copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class CarHireEmptyState extends StatelessWidget {
  const CarHireEmptyState({
    super.key,
    this.icon = Icons.directions_car_outlined,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(32),
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CarHirePalette.surfaceLow,
                shape: BoxShape.circle,
                border: Border.all(color: CarHirePalette.hairline),
              ),
              child: Icon(icon, size: 32, color: CarHirePalette.onSurface),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: CarHireType.title,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: CarHireType.bodySmall.copyWith(height: 1.55),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: FilledButton(
                  onPressed: onAction,
                  style: carHirePrimaryButton(),
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CarHireErrorState extends StatelessWidget {
  const CarHireErrorState({
    super.key,
    this.error,
    this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.padding = const EdgeInsets.all(32),
  });

  final Object? error;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final EdgeInsets padding;

  CarHireApiException? get _apiError =>
      error is CarHireApiException ? error as CarHireApiException : null;

  String get _resolvedMessage {
    final explicit = message?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final api = _apiError;
    if (api != null) return api.message;
    if (error != null) {
      return UserFacingError.from(
        error,
        fallback: 'We could not load this right now. Please try again.',
      );
    }
    return 'We could not load this right now. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final requiresLogin = _apiError?.requiresLogin ?? false;

    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CarHirePalette.errorSoft,
                shape: BoxShape.circle,
                border: Border.all(
                  color: CarHirePalette.error.withValues(alpha: 0.18),
                ),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: CarHirePalette.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: CarHireType.title,
            ),
            const SizedBox(height: 6),
            Text(
              _resolvedMessage,
              textAlign: TextAlign.center,
              style: CarHireType.bodySmall.copyWith(height: 1.55),
            ),
            if (requiresLogin) ...[
              const SizedBox(height: 10),
              Text(
                'You can keep browsing vehicles without signing in.',
                textAlign: TextAlign.center,
                style: CarHireType.labelSmall,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel),
                  style: carHirePrimaryButton(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
