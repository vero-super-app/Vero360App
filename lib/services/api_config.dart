import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  /// List of PROD servers.

  /// For now: ONE real server.
  /// When you have a real backup, add it here:

  static const List<String> _prodServers = [
    'https://heflexitservice.co.za/vero',
    'https://unimatherapyapplication.com/vero',  //BACKUP SERVER
  
  ];

  static const String _prefsKeyBase = 'api_base';

  static bool _inited = false;

  /// Active base (no trailing slash, includes `/vero`)
  static String _base = _prodServers.first;

  static String get prod => _base;
  static String get prodBase => _base;

  // ---------------------------------------------------------------------------
  // INIT & BASE SELECTION
  // ---------------------------------------------------------------------------

  static Future<void> init() async {
    if (_inited) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKeyBase);

    if (saved != null && saved.trim().isNotEmpty) {
      _base = _normalizeBase(saved);
    } else {
      _base = _normalizeBase(_prodServers.first);
    }

    await _selectBestBase();
    _inited = true;
  }

  static Future<String> readBase() async {
    if (!_inited) await init();
    return _base;
  }

  static Future<void> useProd() => init();
  static Future<void> setBase(String _ignored) => useProd();

  // ---------------------------------------------------------------------------
  // URL BUILDERS
  // ---------------------------------------------------------------------------

  static Uri endpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_base$p'); // e.g. https://.../vero/auth/login
  }

  /// For /healthz, /, etc. (ignores /vero prefix).
  static Uri rootEndpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse(_base);
    return Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: p,
    );
  }

  // ---------------------------------------------------------------------------
  // RESILIENCE & HEALTH CHECKS
  // ---------------------------------------------------------------------------


  static Future<bool> ensureBackendUp({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    await init();

    // 1) try the current base
    if (await _isReachable(_base, timeout: timeout)) {
      return true;
    }

    // 2) try others in the list (if you add backups later)
    for (final candidate in _prodServers.map(_normalizeBase)) {
      if (candidate == _base) continue;
      if (await _isReachable(candidate, timeout: timeout)) {
        _base = candidate;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyBase, _base);
        return true;
      }
    }

    return false; // nothing reachable
  }

  static Future<bool> prodReachable({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    await init();
    return _isReachable(_base, timeout: timeout);
  }

  // ---------------------------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------------------------

  static String _normalizeBase(String s) =>
      s.trim().replaceFirst(RegExp(r'/+$'), '');

  static Future<void> _selectBestBase() async {
    // Try the configured servers in order.
    for (final raw in _prodServers) {
      final candidate = _normalizeBase(raw);
      if (await _isReachable(candidate)) {
        _base = candidate;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyBase, _base);
        return;
      }
    }
    // If none reachable, keep whatever was there; app will show error.
  }

  static Future<bool> _isReachable(
    String base, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    final u = Uri.parse(base);
    final root = Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
    );

    final probes = <Uri>[
      root.replace(path: '/healthz'),
      root.replace(path: '/health'),
      root.replace(path: '/'),
      Uri.parse('$base/auth/login'),
    ];

    for (final uri in probes) {
      try {
        final res = await http.get(uri).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 600) {
          return true;
        }
      } catch (_) {
        // ignore and try next probe
      }
    }
    return false;
  }
}
