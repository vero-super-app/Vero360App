import 'package:flutter/material.dart';
import 'package:vero360_app/Pages/car_rental/utils/car_rental_design_system.dart';

/// Empty state widget - displays when no data is available
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;
  final double iconSize;

  const EmptyState({
    Key? key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
    this.iconSize = 64,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CarRentalSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: iconColor ?? CarRentalColors.grey300,
            ),
            const SizedBox(height: CarRentalSpacing.lg),
            Text(
              title,
              style: CarRentalDesignSystem.h3(context),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: CarRentalSpacing.sm),
              Text(
                subtitle!,
                style: CarRentalDesignSystem.bodyMedium(context),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: CarRentalSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state widget - displays error message
class ErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final VoidCallback? onRetry;
  final Color? backgroundColor;

  const ErrorState({
    Key? key,
    required this.title,
    this.message,
    this.icon = Icons.error_outline,
    this.onRetry,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? CarRentalColors.errorLight,
      padding: const EdgeInsets.all(CarRentalSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: CarRentalColors.error,
          ),
          const SizedBox(height: CarRentalSpacing.lg),
          Text(
            title,
            style: CarRentalDesignSystem.h3(context).copyWith(
              color: CarRentalColors.error,
            ),
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: CarRentalSpacing.sm),
            Text(
              message!,
              style: CarRentalDesignSystem.bodyMedium(context),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: CarRentalSpacing.lg),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: CarRentalDesignSystem.secondaryButtonStyle(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading state widget
class LoadingState extends StatelessWidget {
  final String? message;
  final Color? backgroundColor;

  const LoadingState({
    Key? key,
    this.message,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: CarRentalColors.primary,
            ),
            if (message != null) ...[
              const SizedBox(height: CarRentalSpacing.lg),
              Text(
                message!,
                style: CarRentalDesignSystem.bodyMedium(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// No connection state widget
class NoConnectionState extends StatelessWidget {
  final VoidCallback? onRetry;

  const NoConnectionState({
    Key? key,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off,
      title: 'No Internet Connection',
      subtitle: 'Please check your connection and try again',
      iconColor: CarRentalColors.warning,
      action: onRetry != null
          ? ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: CarRentalDesignSystem.primaryButtonStyle(),
            )
          : null,
    );
  }
}

/// Loading shimmer skeleton
class ShimmerLoadingCard extends StatelessWidget {
  final double height;
  final double borderRadius;

  const ShimmerLoadingCard({
    Key? key,
    this.height = 100,
    this.borderRadius = CarRentalBorderRadius.md,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: CarRentalColors.grey200,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// List of shimmer skeletons for loading state
class ShimmerLoadingList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const ShimmerLoadingList({
    Key? key,
    this.itemCount = 5,
    this.itemHeight = 100,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CarRentalSpacing.lg,
            vertical: CarRentalSpacing.sm,
          ),
          child: ShimmerLoadingCard(height: itemHeight),
        );
      },
    );
  }
}

/// Success message with snackbar
class SuccessSnackBar extends SnackBar {
  SuccessSnackBar({
    required String message,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) : super(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: CarRentalColors.success,
              ),
              const SizedBox(width: CarRentalSpacing.md),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          backgroundColor: CarRentalColors.successLight,
          duration: duration,
          action: action,
        );
}

/// Error message with snackbar
class ErrorSnackBar extends SnackBar {
  ErrorSnackBar({
    required String message,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) : super(
          content: Row(
            children: [
              const Icon(
                Icons.error,
                color: CarRentalColors.error,
              ),
              const SizedBox(width: CarRentalSpacing.md),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          backgroundColor: CarRentalColors.errorLight,
          duration: duration,
          action: action,
        );
}

/// Info message with snackbar
class InfoSnackBar extends SnackBar {
  InfoSnackBar({
    required String message,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) : super(
          content: Row(
            children: [
              const Icon(
                Icons.info,
                color: CarRentalColors.info,
              ),
              const SizedBox(width: CarRentalSpacing.md),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          backgroundColor: CarRentalColors.infoLight,
          duration: duration,
          action: action,
        );
}
