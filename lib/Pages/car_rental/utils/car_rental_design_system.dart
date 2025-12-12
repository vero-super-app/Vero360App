import 'package:flutter/material.dart';

// Export all design system classes for easy access
export 'car_rental_design_system.dart';

/// ============================================================================
/// COLOR CONSTANTS
/// ============================================================================

class CarRentalColors {
  // Primary Orange (Brand Color)
  static const Color primary = Color(0xFFFF8A00);
  static const Color primaryDark = Color(0xFFE67E00);
  static const Color primaryLight = Color(0xFFFFAA33);
  static const Color primarySoft = Color(0xFFFFEAD1);
  static const Color primaryPale = Color(0xFFFFF4E6);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color successDark = Color(0xFF388E3C);

  static const Color warning = Color(0xFFFFC107);
  static const Color warningLight = Color(0xFFFFF9C4);
  static const Color warningDark = Color(0xFFFFB300);

  static const Color error = Color(0xFFF44336);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color errorDark = Color(0xFFD32F2F);

  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFE3F2FD);
  static const Color infoDark = Color(0xFF1976D2);

  // Text Colors
  static const Color textPrimary = Color(0xFF101010);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textTertiary = Color(0xFF9E9E9E);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Background Colors
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFAFAFA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFEEEEEE);

  // Chip Colors
  static const Color chip = Color(0xFFF9F5EF);
  static const Color chipDark = Color(0xFFE8E0D5);

  // Neutral Grays
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);
  static const Color grey900 = Color(0xFF212121);
}

/// ============================================================================
/// SPACING CONSTANTS
/// ============================================================================

class CarRentalSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;
}

/// ============================================================================
/// BORDER RADIUS CONSTANTS
/// ============================================================================

class CarRentalBorderRadius {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double full = 999.0;
}

/// ============================================================================
/// SIZE CONSTANTS
/// ============================================================================

class CarRentalSizes {
  static const double buttonHeightLarge = 48.0;
  static const double buttonHeightMedium = 40.0;
  static const double buttonHeightSmall = 32.0;

  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;
  static const double iconXxl = 64.0;

  static const double avatarSm = 32.0;
  static const double avatarMd = 40.0;
  static const double avatarLg = 56.0;
  static const double avatarXl = 64.0;

  static const double imageCardHeight = 200.0;
  static const double imageCardHeightSmall = 160.0;
  static const double imageCardHeightLarge = 240.0;
}

/// ============================================================================
/// SHADOW CONSTANTS
/// ============================================================================

class CarRentalShadows {
  static const List<BoxShadow> elevation0 = [];
  static const List<BoxShadow> elevation1 = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 2,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> elevation2 = [
    BoxShadow(
      color: Color(0x24000000),
      blurRadius: 4,
      offset: Offset(0, 4),
    ),
  ];
  static const List<BoxShadow> elevation3 = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 8,
      offset: Offset(0, 8),
    ),
  ];
  static const List<BoxShadow> elevation4 = [
    BoxShadow(
      color: Color(0x3D000000),
      blurRadius: 12,
      offset: Offset(0, 12),
    ),
  ];
}

/// ============================================================================
/// ANIMATION CONSTANTS
/// ============================================================================

class CarRentalAnimations {
  static const Duration durationXs = Duration(milliseconds: 150);
  static const Duration durationSm = Duration(milliseconds: 200);
  static const Duration durationMd = Duration(milliseconds: 300);
  static const Duration durationLg = Duration(milliseconds: 500);
  static const Duration durationXl = Duration(milliseconds: 800);
}

/// ============================================================================
/// DESIGN SYSTEM - Main class with helper methods
/// ============================================================================

class CarRentalDesignSystem {
  /// Get status color based on status string
  static Color getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return CarRentalColors.warning;
      case 'CONFIRMED':
        return CarRentalColors.info;
      case 'ACTIVE':
      case 'IN PROGRESS':
        return CarRentalColors.success;
      case 'COMPLETED':
        return CarRentalColors.success;
      case 'CANCELLED':
      case 'REJECTED':
        return CarRentalColors.error;
      case 'AVAILABLE':
        return CarRentalColors.success;
      case 'UNAVAILABLE':
      case 'BOOKED':
        return CarRentalColors.error;
      default:
        return CarRentalColors.grey500;
    }
  }

  /// Get status background color
  static Color getStatusBackgroundColor(String status) {
    return getStatusColor(status).withValues(alpha: 0.1);
  }

  /// Get input decoration style
  static InputDecoration inputDecoration({
    required String labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      labelStyle: const TextStyle(
        color: CarRentalColors.textSecondary,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(
        color: CarRentalColors.textTertiary,
        fontSize: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: CarRentalSpacing.lg,
        vertical: CarRentalSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
        borderSide: const BorderSide(color: CarRentalColors.grey300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
        borderSide: const BorderSide(color: CarRentalColors.grey300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
        borderSide: const BorderSide(color: CarRentalColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
        borderSide: const BorderSide(color: CarRentalColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
        borderSide: const BorderSide(color: CarRentalColors.error, width: 2),
      ),
      filled: true,
      fillColor: CarRentalColors.grey50,
    );
  }

  /// Get card decoration
  static BoxDecoration cardDecoration({
    Color backgroundColor = CarRentalColors.card,
    List<BoxShadow> shadows = CarRentalShadows.elevation1,
    double borderRadius = CarRentalBorderRadius.md,
    Border? border,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: border ??
          Border.all(color: CarRentalColors.grey200, width: 1),
      boxShadow: shadows,
    );
  }

  /// Primary button style
  static ButtonStyle primaryButtonStyle({
    double height = CarRentalSizes.buttonHeightMedium,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: CarRentalColors.primary,
      foregroundColor: CarRentalColors.textInverse,
      elevation: 0,
      padding: EdgeInsets.symmetric(
        horizontal: CarRentalSpacing.lg,
        vertical: (height - 20) / 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
      ),
    );
  }

  /// Secondary button style
  static ButtonStyle secondaryButtonStyle({
    double height = CarRentalSizes.buttonHeightMedium,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: CarRentalColors.grey100,
      foregroundColor: CarRentalColors.primary,
      elevation: 0,
      padding: EdgeInsets.symmetric(
        horizontal: CarRentalSpacing.lg,
        vertical: (height - 20) / 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
        side: const BorderSide(color: CarRentalColors.grey300),
      ),
    );
  }

  /// Danger button style
  static ButtonStyle dangerButtonStyle({
    double height = CarRentalSizes.buttonHeightMedium,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: CarRentalColors.error,
      foregroundColor: CarRentalColors.textInverse,
      elevation: 0,
      padding: EdgeInsets.symmetric(
        horizontal: CarRentalSpacing.lg,
        vertical: (height - 20) / 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
      ),
    );
  }

  /// Outlined button style
  static ButtonStyle outlinedButtonStyle({
    double height = CarRentalSizes.buttonHeightMedium,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: CarRentalColors.primary,
      padding: EdgeInsets.symmetric(
        horizontal: CarRentalSpacing.lg,
        vertical: (height - 20) / 2,
      ),
      side: const BorderSide(
        color: CarRentalColors.primary,
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
      ),
    );
  }

  /// Text button style
  static ButtonStyle textButtonStyle() {
    return TextButton.styleFrom(
      foregroundColor: CarRentalColors.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: CarRentalSpacing.md,
        vertical: CarRentalSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.md),
      ),
    );
  }

  /// Heading 1 style
  static TextStyle h1(BuildContext context) {
    return Theme.of(context).textTheme.displayLarge ??
        const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Heading 2 style
  static TextStyle h2(BuildContext context) {
    return Theme.of(context).textTheme.displayMedium ??
        const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Heading 3 style
  static TextStyle h3(BuildContext context) {
    return Theme.of(context).textTheme.displaySmall ??
        const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Subtitle 1 style
  static TextStyle subtitle1(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge ??
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Subtitle 2 style
  static TextStyle subtitle2(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium ??
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Body text large style
  static TextStyle bodyLarge(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Body text medium style
  static TextStyle bodyMedium(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: CarRentalColors.textPrimary,
        );
  }

  /// Body text small style
  static TextStyle bodySmall(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall ??
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: CarRentalColors.textSecondary,
        );
  }

  /// Caption style
  static TextStyle caption(BuildContext context) {
    return Theme.of(context).textTheme.labelSmall ??
        const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: CarRentalColors.textTertiary,
        );
  }
}
