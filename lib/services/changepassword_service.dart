// lib/services/account_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';

class AccountService {

  /// Public method: change password for the current user
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Please sign in again before changing your password.',
      );
    }

    // Try /users/me/password
    try {
      await ApiClient.put(
        '/users/me/password',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );
      return;
    } on ApiException catch (e) {
      // if endpoint doesn’t exist → use fallback route
      if (e.statusCode == 404 || e.statusCode == 405) {
        final userId = await _resolveUserId(token);
        await ApiClient.put(
          '/users/$userId/password',
          headers: {'Authorization': 'Bearer $token'},
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
          }),
        );
        return;
      }
      rethrow; // user-friendly message already
    }
  }

  // ---------- helpers ----------

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ??
           prefs.getString('jwt_token') ??
           prefs.getString('jwt');
  }

  Future<int> _resolveUserId(String token) async {
    final prefs = await SharedPreferences.getInstance();

    // cached ID?
    final cached = prefs.getInt('user_id');
    if (cached != null && cached > 0) return cached;

    // Try /users/me
    try {
      final res = await ApiClient.get(
        '/users/me',
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      final id = int.tryParse(data['id']?.toString() ?? '');
      if (id != null && id > 0) {
        await prefs.setInt('user_id', id);
        return id;
      }
    } catch (_) {}

    throw const ApiException(
      message: 'Could not determine your account information. Please sign in again.',
    );
  }
}
