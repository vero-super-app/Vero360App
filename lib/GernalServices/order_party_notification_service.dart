import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/Gernalproviders/notification_store.dart';

/// Cross-user order alerts via Firestore. Each target device should subscribe in
/// [NotificationService] and mark docs consumed after showing a local notification.
///
/// **Firestore rules:** allow authenticated `create` on [collectionName] with a
/// `toUid` field, and `read`/`update` only when `resource.data.toUid == request.auth.uid`.
/// Add a composite index on (`toUid`, `consumed`) for the listener query.
class OrderPartyNotificationService {
  OrderPartyNotificationService._();

  static const String collectionName = 'order_party_alerts';

  static String _veroOrderNo(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    if (clean.toLowerCase().startsWith('vero')) return clean;
    return 'Vero$clean';
  }

  static Future<void> publishShippedToBuyer({
    required String buyerUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
  }) async {
    final uid = buyerUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'Your order' : 'Your order $on';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Your order has shipped',
        'body':
            '$orderSeg$itemSeg has been shipped. Check progress in Delivered orders.',
        'payload': {
          'type': 'order_update',
          'orderId': orderId,
          'orderNumber': on,
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeReceived,
          'status': 'delivered',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishShippedToBuyer: $e');
    }
  }

  static Future<void> publishFundsReleasedToMerchant({
    required String merchantUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'The order' : 'Order $on';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Buyer confirmed receipt',
        'body':
            '$orderSeg$itemSeg has been received. Funds have been transferred to your wallet.',
        'payload': {
          'type': 'order_escrow_released',
          'orderId': orderId,
          'orderNumber': on,
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeReceived,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishFundsReleasedToMerchant: $e');
    }
  }
}
