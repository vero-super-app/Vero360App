import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:vero360_app/utils/app_logger.dart';

/// Google Maps API Configuration
class GoogleMapsConfig {
  static String apiKey =
      const String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
  static bool _initialized = false;

  /// Initialize configuration from .env file or dart-define
  static Future<void> initialize() async {
    if (_initialized && apiKey.isNotEmpty) return;

    const String dartDefineKey =
        String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

    if (dartDefineKey.isNotEmpty) {
      apiKey = dartDefineKey;
      _initialized = true;
      return;
    }

    // Prefer local .env; fall back to committed .env.example (CI / missing local file).
    try {
      try {
        await dotenv.load(fileName: '.env');
      } catch (_) {
        await dotenv.load(fileName: '.env.example');
      }
      apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    } catch (e) {
      AppLogger.d('[GoogleMapsConfig] Error loading env', e);
      apiKey = '';
    }

    _initialized = true;

    if (kDebugMode && !isConfigured) {
      AppLogger.w(
        '[GoogleMapsConfig] No Google Maps API key found. '
        'Add GOOGLE_MAPS_API_KEY to .env or use --dart-define.',
      );
    }
  }

  /// Check if API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;

  /// Get API key with fallback
  static String getApiKey() {
    if (apiKey.isEmpty) {
      throw Exception(
          'Google Maps API key not configured. '
          'Add GOOGLE_MAPS_API_KEY to .env file or run with: '
          'flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_api_key');
    }
    return apiKey;
  }
}
