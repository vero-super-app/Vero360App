import 'package:flutter/foundation.dart';

/// Maps exceptions to **safe** copy for users.
/// Never returns hostnames, IPs, ports, URLs, raw sockets, or stack traces.
class UserFacingError {
  UserFacingError._();

  static const String generic =
      'Something went wrong. Please try again.';
  static const String offline =
      'You seem offline. Check your connection and try again.';
  static const String timeout =
      'That took too long. Please try again.';
  static const String unauthorized =
      'Please sign in again to continue.';
  static const String notLoggedIn =
      'You’re not logged in. Please sign in to continue.';
  static const String forbidden =
      'You don’t have permission to do that.';
  static const String notFound =
      'We couldn’t find what you were looking for.';
  static const String server =
      'Our servers are busy. Please try again in a moment.';

  /// Prefer this everywhere you would show `e.toString()` or `Failed: $e`.
  static String from(
    Object? error, {
    String fallback = generic,
  }) {
    if (error == null) return fallback;

    if (kDebugMode) {
      debugPrint('[UserFacingError] $error');
    }

    // Prefer typed API messages when present, still sanitize.
    try {
      final dynamic dyn = error;
      final msg = dyn.message;
      if (msg is String && msg.trim().isNotEmpty) {
        return _sanitizeOrFallback(msg, fallback: fallback);
      }
    } catch (_) {}

    final raw = error.toString();
    return _sanitizeOrFallback(raw, fallback: fallback);
  }

  /// Sanitize any string before showing it in UI / toasts.
  static String sanitize(
    String? message, {
    String fallback = generic,
  }) {
    if (message == null || message.trim().isEmpty) return fallback;
    return _sanitizeOrFallback(message, fallback: fallback);
  }

  static bool looksSensitive(String message) {
    final s = message.toLowerCase();
    if (_sensitivePatterns.any((re) => re.hasMatch(s))) return true;
    if (s.contains('exception') &&
        (s.contains('socket') ||
            s.contains('client') ||
            s.contains('http') ||
            s.contains('uri=') ||
            s.contains('errno'))) {
      return true;
    }
    return false;
  }

  static String _sanitizeOrFallback(
    String message, {
    required String fallback,
  }) {
    var cleaned = message.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^(exception|error):\s*', caseSensitive: false), '');

    final lower = cleaned.toLowerCase();

    if (_isNetworkish(lower)) return offline;
    if (_isTimeout(lower)) return timeout;
    if (_isNotLoggedIn(lower)) return notLoggedIn;
    if (_isAuth(lower)) return unauthorized;
    if (_isForbidden(lower)) return forbidden;
    if (_isNotFound(lower)) return notFound;
    if (_isServer(lower)) return server;

    if (looksSensitive(cleaned)) return fallback;

    // Drop leftover infra fragments if any slipped through.
    cleaned = cleaned
        .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}(:\d+)?\b'), '')
        .replaceAll(RegExp(r'\buri\s*=\s*\S+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\baddress\s*=\s*\S+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bport\s*=\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (cleaned.isEmpty || cleaned.length > 160 || looksSensitive(cleaned)) {
      return fallback;
    }

    // Avoid dumping class names like ClientException...
    if (RegExp(r'^[A-Za-z]+Exception\b').hasMatch(cleaned)) {
      return fallback;
    }

    return cleaned;
  }

  static bool _isNetworkish(String s) =>
      s.contains('socket') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('network is unreachable') ||
      s.contains('failed host lookup') ||
      s.contains('no address associated') ||
      s.contains('clientexception') ||
      s.contains('handshake') ||
      s.contains('connection closed') ||
      s.contains('software caused connection abort') ||
      (s.contains('offline') && !s.contains('sign'));

  static bool _isTimeout(String s) =>
      s.contains('timeout') ||
      s.contains('timed out') ||
      s.contains('deadline-exceeded') ||
      s.contains('deadline exceeded');

  static bool _isAuth(String s) =>
      s.contains('unauthenticated') ||
      s.contains('unauthorized') ||
      s.contains('not authenticated') ||
      (s.contains('jwt') && s.contains('expired')) ||
      s.contains('token expired') ||
      s.contains('please sign in') ||
      s.contains('requires login');

  /// Firestore permission-denied for guests usually means “not logged in”.
  static bool _isNotLoggedIn(String s) =>
      s.contains('not logged in') ||
      s.contains('you’re not logged in') ||
      s.contains("you're not logged in") ||
      s.contains('please log in') ||
      s.contains('caller does not have permission') ||
      (s.contains('permission-denied') &&
          (s.contains('caller') || s.contains('execute')));

  static bool _isForbidden(String s) =>
      s.contains('permission-denied') ||
      s.contains('forbidden') ||
      s.contains('not allowed');

  static bool _isNotFound(String s) =>
      s.contains('not found') || s.contains('404');

  static bool _isServer(String s) =>
      s.contains('502') ||
      s.contains('503') ||
      s.contains('504') ||
      s.contains('bad gateway') ||
      s.contains('service unavailable') ||
      s.contains('internal server');

  static final List<RegExp> _sensitivePatterns = [
    RegExp(r'https?://'),
    RegExp(r'\buri\s*='),
    RegExp(r'\baddress\s*='),
    RegExp(r'\bport\s*='),
    RegExp(r'\berrno\s*='),
    RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b'), // IPv4
    RegExp(r'localhost'),
    RegExp(r'\b127\.0\.0\.1\b'),
    RegExp(r'/vero/'),
    RegExp(r':\d{2,5}/'), // :3000/path
    RegExp(r'os error:', caseSensitive: false),
    RegExp(r'clientexception', caseSensitive: false),
    RegExp(r'socketexception', caseSensitive: false),
    RegExp(r'handshakeexception', caseSensitive: false),
    RegExp(r'xmlhttprequest'),
    RegExp(r'firestore\.googleapis'),
    RegExp(r'googleapis\.com'),
    RegExp(r'cloud_firestore', caseSensitive: false),
    RegExp(r'firebase', caseSensitive: false),
    RegExp(r'api[_-]?key', caseSensitive: false),
    RegExp(r'authorization', caseSensitive: false),
    RegExp(r'bearer\s+', caseSensitive: false),
  ];
}
