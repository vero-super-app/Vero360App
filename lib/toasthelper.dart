import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ToastHelper {
  /// Show a custom toast with your app logo and a status color.
  /// [assetPath] defaults to your logo asset.
  static void showCustomToast(
    BuildContext context,
    String message, {
    bool isSuccess = true,
    Duration duration = const Duration(seconds: 3),
    String assetPath = 'assets/logo_mark.png', required String errorMessage, // default logo path
  }) {
    final fToast = FToast()..init(context);

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
          // App logo
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
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
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

  static void showToast(BuildContext context, String s) {}
}
