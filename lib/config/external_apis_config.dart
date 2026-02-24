// lib/config/external_apis_config.dart
/// Centralized configuration for all external third-party APIs
///
/// Includes:
/// - Exchange Rate API
/// - Weather API
/// - And other third-party services
library;

class ExchangeRateConfig {
  /// Exchange Rate API base URL
  /// Get exchange rates for any currency
  static const String baseUrl = 'https://api.exchangerate-api.com/v4/latest';

  /// Build endpoint URL for a specific base currency
  static String endpoint(String baseCurrency) => '$baseUrl/$baseCurrency';

  /// Get URI for currency conversion
  static Uri getExchangeRateUri(String baseCurrency) {
    return Uri.parse(endpoint(baseCurrency));
  }

  /// Standard headers for Exchange Rate API
  static const Map<String, String> defaultHeaders = {
    'Accept': 'application/json',
  };

  /// Free tier - no API key required
  static const bool requiresApiKey = false;
}

class WeatherConfig {
  /// RapidAPI Weather Service base URL
  /// Documentation: https://rapidapi.com/weatherapi/api/weatherapi-com
  static const String baseUrl = 'https://weatherapi-com.p.rapidapi.com';

  /// Alerts endpoint
  static const String alertsEndpoint = '$baseUrl/alerts.json';

  /// Current weather endpoint
  static const String currentEndpoint = '$baseUrl/current.json';

  /// Forecast endpoint
  static const String forecastEndpoint = '$baseUrl/forecast.json';

  /// Get alerts for a location
  static Uri getAlertsUri({required String query}) {
    return Uri.parse('$alertsEndpoint?q=$query');
  }

  /// Get current weather for a location
  static Uri getCurrentWeatherUri({required String query}) {
    return Uri.parse('$currentEndpoint?q=$query');
  }

  /// Standard headers for RapidAPI (requires API key)
  static Map<String, String> defaultHeaders(String apiKey) => {
        'X-RapidAPI-Key': apiKey,
        'X-RapidAPI-Host': 'weatherapi-com.p.rapidapi.com',
        'Accept': 'application/json',
      };

  /// This API requires an API key from RapidAPI
  static const bool requiresApiKey = true;
}

class WhatsAppConfig {
  /// WhatsApp Web URL for messaging
  /// Format: wa.me/{phone_number}?text={message}
  static const String baseUrl = 'https://wa.me';

  /// Build WhatsApp message URL
  static Uri getWhatsAppMessageUri({
    required String phoneNumber,
    required String message,
  }) {
    // Remove any non-digit characters from phone number
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    final encodedMsg = Uri.encodeComponent(message);
    return Uri.parse('$baseUrl/$cleanPhone?text=$encodedMsg');
  }

  /// Build WhatsApp link for direct message
  static Uri getWhatsAppDirectLink(String phoneNumber) {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    return Uri.parse('$baseUrl/$cleanPhone');
  }
}

class GoogleMapsConfig {
  /// Google Maps Web Search base URL
  static const String mapsSearchBase = 'https://www.google.com/maps/search/';

  /// Build Google Maps search URL
  static Uri getMapsSearchUri(String query) {
    final encodedQuery = Uri.encodeComponent(query);
    return Uri.parse('$mapsSearchBase?api=1&query=$encodedQuery');
  }

  /// Build Google Maps embed URL for a location
  static Uri getMapsEmbedUri(String location) {
    final encodedLocation = Uri.encodeComponent(location);
    return Uri.parse('https://maps.google.com/?q=$encodedLocation');
  }

  /// No API key required for basic search links
  static const bool requiresApiKey = false;
}

/// Central registry of all external API configurations
/// Provides easy access to all third-party service endpoints
class ExternalApisRegistry {
  /// Get all configured external APIs
  static Map<String, Map<String, String>> getRegistry() => {
        'exchangeRate': {
          'baseUrl': ExchangeRateConfig.baseUrl,
          'requiresApiKey': 'false',
          'status': 'configured',
        },
        'weather': {
          'baseUrl': WeatherConfig.baseUrl,
          'requiresApiKey': 'true',
          'status': 'configured',
        },
        'whatsapp': {
          'baseUrl': WhatsAppConfig.baseUrl,
          'requiresApiKey': 'false',
          'status': 'configured',
        },
        'googleMaps': {
          'baseUrl': GoogleMapsConfig.mapsSearchBase,
          'requiresApiKey': 'false',
          'status': 'configured',
        },
      };

  /// Check if an external API is configured
  static bool isConfigured(String apiName) {
    final registry = getRegistry();
    return registry.containsKey(apiName) &&
        registry[apiName]!['status'] == 'configured';
  }
}
