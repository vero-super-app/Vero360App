/// Google Maps API Configuration
class GoogleMapsConfig {
  /// Get Google Maps API Key
  ///
  /// This should be set via --dart-define=GOOGLE_MAPS_API_KEY=your_key
  /// Or configure in AndroidManifest.xml and Info.plist
  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyCQ5_4N2J_xwKqmY-lAa8-ifRxovoRTTYk',
  );

  /// Check if API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;

  /// Validate API key configuration
  static void validateConfiguration() {
    if (!isConfigured) {
      throw Exception('Google Maps API key not configured. '
          'Run with: flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key');
    }
  }
}
