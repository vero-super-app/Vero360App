import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';

/// Propagates a profile / merchant display name to prefs, Auth, and denormalized
/// Firestore fields (shop docs, marketplace items, stories) so UI stays in sync.
class DisplayNameSync {
  DisplayNameSync._();

  static final _db = FirebaseFirestore.instance;

  static const _merchantBizPrefsKeys = [
    'business_name',
    'businessName',
    'merchant_business_name',
    'merchantName',
    'shopName',
    'companyName',
  ];

  static const _personalPrefsKeys = [
    'fullName',
    'name',
    'displayName',
    'username',
  ];

  static const _merchantCollections = [
    'marketplace_merchants',
    'food_merchants',
    'accommodation_merchants',
    'courier_merchants',
  ];

  static bool _usableLabel(String raw) {
    final v = raw.trim();
    if (v.isEmpty || v.contains('@')) return false;
    final lower = v.toLowerCase();
    if (lower == 'you' ||
        lower == 'someone' ||
        lower == 'contact' ||
        lower == 'merchant' ||
        lower == 'user') {
      return false;
    }
    return true;
  }

  static String? _firstUsable(Iterable<String?> values) {
    for (final raw in values) {
      final v = (raw ?? '').trim();
      if (_usableLabel(v)) return v;
    }
    return null;
  }

  /// Label for the signed-in account in stories / chat notifications.
  /// Merchants always prefer **business name** over personal name.
  static Future<String> resolveActingDisplayName({
    String fallback = 'You',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = RoleHelper.normalizeAccountRole(
            prefs.getString('user_role') ?? prefs.getString('role'),
          ) ??
          RoleHelper.customer;
      final user = FirebaseAuth.instance.currentUser;
      final uid = (user?.uid ?? '').trim();

      if (role == RoleHelper.merchant) {
        final fromPrefs = _firstUsable(
          _merchantBizPrefsKeys.map(prefs.getString),
        );
        if (fromPrefs != null) return fromPrefs;

        if (uid.isNotEmpty) {
          final fromShop = await _businessNameFromMerchantDocs(uid);
          if (fromShop != null) {
            try {
              await prefs.setString('business_name', fromShop);
            } catch (_) {}
            return fromShop;
          }
          final fromUser = await _businessNameFromUserDoc(uid);
          if (fromUser != null) {
            try {
              await prefs.setString('business_name', fromUser);
            } catch (_) {}
            return fromUser;
          }
        }
        // Merchant with no business name yet — avoid leaking personal name
        // into public story / chat labels.
        return fallback == 'You' ? 'My shop' : fallback;
      }

      final personal = _firstUsable([
        ..._personalPrefsKeys.map(prefs.getString),
        user?.displayName,
      ]);
      if (personal != null) return personal;

      final email = prefs.getString('email') ?? user?.email;
      if (email != null && email.contains('@')) {
        final local = email.split('@').first.trim();
        if (_usableLabel(local)) {
          return local[0].toUpperCase() + local.substring(1);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DisplayNameSync] resolveActingDisplayName: $e');
    }
    return fallback;
  }

  static Future<String?> _businessNameFromMerchantDocs(String uid) async {
    for (final col in _merchantCollections) {
      try {
        final snap = await _db.collection(col).doc(uid).get();
        if (!snap.exists) continue;
        final data = snap.data() ?? const <String, dynamic>{};
        final name = _firstUsable([
          data['businessName']?.toString(),
          data['business_name']?.toString(),
          data['merchantName']?.toString(),
          data['companyName']?.toString(),
          data['shopName']?.toString(),
          data['storeName']?.toString(),
          // Last resort on shop docs only (often already the business title).
          data['name']?.toString(),
        ]);
        if (name != null) return name;
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _businessNameFromUserDoc(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};
      return _firstUsable([
        data['businessName']?.toString(),
        data['business_name']?.toString(),
        data['merchantName']?.toString(),
        data['shopName']?.toString(),
        data['companyName']?.toString(),
      ]);
    } catch (_) {
      return null;
    }
  }

  /// [name] should already be trimmed and non-empty.
  static Future<void> syncEverywhere({
    required String uid,
    required String name,
  }) async {
    final display = name.trim();
    if (uid.isEmpty || display.isEmpty) return;

    final payload = <String, dynamic>{
      'name': display,
      'fullName': display,
      'displayName': display,
      'businessName': display,
      'merchantName': display,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Local session
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fullName', display);
      await prefs.setString('name', display);
      await prefs.setString('business_name', display);
    } catch (_) {}

    // Firebase Auth
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && u.uid == uid) {
        await u.updateDisplayName(display);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DisplayNameSync] auth displayName: $e');
    }

    // Core profile. Only update shop docs that already exist for this uid —
    // never create marketplace/food/stay/courier shops (that mixes dashboards).
    final userPayload = <String, dynamic>{
      'name': display,
      'fullName': display,
      'displayName': display,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _merge(_db.collection('users').doc(uid), userPayload);
    await _merge(_db.collection('profiles').doc(uid), {
      'name': display,
      'displayName': display,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final collection in const [
      'marketplace_merchants',
      'food_merchants',
      'accommodation_merchants',
      'courier_merchants',
    ]) {
      await _mergeIfExists(_db.collection(collection).doc(uid), payload);
    }

    // Denormalized fields used by home stories + marketplace cards
    await _updateQueryField(
      _db.collection('marketplace_items').where('merchantId', isEqualTo: uid),
      {'merchantName': display},
    );
    await _updateQueryField(
      _db.collection('merchant_stories').where('merchantId', isEqualTo: uid),
      {'merchantName': display},
    );
    await _updateQueryField(
      _db.collection('latestarrivals').where('merchantId', isEqualTo: uid),
      {'merchantName': display, 'businessName': display},
    );
  }

  static Future<void> _mergeIfExists(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    try {
      final snap = await ref.get();
      if (!snap.exists) return;
      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[DisplayNameSync] merge existing ${ref.path}: $e');
    }
  }

  static Future<void> _merge(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    try {
      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('[DisplayNameSync] merge ${ref.path}: $e');
    }
  }

  static Future<void> _updateQueryField(
    Query<Map<String, dynamic>> query,
    Map<String, dynamic> patch,
  ) async {
    try {
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        Query<Map<String, dynamic>> page =
            query.orderBy(FieldPath.documentId).limit(400);
        if (cursor != null) {
          page = page.startAfterDocument(cursor);
        }
        final snap = await page.get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.update(d.reference, {
            ...patch,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        if (snap.docs.length < 400) break;
        cursor = snap.docs.last;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DisplayNameSync] query update: $e');
    }
  }
}
