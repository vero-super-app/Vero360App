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

  /// Build URIs safely (no double slashes) — this is your prefixed API builder.
  static Uri endpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$prod$p'); // e.g. https://.../vero/auth/login
  }

  /// NEW: Build root URIs that ignore the /vero prefix (for /healthz, etc.).
  static Uri rootEndpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse(prod);
    final base = Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : 0,
    ).toString().replaceAll(RegExp(r'/:?0$'), ''); // drop :0 if no port
    return Uri.parse('$base$p'); // e.g. https://.../healthz
  }

  /// Quick reachability check: try unprefixed health first, then fallback.
  static Future<bool> prodReachable({Duration timeout = const Duration(milliseconds: 800)}) async {
    final probes = <Uri>[
      rootEndpoint('/healthz'), // unprefixed — you excluded it in Nest
      rootEndpoint('/health'),
      rootEndpoint('/'),
      // As a last resort, prove the prefixed path exists (will likely 404 on GET, but DNS/TLS works)
      endpoint('/auth/login'),
    ];
    for (final u in probes) {
      try {
        final res = await http.get(u).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 600) return true;
      } catch (_) {}
    }
    return false;
  }
}
