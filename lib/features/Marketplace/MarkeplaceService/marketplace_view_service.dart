import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifetime opens of a marketplace listing. Doc id is the Firestore item id.
class MarketplaceViewService {
  MarketplaceViewService._();

  static final _db = FirebaseFirestore.instance;
  static const _col = 'marketplace_item_views';
  static final Set<String> _countedThisSession = <String>{};

  static Future<void> recordView({
    String? firestoreDocId,
    int? sqlId,
  }) async {
    final id = (firestoreDocId ?? '').trim().isNotEmpty
        ? firestoreDocId!.trim()
        : (sqlId != null && sqlId > 0 ? 'id_$sqlId' : '');
    if (id.isEmpty || !_countedThisSession.add(id)) return;
    try {
      await _db.collection(_col).doc(id).set({
        'views': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<Map<String, int>> fetchViews(Iterable<String> itemIds) async {
    final ids = itemIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    final out = <String, int>{};
    for (var i = 0; i < ids.length; i += 10) {
      final end = i + 10 > ids.length ? ids.length : i + 10;
      final chunk = ids.sublist(i, end);
      try {
        final snap = await _db
            .collection(_col)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final raw = doc.data()['views'];
          out[doc.id] = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
        }
      } catch (_) {}
    }
    return out;
  }
}
