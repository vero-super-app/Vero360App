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

  /// Merchant wallet credited after buyer confirm or auto-release.
  static Future<void> publishFundsReleasedToMerchant({
    required String merchantUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
    bool buyerConfirmed = true,
    String autoReleaseLabel = '7 days',
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'The order' : 'Order $on';
    final title = buyerConfirmed
        ? 'Buyer confirmed receipt'
        : 'Escrow funds released';
    final body = buyerConfirmed
        ? '$orderSeg$itemSeg has been received. Funds have been transferred to your wallet.'
        : '$orderSeg$itemSeg — $autoReleaseLabel escrow ended. Funds have been transferred to your wallet.';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': title,
        'body': body,
        'payload': {
          'type': 'order_escrow_released',
          'releaseKind': buyerConfirmed ? 'buyer_confirm' : 'auto_7d',
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

  /// Merchant: buyer applied for a refund.
  static Future<void> publishRefundRequestedToMerchant({
    required String merchantUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
    required String refundType,
    required String reason,
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'An order' : 'Order $on';
    final type = refundType.trim().isEmpty ? 'Refund' : refundType.trim();
    final why = reason.trim();
    final body = why.isEmpty
        ? '$orderSeg$itemSeg: $type requested. Refunds are processed within 3 days.'
        : '$orderSeg$itemSeg: $type. Reason: $why. Refunds are processed within 3 days.';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Refund requested',
        'body': body,
        'payload': {
          'type': 'refund_request',
          'orderId': orderId,
          'orderNumber': on,
          'refundType': type,
          NotificationStore.kPayloadBadgeRoute: NotificationStore.kBadgeRefund,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint(
        '[OrderPartyNotification] publishRefundRequestedToMerchant: $e',
      );
    }
  }

  /// Buyer: seller initiated a refund / update.
  static Future<void> publishRefundUpdateToBuyer({
    required String buyerUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
    required String refundType,
    int processingDays = 3,
  }) async {
    final uid = buyerUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'Your order' : 'Your order $on';
    final type = refundType.trim().isEmpty ? 'Refund' : refundType.trim();
    final days = processingDays > 0 ? processingDays : 3;
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Refund update',
        'body':
            '$orderSeg$itemSeg: $type. Your refund will be processed within $days days.',
        'payload': {
          'type': 'refund_update',
          'orderId': orderId,
          'orderNumber': on,
          'refundType': type,
          'processingDays': days,
          NotificationStore.kPayloadBadgeRoute: NotificationStore.kBadgeRefund,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishRefundUpdateToBuyer: $e');
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

  /// Sender: parcel accepted / rejected / delivered (Vero Courier).
  static Future<void> publishCourierStatusToSender({
    required String senderUid,
    required String trackingCode,
    required String statusValue,
    String? pickup,
    String? dropoff,
  }) async {
    final uid = senderUid.trim();
    if (uid.isEmpty) return;

    final code = trackingCode.trim().isEmpty ? 'your parcel' : trackingCode.trim();
    final status = statusValue.trim().toUpperCase();

    late final String title;
    late final String body;
    late final String event;

    switch (status) {
      case 'ACCEPTED':
        title = 'Parcel accepted';
        body = 'Your parcel $code has been accepted by Vero Courier.';
        event = 'accepted';
        break;
      case 'CANCELLED':
        title = 'Parcel rejected';
        body = 'Your parcel $code was rejected. Contact support if you need help.';
        event = 'rejected';
        break;
      case 'DELIVERED':
        title = 'Parcel delivered';
        body = 'Your parcel $code has been delivered.';
        event = 'delivered';
        break;
      default:
        return;
    }

    final from = (pickup ?? '').trim();
    final to = (dropoff ?? '').trim();
    final routeSeg = (from.isNotEmpty && to.isNotEmpty) ? ' ($from → $to)' : '';

    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': title,
        'body': '$body$routeSeg',
        'payload': {
          'type': 'courier_status',
          'status': event,
          'trackingNumber': code,
          'courierStatus': status,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
      if (kDebugMode) {
        debugPrint(
          '[OrderPartyNotification] courier $event queued toUid=$uid code=$code',
        );
      }
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishCourierStatusToSender: $e');
    }
  }

  /// Resolve Firebase Auth uid from a users/{doc} email field (best-effort).
  static Future<String?> resolveUidByEmail(String? email) async {
    final e = (email ?? '').trim().toLowerCase();
    if (e.isEmpty || e == 'no-email@vero.local') return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: e)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (err) {
      debugPrint('[OrderPartyNotification] resolveUidByEmail: $err');
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: (email ?? '').trim())
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (_) {}
    return null;
  }
}
