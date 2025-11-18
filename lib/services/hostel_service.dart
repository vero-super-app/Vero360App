// lib/services/hostel_service.dart

import 'dart:convert';

import 'package:vero360_app/models/hostel_model.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';

class AccommodationService {

  Future<List<Accommodation>> fetchAll() async {
    try {
      final res = await ApiClient.get('/accommodations/all');

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw const ApiException(
            message: 'Unexpected response format from server.');
      }

      return decoded
          .map<Accommodation>((e) =>
              Accommodation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        message: 'Unable to load accommodations. Please try again.',
      );
    }
  }
}
