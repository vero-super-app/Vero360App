import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/config/api_config.dart';

class RoleSyncResult {
  final Map<String, dynamic>? user;
  final bool isUnauthorized;

  const RoleSyncResult._({
    this.user,
    this.isUnauthorized = false,
  });

  const RoleSyncResult.user(Map<String, dynamic> user) : this._(user: user);

  const RoleSyncResult.unauthorized() : this._(isUnauthorized: true);

  bool get hasUser => user != null;

  bool get isMerchant => user != null && RoleHelper.isMerchant(user!);

  bool get isDriver => user != null && !isMerchant && RoleHelper.isDriver(user!);

  String get roleKey => isMerchant ? 'merchant' : (isDriver ? 'driver' : 'customer');

  String get email => (user?['email'] ?? '').toString();
}

class RoleSessionService {
  const RoleSessionService._();

  static String? readToken(SharedPreferences prefs) =>
      prefs.getString('jwt_token') ??
      prefs.getString('token') ??
      prefs.getString('authToken');

  static String readCachedRole(SharedPreferences prefs) =>
      (prefs.getString('user_role') ?? prefs.getString('role') ?? '')
          .toLowerCase()
          .trim();

  static Future<RoleSyncResult?> syncFromServer({
    required SharedPreferences prefs,
    required String token,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final fetched = await _fetchCurrentUser(token, timeout);
    if (fetched.isUnauthorized) {
      return const RoleSyncResult.unauthorized();
    }

    final user = fetched.user;
    if (user == null || user.isEmpty) {
      return null;
    }

    final backendRole = (user['role'] ?? '').toString().toLowerCase();
    final cachedRole = readCachedRole(prefs);

    if (cachedRole.isNotEmpty &&
        cachedRole != 'customer' &&
        backendRole == 'customer') {
      return _repairRoleMismatch(
        prefs: prefs,
        token: token,
        correctRole: cachedRole,
        fallbackUser: user,
        timeout: timeout,
      );
    }

    if (backendRole == 'customer') {
      final firestoreRole = await _getRoleFromFirestore();
      if (firestoreRole != null &&
          firestoreRole != 'customer' &&
          firestoreRole != backendRole) {
        return _repairRoleMismatch(
          prefs: prefs,
          token: token,
          correctRole: firestoreRole,
          fallbackUser: user,
          timeout: timeout,
        );
      }
    }

    await persistUserToPrefs(prefs, user);
    return RoleSyncResult.user(user);
  }

  static Future<void> persistUserToPrefs(
    SharedPreferences prefs,
    Map<String, dynamic> user,
  ) async {
    String join(String? a, String? b) {
      final parts = [a, b]
          .where((x) => x != null && x.trim().isNotEmpty)
          .map((x) => x!.trim())
          .toList();
      return parts.isEmpty ? '' : parts.join(' ');
    }

    final name =
        (user['name'] ?? join(user['firstName'], user['lastName'])).toString();
    final email = (user['email'] ?? user['userEmail'] ?? '').toString();
    final phone = (user['phone'] ?? '').toString();
    final pic = (user['profilepicture'] ?? user['profilePicture'] ?? '').toString();

    await prefs.setString('fullName', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('name', name.isEmpty ? 'Guest User' : name);
    await prefs.setString('email', email);
    await prefs.setString('phone', phone);
    await prefs.setString('profilepicture', pic);

    final isMerchant = RoleHelper.isMerchant(user);
    final isDriver = !isMerchant && RoleHelper.isDriver(user);

    if (isMerchant) {
      await prefs.setString('user_role', 'merchant');
      await prefs.setString('role', 'merchant');
      await persistMerchantServiceFromApi(
        prefs,
        user['merchantService']?.toString() ??
            user['serviceType']?.toString() ??
            user['merchant_service']?.toString(),
      );
    } else if (isDriver) {
      await prefs.setString('user_role', 'driver');
      await prefs.setString('role', 'driver');
    } else {
      await prefs.setString('user_role', 'customer');
      await prefs.setString('role', 'customer');
    }
  }

  static Future<RoleSyncResult> _repairRoleMismatch({
    required SharedPreferences prefs,
    required String token,
    required String correctRole,
    required Map<String, dynamic> fallbackUser,
    required Duration timeout,
  }) async {
    final correctedUser = Map<String, dynamic>.from(fallbackUser)
      ..['role'] = correctRole;

    await _putRoleToBackend(token, correctRole, timeout);

    final refreshed = await _fetchCurrentUser(token, timeout);
    final resolvedUser = refreshed.user ?? correctedUser;

    await persistUserToPrefs(prefs, resolvedUser);
    return RoleSyncResult.user(resolvedUser);
  }

  static Future<void> _putRoleToBackend(
    String token,
    String role,
    Duration timeout,
  ) async {
    try {
      await http
          .put(
            ApiConfig.endpoint('/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'role': role}),
          )
          .timeout(timeout);
    } catch (_) {}
  }

  static Future<String?> _getRoleFromFirestore() async {
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) return null;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(fbUser.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['role'] ?? '').toString().toLowerCase();
      }
    } catch (_) {}
    return null;
  }

  static Future<_FetchedUser> _fetchCurrentUser(
    String token,
    Duration timeout,
  ) async {
    try {
      final resp = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return const _FetchedUser(isUnauthorized: true);
      }

      if (resp.statusCode != 200) {
        return const _FetchedUser();
      }

      final decoded = json.decode(resp.body);
      final user = (decoded is Map && decoded['data'] is Map)
          ? Map<String, dynamic>.from(decoded['data'])
          : (decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{});

      return _FetchedUser(user: user);
    } catch (_) {
      return const _FetchedUser();
    }
  }
}

class _FetchedUser {
  final Map<String, dynamic>? user;
  final bool isUnauthorized;

  const _FetchedUser({
    this.user,
    this.isUnauthorized = false,
  });
}
