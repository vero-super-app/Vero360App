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

  static const intendedRoleKey = 'session_intended_role';
  static const intendedServiceKey = 'session_intended_merchant_service';
  static const intendedUidKey = 'session_intended_uid';

  static String? readToken(SharedPreferences prefs) =>
      prefs.getString('jwt_token') ??
      prefs.getString('token') ??
      prefs.getString('authToken');

  static String readCachedRole(SharedPreferences prefs) =>
      RoleHelper.normalizeAccountRole(
        prefs.getString('user_role') ?? prefs.getString('role'),
      ) ??
      '';

  static Future<void> clearRoleKeys(SharedPreferences prefs) async {
    await prefs.remove('user_role');
    await prefs.remove('role');
    await prefs.remove('is_merchant');
    await prefs.remove('merchant_service');
    await prefs.remove('business_name');
    await prefs.remove('business_address');
    await prefs.remove(intendedRoleKey);
    await prefs.remove(intendedServiceKey);
    await prefs.remove(intendedUidKey);
  }

  /// Remember the role the user just chose this session (signup), scoped to uid.
  static Future<void> lockIntendedRole({
    required SharedPreferences prefs,
    required String role,
    String? merchantService,
    String? uid,
  }) async {
    final r = RoleHelper.normalizeAccountRole(role) ?? RoleHelper.customer;
    await prefs.setString(intendedRoleKey, r);
    final service = normalizeMerchantServiceKey(merchantService);
    if (r == RoleHelper.merchant && service != null && service.isNotEmpty) {
      await prefs.setString(intendedServiceKey, service);
    } else {
      await prefs.remove(intendedServiceKey);
    }
    final id = (uid ?? '').trim();
    if (id.isNotEmpty) {
      await prefs.setString(intendedUidKey, id);
    }
  }

  static Future<RoleSyncResult?> syncFromServer({
    required SharedPreferences prefs,
    required String token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final fetched = await _fetchCurrentUser(token, timeout);
    if (fetched.isUnauthorized) {
      return const RoleSyncResult.unauthorized();
    }

    final user = fetched.user;
    if (user == null || user.isEmpty) {
      return null;
    }

    var backendRole = RoleHelper.roleFromUserMap(user);
    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final intendedRole = RoleHelper.normalizeAccountRole(
      prefs.getString(intendedRoleKey),
    );
    final intendedUid = (prefs.getString(intendedUidKey) ?? '').trim();
    final intendedMatchesThisUser =
        intendedRole != null &&
        intendedRole != RoleHelper.customer &&
        fbUid.isNotEmpty &&
        intendedUid == fbUid;

    // Signup race only: this uid just registered as driver/merchant, API still
    // returns customer. Retry PUT. Never copy a *previous* account's prefs.
    if (intendedMatchesThisUser && backendRole == RoleHelper.customer) {
      await _putRoleToBackend(token, intendedRole, timeout);
      if (intendedRole == RoleHelper.merchant) {
        final service = prefs.getString(intendedServiceKey);
        if (service != null && service.isNotEmpty) {
          try {
            await http
                .put(
                  ApiConfig.endpoint('/users/me'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                  },
                  body: json.encode({'merchantService': service}),
                )
                .timeout(timeout);
          } catch (_) {}
        }
      }
      final refreshed = await _fetchCurrentUser(token, timeout);
      final resolved = Map<String, dynamic>.from(refreshed.user ?? user);
      if (RoleHelper.roleFromUserMap(resolved) == RoleHelper.customer) {
        resolved['role'] = intendedRole;
      }
      if (intendedRole == RoleHelper.merchant &&
          (resolved['merchantService'] == null ||
              resolved['merchantService'].toString().trim().isEmpty)) {
        final service = prefs.getString(intendedServiceKey);
        if (service != null && service.isNotEmpty) {
          resolved['merchantService'] = service;
        }
      }
      await persistUserToPrefs(prefs, resolved);
      return RoleSyncResult.user(resolved);
    }

    // Firestore is a backup if API role is missing/customer but this uid is
    // already a driver/merchant there — still never use leftover prefs.
    if (backendRole == RoleHelper.customer) {
      final firestoreRole = RoleHelper.normalizeAccountRole(
        await _getRoleFromFirestore(),
      );
      if (firestoreRole != null &&
          firestoreRole != RoleHelper.customer &&
          (intendedMatchesThisUser || fbUid.isNotEmpty)) {
        final corrected = Map<String, dynamic>.from(user)..['role'] = firestoreRole;
        await persistUserToPrefs(prefs, corrected);
        return RoleSyncResult.user(corrected);
      }
    }

    await persistUserToPrefs(prefs, user);
    return RoleSyncResult.user(user);
  }

  static Future<void> persistUserToPrefs(
    SharedPreferences prefs,
    Map<String, dynamic> user, {
    bool resolveMerchantVertical = true,
  }) async {
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

    final uid = (user['uid'] ?? user['firebaseUid'] ?? user['id'] ?? '')
        .toString()
        .trim();
    if (uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }

    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final lookupUid = fbUid.isNotEmpty ? fbUid : uid;

    final role = RoleHelper.roleFromUserMap(user);
    await prefs.setString('user_role', role);
    await prefs.setString('role', role);
    await prefs.setBool('is_merchant', role == RoleHelper.merchant);

    if (role == RoleHelper.merchant) {
      final intendedUid = (prefs.getString(intendedUidKey) ?? '').trim();
      final intendedService =
          (lookupUid.isNotEmpty && intendedUid == lookupUid)
              ? normalizeMerchantServiceKey(prefs.getString(intendedServiceKey))
              : null;
      var service = intendedService ??
          normalizeMerchantServiceKey(
            user['merchantService']?.toString() ??
                user['serviceType']?.toString() ??
                user['merchant_service']?.toString(),
          );
      if (resolveMerchantVertical &&
          lookupUid.isNotEmpty &&
          (service == null ||
              service.isEmpty ||
              service == 'marketplace')) {
        final discovered = await resolveMerchantServiceForUid(lookupUid);
        if (discovered != null &&
            discovered.isNotEmpty &&
            (service == null ||
                service.isEmpty ||
                (service == 'marketplace' && discovered != 'marketplace'))) {
          service = discovered;
        }
      }
      if (service != null && service.isNotEmpty) {
        await persistMerchantServiceFromApi(prefs, service);
      }
    } else {
      await prefs.remove('merchant_service');
      await prefs.remove('business_name');
      await prefs.remove('business_address');
    }
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
        return RoleHelper.roleFromUserMap(doc.data()!);
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
