import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

class ToastHelper {
  /// Show a custom toast with your app logo and a status color.
  /// Failure [message] / [errorMessage] are sanitized so hosts, IPs, and
  /// raw exceptions never appear in production UI.
  static void showCustomToast(
    BuildContext context,
    String message, {
    bool isSuccess = true,
    Duration duration = const Duration(seconds: 3),
    String assetPath = 'assets/logo_mark.png',
    required String errorMessage,
  }) {
    final fToast = FToast()..init(context);

    final safeMessage = isSuccess
        ? message
        : UserFacingError.sanitize(message);

    final rawDetails = errorMessage.trim();
    final safeDetails = (!isSuccess && rawDetails.isNotEmpty)
        ? UserFacingError.sanitize(rawDetails, fallback: '')
        : '';

    final hasErrorDetails = safeDetails.isNotEmpty &&
        safeDetails != safeMessage &&
        !UserFacingError.looksSensitive(rawDetails);

    final bg = isSuccess ? Colors.green.shade700 : Colors.red.shade700;

    final toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              assetPath,
              height: 50,
              width: 50,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  safeMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (hasErrorDetails) ...[
                  const SizedBox(height: 4),
                  Text(
                    safeDetails,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.CENTER,
      toastDuration: duration,
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

  static void showToast(BuildContext context, String s) {}
}
