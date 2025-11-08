// lib/services/api_config.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  /// 🔒 Single source of truth (NO trailing slash)
  static const String prod =   'https://unimatherapyapplication.com/vero/';     ///'http://10.0.2.2:3000';
  static String get prodBase => prod;

  static const String _prefsKey = 'api_base';
  static bool _inited = false;

  /// Force PROD and persist it (overwrites any dev/custom base you may have saved earlier).
  static Future<void> init() async {
    if (_inited) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, prod);
    _inited = true;
  }

  /// Always returns PROD.
  static Future<String> readBase() async {
    if (!_inited) await init();
    return prod;
  }

  /// Alias you can call in main() for clarity.
  static Future<void> useProd() => init();

  /// Kept for compatibility with older code that might call setBase().
  /// It is a NO-OP that still forces PROD.
  static Future<void> setBase(String _ignored) => useProd();

  /// Build URIs safely (no double slashes).
  static Uri endpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$prod$p');
  }

  /// Optional: quick reachability check for logs/debug UI.
  static Future<bool> prodReachable({Duration timeout = const Duration(milliseconds: 800)}) async {
    for (final path in const ['/healthz', '/health', '/']) {
      try {
        final res = await http.get(Uri.parse('$prod$path')).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 500) return true;
      } catch (_) {}
    }
    return false;
  }
}
