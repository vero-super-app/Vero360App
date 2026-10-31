import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/utils/firebase_bootstrap.dart';

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
  static String? _listingConfirmedUid;
  static String? _listingConfirmedService;

  static MerchantIdentity? peek() => _memory;

  /// Vertical last confirmed by Firestore listings/shops for this uid.
  /// Cached `food` must not open the kitchen until this matches.
  static String? peekListingConfirmedService(String uid) {
    final id = uid.trim();
    if (id.isEmpty || _listingConfirmedUid != id) return null;
    return _listingConfirmedService;
  }

  static void clear() {
    _memory = null;
    _listingConfirmedUid = null;
    _listingConfirmedService = null;
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
    final auth = tryFirebaseUser()?.uid.trim() ?? '';
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
    final intendedRole = RoleHelper.normalizeAccountRole(
      prefs.getString('session_intended_role'),
    );
    final shoppingThisUid =
        intendedRole == RoleHelper.customer && intendedUid == id;
    final intendedService = intendedUid == id
        ? normalizeMerchantServiceKey(
            prefs.getString('session_intended_merchant_service'),
          )
        : null;
    // Prefer uid-scoped vertical. Signup "intended" must not override a
    // later correction (e.g. leftover food after a marketplace login).
    final service = normalizeMerchantServiceKey(
          prefs.getString(prefsServiceKeyForUid(id)),
        ) ??
        normalizeMerchantServiceKey(prefs.getString('merchant_service')) ??
        intendedService;

    // A cached shop vertical must not freeze someone who chose "shop as customer".
    final effectiveRole = shoppingThisUid
        ? RoleHelper.customer
        : (isKnownMerchantServiceKey(service) && role != RoleHelper.driver
            ? RoleHelper.merchant
            : role);

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
    bool keepVerticalCache = false,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) {
      throw ArgumentError('uid required');
    }
    final r = RoleHelper.normalizeAccountRole(role) ?? RoleHelper.customer;
    var s = isKnownMerchantServiceKey(service)
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
      final intendedFor = (sp.getString('session_intended_uid') ?? '').trim();
      if (intendedFor.isEmpty || intendedFor == id) {
        await sp.setString('session_intended_merchant_service', s);
        await sp.setString('session_intended_uid', id);
      }
    } else if (r != RoleHelper.merchant) {
      await sp.remove('merchant_service');
      if (keepVerticalCache) {
        s ??= normalizeMerchantServiceKey(
          sp.getString(prefsServiceKeyForUid(id)),
        );
      } else {
        await sp.remove(prefsServiceKeyForUid(id));
      }
    }

    final identity = MerchantIdentity(
      uid: id,
      role: r,
      service: isKnownMerchantServiceKey(s) ? s : null,
    );
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

    final intendedUid = (sp.getString('session_intended_uid') ?? '').trim();
    final intendedRole = RoleHelper.normalizeAccountRole(
      sp.getString('session_intended_role'),
    );
    if (intendedRole == RoleHelper.customer && intendedUid == id) {
      return stamp(
        uid: id,
        role: RoleHelper.customer,
        prefs: sp,
        keepVerticalCache: true,
        writeFirestore: false,
      );
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
    var serviceFromUsers = false;
    final extraSellerIds = <String>{};

    // 1) Authoritative: users/{uid}
    if (!isFirebaseAppReady) {
      return cached ??
          MerchantIdentity(uid: id, role: role, service: service);
    }
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
          serviceFromUsers = true;
          // Keep last vertical, but do not promote a customer shopping session.
          if (fromDoc != RoleHelper.customer &&
              fromDoc != RoleHelper.driver) {
            role = RoleHelper.merchant;
          }
        }
        for (final key in const [
          'backendUserId',
          'userId',
          'sellerUserId',
          'id',
        ]) {
          final raw = data[key]?.toString().trim() ?? '';
          if (raw.isNotEmpty && raw != id) extraSellerIds.add(raw);
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
    final intendedService = intendedUid == id
        ? normalizeMerchantServiceKey(
            sp.getString('session_intended_merchant_service'),
          )
        : null;
    if (isKnownMerchantServiceKey(intendedService) && !serviceFromUsers) {
      // Intended fills a missing vertical. Never override users/{uid}.
      if (!isKnownMerchantServiceKey(service)) {
        service = intendedService;
      }
      if (intendedRole == RoleHelper.merchant ||
          (role != RoleHelper.customer && role != RoleHelper.driver)) {
        role = RoleHelper.merchant;
      }
    }

    // 3) Listings beat leftover shop stubs. Opening the restaurant UI once
    // stamps food_merchants.serviceType=food (+100) and used to trap
    // marketplace sellers on the kitchen dashboard.
    final nestPref = (sp.getString('backendUserId') ?? '').trim();
    if (nestPref.isNotEmpty && nestPref != id) extraSellerIds.add(nestPref);

    if (allowShopProbe &&
        (forceRefresh || !isKnownMerchantServiceKey(service))) {
      final hint = await _listingHint(
        id,
        extraSellerIds: extraSellerIds,
        timeout: shopTimeout,
      );
      final probe = await _probeShopVertical(id, timeout: shopTimeout);
      final marketScore = probe.scoreFor('marketplace');
      String? fromStock;
      if (hint.hasMarketItems && !hint.hasFoodMenu) {
        fromStock = 'marketplace';
      } else if (hint.hasFoodMenu && !hint.hasMarketItems) {
        fromStock = 'food';
      } else if (hint.hasMarketItems && hint.hasFoodMenu) {
        // Both exist — leftover kitchen from a wrong dashboard visit.
        // Real store stock wins.
        fromStock = 'marketplace';
      } else if (!hint.hasFoodMenu && marketScore >= 20) {
        fromStock = 'marketplace';
      } else if (!isKnownMerchantServiceKey(service) &&
          isKnownMerchantServiceKey(probe.service)) {
        fromStock = probe.service;
      }
      if (kDebugMode) {
        debugPrint(
          '[MerchantIdentity] listings market=${hint.hasMarketItems} '
          'foodMenu=${hint.hasFoodMenu} marketScore=$marketScore '
          'fromStock=$fromStock was=$service',
        );
      }
      if (isKnownMerchantServiceKey(fromStock) && fromStock != service) {
        service = fromStock;
        if (role != RoleHelper.customer && role != RoleHelper.driver) {
          role = RoleHelper.merchant;
          await _writeServiceToUsers(id, fromStock!);
        }
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
    }

    if (isKnownMerchantServiceKey(service) &&
        role != RoleHelper.customer &&
        role != RoleHelper.driver) {
      role = RoleHelper.merchant;
    }

    if (allowShopProbe && isKnownMerchantServiceKey(service)) {
      _listingConfirmedUid = id;
      _listingConfirmedService = service;
    }

    return stamp(
      uid: id,
      role: role,
      service: service,
      prefs: sp,
      writeFirestore: false,
    );
  }

  static Future<_ListingHint> _listingHint(
    String uid, {
    Iterable<String> extraSellerIds = const [],
    required Duration timeout,
  }) async {
    Future<bool> hasDocs(String collection, String field, String value) async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .where(field, isEqualTo: value)
            .limit(1)
            .get()
            .timeout(timeout);
        return snap.docs.isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    final ids = <String>{
      uid,
      ...extraSellerIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };
    final checks = <Future<bool>>[];
    for (final id in ids) {
      checks.add(hasDocs('marketplace_items', 'merchantId', id));
      checks.add(hasDocs('marketplace_items', 'firebaseUid', id));
      checks.add(hasDocs('marketplace_items', 'sellerUserId', id));
      checks.add(hasDocs('latestarrivals', 'merchantId', id));
      checks.add(hasDocs('food_menu_items', 'merchantId', id));
    }
    final hits = await Future.wait(checks);
    var hasMarketItems = false;
    var hasFoodMenu = false;
    for (var i = 0; i < hits.length; i += 5) {
      hasMarketItems = hasMarketItems ||
          hits[i] ||
          hits[i + 1] ||
          hits[i + 2] ||
          hits[i + 3];
      hasFoodMenu = hasFoodMenu || hits[i + 4];
    }
    return _ListingHint(
      hasMarketItems: hasMarketItems,
      hasFoodMenu: hasFoodMenu,
    );
  }

  /// Pick the strongest real shop for this uid.
  static Future<_ShopProbe> _probeShopVertical(
    String uid, {
    required Duration timeout,
  }) async {
    const services = ['marketplace', 'food', 'accommodation', 'courier'];
    final scores = <String, int>{
      for (final s in services) s: 0,
    };
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
            return (service, merchantShopDocStrength(doc.data()));
          } catch (_) {
            return (service, 0);
          }
        }),
      );

      String? bestStrong;
      var bestStrongScore = 0;
      final weakHits = <String>[];
      for (final (service, score) in scored) {
        scores[service] = score;
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
        return _ShopProbe(service: bestStrong, scores: scores);
      }

      // Lone name-only shop. Never guess food when a marketplace stub also exists.
      if (weakHits.length == 1) {
        return _ShopProbe(service: weakHits.first, scores: scores);
      }
      if (weakHits.contains('marketplace')) {
        return _ShopProbe(service: 'marketplace', scores: scores);
      }
    } catch (_) {}
    return _ShopProbe(service: null, scores: scores);
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

class _ListingHint {
  const _ListingHint({
    required this.hasMarketItems,
    required this.hasFoodMenu,
  });

  final bool hasMarketItems;
  final bool hasFoodMenu;
}

class _ShopProbe {
  const _ShopProbe({required this.service, required this.scores});

  final String? service;
  final Map<String, int> scores;

  int scoreFor(String? key) {
    final k = (key ?? '').trim();
    if (k.isEmpty) return 0;
    return scores[k] ?? 0;
  }
}
