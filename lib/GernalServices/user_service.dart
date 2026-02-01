import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/api_config.dart';

class UserService {
  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }

  Future<String> _base() => ApiConfig.readBase();

  String _pretty(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] != null) return j['message'].toString();
      if (j is Map && j['error'] != null) return j['error'].toString();
      if (j is List && j.isNotEmpty) return j.first.toString();
    } catch (_) {}
    return body;
  }

  Future<Map<String, dynamic>> getMe() async {
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      throw Exception('No auth token found (please log in).');
    }

    final url = Uri.parse('${await _base()}/vero/users/me');
    final res = await http.get(url, headers: {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    });

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
