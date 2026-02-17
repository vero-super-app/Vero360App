// lib/services/api_config.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  /// API prefix (your endpoints are /vero/...)https://unbigamous-unappositely-kory.ngrok-free.dev
  static const String apiPrefix = '/vero';

  /// PROD root (as you requested)
  // static const String _defaultProdRoot = 'https://heflexitservice.co.za';

  // static const String _defaultProdRoot =
  //     'https://unbigamous-unappositely-kory.ngrok-free.dev';

  static const String _defaultProdRoot =
      'http://10.0.2.2:3000'; // Android emulator localhost

  /// Optional override at build time:
  /// flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultProdRoot,
  );

  /// Allowed servers (roots only, no /vero here)
  static const List<String> _prodServers = <String>[
    baseUrl, // uses dart-define or default
  ];

  /// IMPORTANT: bump key so old saved value (heflexitservice...) stops overriding.
  static const String _prefsKeyBase = 'api_base_v2';

  static bool _inited = false;
  static String _baseRoot = _normalizeBase(_prodServers.first);

  static String get prod => _baseRoot;
  static String get prodBase => _baseRoot;

  // ---------------------------------------------------------------------------
  // INIT / SELECTION
  // ---------------------------------------------------------------------------

  static Future<void> init() async {
    if (_inited) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKeyBase);

    // Only accept saved base if it is one of the allowed servers
    if (saved != null && saved.trim().isNotEmpty) {
      final normSaved = _normalizeBase(saved);
      if (_isAllowed(normSaved)) {
        _baseRoot = normSaved;
      } else {
        _baseRoot = _normalizeBase(_prodServers.first);
        await prefs.remove(_prefsKeyBase);
      }
    } else {
      _baseRoot = _normalizeBase(_prodServers.first);
    }

    // pick best (if you add more servers later)
    await _selectBestBase();
    _inited = true;
  }

  static Future<String> readBase() async {
    if (!_inited) await init();
    return _baseRoot;
  }

  static Future<void> useProd() => init();

  /// Keep compatibility with existing code (ignored param).
  static Future<void> setBase(String _ignored) => useProd();

  // ---------------------------------------------------------------------------
  // URL BUILDERS
  // ---------------------------------------------------------------------------

  /// Builds: {root}{/vero}{path}
  /// - If you pass '/cart' => http://root/vero/cart
  /// - If you pass '/vero/cart' => http://root/vero/cart (no double prefix)
  static Uri endpoint(String path) {
    final clean = path.startsWith('/') ? path : '/$path';
    final fullPath = clean.startsWith(apiPrefix) ? clean : '$apiPrefix$clean';

    final u = Uri.parse(_baseRoot);
    return Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: fullPath,
    );
  }

  /// Root endpoint without /vero prefix (for /health, /, etc.)
  static Uri rootEndpoint(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    final u = Uri.parse(_baseRoot);
    return Uri(
      scheme: u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: p,
    );
  }

  // ---------------------------------------------------------------------------
  // HEALTH CHECKS
  // ---------------------------------------------------------------------------

  static Future<bool> ensureBackendUp({
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    await init();

    // Try current base first
    if (await _isReachable(_baseRoot, timeout: timeout)) return true;

    // Try other servers (if you add later)
    for (final raw in _prodServers) {
      final candidate = _normalizeBase(raw);
      if (candidate == _baseRoot) continue;

      if (await _isReachable(candidate, timeout: timeout)) {
        _baseRoot = candidate;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyBase, _baseRoot);
        return true;
      }
    }

    return false;
  }

  static Future<bool> prodReachable({
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    await init();
    return _isReachable(_baseRoot, timeout: timeout);
  }

  // ---------------------------------------------------------------------------
  // INTERNAL
  // ---------------------------------------------------------------------------

  static String _normalizeBase(String s) =>
      s.trim().replaceFirst(RegExp(r'/+$'), '');

  static bool _isAllowed(String base) {
    final normalized = _normalizeBase(base);
    return _prodServers.map(_normalizeBase).contains(normalized);
  }

  static bool _isPassengerHtml(String body) {
    final s = body.trimLeft().toLowerCase();
    return s.startsWith('<!doctype html') ||
        s.startsWith('<html') ||
        s.contains('phusion passenger') ||
        s.contains('web application could not be started') ||
        s.contains("we're sorry, but something went wrong");
  }

  static Future<void> _selectBestBase() async {
    for (final raw in _prodServers) {
      final candidate = _normalizeBase(raw);
      if (await _isReachable(candidate)) {
        _baseRoot = candidate;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKeyBase, _baseRoot);
        return;
      }
    }
  }

  static Future<bool> _isReachable(
    String base, {
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final u = Uri.parse(base);

    // Probes that actually reflect your API is running (not just “host responds”).
    final probes = <Uri>[
      Uri(
          scheme: u.scheme,
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '$apiPrefix/healthz'),
      Uri(
          scheme: u.scheme,
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '$apiPrefix/health'),
      Uri(
          scheme: u.scheme,
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '$apiPrefix/'),
      Uri(
          scheme: u.scheme,
          host: u.host,
          port: u.hasPort ? u.port : null,
          path: '/'),
    ];

    for (final uri in probes) {
      try {
        final res = await http.get(uri).timeout(timeout);

        // Passenger crash page => NOT reachable
        if (_isPassengerHtml(res.body)) continue;

        // Consider reachable only if it's not a server crash
        // (200-499 is fine; 404 still means server is up)
        if (res.statusCode >= 200 && res.statusCode < 500) return true;
      } catch (_) {
        // try next probe
      }
    }
    return false;
  }
}