import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GeneralModels/place_prediction_model.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/config/google_maps_config.dart';

/// Google Places Autocomplete API Service
/// 
/// This service handles autocomplete search requests to Google Places API
/// for global place searches
class GooglePlacesService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';
  static const Duration _timeout = Duration(seconds: 8);

  late final String _apiKey;

  GooglePlacesService({String? apiKey}) {
    _apiKey = apiKey ?? GoogleMapsConfig.apiKey;
    if (_apiKey.isEmpty) {
      throw const ApiException(
        message: 'Google Maps API key not configured. '
            'Run: flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key',
      );
    }
    if (kDebugMode) {
      debugPrint('[GooglePlaces] Service initialized with key: ${_apiKey.substring(0, 10)}...');
    }
  }

  /// Search for places using Google Places Autocomplete API
  ///
  /// [input] - The search query (minimum 1 character)
  /// 
  /// Returns a list of [PlacePrediction] objects
  /// Throws [ApiException] on error
  Future<List<PlacePrediction>> autocompleteSearch(String input) async {
    if (input.isEmpty) {
      return [];
    }

    try {
      final queryParams = {
        'input': input,
        'key': _apiKey,
        'language': 'en',
        'components': 'country:mw', // Restrict to Malawi
        'region': 'mw', // Bias results to Malawi
      };

      final Uri uri = Uri.parse('$_baseUrl/autocomplete/json').replace(
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint('[GooglePlaces] Searching: $input');
        debugPrint('[GooglePlaces] URL: $uri');
      }

      final response = await http.get(uri).timeout(_timeout);

      if (kDebugMode) {
        debugPrint('[GooglePlaces] Status: ${response.statusCode}');
        debugPrint('[GooglePlaces] Response: ${response.body}');
      }

      if (response.statusCode != 200) {
        throw ApiException(
          message: 'HTTP ${response.statusCode}: Failed to fetch place predictions',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final status = jsonResponse['status'] as String? ?? '';

      if (kDebugMode) {
        debugPrint('[GooglePlaces] API Status: $status');
      }

      if (status == 'ZERO_RESULTS') {
        return [];
      }

      if (status != 'OK') {
        final errorMsg = jsonResponse['error_message'] as String? ?? 'Unknown error';
        
        // Handle REQUEST_DENIED (billing not enabled)
        if (status == 'REQUEST_DENIED') {
          throw ApiException(
            message: 'Google Maps billing not enabled. '
                'Enable billing at: https://console.cloud.google.com/project/_/billing/enable',
          );
        }
        
        throw ApiException(message: 'API Error [$status]: $errorMsg');
      }

      final predictions = (jsonResponse['predictions'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      if (kDebugMode) {
        debugPrint('[GooglePlaces] Found ${predictions.length} predictions');
      }

      return predictions
          .map((json) => PlacePrediction.fromJson(json))
          .toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GooglePlaces] Error: $e');
      }
      throw ApiException(
        message: 'Error fetching place predictions: ${e.toString()}',
      );
    }
  }

  /// Get place details from a place ID
  ///
  /// [placeId] - The Google Places place ID
  /// 
  /// Returns a map with place details including:
  /// - formatted_address
  /// - geometry (lat/lng)
  /// - address_components
  Future<Map<String, dynamic>> getPlaceDetails(String placeId) async {
    try {
      final Uri uri = Uri.parse('$_baseUrl/details/json').replace(
        queryParameters: {
          'place_id': placeId,
          'key': _apiKey,
          'fields': 'formatted_address,geometry,address_components,name',
          'language': 'en',
        },
      );

      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw ApiException(
          message: 'Failed to fetch place details',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final status = jsonResponse['status'] as String? ?? '';

      if (status != 'OK') {
        final errorMsg = jsonResponse['error_message'] as String? ?? 'Unknown error';
        
        // Handle REQUEST_DENIED (billing not enabled)
        if (status == 'REQUEST_DENIED') {
          throw ApiException(
            message: 'Google Maps billing not enabled. '
                'Enable billing at: https://console.cloud.google.com/project/_/billing/enable',
          );
        }
        
        throw ApiException(message: 'API Error [$status]: $errorMsg');
      }

      return (jsonResponse['result'] as Map<String, dynamic>?) ?? {};
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        message: 'Error fetching place details: ${e.toString()}',
      );
    }
  }
}
