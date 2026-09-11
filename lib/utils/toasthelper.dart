import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

enum ToastKind { success, error, info }

class ToastHelper {
  /// Show a modern toast with logo + status styling.
  /// Failure [message] / [errorMessage] are sanitized so hosts, IPs, and
  /// raw exceptions never appear in production UI.
  ///
  /// Set [showFacebook] on post/save success to include the Facebook mark
  /// and an optional share note.
  static void showCustomToast(
    BuildContext context,
    String message, {
    bool isSuccess = true,
    Duration duration = const Duration(seconds: 3),
    String assetPath = 'assets/logo_mark.png',
    required String errorMessage,
    ToastKind? kind,
    bool showFacebook = false,
    String? facebookMessage,
  }) {
    final resolvedKind = kind ?? (isSuccess ? ToastKind.success : ToastKind.error);
    final fToast = FToast()..init(context);

    final safeMessage = resolvedKind == ToastKind.error
        ? UserFacingError.sanitize(message)
        : message;

    final rawDetails = errorMessage.trim();
    final safeDetails = (resolvedKind == ToastKind.error && rawDetails.isNotEmpty)
        ? UserFacingError.sanitize(rawDetails, fallback: '')
        : '';

    final hasErrorDetails = safeDetails.isNotEmpty &&
        safeDetails != safeMessage &&
        !UserFacingError.looksSensitive(rawDetails);

    final fbNote = showFacebook
        ? (facebookMessage?.trim().isNotEmpty == true
            ? facebookMessage!.trim()
            : 'Also sharing on the Vero360 Facebook Page.')
        : null;

    final palette = _ToastPalette.of(resolvedKind);

    final toast = _ModernToast(
      message: safeMessage,
      details: hasErrorDetails ? safeDetails : fbNote,
      assetPath: assetPath,
      palette: palette,
      showFacebook: showFacebook,
    );

    fToast.removeCustomToast();
    fToast.showToast(
      child: toast,
      gravity: ToastGravity.TOP,
      toastDuration: duration,
      fadeDuration: const Duration(milliseconds: 280),
    );
  }

  /// Convenience: never leaks exception text into the UI.
  static void showFailure(
    BuildContext context,
    String message, {
    Object? error,
  }) {
    showCustomToast(
      context,
      UserFacingError.sanitize(message),
      isSuccess: false,
      errorMessage:
          error == null ? '' : UserFacingError.from(error, fallback: ''),
    );
  }

  /// Neutral info toast (same modern chrome).
  static void showToast(BuildContext context, String message) {
    showCustomToast(
      context,
      message,
      isSuccess: true,
      errorMessage: '',
      kind: ToastKind.info,
    );
  }
}

/// Compact Facebook share tip — place **above** Save / Post buttons.
class FacebookShareHint extends StatelessWidget {
  const FacebookShareHint({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1877F2).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1877F2).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FacebookLogoMark(size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Classic Facebook “f” mark (no asset required).
class FacebookLogoMark extends StatelessWidget {
  const FacebookLogoMark({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1877F2),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: Text(
        'f',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.72,
          fontWeight: FontWeight.w800,
          height: 1,
          fontFamily: 'Arial',
        ),
      ),
    );
  }
}

class _ToastPalette {
  const _ToastPalette({
    required this.accent,
    required this.softFill,
    required this.iconBg,
    required this.titleColor,
    required this.bodyColor,
    required this.border,
    required this.icon,
    required this.label,
  });

  final Color accent;
  final Color softFill;
  final Color iconBg;
  final Color titleColor;
  final Color bodyColor;
  final Color border;
  final IconData icon;
  final String label;

  static _ToastPalette of(ToastKind kind) {
    switch (kind) {
      case ToastKind.success:
        return const _ToastPalette(
          accent: Color(0xFF16A34A),
          softFill: Color(0xFFF0FDF4),
          iconBg: Color(0xFFDCFCE7),
          titleColor: Color(0xFF14532D),
          bodyColor: Color(0xFF3F6212),
          border: Color(0xFFBBF7D0),
          icon: Icons.check_rounded,
          label: 'Success',
        );
      case ToastKind.error:
        return const _ToastPalette(
          accent: Color(0xFFDC2626),
          softFill: Color(0xFFFEF2F2),
          iconBg: Color(0xFFFEE2E2),
          titleColor: Color(0xFF7F1D1D),
          bodyColor: Color(0xFF991B1B),
          border: Color(0xFFFECACA),
          icon: Icons.error_outline_rounded,
          label: 'Error',
        );
      case ToastKind.info:
        return const _ToastPalette(
          accent: Color(0xFF2563EB),
          softFill: Color(0xFFEFF6FF),
          iconBg: Color(0xFFDBEAFE),
          titleColor: Color(0xFF1E3A8A),
          bodyColor: Color(0xFF1D4ED8),
          border: Color(0xFFBFDBFE),
          icon: Icons.info_outline_rounded,
          label: 'Info',
        );
    }
  }
}

class _ModernToast extends StatelessWidget {
  const _ModernToast({
    required this.message,
    required this.assetPath,
    required this.palette,
    this.details,
    this.showFacebook = false,
  });

  final String message;
  final String? details;
  final String assetPath;
  final _ToastPalette palette;
  final bool showFacebook;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxW = width > 520 ? 420.0 : width - 28;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: maxW,
                decoration: BoxDecoration(
                  color: palette.softFill.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border.withValues(alpha: 0.9)),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        color: showFacebook
                            ? const Color(0xFF1877F2)
                            : palette.accent,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: showFacebook
                                      ? const Color(0xFF1877F2)
                                          .withValues(alpha: 0.12)
                                      : palette.iconBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: showFacebook
                                    ? const Center(
                                        child: FacebookLogoMark(size: 22),
                                      )
                                    : Icon(
                                        palette.icon,
                                        size: 20,
                                        color: palette.accent,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      showFacebook ? 'Facebook' : palette.label,
                                      style: TextStyle(
                                        color: showFacebook
                                            ? const Color(0xFF1877F2)
                                            : palette.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      message,
                                      style: TextStyle(
                                        color: palette.titleColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                      ),
                                    ),
                                    if (details != null && details!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        details!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.bodyColor
                                              .withValues(alpha: 0.85),
                                          fontSize: 12,
                                          height: 1.3,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.asset(
                                  assetPath,
                                  height: 28,
                                  width: 28,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
