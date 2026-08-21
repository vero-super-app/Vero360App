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
/// 1. Firestore `users/{uid}` (`role` + `merchantService`) — authoritative
/// 2. Strongest real shop doc among `{vertical}_merchants/{uid}`
/// 3. Prefs / memory bound to this Firebase uid (never cross-account)
///
/// Dashboards: food → Food, marketplace → Marketplace, accommodation → Stay,
/// courier → Courier. Drivers use role `driver` (not a merchant vertical).
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

  static String prefsServiceKeyForUid(String uid) =>
      'merchant_service_v1_${uid.trim()}';

  static MerchantIdentity? _memory;

  static MerchantIdentity? peek() => _memory;

  static void clear() {
    _memory = null;
  }

  /// Drop in-memory + global routing prefs so the next login cannot reopen the
  /// previous account's dashboard on the same phone.
  static Future<void> clearRoutingCache(SharedPreferences prefs) async {
    clear();
    await prefs.remove('merchant_service');
    await prefs.remove(prefsIdentityUidKey);
    await prefs.remove('business_name');
    await prefs.remove('business_address');
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
    // Prefer uid-scoped vertical, then session key, then signup intended.
    final service = intendedService ??
        normalizeMerchantServiceKey(prefs.getString(prefsServiceKeyForUid(id))) ??
        normalizeMerchantServiceKey(prefs.getString('merchant_service'));

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
      await sp.setString(prefsServiceKeyForUid(id), s);
    } else if (r != RoleHelper.merchant) {
      await sp.remove('merchant_service');
      await sp.remove(prefsServiceKeyForUid(id));
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

  /// Resolve role + vertical for [uid].
  ///
  /// Set [forceRefresh] on login / recovering tab so a stale marketplace
  /// cache cannot keep a food/stay/courier merchant on the wrong dashboard.
  static Future<MerchantIdentity> resolve({
    String? uid,
    SharedPreferences? prefs,
    bool allowShopProbe = true,
    bool forceRefresh = false,
    Duration usersTimeout = const Duration(seconds: 8),
    Duration shopTimeout = const Duration(seconds: 5),
  }) async {
    final sp = prefs ?? await SharedPreferences.getInstance();
    final id = (uid ?? _currentUid(prefs: sp)).trim();
    if (id.isEmpty) {
      return const MerchantIdentity(uid: '', role: RoleHelper.customer);
    }

    final cached = readCached(prefs: sp, uid: id);
    if (!forceRefresh &&
        cached != null &&
        cached.isMerchant &&
        cached.hasVertical) {
      return cached;
    }
    if (!forceRefresh &&
        cached != null &&
        !cached.isMerchant &&
        !allowShopProbe) {
      return cached;
    }

    String role = cached?.role ?? RoleHelper.customer;
    String? service = forceRefresh ? null : cached?.service;

    // 1) Authoritative: users/{uid}
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
          // Sticky: never demote merchant/driver → customer from a flaky read
          // when prefs already know this uid is merchant/driver (unless refresh
          // and Firestore explicitly says otherwise for driver/customer).
          if (forceRefresh) {
            role = fromDoc;
          } else if (!(fromDoc == RoleHelper.customer &&
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
      // On refresh failure, fall back to previous cache rather than blank.
      if (forceRefresh && cached != null) {
        service ??= cached.service;
        role = cached.role;
      }
    }

    // 2) Signup intended vertical for this uid only.
    final intendedUid = (sp.getString('session_intended_uid') ?? '').trim();
    final intendedService = intendedUid == id
        ? normalizeMerchantServiceKey(
            sp.getString('session_intended_merchant_service'),
          )
        : null;
    if (isKnownMerchantServiceKey(intendedService)) {
      // Intended beats a generic marketplace default from API/users.
      if (!isKnownMerchantServiceKey(service) || service == 'marketplace') {
        service = intendedService;
      }
      if (role == RoleHelper.customer) role = RoleHelper.merchant;
    }

    // 3) Probe shops when vertical unknown, or when refresh still looks like
    // the generic marketplace default (often wrong for food/stay/courier).
    final shouldProbe = allowShopProbe &&
        (!isKnownMerchantServiceKey(service) ||
            (forceRefresh && service == 'marketplace'));
    if (shouldProbe) {
      final probed = await _probeShopVertical(id, timeout: shopTimeout);
      if (isKnownMerchantServiceKey(probed)) {
        // Prefer non-marketplace shop over a marketplace-only default.
        if (!isKnownMerchantServiceKey(service) ||
            service == 'marketplace' ||
            probed == service) {
          service = probed;
        }
        role = RoleHelper.merchant;
        unawaited(_writeServiceToUsers(id, probed!));
      }
    }

    // 4) Last resort: uid-scoped prefs (same phone, same account).
    if (!isKnownMerchantServiceKey(service)) {
      service = normalizeMerchantServiceKey(
            sp.getString(prefsServiceKeyForUid(id)),
          ) ??
          (forceRefresh
              ? null
              : normalizeMerchantServiceKey(sp.getString('merchant_service')));
      if (isKnownMerchantServiceKey(service) && role == RoleHelper.customer) {
        role = RoleHelper.merchant;
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

  /// Pick the strongest real shop for this uid.
  /// Marketplace is last in tie-break — name stubs often exist there wrongly.
  static Future<String?> _probeShopVertical(
    String uid, {
    required Duration timeout,
  }) async {
    const services = ['food', 'accommodation', 'courier', 'marketplace'];
    try {
      final scored = await Future.wait(
        services.map((service) async {
          try {
            final collection = merchantCollectionForService(service)!;
            final doc = await FirebaseFirestore.instance
                .collection(collection)
                .doc(uid)
                .get()
                .timeout(timeout);
            if (!doc.exists) return (service, 0);
            final strength = merchantShopDocStrength(doc.data());
            return (service, strength);
          } catch (_) {
            return (service, 0);
          }
        }),
      );

      String? bestStrong;
      var bestStrongScore = 0;
      final weakHits = <String>[];
      for (final (service, score) in scored) {
        if (score <= 0) continue;
        if (score >= 20) {
          if (score > bestStrongScore) {
            bestStrongScore = score;
            bestStrong = service;
          }
        } else {
          weakHits.add(service);
        }
      }
      if (bestStrong != null) {
        if (kDebugMode) {
          debugPrint(
            '[MerchantIdentity] shop probe → $bestStrong '
            '(score $bestStrongScore) for $uid',
          );
        }
        return bestStrong;
      }

      // Soft fallback: a lone name-only shop (common for new food merchants).
      // Never guess marketplace when multiple weak stubs exist.
      if (weakHits.length == 1) return weakHits.first;
      final nonMarket = weakHits.where((s) => s != 'marketplace').toList();
      if (nonMarket.length == 1) return nonMarket.first;
      if (nonMarket.isNotEmpty) return nonMarket.first; // food first in list
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
