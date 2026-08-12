import 'package:flutter/foundation.dart';

/// Debug-only logging. Never emits to console in release/profile builds.
abstract final class AppLogger {
  static void d(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode) return;
    if (error != null) {
      debugPrint('$message: $error');
      if (stack != null) debugPrint(stack.toString());
    } else {
      debugPrint(message);
    }
  }

  static void w(String message, [Object? error]) {
    d(message, error);
  }

  static void e(String message, [Object? error, StackTrace? stack]) {
    d(message, error, stack);
  }
}
