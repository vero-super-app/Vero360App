/// SerpAPI Configuration
class SerpapiConfig {
  /// SerpAPI Key
  static const String apiKey = String.fromEnvironment(
    'SERPAPI_API_KEY',
    defaultValue: '7323b451428f90b2926ae01bd2fc04f14ada175b9e397e0e62d04dfa0c12a565',
  );

  /// SerpAPI Base URL
  static const String baseUrl = 'https://serpapi.com/search.json';

  /// Check if API key is configured
  static bool get isConfigured => apiKey.isNotEmpty;

  /// Validate API key configuration
  static void validateConfiguration() {
    if (!isConfigured) {
      throw Exception(
        'SerpAPI key not configured. '
        'Run with: flutter run --dart-define=SERPAPI_API_KEY=your_key'
      );
    }
  }
}
