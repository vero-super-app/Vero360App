import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

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
                color: CarRentalColors.brandOrange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CarRentalColors.body,
                fontSize: 13.5,
              ),
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
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: CarRentalColors.brandOrangePale,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: CarRentalColors.brandOrange),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CarRentalColors.title,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CarRentalColors.body,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CarRentalColors.brandOrange,
                  side: const BorderSide(color: CarRentalColors.brandOrange),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: Text(actionLabel!),
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
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: CarRentalColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 30,
                color: CarRentalColors.error,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CarRentalColors.title,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _resolvedMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CarRentalColors.body,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (requiresLogin) ...[
              const SizedBox(height: 10),
              const Text(
                'You can keep browsing vehicles without signing in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CarRentalColors.grey,
                  fontSize: 12,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: CarRentalColors.brandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
