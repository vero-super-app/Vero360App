import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:vero360_app/utils/app_logger.dart';

/// Google Maps API Configuration.
///
/// Maps SDK keys are client-side by design (restrict in Google Cloud by
/// Android package/SHA-1 and iOS bundle id). A built-in fallback keeps maps
/// working when `.env` / dart-define are missing after security scans.
class GoogleMapsConfig {
  /// Same key as AndroidManifest / iOS Info.plist / `.env`.
  static const String _fallbackApiKey =
      'AIzaSyAQtLkqSetILdLacfIxnqH8DEC0qcobCuI';

  static String _apiKey = '';
  static bool _initialized = false;

  static String get apiKey =>
      _apiKey.isNotEmpty ? _apiKey : _fallbackApiKey;

  /// Initialize configuration from dart-define, then .env / .env.example.
  static Future<void> initialize() async {
    if (_initialized && _apiKey.isNotEmpty) return;

    const String dartDefineKey =
        String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

    if (dartDefineKey.isNotEmpty) {
      _apiKey = dartDefineKey;
      _initialized = true;
      return;
    }

    // Prefer local .env; fall back to committed .env.example (CI / missing local file).
    try {
      try {
        await dotenv
            .load(fileName: '.env')
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        await dotenv
            .load(fileName: '.env.example')
            .timeout(const Duration(seconds: 1));
      }
      _apiKey = (dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '').trim();
    } catch (e) {
      AppLogger.d('[GoogleMapsConfig] Error loading env', e);
      _apiKey = '';
    }

    if (_apiKey.isEmpty) {
      _apiKey = _fallbackApiKey;
      if (kDebugMode) {
        AppLogger.d('[GoogleMapsConfig] Using built-in Maps API key fallback');
      }
    }

    _initialized = true;
  }

  /// Check if API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;

  /// Get API key with fallback
  static String getApiKey() {
    final key = apiKey;
    if (key.isEmpty) {
      throw Exception(
          'Google Maps API key not configured. '
          'Add GOOGLE_MAPS_API_KEY to .env file or run with: '
          'flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_api_key');
    }
    return key;
  }
}
