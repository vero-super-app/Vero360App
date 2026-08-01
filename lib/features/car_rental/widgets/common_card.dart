import 'package:flutter/material.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_design_system.dart';

/// Unified Card component with consistent styling
class CommonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final List<BoxShadow> shadows;
  final double borderRadius;
  final Border? border;
  final GestureTapCallback? onTap;
  final double? height;
  final double? width;
  final BoxConstraints? constraints;

  const CommonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CarRentalSpacing.lg),
    this.backgroundColor = CarRentalColors.card,
    this.shadows = CarRentalShadows.elevation1,
    this.borderRadius = CarRentalBorderRadius.md,
    this.border,
    this.onTap,
    this.height,
    this.width,
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: CarRentalColors.grey200, width: 1),
        boxShadow: shadows,
      ),
      height: height,
      width: width,
      constraints: constraints,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Card with image header and content
class ImageCard extends StatelessWidget {
  final String? imageUrl;
  final double imageHeight;
  final Widget content;
  final EdgeInsetsGeometry contentPadding;
  final GestureTapCallback? onTap;
  final Widget? imageOverlay;
  final BoxFit imageFit;

  const ImageCard({
    super.key,
    this.imageUrl,
    this.imageHeight = CarRentalSizes.imageCardHeight,
    required this.content,
    this.contentPadding = const EdgeInsets.all(CarRentalSpacing.lg),
    this.onTap,
    this.imageOverlay,
    this.imageFit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = CommonCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image section
          Stack(
            children: [
              if (imageUrl != null && imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(CarRentalBorderRadius.md),
                    topRight: Radius.circular(CarRentalBorderRadius.md),
                  ),
                  child: Image.network(
                    imageUrl!,
                    height: imageHeight,
                    width: double.infinity,
                    fit: imageFit,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildPlaceholder();
                    },
                  ),
                )
              else
                _buildPlaceholder(),
              if (imageOverlay != null) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(CarRentalBorderRadius.md),
                      topRight: Radius.circular(CarRentalBorderRadius.md),
                    ),
                    child: imageOverlay!,
                  ),
                ),
              ],
            ],
          ),
          // Content section
          Padding(
            padding: contentPadding,
            child: content,
          ),
        ],
      ),
    );

    return card;
  }

  Widget _buildPlaceholder() {
    return Container(
      height: imageHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: CarRentalColors.grey100,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(CarRentalBorderRadius.md),
          topRight: Radius.circular(CarRentalBorderRadius.md),
        ),
      ),
      child: const Icon(
        Icons.directions_car,
        size: 64,
        color: CarRentalColors.grey400,
      ),
    );
  }
}

/// Horizontal info card with icon and text
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final GestureTapCallback? onTap;
  final Widget? trailing;

  const InfoCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            color: iconColor ?? CarRentalColors.primary,
            size: CarRentalSizes.iconMd,
          ),
          const SizedBox(width: CarRentalSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: CarRentalDesignSystem.bodySmall(context),
                ),
                const SizedBox(height: CarRentalSpacing.xs),
                Text(
                  value,
                  style: CarRentalDesignSystem.subtitle1(context),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: CarRentalSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Section card with header and content
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget>? actions;
  final bool expandable;
  final bool initiallyExpanded;

  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    this.actions,
    this.expandable = false,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!expandable) {
      return CommonCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: CarRentalDesignSystem.subtitle1(context),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: CarRentalSpacing.xs),
                        Text(
                          subtitle!,
                          style: CarRentalDesignSystem.bodySmall(context),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions != null)
                  Row(
                    children: actions!,
                  ),
              ],
            ),
            const SizedBox(height: CarRentalSpacing.md),
            content,
          ],
        ),
      );
    }

    // Expandable version
    return CommonCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text(
          title,
          style: CarRentalDesignSystem.subtitle1(context),
        ),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        initiallyExpanded: initiallyExpanded,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CarRentalSpacing.lg,
              0,
              CarRentalSpacing.lg,
              CarRentalSpacing.lg,
            ),
            child: content,
          ),
        ],
      ),
    );
  }
}
