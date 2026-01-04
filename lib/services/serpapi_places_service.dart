import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/models/place_prediction_model.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/config/serpapi_config.dart';

/// SerpAPI Places Search Service
/// 
/// Uses SerpAPI to search Google Maps for places with autocomplete support
class SerpapiPlacesService {
  static const Duration _timeout = Duration(seconds: 8);

  late final String _apiKey;

  SerpapiPlacesService({String? apiKey}) {
    _apiKey = apiKey ?? SerpapiConfig.apiKey;
    if (_apiKey.isEmpty) {
      throw const ApiException(
        message: 'SerpAPI key not configured. '
            'Run: flutter run --dart-define=SERPAPI_API_KEY=your_key',
      );
    }
    if (kDebugMode) {
      debugPrint('[SerpAPI] Service initialized with key: ${_apiKey.substring(0, 10)}...');
    }
  }

  /// Search for places using SerpAPI Google Maps search
  ///
  /// [query] - The search query (e.g., "Blantyre", "Lilongwe")
  /// [latitude] - Optional latitude for location bias
  /// [longitude] - Optional longitude for location bias
  /// 
  /// Returns a list of [PlacePrediction] objects
  /// Throws [ApiException] on error
  Future<List<PlacePrediction>> searchPlaces(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    // Require at least 4 characters for search
    if (query.length < 4) {
      return [];
    }

    try {
      // For search, use q parameter without type=place
      // type=place is only for detailed place lookups with data/place_id
      final queryParams = {
        'engine': 'google_maps',
        'q': query,
        'type': 'search', // Use search type for autocomplete
        'gl': 'mw', // Malawi
        'api_key': _apiKey,
      };

      // Add location bias if provided
      if (latitude != null && longitude != null) {
        queryParams['ll'] = '$latitude,$longitude';
      }

      final Uri uri = Uri.parse(SerpapiConfig.baseUrl).replace(
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint('[SerpAPI] Searching: $query');
        debugPrint('[SerpAPI] URL: $uri');
      }

      final response = await http.get(uri).timeout(_timeout);

      if (kDebugMode) {
        debugPrint('[SerpAPI] Status: ${response.statusCode}');
        debugPrint('[SerpAPI] Response: ${response.body}');
      }

      if (response.statusCode != 200) {
        throw ApiException(
          message: 'HTTP ${response.statusCode}: Failed to fetch place results',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

      // Check for search results
      final localResults = jsonResponse['local_results'] as List<dynamic>?;
      if (localResults == null || localResults.isEmpty) {
        if (kDebugMode) {
          debugPrint('[SerpAPI] No local results found');
        }
        return [];
      }

      if (kDebugMode) {
        debugPrint('[SerpAPI] Found ${localResults.length} results');
      }

      final predictions = <PlacePrediction>[];
      for (final result in localResults) {
        try {
          final resultMap = result as Map<String, dynamic>;
          final title = resultMap['title'] as String? ?? '';
          final address = resultMap['address'] as String? ?? '';
          final dataId = resultMap['data_id'] as String? ?? '';

          if (title.isNotEmpty && dataId.isNotEmpty) {
            // Handle type as either List or String
            List<dynamic> types = [];
            final typeValue = resultMap['type'];
            if (typeValue is List) {
              types = typeValue;
            } else if (typeValue is String) {
              types = [typeValue];
            }

            // Extract coordinates if available
            double? latitude;
            double? longitude;
            final gpsCoordinates = resultMap['gps_coordinates'] as Map<String, dynamic>?;
            if (gpsCoordinates != null) {
              latitude = (gpsCoordinates['latitude'] as num?)?.toDouble();
              longitude = (gpsCoordinates['longitude'] as num?)?.toDouble();
            }

            final prediction = PlacePrediction(
              placeId: dataId,
              mainText: title,
              secondaryText: address.isNotEmpty ? address : 'Location',
              fullText: address.isNotEmpty ? '$title, $address' : title,
              types: types,
              latitude: latitude,
              longitude: longitude,
            );
            predictions.add(prediction);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[SerpAPI] Error parsing result: $e');
          }
        }
      }

      return predictions;
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SerpAPI] Error: $e');
      }
      throw ApiException(
        message: 'Error searching places: ${e.toString()}',
      );
    }
  }

  /// Get detailed information about a place using its data_id
  ///
  /// [dataId] - The SerpAPI data_id from search results
  /// Format: !4m5!3m4!1s{data_id}!8m2!3d{latitude}!4d{longitude}
  /// 
  /// Returns a map with place details including gps_coordinates
  Future<Map<String, dynamic>> getPlaceDetails(String dataId) async {
    try {
      // For place details, we need the properly formatted data parameter
      // Data format: !4m5!3m4!1s + data_id + !8m2!3d + latitude + !4d + longitude
      final queryParams = {
        'engine': 'google_maps',
        'type': 'place',
        'data': dataId,
        'api_key': _apiKey,
      };

      final Uri uri = Uri.parse(SerpapiConfig.baseUrl).replace(
        queryParameters: queryParams,
      );

      if (kDebugMode) {
        debugPrint('[SerpAPI] Getting place details for: $dataId');
        debugPrint('[SerpAPI] Details URL: $uri');
      }

      final response = await http.get(uri).timeout(_timeout);

      if (kDebugMode) {
        debugPrint('[SerpAPI] Details Status: ${response.statusCode}');
      }

      if (response.statusCode != 200) {
        final errorResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final error = errorResponse['error'] as String?;
        if (kDebugMode) {
          debugPrint('[SerpAPI] Details Error: $error');
        }
        throw ApiException(
          message: 'Failed to fetch place details: $error',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final placeResults = jsonResponse['place_results'] as Map<String, dynamic>?;

      if (placeResults == null) {
        throw const ApiException(message: 'No place details found');
      }

      if (kDebugMode) {
        debugPrint('[SerpAPI] Got place details: ${placeResults['title']}');
      }

      return placeResults;
    } on ApiException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SerpAPI] Error fetching place details: $e');
      }
      throw ApiException(
        message: 'Error fetching place details: ${e.toString()}',
      );
    }
  }
}
