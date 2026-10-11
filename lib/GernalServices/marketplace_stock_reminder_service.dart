import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';

/// After a marketplace sale: if quantity is finished, Vero360 Team reminds the
/// merchant to take the listing off the shelf / mark it out of stock.
class MarketplaceStockReminderService {
  MarketplaceStockReminderService._();

  static String _dayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Call after paid marketplace orders are created (escrow holds).
  static Future<void> remindIfStockFinishedForOrders({
    required List<CreatedOrderRef> refs,
  }) async {
    for (final r in refs) {
      try {
        await remindIfStockFinishedForCartLine(
          item: r.item,
          orderId: r.orderId,
          orderNumber: r.orderNumber,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[StockReminder] order ${r.orderId}: $e');
        }
      }
    }
  }

  static Future<void> remindIfStockFinishedForCartLine({
    required CartModel item,
    String? orderId,
    String? orderNumber,
  }) async {
    if (item.isFood) return;
    if (!item.hasValidMerchant) return;

    final stock = item.availableStock;
    if (stock == null) return; // unknown stock — can't tell if finished

    final remaining = stock - item.quantity;
    if (remaining > 0) return;

    final mid = item.merchantId.trim();
    final dedupeKey = 'oos_shelf_${mid}_${item.item}_${_dayKey()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(dedupeKey) ?? false) return;

      await OrderPartyNotificationService.publishOutOfStockShelfReminder(
        merchantUid: mid,
        itemName: item.name,
        orderNumber: orderNumber,
        orderId: orderId,
        listingSqlId: item.item > 0 ? item.item : null,
      );

      // Best-effort: zero stock / deactivate on Firestore if signed-in user is owner.
      unawaited(_tryDeactivateFirestoreListing(
        merchantUid: mid,
        sqlItemId: item.item > 0 ? item.item : null,
        itemName: item.name,
      ));

      await prefs.setBool(dedupeKey, true);
    } catch (e) {
      if (kDebugMode) debugPrint('[StockReminder] remind failed: $e');
    }
  }

  /// Merchant opens Manage listings: nudge once/day for active 0-stock items.
  static Future<void> nudgeActiveOutOfStockListings({
    required String merchantUid,
  }) async {
    final mid = merchantUid.trim();
    if (mid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .where('merchantId', isEqualTo: mid)
          .limit(40)
          .get();

      final prefs = await SharedPreferences.getInstance();
      for (final doc in snap.docs) {
        final data = doc.data();
        final active = data['isActive'] == true;
        if (!active) continue;
        final raw = data['stockQuantity'] ?? data['quantity'] ?? data['stock'];
        final stock = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '');
        if (stock == null || stock > 0) continue;

        final key = 'oos_active_${doc.id}_${_dayKey()}';
        if (prefs.getBool(key) ?? false) continue;

        final name = (data['name'] ?? 'Listing').toString();
        final sqlRaw = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'];
        final sqlId = sqlRaw is num
            ? sqlRaw.toInt()
            : int.tryParse(sqlRaw?.toString() ?? '');

        await OrderPartyNotificationService.publishOutOfStockShelfReminder(
          merchantUid: mid,
          itemName: name,
          listingSqlId: sqlId,
          marketplaceItemId: doc.id,
        );
        await prefs.setBool(key, true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StockReminder] nudgeActiveOutOfStockListings: $e');
      }
    }
  }

  static Future<void> _tryDeactivateFirestoreListing({
    required String merchantUid,
    int? sqlItemId,
    required String itemName,
  }) async {
    try {
      QuerySnapshot<Map<String, dynamic>>? snap;
      if (sqlItemId != null && sqlItemId > 0) {
        snap = await FirebaseFirestore.instance
            .collection('marketplace_items')
            .where('sqlItemId', isEqualTo: sqlItemId)
            .limit(3)
            .get();
        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('marketplace_items')
              .where('itemId', isEqualTo: sqlItemId)
              .limit(3)
              .get();
        }
      }

      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      if (snap != null && snap.docs.isNotEmpty) {
        docs.addAll(snap.docs);
      } else {
        final byMerchant = await FirebaseFirestore.instance
            .collection('marketplace_items')
            .where('merchantId', isEqualTo: merchantUid)
            .limit(30)
            .get();
        final nameLc = itemName.trim().toLowerCase();
        docs.addAll(byMerchant.docs.where((d) {
          final n = (d.data()['name'] ?? '').toString().trim().toLowerCase();
          return n == nameLc;
        }));
      }

      for (final d in docs) {
        final owner = (d.data()['merchantId'] ?? '').toString().trim();
        if (owner.isNotEmpty && owner != merchantUid) continue;
        await d.reference.set(
          {
            'stockQuantity': 0,
            'quantity': 0,
            'isActive': false,
            'sold': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      // Expected when buyer (not owner) tries to write — reminder still sent.
      if (kDebugMode) {
        debugPrint('[StockReminder] deactivate skipped: $e');
      }
    }
  }
}
