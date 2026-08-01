// =============================================================================
// Copy this file into your Flutter app (e.g. lib/core/network/auth_interceptor.dart)
// and wire it to your Dio client. See docs/flutter_auth_setup.md for steps.
// =============================================================================

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

/// Adds a fresh Firebase ID token to every request so the backend rarely sees
/// an expired token. Keeps the user "logged in" until they sign out.
/// Also syncs the token to SharedPreferences so screens that only read SP stay in sync.
class FirebaseAuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // false = use cache if still valid; SDK refreshes automatically when needed
        final token = await user.getIdToken(false);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
          await AuthHandler.persistTokenToSp(token);
        }
      } catch (_) {
        // If token fails (e.g. user signed out elsewhere), let the request go
        // and the backend will return 401
      }
    }
    handler.next(options);
  }
}

/// When the backend returns 401 (e.g. token expired), force refresh and retry once.
class FirebaseAuthRetryInterceptor extends QueuedInterceptor {
  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return handler.next(err);
    }

    try {
      // Force refresh the ID token
      final newToken = await user.getIdToken(true);
      if (newToken == null || newToken.isEmpty) {
        return handler.next(err);
      }

      await AuthHandler.persistTokenToSp(newToken);
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer $newToken';

      final dio = Dio();
      final response = await dio.fetch(opts);
      return handler.resolve(response);
    } catch (_) {
      handler.next(err);
    }
  }
}
