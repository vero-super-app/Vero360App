import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

/// Google Maps API Configuration
class GoogleMapsConfig {
  static late final String apiKey;

  /// Initialize configuration from .env file
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
      apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GoogleMapsConfig] .env file not found: $e');
      }
      apiKey = '';
    }
    
    if (kDebugMode && !isConfigured) {
      debugPrint('[GoogleMapsConfig] Warning: API key not configured');
    }
  }

  /// Check if API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;

  /// Get API key with fallback
  static String getApiKey() {
    if (apiKey.isEmpty) {
      throw Exception(
          'Google Maps API key not configured. '
          'Add GOOGLE_MAPS_API_KEY to .env file or set it via environment variables.');
    }
    return apiKey;
  }
}
