import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/place_prediction_model.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/config/google_maps_config.dart';

/// Google Places Autocomplete / Details / resolve service.
class GooglePlacesService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';
  static const String _geocodeUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const Duration _timeout = Duration(seconds: 10);

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
      debugPrint(
        '[GooglePlaces] Service initialized with key: ${_apiKey.substring(0, 10)}...',
      );
    }
  }

  Future<List<PlacePrediction>> autocompleteSearch(String input) async {
    if (input.isEmpty) return [];

    try {
      final uri = Uri.parse('$_baseUrl/autocomplete/json').replace(
        queryParameters: {
          'input': input,
          'key': _apiKey,
          'language': 'en',
          'components': 'country:mw',
          'region': 'mw',
        },
      );

      if (kDebugMode) {
        debugPrint('[GooglePlaces] Searching: $input');
      }

      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw ApiException(
          message:
              'HTTP ${response.statusCode}: Failed to fetch place predictions',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final status = jsonResponse['status'] as String? ?? '';

      if (status == 'ZERO_RESULTS') return [];
      if (status != 'OK') {
        final errorMsg =
            jsonResponse['error_message'] as String? ?? 'Unknown error';
        if (status == 'REQUEST_DENIED') {
          throw ApiException(
            message: 'Google Maps billing not enabled. '
                'Enable billing at: https://console.cloud.google.com/project/_/billing/enable',
          );
        }
        throw ApiException(message: 'API Error [$status]: $errorMsg');
      }

      final predictions = (jsonResponse['predictions'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];

      return predictions.map(PlacePrediction.fromJson).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        message: 'Error fetching place predictions: ${e.toString()}',
      );
    }
  }

  Future<Map<String, dynamic>> getPlaceDetails(String placeId) async {
    try {
      final uri = Uri.parse('$_baseUrl/details/json').replace(
        queryParameters: {
          'place_id': placeId,
          'key': _apiKey,
          'fields': 'place_id,formatted_address,geometry,name',
          'language': 'en',
        },
      );

      if (kDebugMode) {
        debugPrint('[GooglePlaces] Details for: $placeId');
      }

      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw ApiException(
          message: 'Failed to fetch place details',
          statusCode: response.statusCode,
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final status = jsonResponse['status'] as String? ?? '';

      if (kDebugMode) {
        debugPrint('[GooglePlaces] Details API status: $status');
        debugPrint('[GooglePlaces] Details body: ${response.body}');
      }

      if (status != 'OK') {
        final errorMsg =
            jsonResponse['error_message'] as String? ?? 'Unknown error';
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

  /// Resolve autocomplete prediction → [Place] with coordinates.
  /// Tries several backends so selection still works when Details is flaky.
  Future<Place> resolvePrediction(PlacePrediction prediction) async {
    final placeId = prediction.placeId.trim();
    final errors = <String>[];

    // 1) Direct Google Place Details
    if (placeId.isNotEmpty) {
      try {
        final details = await getPlaceDetails(placeId);
        final place = _placeFromDetails(details, prediction);
        if (place != null) {
          if (kDebugMode) {
            debugPrint(
              '[GooglePlaces] Resolved via Details: ${place.latitude},${place.longitude}',
            );
          }
          return place;
        }
        errors.add('Details returned no geometry');
      } catch (e) {
        errors.add('Details: $e');
        if (kDebugMode) debugPrint('[GooglePlaces] Details failed: $e');
      }
    }

    // 2) Backend Places Details proxy (public route)
    if (placeId.isNotEmpty) {
      try {
        final details = await _detailsViaBackend(placeId);
        final place = _placeFromDetails(details, prediction);
        if (place != null) {
          if (kDebugMode) {
            debugPrint(
              '[GooglePlaces] Resolved via backend: ${place.latitude},${place.longitude}',
            );
          }
          return place;
        }
        errors.add('Backend details returned no geometry');
      } catch (e) {
        errors.add('Backend: $e');
        if (kDebugMode) debugPrint('[GooglePlaces] Backend details failed: $e');
      }
    }

    // 3) Find Place From Text (Places API — same product as Autocomplete)
    final textQueries = _candidateQueries(prediction);
    for (final query in textQueries) {
      try {
        final place = await _findPlaceFromText(query, prediction);
        if (place != null) {
          if (kDebugMode) {
            debugPrint(
              '[GooglePlaces] Resolved via FindPlace: ${place.latitude},${place.longitude}',
            );
          }
          return place;
        }
      } catch (e) {
        errors.add('FindPlace($query): $e');
        if (kDebugMode) {
          debugPrint('[GooglePlaces] FindPlace failed for "$query": $e');
        }
      }
    }

    // 4) Google Geocoding HTTP API
    for (final query in textQueries) {
      try {
        final place = await _geocodeHttp(query, prediction);
        if (place != null) {
          if (kDebugMode) {
            debugPrint(
              '[GooglePlaces] Resolved via Geocode API: ${place.latitude},${place.longitude}',
            );
          }
          return place;
        }
      } catch (e) {
        errors.add('GeocodeAPI($query): $e');
        if (kDebugMode) {
          debugPrint('[GooglePlaces] Geocode API failed for "$query": $e');
        }
      }
    }

    // 5) Platform geocoding (last resort, short timeout)
    for (final query in textQueries) {
      try {
        final locations = await locationFromAddress(query)
            .timeout(const Duration(seconds: 6));
        if (locations.isEmpty) continue;
        final loc = locations.first;
        return Place(
          id: placeId.isNotEmpty
              ? placeId
              : 'geo_${loc.latitude}_${loc.longitude}',
          name: prediction.mainText.isNotEmpty
              ? prediction.mainText
              : query.split(',').first.trim(),
          address: prediction.fullText.isNotEmpty ? prediction.fullText : query,
          latitude: loc.latitude,
          longitude: loc.longitude,
          type: PlaceType.RECENT,
        );
      } catch (e) {
        errors.add('PlatformGeocode($query): $e');
        if (kDebugMode) {
          debugPrint('[GooglePlaces] Platform geocode failed for "$query": $e');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('[GooglePlaces] All resolve paths failed: $errors');
    }

    throw ApiException(
      message:
          'Could not resolve coordinates for this place. ${errors.isNotEmpty ? errors.first : ''}',
    );
  }

  List<String> _candidateQueries(PlacePrediction prediction) {
    final full = prediction.fullText.trim();
    final main = prediction.mainText.trim();
    final secondary = prediction.secondaryText.trim();
    final queries = <String>[
      if (full.isNotEmpty) full,
      if (full.isNotEmpty && !full.toLowerCase().contains('malawi'))
        '$full, Malawi',
      if (main.isNotEmpty && secondary.isNotEmpty) '$main, $secondary',
      if (main.isNotEmpty) main,
      if (main.isNotEmpty) '$main, Malawi',
    ];
    // Deduplicate while preserving order
    final seen = <String>{};
    return queries.where((q) => seen.add(q.toLowerCase())).toList();
  }

  Place? _placeFromDetails(
    Map<String, dynamic>? details,
    PlacePrediction prediction,
  ) {
    if (details == null || details.isEmpty) return null;
    final coords = extractLatLng(details);
    if (coords == null) return null;

    final name = (details['name'] as String?)?.trim();
    final address = (details['formatted_address'] as String?)?.trim();
    final id = (details['place_id'] as String?)?.trim();

    return Place(
      id: (id != null && id.isNotEmpty)
          ? id
          : (prediction.placeId.isNotEmpty
              ? prediction.placeId
              : 'place_${coords.$1}_${coords.$2}'),
      name: (name != null && name.isNotEmpty) ? name : prediction.mainText,
      address: (address != null && address.isNotEmpty)
          ? address
          : prediction.fullText,
      latitude: coords.$1,
      longitude: coords.$2,
      type: PlaceType.RECENT,
    );
  }

  Future<Map<String, dynamic>?> _detailsViaBackend(String placeId) async {
    await ApiConfig.init();
    final encoded = Uri.encodeComponent(placeId);
    final uri = ApiConfig.endpoint('addresses/places/details/$encoded');

    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException(
        message: 'Backend details HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      if (data['result'] is Map) {
        return _asMap(data['result']);
      }
      if (data['status'] == 'OK' && data['result'] is Map) {
        return _asMap(data['result']);
      }
      // Some proxies return the Google payload directly
      if (data.containsKey('geometry') || data.containsKey('formatted_address')) {
        return data;
      }
      final nested = _asMap(data['data']);
      if (nested != null) {
        return _asMap(nested['result']) ?? nested;
      }
    }
    return null;
  }

  Future<Place?> _findPlaceFromText(
    String query,
    PlacePrediction prediction,
  ) async {
    final uri = Uri.parse('$_baseUrl/findplacefromtext/json').replace(
      queryParameters: {
        'input': query,
        'inputtype': 'textquery',
        'fields': 'place_id,formatted_address,geometry,name',
        'locationbias': 'circle:80000:-13.9626,33.7741',
        'key': _apiKey,
        'language': 'en',
      },
    );

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    final status = jsonResponse['status'] as String? ?? '';
    if (status != 'OK') {
      if (kDebugMode) {
        debugPrint('[GooglePlaces] FindPlace status=$status body=${response.body}');
      }
      return null;
    }

    final candidates = jsonResponse['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) return null;
    return _placeFromDetails(_asMap(candidates.first), prediction);
  }

  Future<Place?> _geocodeHttp(
    String query,
    PlacePrediction prediction,
  ) async {
    final uri = Uri.parse(_geocodeUrl).replace(
      queryParameters: {
        'address': query,
        'components': 'country:MW',
        'region': 'mw',
        'key': _apiKey,
        'language': 'en',
      },
    );

    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    final status = jsonResponse['status'] as String? ?? '';
    if (status != 'OK') {
      if (kDebugMode) {
        debugPrint('[GooglePlaces] Geocode status=$status');
      }
      return null;
    }

    final results = jsonResponse['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) return null;
    return _placeFromDetails(_asMap(results.first), prediction);
  }

  static (double, double)? extractLatLng(Map<String, dynamic> details) {
    final geometry = _asMap(details['geometry']);
    final location =
        _asMap(geometry?['location']) ?? _asMap(details['location']);
    if (location == null) return null;

    final lat = _asDouble(location['lat'] ?? location['latitude']);
    final lng = _asDouble(location['lng'] ?? location['longitude']);
    if (lat == null || lng == null) return null;
    if (lat.abs() < 0.000001 && lng.abs() < 0.000001) return null;
    return (lat, lng);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
