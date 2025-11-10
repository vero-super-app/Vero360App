import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_config.dart';

class AccountService {
  /// Public method: change password for the *current* user (no id required in UI).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      throw Exception('No auth token found. Please log in again.');
    }

    final base = await ApiConfig.prod;
    final headers = {
      'Accept': '*/*', // match your working cURL
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = jsonEncode({
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });

    // 1) Try /users/me/password if backend supports it
    final meUri = Uri.parse('$base/users/me/password');
    final meRes = await http.put(meUri, headers: headers, body: body);

    if (meRes.statusCode == 200 || meRes.statusCode == 204) {
      return; // success
    }

    // If endpoint not found/allowed, fallback to id route
    if (meRes.statusCode == 404 || meRes.statusCode == 405) {
      final userId = await _resolveUserId(token, base, headers);
      final idUri = Uri.parse('$base/users/$userId/password');
      final idRes = await http.put(idUri, headers: headers, body: body);
      if (idRes.statusCode == 200 || idRes.statusCode == 204) {
        return; // success
      }
      _throwFor(idRes);
    }

    // If backend returned another error on /users/me/password, surface it
    _throwFor(meRes);
  }

  // ---------- helpers ----------

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }

  Future<int> _resolveUserId(String token, String base, Map<String, String> headers) async {
    final prefs = await SharedPreferences.getInstance();

    // a) cached id?
    final cached = prefs.getInt('user_id');
    if (cached != null && cached > 0) return cached;

    // b) decode JWT sub
    final fromJwt = _jwtSub(token);
    if (fromJwt != null && fromJwt > 0) {
      await prefs.setInt('user_id', fromJwt);
      return fromJwt;
    }

    // c) fallback GET /users/me
    final res = await http.get(Uri.parse('$base/users/me'), headers: headers);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final id = (data is Map && data['id'] != null)
          ? int.tryParse(data['id'].toString())
          : null;
      if (id != null) {
        await prefs.setInt('user_id', id);
        return id;
      }
    }

    throw Exception('Could not resolve current user id.');
  }

  int? _jwtSub(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = _base64UrlDecode(parts[1]);
      final map = jsonDecode(utf8.decode(payload));
      final sub = map['sub'];
      if (sub is int) return sub;
      if (sub is String) return int.tryParse(sub);
      return null;
    } catch (_) {
      return null;
    }
  }

  Uint8List _base64UrlDecode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (s.length % 4) {
      case 2: s += '=='; break;
      case 3: s += '='; break;
    }
    return base64.decode(s);
  }

  Never _throwFor(http.Response res) {
    String msg;
    try {
      final parsed = jsonDecode(res.body);
      if (parsed is Map) {
        msg = (parsed['message'] ?? parsed['error'] ?? res.body).toString();
      } else if (parsed is List && parsed.isNotEmpty) {
        msg = parsed.first.toString();
      } else {
        msg = res.body;
      }
    } catch (_) {
      msg = res.body;
    }
    throw Exception('HTTP ${res.statusCode}: $msg');
  }
}
