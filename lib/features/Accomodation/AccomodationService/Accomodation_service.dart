import 'dart:convert';

import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class AccommodationService {
  Future<List<Accommodation>> fetch({
    String? type,      // hotel, lodge, bnb, house, hostel
    String? location,  // free text, sent to /by-location
  }) async {
    try {
      String path = '/accommodations/all';
      Map<String, String>? query;

      if (location != null && location.trim().isNotEmpty) {
        // District / location search
        path = '/accommodations/by-location';
        query = {'location': location.trim()};
      } else if (type != null &&
          type.isNotEmpty &&
          type.toLowerCase() != 'all') {
        // Filter by accommodation type ('hostel', 'hotel', etc.)
        path = '/accommodations';
        query = {'type': type.toLowerCase()};
      }

      final res = await ApiClient.get(
        path,
        queryParameters: query,
      );
      final decoded = jsonDecode(res.body);

      if (decoded is! List) {
        throw const ApiException(
          message: 'Unexpected response format from server.',
        );
      }

      return decoded
          .map<Accommodation>(
            (e) => Accommodation.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Unable to load accommodations. Please try again.',
      );
    }
  }

  // Optional compatibility method
  Future<List<Accommodation>> fetchAll() => fetch();
}