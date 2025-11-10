// lib/services/hostel_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:vero360_app/models/Latest_model.dart';


class LatestArrivalServices {
  String _localHost() {
    if (kIsWeb) return 'localhost'; // Flutter web
    if (defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2'; // Android emulator -> host machine
    }
    return '127.0.0.1'; // iOS sim / desktop
  }

  Uri _allUri() => Uri.parse('https://unimatherapyapplication.com/vero/latestarrivals');

  Future<List<LatestArrivalModels>> fetchLatestArrivals() async {
    try {
      final response = await http
          .get(_allUri(), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'GET /latestarrivals failed: ${response.statusCode} ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);

      // Accept either `[{...}, ...]` or `{"data":[{...}]}`.
      final List list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List)
              ? decoded['data'] as List
              : <dynamic>[];

      return list
          .whereType<Map<String, dynamic>>()
          .map<LatestArrivalModels>((m) => LatestArrivalModels.fromJson(m))
          .toList();
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } on http.ClientException catch (e) {
      throw Exception('Network error: $e');
    } catch (e) {
      throw Exception('Unexpected error: $e');
    }
  }
}
