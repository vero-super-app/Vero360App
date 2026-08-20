import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';

/// Single in-memory + prefs identity for the signed-in account.
///
/// Source of truth order:
/// 1. Memory (same process)
/// 2. Prefs bound to this Firebase uid
/// 3. Firestore `users/{uid}` (`role` + `merchantService`)
/// 4. Shop docs `{vertical}_merchants/{uid}` (legacy repair / when users is slow)
///
/// Each merchant vertical dashboard is independently keyed by [uid] + [service].
class MerchantIdentity {
  const MerchantIdentity({
    required this.uid,
    required this.role,
    this.service,
  });

  final String uid;
  final String role;
  final String? service;

  bool get isMerchant => role == RoleHelper.merchant;
  bool get isDriver => role == RoleHelper.driver;
  bool get isCustomer => !isMerchant && !isDriver;
  bool get hasVertical => isKnownMerchantServiceKey(service);

  MerchantIdentity copyWith({
    String? uid,
    String? role,
    String? service,
    bool clearService = false,
  }) {
    return MerchantIdentity(
      uid: uid ?? this.uid,
      role: role ?? this.role,
      service: clearService ? null : (service ?? this.service),
    );
  }
}

/// Fast, uid-scoped merchant/customer recognition.
class MerchantIdentityStore {
  MerchantIdentityStore._();

  static const prefsIdentityUidKey = 'merchant_identity_uid';

  static MerchantIdentity? _memory;

  static MerchantIdentity? peek() => _memory;

  static void clear() {
    _memory = null;
  }

  static String _currentUid({SharedPreferences? prefs}) {
    final auth = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (auth.isNotEmpty) return auth;
    return (prefs?.getString('uid') ?? '').trim();
  }

  /// Instant read from memory/prefs. Never hits the network.
  static MerchantIdentity? readCached({
    SharedPreferences? prefs,
    String? uid,
  }) {
    final id = (uid ?? _currentUid(prefs: prefs)).trim();
    if (id.isEmpty) return null;

    final mem = _memory;
    if (mem != null && mem.uid == id) return mem;

    if (prefs == null) return null;
    final boundUid = (prefs.getString(prefsIdentityUidKey) ??
            prefs.getString('uid') ??
            '')
        .trim();
    // Stale prefs from another account must not drive routing.
    if (boundUid.isNotEmpty && boundUid != id) {
      // Still allow intended-role keys if they match this uid.
      final intendedUid = (prefs.getString('session_intended_uid') ?? '').trim();
      if (intendedUid != id) return null;
    }

    final role = RoleHelper.normalizeAccountRole(
          prefs.getString('user_role') ?? prefs.getString('role'),
        ) ??
        RoleHelper.customer;
    final intendedUid = (prefs.getString('session_intended_uid') ?? '').trim();
    final intendedService = intendedUid == id
        ? normalizeMerchantServiceKey(
            prefs.getString('session_intended_merchant_service'),
          )
        : null;
    // Prefer any known local vertical even when identity uid binding is empty.
    final service = intendedService ??
        normalizeMerchantServiceKey(prefs.getString('merchant_service'));

    // If prefs already know this account is a merchant with a vertical, trust it.
    final effectiveRole =
        (isKnownMerchantServiceKey(service) && role == RoleHelper.customer)
            ? RoleHelper.merchant
            : role;

    final identity = MerchantIdentity(
      uid: id,
      role: effectiveRole,
      service: isKnownMerchantServiceKey(service) ? service : null,
    );
    _memory = identity;
    return identity;
  }

  /// Persist identity for [uid] locally (and optionally to Firestore users doc).
  static Future<MerchantIdentity> stamp({
    required String uid,
    required String role,
    String? service,
    SharedPreferences? prefs,
    bool writeFirestore = false,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) {
      throw ArgumentError('uid required');
    }
    final r = RoleHelper.normalizeAccountRole(role) ?? RoleHelper.customer;
    final s = isKnownMerchantServiceKey(service)
        ? normalizeMerchantServiceKey(service)
        : null;

    final sp = prefs ?? await SharedPreferences.getInstance();
    await sp.setString(prefsIdentityUidKey, id);
    await sp.setString('uid', id);
    await sp.setString('user_role', r);
    await sp.setString('role', r);
    await sp.setBool('is_merchant', r == RoleHelper.merchant);
    if (r == RoleHelper.merchant && s != null) {
      await sp.setString('merchant_service', s);
    } else if (r != RoleHelper.merchant) {
      await sp.remove('merchant_service');
    }

    final identity = MerchantIdentity(uid: id, role: r, service: s);
    _memory = identity;

    if (writeFirestore) {
      try {
        final payload = <String, dynamic>{
          'role': r,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (r == RoleHelper.merchant && s != null) {
          payload['merchantService'] = s;
          payload['merchant_service'] = s;
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(id)
            .set(payload, SetOptions(merge: true))
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MerchantIdentity] stamp Firestore failed: $e');
        }
      }
    }
    return identity;
  }

  /// Resolve role + vertical for [uid]. Cache-first; network only when needed.
  static Future<MerchantIdentity> resolve({
    String? uid,
    SharedPreferences? prefs,
    bool allowShopProbe = true,
    Duration usersTimeout = const Duration(seconds: 8),
    Duration shopTimeout = const Duration(seconds: 5),
  }) async {
    final sp = prefs ?? await SharedPreferences.getInstance();
    final id = (uid ?? _currentUid(prefs: sp)).trim();
    if (id.isEmpty) {
      return const MerchantIdentity(uid: '', role: RoleHelper.customer);
    }

    final cached = readCached(prefs: sp, uid: id);
    if (cached != null) {
      if (!cached.isMerchant) {
        // Still probe shops — role prefs can lag behind a real merchant shop.
        if (!allowShopProbe) return cached;
      } else if (cached.hasVertical) {
        return cached;
      } else if (!allowShopProbe) {
        return cached;
      }
    }

    String role = cached?.role ?? RoleHelper.customer;
    String? service = cached?.service;

    // Primary SSOT: users/{uid} (longer timeout — flaky networks were failing at 2.5s).
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .get()
          .timeout(usersTimeout);
      final data = doc.data();
      if (data != null) {
        final fromDoc = RoleHelper.normalizeAccountRole(data['role']);
        if (fromDoc != null) {
          // Sticky: never demote merchant/driver to customer from a flaky read
          // when prefs already know this uid is merchant/driver.
          if (!(fromDoc == RoleHelper.customer &&
              (role == RoleHelper.merchant || role == RoleHelper.driver))) {
            role = fromDoc;
          }
        }
        final fromService = normalizeMerchantServiceKey(
          data['merchantService']?.toString() ??
              data['merchant_service']?.toString(),
        );
        if (isKnownMerchantServiceKey(fromService)) {
          service = fromService;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MerchantIdentity] users/{uid} read: $e');
      }
    }

    // Intended signup vertical wins when still matching this uid.
    final intendedUid = (sp.getString('session_intended_uid') ?? '').trim();
    final intendedService = intendedUid == id
        ? normalizeMerchantServiceKey(
            sp.getString('session_intended_merchant_service'),
          )
        : null;
    if (isKnownMerchantServiceKey(intendedService)) {
      service = intendedService;
      if (role == RoleHelper.customer) role = RoleHelper.merchant;
    }

    // Probe shop docs when vertical still unknown.
    // Also probe when role looks like customer — shop ownership is definitive.
    if (allowShopProbe && !isKnownMerchantServiceKey(service)) {
      final probed = await _probeShopVertical(id, timeout: shopTimeout);
      if (isKnownMerchantServiceKey(probed)) {
        service = probed;
        role = RoleHelper.merchant;
        // Write vertical back to users/{uid} so next open is instant.
        unawaited(_writeServiceToUsers(id, probed!));
      }
    }

    return stamp(
      uid: id,
      role: role,
      service: service,
      prefs: sp,
      writeFirestore: false,
    );
  }

  static Future<String?> _probeShopVertical(
    String uid, {
    required Duration timeout,
  }) async {
    // Marketplace first — most merchants; also avoids food-stub false positives.
    const services = ['marketplace', 'food', 'accommodation', 'courier'];
    try {
      final probes = await Future.wait(
        services.map((service) async {
          try {
            final collection = merchantCollectionForService(service)!;
            final doc = await FirebaseFirestore.instance
                .collection(collection)
                .doc(uid)
                .get()
                .timeout(timeout);
            if (doc.exists && looksLikeRealMerchantShopDoc(doc.data())) {
              return service;
            }
          } catch (_) {}
          return null;
        }),
      );
      for (final hit in probes) {
        if (isKnownMerchantServiceKey(hit)) return hit;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeServiceToUsers(String uid, String service) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'role': RoleHelper.merchant,
          'merchantService': service,
          'merchant_service': service,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
