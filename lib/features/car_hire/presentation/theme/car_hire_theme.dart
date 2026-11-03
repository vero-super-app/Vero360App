import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Vero360 car-hire design tokens.
///
/// The palette mirrors the reference "UrbanMove" system: near-black navy for
/// brand depth, a single warm orange for action, warm off-white surfaces and
/// low-contrast hairlines. Keep every car-hire screen on these tokens so the
/// journey feels like one product.
class CarHirePalette {
  CarHirePalette._();

  // Brand
  static const primary = Color(0xFF000613);
  static const primaryContainer = Color(0xFF001F3F);
  static const onPrimaryContainer = Color(0xFF6F88AD);

  /// The only action colour. Use it for a primary CTA or a live highlight.
  static const accent = Color(0xFFFF851B);
  static const accentPressed = Color(0xFFE5760F);
  static const accentSoft = Color(0xFFFFDCC7);
  static const accentPale = Color(0xFFFFF3E8);
  static const onAccent = Color(0xFFFFFFFF);
  static const onAccentSoft = Color(0xFF612D00);

  // Surfaces
  static const background = Color(0xFFFCF9F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF6F3F2);
  static const surfaceContainer = Color(0xFFF0EDED);
  static const surfaceHigh = Color(0xFFEAE7E7);

  // Content
  static const onSurface = Color(0xFF1C1B1B);
  static const onSurfaceVariant = Color(0xFF43474E);
  static const muted = Color(0xFF74777F);
  static const outlineVariant = Color(0xFFC4C6CF);
  static const hairline = Color(0xFFE5E2E1);

  // Feedback
  static const success = Color(0xFF1E7A5A);
  static const successSoft = Color(0xFFE4F3EC);
  static const warning = Color(0xFFB26A00);
  static const warningSoft = Color(0xFFFFF1DC);
  static const error = Color(0xFFBA1A1A);
  static const errorSoft = Color(0xFFFFDAD6);
}

/// Typography for the car-hire journey.
///
/// The reference designs use Manrope for headlines and Inter for body copy.
/// Those families are not bundled with the app, so the platform sans is used
/// with matching sizes, weights, letter-spacing and line-heights to preserve
/// the same visual hierarchy without adding a network font dependency.
class CarHireType {
  CarHireType._();

  static const display = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 32,
    height: 1.16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
  );

  static const headline = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 24,
    height: 1.22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static const titleLarge = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static const title = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const subtitle = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(
    color: CarHirePalette.onSurfaceVariant,
    fontSize: 13.5,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const bodySmall = TextStyle(
    color: CarHirePalette.onSurfaceVariant,
    fontSize: 12,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const label = TextStyle(
    color: CarHirePalette.onSurfaceVariant,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static const labelSmall = TextStyle(
    color: CarHirePalette.muted,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
  );

  /// Small uppercase eyebrow used above section groups.
  static const overline = TextStyle(
    color: CarHirePalette.muted,
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
  );

  static const price = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 24,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  static const priceSmall = TextStyle(
    color: CarHirePalette.onSurface,
    fontSize: 16,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );
}

/// Shared geometry and motion so cards, sheets and buttons line up.
class CarHireShape {
  CarHireShape._();

  static const double pagePadding = 16;
  static const double cardRadius = 20;
  static const double tileRadius = 14;
  static const double pillRadius = 999;
  static const double buttonHeight = 52;

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 240);

  static List<BoxShadow> get cardShadow => <BoxShadow>[
    BoxShadow(
      color: CarHirePalette.primary.withValues(alpha: 0.05),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get floatingShadow => <BoxShadow>[
    BoxShadow(
      color: CarHirePalette.primary.withValues(alpha: 0.08),
      blurRadius: 30,
      offset: const Offset(0, 12),
    ),
  ];
}

/// The canonical white card used across the provider and renter screens.
class CarHireSurface extends StatelessWidget {
  const CarHireSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.radius = CarHireShape.cardRadius,
    this.color = CarHirePalette.surface,
    this.borderColor = CarHirePalette.hairline,
    this.onTap,
    this.shadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: shadow ? CarHireShape.cardShadow : null,
      ),
      child: child,
    );

    if (onTap == null) {
      return Padding(padding: margin, child: content);
    }

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      ),
    );
  }
}

/// Section heading with an optional trailing action, used on every page.
class CarHireSectionHeader extends StatelessWidget {
  const CarHireSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CarHireType.title),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: CarHireType.bodySmall),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

/// Compact status / feature pill. Colour is always paired with a label.
class CarHirePill extends StatelessWidget {
  const CarHirePill({
    super.key,
    required this.label,
    this.icon,
    this.background = CarHirePalette.surfaceLow,
    this.foreground = CarHirePalette.onSurface,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.fontSize = 11,
    this.fontWeight = FontWeight.w700,
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: fontSize,
              fontWeight: fontWeight,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ratings are shown as a single quiet pill instead of colour-only stars.
class CarHireRatingPill extends StatelessWidget {
  const CarHireRatingPill({super.key, required this.rating, this.reviews = 0});

  final double rating;
  final int reviews;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            size: 14,
            color: CarHirePalette.accent,
          ),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(2),
            style: const TextStyle(
              color: CarHirePalette.onSurface,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (reviews > 0) ...[
            const SizedBox(width: 3),
            Text(
              '($reviews)',
              style: const TextStyle(
                color: CarHirePalette.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The single primary action style for the journey: orange, tall, full pill.
ButtonStyle carHirePrimaryButton({Color background = CarHirePalette.accent}) {
  return FilledButton.styleFrom(
    backgroundColor: background,
    foregroundColor: CarHirePalette.onAccent,
    disabledBackgroundColor: background.withValues(alpha: 0.38),
    disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
    minimumSize: const Size.fromHeight(CarHireShape.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 22),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
    ),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.1,
    ),
  );
}

ButtonStyle carHireGhostButton({Color? foreground}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foreground ?? CarHirePalette.onSurface,
    side: const BorderSide(color: CarHirePalette.outlineVariant),
    minimumSize: const Size.fromHeight(46),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
    ),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );
}

/// Consistent input styling: warm fill, hairline border, orange focus.
InputDecoration carHireInputDecoration({
  String? label,
  String? hint,
  String? helper,
  Widget? prefixIcon,
  bool alignLabelWithHint = false,
  int? helperMaxLines,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: helperMaxLines,
    prefixIcon: prefixIcon,
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: CarHirePalette.surfaceLow,
    isDense: true,
    labelStyle: const TextStyle(
      color: CarHirePalette.muted,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: const TextStyle(color: CarHirePalette.muted, fontSize: 13),
    helperStyle: const TextStyle(
      color: CarHirePalette.muted,
      fontSize: 10.5,
      height: 1.4,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(CarHirePalette.hairline),
    enabledBorder: border(CarHirePalette.hairline),
    focusedBorder: border(CarHirePalette.accent, 1.5),
    errorBorder: border(CarHirePalette.error),
    focusedErrorBorder: border(CarHirePalette.error, 1.5),
  );
}

/// The app header shared by every car-hire screen.
///
/// One consistent branded bar: a compact orange-on-navy car mark, a bold
/// title with an optional context line, and quiet pill actions. Keeping every
/// page on this header makes the journey feel like a single product instead of
/// a set of unrelated screens.
class CarHireAppHeader extends StatelessWidget implements PreferredSizeWidget {
  const CarHireAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.showBrandMark = true,
  });

  final String title;

  /// Optional mark rendered just after the title, e.g. a verified tick.
  final Widget? titleTrailing;
  final String? subtitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool showBrandMark;

  double get _toolbarHeight =>
      subtitle != null && subtitle!.trim().isNotEmpty ? 64 : 56;

  @override
  Size get preferredSize =>
      Size.fromHeight(_toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    // Only reserve a back-button lane when there is actually a route to pop,
    // so a labelled action still has room for the title on small phones.
    final showsBack =
        automaticallyImplyLeading && (ModalRoute.of(context)?.canPop ?? false);
    return AppBar(
      backgroundColor: CarHirePalette.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: CarHirePalette.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: _toolbarHeight,
      automaticallyImplyLeading: false,
      leadingWidth: showsBack ? 52 : 12,
      leading: showsBack ? const CarHireBackButton() : null,
      titleSpacing: showsBack ? 0 : 4,
      centerTitle: false,
      title: Row(
        children: [
          if (showBrandMark) ...[
            const _CarHireBrandMark(),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CarHirePalette.onSurface,
                          fontSize: 17.5,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    if (titleTrailing != null) ...[
                      const SizedBox(width: 5),
                      titleTrailing!,
                    ],
                  ],
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CarHirePalette.muted,
                      fontSize: 10.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: actions == null
          ? null
          : [...actions!, const SizedBox(width: 14)],
      bottom: bottom,
    );
  }
}

class _CarHireBrandMark extends StatelessWidget {
  const _CarHireBrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CarHirePalette.primaryContainer, CarHirePalette.primary],
        ),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: CarHirePalette.primary.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_car_filled_rounded,
        size: 19,
        color: CarHirePalette.accent,
      ),
    );
  }
}

/// App bar shared by the journey. Modern, branded and consistent everywhere.
PreferredSizeWidget carHireAppBar({
  required String title,
  String? subtitle,
  Widget? titleTrailing,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
  bool showBrandMark = true,
}) {
  return CarHireAppHeader(
    title: title,
    subtitle: subtitle,
    titleTrailing: titleTrailing,
    actions: actions,
    bottom: bottom,
    automaticallyImplyLeading: automaticallyImplyLeading,
    showBrandMark: showBrandMark,
  );
}

/// iOS-style back chevron. Renders nothing when there is no route to return
/// to.
class CarHireBackButton extends StatelessWidget {
  const CarHireBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || !route.canPop) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Back',
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(
        CupertinoIcons.back,
        size: 27,
        color: CarHirePalette.accent,
      ),
    );
  }
}

/// Circular icon button with a soft surface, used in app bars and cards.
class CarHireIconButton extends StatelessWidget {
  const CarHireIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background = CarHirePalette.surface,
    this.foreground = CarHirePalette.onSurface,
    this.size = 40,
    this.iconSize = 19,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color background;
  final Color foreground;
  final double size;
  final double iconSize;

  /// Optional replacement for the icon, e.g. a small progress indicator.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: CircleBorder(
        side: BorderSide(
          color: CarHirePalette.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: child ?? Icon(icon, size: iconSize, color: foreground),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Pill-shaped action with an icon and a short label, for app bars where an
/// icon alone would be ambiguous (e.g. "Add car").
class CarHirePillButton extends StatelessWidget {
  const CarHirePillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.background = CarHirePalette.accent,
    this.foreground = Colors.white,
    this.height = 34,
    this.iconSize = 16,
    this.fontSize = 11.5,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final double height;
  final double iconSize;
  final double fontSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: foreground),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontSize: fontSize,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

// ---------------------------------------------------------------------------
// Shared form building blocks
//
// The add-vehicle wizard and the listing-rules editor use the same pieces, so
// rules read exactly like the fields above them instead of a second design.
// ---------------------------------------------------------------------------

/// Small label that sits above a field, matching the wizard's field labels.
class CarHireFieldLabel extends StatelessWidget {
  const CarHireFieldLabel(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.only(left: 2, bottom: 5),
    this.trailing,
  });

  final String label;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(label, style: CarHireType.label)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Selectable pill used for one-of-many and many-of-many choices.
class CarHireChoiceChip extends StatelessWidget {
  const CarHireChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? CarHirePalette.muted
        : selected
        ? Colors.white
        : CarHirePalette.onSurfaceVariant;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: CarHireShape.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected && enabled
              ? CarHirePalette.primary
              : CarHirePalette.surfaceLow,
          borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
          border: Border.all(
            color: selected && enabled
                ? CarHirePalette.primary
                : CarHirePalette.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet yes/no row with a rounded check box, used for listing rules.
class CarHireCheckRow extends StatelessWidget {
  const CarHireCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onChanged != null;
    final foreground = active ? CarHirePalette.onSurface : CarHirePalette.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: active ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value && active
                    ? CarHirePalette.accentSoft
                    : CarHirePalette.hairline,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: CarHireShape.fast,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: value && active
                        ? CarHirePalette.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: value && active
                          ? CarHirePalette.accent
                          : active
                          ? CarHirePalette.outlineVariant
                          : CarHirePalette.hairline,
                      width: 1.4,
                    ),
                  ),
                  child: value && active
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: value ? FontWeight.w700 : FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          style: CarHireType.bodySmall.copyWith(
                            fontSize: 10.5,
                            color: CarHirePalette.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
