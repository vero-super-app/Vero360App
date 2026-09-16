import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:vero360_app/features/Restraurants/Models/food_order_model.dart';

/// Resolves a displayable food image URL for a [FoodOrder] document.
class FoodOrderImageResolver {
  FoodOrderImageResolver._();

  static String? pickImageUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in [
      'imageUrl',
      'image',
      'FoodImage',
      'photo',
      'coverImage',
      'coverImageUrl',
      'foodImageUrl',
      'picture',
      'coverUrl',
    ]) {
      final v = data[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    for (final key in ['gallery', 'galleryUrls', 'images']) {
      final gallery = data[key];
      if (gallery is List) {
        for (final e in gallery) {
          final v = e.toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
    }
    return null;
  }

  /// Converts http(s), gs://, or Firebase Storage paths to a cached network URL.
  static Future<String?> toHttpUrl(String? raw) async {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return s;
    if (lower.startsWith('//')) return 'https:$s';
    try {
      final ref = lower.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(s)
          : FirebaseStorage.instance.ref(s);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> resolve(FoodOrder order) async {
    final direct = order.headerFoodImageUrl;
    if (direct != null && direct.isNotEmpty) {
      final http = await toHttpUrl(direct);
      if (http != null) return http;
    }

    final db = FirebaseFirestore.instance;

    for (final line in order.lineItems) {
      final docId = line.menuItemId.trim();
      if (docId.length >= 12 && !RegExp(r'^\d+$').hasMatch(docId)) {
        try {
          final doc = await db.collection('food_menu_items').doc(docId).get();
          final url = pickImageUrl(doc.data());
          if (url != null) {
            final http = await toHttpUrl(url);
            if (http != null) return http;
          }
        } catch (_) {}
      }
    }

    final merchantId = order.merchantId.trim();
    if (merchantId.isNotEmpty && order.lineItems.isNotEmpty) {
      try {
        final snap = await db
            .collection('food_menu_items')
            .where('merchantId', isEqualTo: merchantId)
            .limit(40)
            .get();
        final targets = order.lineItems
            .map((e) => e.name.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();
        for (final doc in snap.docs) {
          final data = doc.data();
          final name = (data['name'] ?? '').toString().trim().toLowerCase();
          if (targets.contains(name)) {
            final url = pickImageUrl(data);
            if (url != null) {
              final http = await toHttpUrl(url);
              if (http != null) return http;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }
}
