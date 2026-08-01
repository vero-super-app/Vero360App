import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Propagates a profile / merchant display name to prefs, Auth, and denormalized
/// Firestore fields (shop docs, marketplace items, stories) so UI stays in sync.
class DisplayNameSync {
  DisplayNameSync._();

  static final _db = FirebaseFirestore.instance;

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

    // Core profile + merchant shop docs
    await Future.wait([
      _merge(_db.collection('users').doc(uid), payload),
      _merge(_db.collection('marketplace_merchants').doc(uid), payload),
      _merge(_db.collection('food_merchants').doc(uid), payload),
      _merge(_db.collection('accommodation_merchants').doc(uid), payload),
      _merge(_db.collection('courier_merchants').doc(uid), payload),
      _merge(_db.collection('profiles').doc(uid), {
        'name': display,
        'displayName': display,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    ]);

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
