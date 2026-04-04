import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
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

  /// Host receives this on their signed-in device via [NotificationService] listener.
  static Future<void> publishAccommodationBookingToHost({
    required String hostUid,
    required String propertyName,
    required String bookingRef,
    String? guestLine,
    String? guestEmail,
    String? checkInLabel,
    int? nights,
    String? fromUid,
  }) async {
    final uid = hostUid.trim();
    final refRaw = bookingRef.trim();
    if (uid.isEmpty || refRaw.isEmpty) return;
    final ref = formatVeroAccommodationBookingRef(refRaw);
    if (ref.isEmpty) return;
    final sender =
        (fromUid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    final prop =
        propertyName.trim().isEmpty ? 'Your listing' : propertyName.trim();
    final name = (guestLine ?? '').trim();
    final who = name.isEmpty ? 'A guest' : name;
    final email = (guestEmail ?? '').trim();
    final whoDetail = email.isNotEmpty && email != name ? '$who ($email)' : who;

    final buf = StringBuffer("$whoDetail booked $prop");
    final cin = (checkInLabel ?? '').trim();
    if (cin.isNotEmpty) buf.write(' · Check-in $cin');
    if (nights != null && nights > 0) {
      buf.write(' · $nights night${nights == 1 ? '' : 's'}');
    }
    buf.write('. Ref $ref.');

    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        if (sender.isNotEmpty) 'fromUid': sender,
        'title': 'New stay booking',
        'body': buf.toString(),
        'payload': {
          'type': 'accommodation_booking',
          'bookingRef': ref,
          'role': 'host',
          'propertyName': prop,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
      if (kDebugMode) {
        debugPrint(
          '[OrderPartyNotification] accommodation alert queued toUid=$uid ref=$ref',
        );
      }
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishAccommodationBookingToHost: $e');
    }
  }
}
