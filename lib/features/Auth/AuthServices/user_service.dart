import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

class UserService {
  String _pretty(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] != null) return j['message'].toString();
      if (j is Map && j['error'] != null) return j['error'].toString();
      if (j is List && j.isNotEmpty) return j.first.toString();
    } catch (_) {}
    return body;
  }

  /// Calls NestJS /vero/users/me with the Firebase ID token in Authorization header.
  Future<Map<String, dynamic>> getMe() async {
    var token = await AuthHandler.getFirebaseToken();
    if (token == null || token.isEmpty) {
      throw Exception('No Firebase token found (please log in).');
    }

    final url = ApiConfig.endpoint('/users/me');
    Future<http.Response> once(String bearer) => http.get(
          url,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $bearer',
          },
        );

    var res = await once(token);
    if (res.statusCode == 401 || res.statusCode == 403) {
      final refreshed = await AuthHandler.refreshTokenAfterUnauthorized();
      if (refreshed != null && refreshed.isNotEmpty) {
        token = refreshed;
        res = await once(token);
      }
    }

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data is Map<String, dynamic>
          ? data
          : <String, dynamic>{'raw': data};
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('Session expired. Please log in again.');
    }
    throw Exception('Failed: ${_pretty(res.body)}');
  }
}