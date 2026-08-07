import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Customer-side hide list: blocked merchants' shops, items, stories, and promos
/// are filtered from the signed-in user's app until unblocked in Settings.
class BlockedMerchantRecord {
  final String merchantId;
  final String? displayName;
  final DateTime? blockedAt;

  const BlockedMerchantRecord({
    required this.merchantId,
    this.displayName,
    this.blockedAt,
  });
}

class BlockedMerchantService {
  BlockedMerchantService._();

  static const _subcollection = 'blocked_merchants';

  static Set<String> _ids = {};
  static bool _loaded = false;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid.trim();

  static void clearSessionCache() {
    _ids = {};
    _loaded = false;
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await reload();
  }

  static Future<void> reload() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      _ids = {};
      _loaded = true;
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(_subcollection)
          .get();
      _ids = snap.docs.map((d) => d.id.trim()).where((id) => id.isNotEmpty).toSet();
      _loaded = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockedMerchantService] reload: $e');
      _loaded = true;
    }
  }

  static Future<Set<String>> blockedIds() async {
    await ensureLoaded();
    return Set<String>.from(_ids);
  }

  static bool isBlockedSync(String? merchantId) {
    final id = (merchantId ?? '').trim();
    if (id.isEmpty) return false;
    return _ids.contains(id);
  }

  static Future<bool> isBlocked(String? merchantId) async {
    await ensureLoaded();
    return isBlockedSync(merchantId);
  }

  /// True when any candidate id for a listing/story/promo matches the block list.
  static bool matchesBlocked(
    Set<String> blocked, {
    String? merchantId,
    String? sellerUserId,
    String? serviceProviderId,
  }) {
    if (blocked.isEmpty) return false;
    for (final raw in [merchantId, sellerUserId, serviceProviderId]) {
      final id = (raw ?? '').trim();
      if (id.isNotEmpty && blocked.contains(id)) return true;
    }
    return false;
  }

  static Future<void> blockMerchant({
    required String merchantId,
    String? displayName,
  }) async {
    final uid = _uid;
    final id = merchantId.trim();
    if (uid == null || uid.isEmpty || id.isEmpty) return;

    final name = (displayName ?? '').trim();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(_subcollection)
        .doc(id)
        .set({
      if (name.isNotEmpty) 'displayName': name,
      'blockedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _ids.add(id);
    _loaded = true;
  }

  static Future<void> unblockMerchant(String merchantId) async {
    final uid = _uid;
    final id = merchantId.trim();
    if (uid == null || uid.isEmpty || id.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(_subcollection)
        .doc(id)
        .delete();

    _ids.remove(id);
    _loaded = true;
  }

  static Future<List<BlockedMerchantRecord>> listBlocked() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return [];

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(_subcollection)
          .orderBy('blockedAt', descending: true)
          .get();
      final rows = snap.docs.map((d) {
        final data = d.data();
        DateTime? at;
        final raw = data['blockedAt'];
        if (raw is Timestamp) at = raw.toDate();
        return BlockedMerchantRecord(
          merchantId: d.id,
          displayName: (data['displayName'] ?? '').toString().trim().isEmpty
              ? null
              : (data['displayName'] ?? '').toString().trim(),
          blockedAt: at,
        );
      }).toList();
      _ids = rows.map((r) => r.merchantId).toSet();
      _loaded = true;
      return rows;
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockedMerchantService] listBlocked: $e');
      return [];
    }
  }
}
