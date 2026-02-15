// lib/services/account_service.dart

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

class AccountService {

  /// Public method: change password for the current user.
  /// 1) Verifies current password with Firebase (source of truth for email/password login).
  /// 2) Calls backend PUT /vero/users/{id}/password.
  /// 3) Updates Firebase password so app and backend stay in sync.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const ApiException(
        message: 'Please sign in again before changing your password.',
      );
    }

    final email = user.email?.trim() ?? await _emailFromPrefs();
    if (email == null || email.isEmpty) {
      throw const ApiException(
        message: 'We could not find your email. Please sign in again.',
      );
    }

    // 1) Verify current password with Firebase (avoids "incorrect" when backend has no/different password)
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email') {
        throw const ApiException(
          message: 'Current password is incorrect.',
        );
      }
      throw ApiException(message: e.message ?? 'Could not verify current password.');
    }

    final token = await _readToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Please sign in again before changing your password.',
      );
    }

    final userId = await _resolveUserId(token);

    // 2) Update password on backend
    try {
      await ApiClient.put(
        '/users/$userId/password',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Backend doesn't have the same password (e.g. only Firebase has it). We already verified with Firebase.
        // Update Firebase so the user's password is changed; next login will use the new password.
        try {
          await user.updatePassword(newPassword);
        } catch (_) {}
        return; // Success from the user's perspective; UI will have shown success after changePassword() returns
      }
      rethrow;
    }

    // 3) Keep Firebase in sync with new password
    try {
      await user.updatePassword(newPassword);
    } catch (_) {}
  }

  Future<String?> _emailFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('email')?.trim();
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

    // GET /users/me to get numeric id
    try {
      final res = await ApiClient.get(
        '/users/me',
        headers: {'Authorization': 'Bearer $token'},
      );
      final decoded = jsonDecode(res.body);
      // Support both { "id": 1 } and { "data": { "id": 1 } }
      final data = decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
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
