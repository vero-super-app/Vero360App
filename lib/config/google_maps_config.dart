import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Google Maps API Configuration
class GoogleMapsConfig {
  static late final String apiKey;

  /// Initialize configuration from .env file
  static Future<void> initialize() async {
    await dotenv.load(fileName: ".env");
    apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    validateConfiguration();
  }

  /// Check if API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;

  /// Validate API key configuration
  static void validateConfiguration() {
    if (!isConfigured) {
      throw Exception(
          'Google Maps API key not configured in .env file. '
          'Please add GOOGLE_MAPS_API_KEY=your_key to .env');
    }
  }
}
