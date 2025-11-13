// lib/services/api_config.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  /// PRIMARY + BACKUP PROD SERVERS

  /// set up a second instance / load balancer).
  static const String _primaryProd = 'https://unimatherapyapplication.com/vero';
  static const String _backupProd  = 'https://backup.unimatherapyapplication.com/vero';

  static const String _prefsKeyBase = 'api_base';

  static bool _inited = false;


  static String _base = _primaryProd;

  static String get prod => _base;
  static String get prodBase => _base;


  static Future<void> init() async {
    if (_inited) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKeyBase);

    if (saved != null && saved.trim().isNotEmpty) {
      _base = _normalizeBase(saved);
    } else {
      _base = _normalizeBase(_primaryProd);
    }

    // Pick the best reachable between primary + backup
    await _selectBestBase();

    _inited = true;
  }


  static Future<String> readBase() async {
    if (!_inited) await init();
    return _base;
  }

  static Future<void> useProd() => init();
  static Future<void> setBase(String _ignored) => useProd();

 
  static Uri endpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_base$p'); 
  }

  /// Build URIs that ignore `/vero` (for /healthz, /, etc.).

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

  /// Ensure some backend is up.
  /// - Checks current `_base`
  /// - If dead, tries backup
  /// - Updates `_base` + persists if it switches
  static Future<bool> ensureBackendUp({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    await init();

    // 1) Try current base
    if (await _isReachable(_base, timeout: timeout)) {
      return true;
    }

    // 2) Try the other one (primary/backup)
    final candidates = <String>{
      _normalizeBase(_primaryProd),
      _normalizeBase(_backupProd),
    }.toList();

    candidates.remove(_base); // don't re-test the one that just failed

    for (final candidate in candidates) {
      if (await _isReachable(candidate, timeout: timeout)) {
        _base = candidate;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyBase, _base);
        return true;
      }
    }

    return false; // nothing reachable
  }

  /// Simple public health check that uses the current base.
  static Future<bool> prodReachable({
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    await init();
    return _isReachable(_base, timeout: timeout);
  }



  static String _normalizeBase(String s) =>
      s.trim().replaceFirst(RegExp(r'/+$'), '');

  static Future<void> _selectBestBase() async {
    final candidates = [
      _normalizeBase(_primaryProd),
      _normalizeBase(_backupProd),
    ];

    for (final c in candidates) {
      if (await _isReachable(c)) {
        _base = c;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyBase, _base);
        return;
      }
    }

    // If both look dead, still pick primary as default.
    _base = candidates.first;
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
      root.replace(path: '/healthz'),     // matches your Nest /healthz
      root.replace(path: '/health'),
      root.replace(path: '/'),
      Uri.parse('$base/auth/login'),      // prove /vero side also works
    ];

    for (final uri in probes) {
      try {
        final res = await http.get(uri).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 600) {
          return true;
        }
      } catch (_) {
        // ignore error and try next probe
      }
    }
    return false;
  }


}
