import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/merchant_identity.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';

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
  static const intendedRoleHeader = 'x-intended-role';

  static String? readToken(SharedPreferences prefs) =>
      prefs.getString('jwt_token') ??
      prefs.getString('token') ??
      prefs.getString('authToken');

  static String readCachedRole(SharedPreferences prefs) =>
      RoleHelper.normalizeAccountRole(
        prefs.getString('user_role') ?? prefs.getString('role'),
      ) ??
      '';

  /// Driver/merchant role the backend should use when inserting a new user row.
  /// Only the role locked for *this* Firebase uid — never leftover prefs.
  static String? intendedRoleForRequest(SharedPreferences prefs) {
    final intendedUid = (prefs.getString(intendedUidKey) ?? '').trim();
    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (intendedUid.isEmpty || fbUid.isEmpty || intendedUid != fbUid) {
      return null;
    }
    final role = RoleHelper.normalizeAccountRole(prefs.getString(intendedRoleKey));
    if (role == RoleHelper.driver || role == RoleHelper.merchant) {
      return role;
    }
    return null;
  }

  static Future<void> applyIntendedRoleHeader(
    Map<String, String> headers, {
    SharedPreferences? prefs,
  }) async {
    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      final role = intendedRoleForRequest(sp);
      if (role != null) {
        headers[intendedRoleHeader] = role;
      }
    } catch (_) {}
  }

  static Future<void> clearRoleKeys(SharedPreferences prefs) async {
    await prefs.remove('user_role');
    await prefs.remove('role');
    await prefs.remove('is_merchant');
    await prefs.remove('merchant_service');
    await prefs.remove('business_name');
    await prefs.remove('business_address');
    await prefs.remove(MerchantIdentityStore.prefsIdentityUidKey);
    await prefs.remove(intendedRoleKey);
    await prefs.remove(intendedServiceKey);
    await prefs.remove(intendedUidKey);
    MerchantIdentityStore.clear();
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
      await MerchantIdentityStore.stamp(
        uid: id,
        role: r,
        service: r == RoleHelper.merchant ? service : null,
        prefs: prefs,
        writeFirestore: true,
      );
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
    // Explicit local choice for *this* uid — including passenger. A Profile
    // toggle must not be undone by a stale /users/me payload or a failed PUT.
    final intendedMatchesThisUser =
        intendedRole != null &&
        fbUid.isNotEmpty &&
        intendedUid == fbUid;

    if (intendedMatchesThisUser && backendRole != intendedRole) {
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
      if (RoleHelper.roleFromUserMap(resolved) != intendedRole) {
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
      final existingRole = RoleHelper.normalizeAccountRole(
        prefs.getString('user_role') ?? prefs.getString('role'),
      );
      final prefsUid = (prefs.getString('uid') ?? '').trim();
      final sameAccount =
          fbUid.isEmpty || prefsUid.isEmpty || prefsUid == fbUid;

      // Keep local merchant/driver sticky when network is weak and API briefly
      // returns the default customer role for this same account.
      if (sameAccount &&
          (existingRole == RoleHelper.merchant ||
              existingRole == RoleHelper.driver)) {
        final sticky = Map<String, dynamic>.from(user)
          ..['role'] = existingRole;
        if (existingRole == RoleHelper.merchant) {
          final service = normalizeMerchantServiceKey(
                prefs.getString('merchant_service'),
              ) ??
              normalizeMerchantServiceKey(prefs.getString(intendedServiceKey));
          if (service != null && service.isNotEmpty) {
            sticky['merchantService'] = service;
          }
        }
        await persistUserToPrefs(prefs, sticky, resolveMerchantVertical: false);
        return RoleSyncResult.user(sticky);
      }

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

    if (name.trim().isNotEmpty) {
      await prefs.setString('fullName', name.trim());
      await prefs.setString('name', name.trim());
    }
    if (email.trim().isNotEmpty) {
      await prefs.setString('email', email.trim());
    }
    if (phone.trim().isNotEmpty) {
      final cleaned = phone.trim();
      final lower = cleaned.toLowerCase();
      final looksLikeFirebaseId = lower.contains('firebase') ||
          lower.contains('firestore') ||
          lower.startsWith('+firebase');
      if (!looksLikeFirebaseId) {
        await prefs.setString('phone', cleaned);
      }
    }
    if (pic.trim().isNotEmpty) {
      await prefs.setString('profilepicture', pic.trim());
    }

    final uid = (user['uid'] ?? user['firebaseUid'] ?? user['id'] ?? '')
        .toString()
        .trim();
    if (uid.isNotEmpty) {
      await prefs.setString('uid', uid);
    }

    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final lookupUid = fbUid.isNotEmpty ? fbUid : uid;

    final incomingRole = RoleHelper.tryRoleFromUserMap(user);
    final existingRole = RoleHelper.normalizeAccountRole(
      prefs.getString('user_role') ?? prefs.getString('role'),
    );
    final prefsUid = (prefs.getString('uid') ?? '').trim();
    final sameAccount =
        lookupUid.isEmpty || prefsUid.isEmpty || prefsUid == lookupUid;
    final intendedRole = RoleHelper.normalizeAccountRole(
      prefs.getString(intendedRoleKey),
    );
    final intendedUid = (prefs.getString(intendedUidKey) ?? '').trim();
    final intendedMatchesThisUser = intendedRole != null &&
        lookupUid.isNotEmpty &&
        intendedUid == lookupUid;

    // 1) Explicit toggle / signup lock for this uid always wins (offline too).
    // 2) Sticky merchant/driver on flaky networks: never demote a known local
    //    merchant/driver to customer just because /users/me omitted role —
    //    unless the user intentionally switched to passenger.
    String role;
    if (intendedMatchesThisUser) {
      role = intendedRole ?? RoleHelper.customer;
    } else if (incomingRole == RoleHelper.customer &&
        sameAccount &&
        (existingRole == RoleHelper.merchant ||
            existingRole == RoleHelper.driver)) {
      role = existingRole!;
    } else {
      role = incomingRole ??
          (sameAccount ? existingRole : null) ??
          RoleHelper.customer;
    }
    await prefs.setString('user_role', role);
    await prefs.setString('role', role);
    await prefs.setBool('is_merchant', role == RoleHelper.merchant);

    if (role == RoleHelper.merchant) {
      final intendedUid = (prefs.getString(intendedUidKey) ?? '').trim();
      final intendedService =
          (lookupUid.isNotEmpty && intendedUid == lookupUid)
              ? normalizeMerchantServiceKey(prefs.getString(intendedServiceKey))
              : null;
      final existingService =
          normalizeMerchantServiceKey(prefs.getString('merchant_service'));
      var service = intendedService ??
          normalizeMerchantServiceKey(
            user['merchantService']?.toString() ??
                user['merchant_service']?.toString(),
          ) ??
          existingService;
      if (!isKnownMerchantServiceKey(service)) service = null;
      if (resolveMerchantVertical &&
          lookupUid.isNotEmpty &&
          !isKnownMerchantServiceKey(service)) {
        try {
          final discovered = await resolveMerchantServiceForUid(lookupUid)
              .timeout(const Duration(seconds: 6));
          if (isKnownMerchantServiceKey(discovered)) {
            service = discovered;
          }
        } catch (_) {
          // Keep cached vertical when discovery times out offline.
          service = existingService;
        }
      }
      // Prefer any known cached vertical over wiping it.
      service ??= existingService;
      if (service != null && service.isNotEmpty) {
        await persistMerchantServiceFromApi(prefs, service);
      } else if (lookupUid.isNotEmpty) {
        await MerchantIdentityStore.stamp(
          uid: lookupUid,
          role: role,
          prefs: prefs,
          writeFirestore: false,
        );
      }
    } else if (role != RoleHelper.merchant) {
      await prefs.remove('merchant_service');
      await prefs.remove('business_name');
      await prefs.remove('business_address');
      if (lookupUid.isNotEmpty) {
        await MerchantIdentityStore.stamp(
          uid: lookupUid,
          role: role,
          prefs: prefs,
          writeFirestore: false,
        );
      }
    }
  }

  static Future<void> persistRoleToFirestore(String role) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'role': role,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Persist a backend user (e.g. after apply-as-driver) and keep Firestore in sync.
  static Future<void> persistPromotedUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    final role = RoleHelper.tryRoleFromUserMap(user) ?? RoleHelper.driver;
    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    await lockIntendedRole(
      prefs: prefs,
      role: role,
      uid: fbUid.isNotEmpty ? fbUid : user['firebaseUid']?.toString(),
    );
    final merged = Map<String, dynamic>.from(user)..['role'] = role;
    await persistUserToPrefs(prefs, merged);
    await persistRoleToFirestore(role);
  }

  /// Switch the active session role (Profile / Settings driver mode switch).
  /// Updates prefs + Firestore, then best-effort PUT `/users/me`.
  /// Writes role keys directly so sticky signup/sync guards do not block
  /// an intentional passenger ↔ driver toggle.
  static Future<bool> setAccountRole(String role) async {
    final normalized =
        RoleHelper.normalizeAccountRole(role) ?? RoleHelper.customer;
    final prefs = await SharedPreferences.getInstance();
    final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    await lockIntendedRole(
      prefs: prefs,
      role: normalized,
      uid: fbUid.isNotEmpty ? fbUid : null,
    );
    await prefs.setString('user_role', normalized);
    await prefs.setString('role', normalized);
    await prefs.setBool('is_merchant', normalized == RoleHelper.merchant);
    if (normalized != RoleHelper.merchant) {
      await prefs.remove('merchant_service');
      await prefs.remove('business_name');
      await prefs.remove('business_address');
    }
    if (fbUid.isNotEmpty) {
      await MerchantIdentityStore.stamp(
        uid: fbUid,
        role: normalized,
        prefs: prefs,
        writeFirestore: false,
      );
    }
    await persistRoleToFirestore(normalized);
    return _putProfileToBackend(role: normalized);
  }

  /// Retries PUT /users/me after signup. Must not depend on a widget being mounted.
  static Future<bool> retryPromoteAccountRole({
    required String role,
    String? name,
    String? email,
    String? phone,
    String? merchantService,
    String? businessName,
    String? businessAddress,
  }) async {
    final delays = [
      const Duration(seconds: 2),
      const Duration(seconds: 5),
      const Duration(seconds: 10),
    ];
    for (final delay in delays) {
      await Future.delayed(delay);
      await persistRoleToFirestore(role);
      final ok = await _putProfileToBackend(
        role: role,
        name: name,
        email: email,
        phone: phone,
        merchantService: merchantService,
        businessName: businessName,
        businessAddress: businessAddress,
      );
      if (ok) return true;
    }
    return false;
  }

  static Future<bool> _putProfileToBackend({
    required String role,
    String? name,
    String? email,
    String? phone,
    String? merchantService,
    String? businessName,
    String? businessAddress,
  }) async {
    try {
      final token = await AuthHandler.getTokenForApi();
      if (token == null || token.isEmpty) return false;
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      await applyIntendedRoleHeader(headers);
      if (await _putUsersMe(headers, {'role': role})) return true;

      final body = <String, dynamic>{'role': role};
      if ((name ?? '').trim().isNotEmpty) body['name'] = name!.trim();
      if ((email ?? '').trim().isNotEmpty) body['email'] = email!.trim();
      if ((phone ?? '').trim().isNotEmpty) body['phone'] = phone!.trim();
      if (role == RoleHelper.merchant) {
        if ((merchantService ?? '').trim().isNotEmpty) {
          body['merchantService'] = merchantService!.trim();
        }
        if ((businessName ?? '').trim().isNotEmpty) {
          body['businessName'] = businessName!.trim();
        }
        if ((businessAddress ?? '').trim().isNotEmpty) {
          body['businessAddress'] = businessAddress!.trim();
        }
      }
      return _putUsersMe(headers, body);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _putUsersMe(
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http
          .put(
            ApiConfig.endpoint('/users/me'),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _putRoleToBackend(
    String token,
    String role,
    Duration timeout,
  ) async {
    try {
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      await applyIntendedRoleHeader(headers);
      await http
          .put(
            ApiConfig.endpoint('/users/me'),
            headers: headers,
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
          .get()
          .timeout(const Duration(seconds: 4));
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
      Future<http.Response> once(String bearer) async {
        final headers = <String, String>{
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json',
        };
        await applyIntendedRoleHeader(headers);
        return http
            .get(
              ApiConfig.endpoint('/users/me'),
              headers: headers,
            )
            .timeout(timeout);
      }

      var resp = await once(token);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        final refreshed = await AuthHandler.refreshTokenAfterUnauthorized();
        if (refreshed != null && refreshed.isNotEmpty) {
          resp = await once(refreshed);
        }
      }

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
      // Timeout / offline — caller must keep cached merchant role.
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
