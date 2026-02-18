import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

/// Google Maps API Configuration
class GoogleMapsConfig {
  static late final String apiKey;

  /// Initialize configuration from .env file or dart-define
  static Future<void> initialize() async {
    // First try to get from dart-define
    const String dartDefineKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
    
    if (dartDefineKey.isNotEmpty) {
      apiKey = dartDefineKey;
      if (kDebugMode) {
        debugPrint('[GoogleMapsConfig] API key loaded from dart-define: ${dartDefineKey.substring(0, 10)}...');
      }
      return;
    }

    // Fallback to .env file
    try {
      await dotenv.load(fileName: ".env");
      apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      
      if (apiKey.isNotEmpty && kDebugMode) {
        debugPrint('[GoogleMapsConfig] API key loaded from .env: ${apiKey.substring(0, 10)}...');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GoogleMapsConfig] Error loading .env: $e');
      }
      apiKey = '';
    }
    
    if (kDebugMode && !isConfigured) {
      debugPrint('[GoogleMapsConfig] ⚠️ WARNING: No Google Maps API key found!');
      debugPrint('[GoogleMapsConfig] Please add GOOGLE_MAPS_API_KEY to .env or run with --dart-define');
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
