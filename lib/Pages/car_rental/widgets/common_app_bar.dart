import 'package:flutter/material.dart';
import 'package:vero360_app/Pages/car_rental/utils/car_rental_design_system.dart';

/// Unified AppBar component for car rental module
/// Provides consistent styling across all pages
class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final Color? backgroundColor;
  final double elevation;
  final Color? foregroundColor;

  const CommonAppBar({
    Key? key,
    required this.title,
    this.showBackButton = true,
    this.onBackPressed,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = false,
    this.backgroundColor,
    this.elevation = 0,
    this.foregroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: CarRentalColors.textPrimary,
        ),
      ),
      centerTitle: centerTitle,
      elevation: elevation,
      backgroundColor: backgroundColor ?? CarRentalColors.card,
      foregroundColor: foregroundColor ?? CarRentalColors.textPrimary,
      leading: leading ??
          (showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
                )
              : null),
      actions: actions,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}

/// Simple header with title and subtitle
class SimpleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;

  const SimpleHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(
      horizontal: CarRentalSpacing.lg,
      vertical: CarRentalSpacing.md,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: CarRentalColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: CarRentalSpacing.xs),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CarRentalColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page header with colored background
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? backgroundColor;
  final Widget? backgroundWidget;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  const PageHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.backgroundColor,
    this.backgroundWidget,
    this.padding = const EdgeInsets.all(CarRentalSpacing.lg),
    this.borderRadius = const BorderRadius.only(
      bottomLeft: Radius.circular(CarRentalBorderRadius.lg),
      bottomRight: Radius.circular(CarRentalBorderRadius.lg),
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (backgroundWidget != null)
          SizedBox(
            width: double.infinity,
            child: backgroundWidget,
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: backgroundColor ?? CarRentalColors.primaryLight,
              borderRadius: borderRadius,
            ),
          ),
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: CarRentalColors.textInverse,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: CarRentalSpacing.xs),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: CarRentalColors.textInverse.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: CarRentalSpacing.md),
                    trailing!,
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
