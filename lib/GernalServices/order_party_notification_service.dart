import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';

/// Cross-user order alerts via Firestore. Content is shown in the Vero360 Team
/// chat; [NotificationService] only increments the badge count (`notifCounted`).
///
/// **Firestore rules:** allow authenticated `create` on [collectionName] with a
/// `toUid` field, and `read`/`update` only when `resource.data.toUid == request.auth.uid`.
class OrderPartyNotificationService {
  OrderPartyNotificationService._();

  static const String collectionName = 'order_party_alerts';

  static String _veroOrderNo(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return '';
    if (clean.toLowerCase().startsWith('vero')) return clean;
    return 'Vero$clean';
  }

  static Future<void> publishDigitalOrderToBuyer({
    required String buyerUid,
    required String productName,
    required String orderId,
    required String title,
    required String body,
    String type = 'digital_order',
  }) async {
    final uid = buyerUid.trim();
    if (uid.isEmpty) return;
    final name = productName.trim().isEmpty ? 'digital order' : productName.trim();
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': title.trim().isEmpty ? 'Digital order update' : title.trim(),
        'body': body.trim().isEmpty
            ? 'Open My Digital Orders for $name.'
            : body.trim(),
        'payload': {
          'type': type,
          'orderId': orderId,
          'productName': name,
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeDigitalOrders,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishDigitalOrderToBuyer: $e');
    }
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
            '$orderSeg$itemSeg has been shipped. Open Received Parcel to track '
            'progress and confirm when it arrives.',
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
        'read': false,
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

  /// Seller: admin confirmed a bank transfer — this is now a real paid order.
  static Future<void> publishNewMarketplaceOrderToMerchant({
    required String merchantUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
    String customerName = '',
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemPrefix = item.isEmpty ? '' : '$item - ';
    final who = customerName.trim();
    final customerSuffix = who.isEmpty ? '' : ' from $who';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'New order',
        'body': on.isEmpty
            ? 'You received a new paid order$customerSuffix. Open Send Parcel to ship it.'
            : 'New order received: $itemPrefix$on$customerSuffix. Open Send Parcel to ship it.',
        'payload': {
          'type': 'order_update',
          'orderId': orderId,
          'orderNumber': on,
          'status': 'confirmed',
          'role': 'merchant',
          'action': 'send_parcel',
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeShipped,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
        'from': 'vero360_team',
      });
    } catch (e) {
      debugPrint(
        '[OrderPartyNotification] publishNewMarketplaceOrderToMerchant: $e',
      );
    }
  }

  /// Kitchen merchant: a customer paid for a food order.
  static Future<void> publishNewFoodOrderToMerchant({
    required String merchantUid,
    required String customerName,
    required String orderNumber,
    required String orderId,
    required String itemsSummary,
    required double totalMwk,
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final who = customerName.trim().isEmpty ? 'A customer' : customerName.trim();
    final items = itemsSummary.trim().isEmpty ? 'food' : itemsSummary.trim();
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'New food order',
        'body': '$who has ordered $items',
        'payload': {
          'type': 'food_order',
          'orderId': orderId,
          'orderNumber': on,
          'status': 'pending',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishNewFoodOrderToMerchant: $e');
    }
  }

  /// Buyer: kitchen sent the food — confirm receipt in My Food Orders.
  static Future<void> publishFoodSentToBuyer({
    required String buyerUid,
    required String orderNumber,
    required String orderId,
    required String restaurantName,
  }) async {
    final uid = buyerUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final kitchen =
        restaurantName.trim().isEmpty ? 'the kitchen' : restaurantName.trim();
    final orderSeg = on.isEmpty ? 'Your food order' : 'Order $on';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Your food is on the way',
        'body':
            '$orderSeg from $kitchen has been sent. Open My Food Orders to track it and confirm when it arrives.',
        'payload': {
          'type': 'food_sent',
          'orderId': orderId,
          'orderNumber': on,
          'status': 'sent',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishFoodSentToBuyer: $e');
    }
  }

  /// Buyer: food order placed successfully.
  static Future<void> publishFoodOrderPlacedToBuyer({
    required String buyerUid,
    required String orderNumber,
    required String orderId,
    required String restaurantName,
    required String itemsSummary,
  }) async {
    final uid = buyerUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final kitchen =
        restaurantName.trim().isEmpty ? 'the kitchen' : restaurantName.trim();
    final items = itemsSummary.trim().isEmpty ? 'your order' : itemsSummary.trim();
    final orderSeg = on.isEmpty ? 'Your food order' : 'Order $on';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Food order placed',
        'body': '$orderSeg from $kitchen is confirmed — $items.',
        'payload': {
          'type': 'food_order_placed',
          'orderId': orderId,
          'orderNumber': on,
          'status': 'pending',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishFoodOrderPlacedToBuyer: $e');
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
    String? staySummary,
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
    final summary = (staySummary ?? '').trim();
    if (summary.isNotEmpty) {
      buf.write(' · $summary');
    } else if (nights != null && nights > 0) {
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

  /// Sender: parcel accepted / coming / delivered / cancelled (Vero Courier).
  static Future<void> publishCourierStatusToSender({
    required String senderUid,
    required String trackingCode,
    required String statusValue,
    String? pickup,
    String? dropoff,
    String? cancelReason,
  }) async {
    final uid = senderUid.trim();
    if (uid.isEmpty) return;

    final code = trackingCode.trim().isEmpty ? 'your parcel' : trackingCode.trim();
    final status = statusValue.trim().toUpperCase();
    final reason = (cancelReason ?? '').trim();

    late final String title;
    late final String body;
    late final String event;

    switch (status) {
      case 'PENDING':
        title = 'Parcel request received';
        body = 'We received your parcel $code. A courier will accept it shortly.';
        event = 'pending';
        break;
      case 'ACCEPTED':
        title = 'Parcel accepted';
        body = 'Your parcel $code has been accepted by Vero Courier.';
        event = 'accepted';
        break;
      case 'ON_THE_WAY':
      case 'COMING':
        title = 'Courier is coming';
        body = 'Your parcel $code is on the way. The courier is coming now.';
        event = 'coming';
        break;
      case 'CANCELLED':
      case 'REJECTED':
        title = 'Parcel rejected';
        body = reason.isNotEmpty
            ? 'Your parcel $code was rejected. Reason: $reason'
            : 'Your parcel $code was rejected. Contact support if you need help.';
        event = 'rejected';
        break;
      case 'DELIVERED':
        title = 'Parcel delivered';
        body = 'Your parcel $code has been delivered.';
        event = 'delivered';
        break;
      default:
        title = 'Parcel update';
        body = 'Your parcel $code status is now $status.';
        event = status.toLowerCase();
        break;
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
          if (reason.isNotEmpty) 'cancelReason': reason,
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

  /// Vero360 Team → buyer + merchant right after a paid marketplace order is held.
  static Future<void> publishPaidOrderTeamMessages({
    required String buyerUid,
    required String merchantUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
  }) async {
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'your order' : 'order $on';

    final buyer = buyerUid.trim();
    if (buyer.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection(collectionName).add({
          'toUid': buyer,
          'title': 'Vero360 Team',
          'body':
              'Your $orderSeg$itemSeg is confirmed and paid. '
              'When it ships, open Received Parcel to track and confirm receipt. '
              'If it is late, you can also remind the merchant from that order.',
          'payload': {
            'type': 'order_team_tip',
            'orderId': orderId,
            'orderNumber': on,
            'role': 'buyer',
            'action': 'received_parcel',
            NotificationStore.kPayloadBadgeRoute:
                NotificationStore.kBadgeReceived,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'consumed': false,
          'read': false,
          'from': 'vero360_team',
        });
      } catch (e) {
        debugPrint('[OrderPartyNotification] paidOrder buyer tip: $e');
      }
    }

    final merchant = merchantUid.trim();
    if (merchant.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection(collectionName).add({
          'toUid': merchant,
          'title': 'Vero360 Team',
          'body':
              'New paid $orderSeg$itemSeg. Open Send Parcel, pack and ship, '
              'then upload courier proof so the buyer can confirm on Received Parcel.',
          'payload': {
            'type': 'order_team_tip',
            'orderId': orderId,
            'orderNumber': on,
            'role': 'merchant',
            'action': 'send_parcel',
            NotificationStore.kPayloadBadgeRoute:
                NotificationStore.kBadgeShipped,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'consumed': false,
          'read': false,
          'from': 'vero360_team',
        });
      } catch (e) {
        debugPrint('[OrderPartyNotification] paidOrder merchant tip: $e');
      }
    }
  }

  /// Buyer asked the merchant to ship (also used for once-a-day reminders).
  static Future<void> publishShipReminderToMerchant({
    required String merchantUid,
    required String orderNumber,
    required String itemName,
    required String orderId,
    String buyerName = '',
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final on = _veroOrderNo(orderNumber);
    final item = itemName.trim();
    final itemSeg = item.isEmpty ? '' : ' — $item';
    final orderSeg = on.isEmpty ? 'An order' : 'Order $on';
    final who = buyerName.trim().isEmpty ? 'Your buyer' : buyerName.trim();
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Vero360 Team — ship reminder',
        'body':
            '$who reminded you to ship $orderSeg$itemSeg. '
            'Open Send Parcel, send the parcel, and upload courier proof.',
        'payload': {
          'type': 'ship_reminder',
          'orderId': orderId,
          'orderNumber': on,
          'action': 'send_parcel',
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeShipped,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
        'from': 'vero360_team',
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishShipReminderToMerchant: $e');
    }
  }

  /// Daily Vero360 Team nudge for merchants who have not shipped yet.
  static Future<void> publishTeamShipNudgeToMerchant({
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
    final orderSeg = on.isEmpty ? 'a paid order' : 'order $on';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Vero360 Team',
        'body':
            'Reminder: please ship $orderSeg$itemSeg. '
            'Buyers are waiting — open Send Parcel and upload courier proof.',
        'payload': {
          'type': 'ship_reminder',
          'orderId': orderId,
          'orderNumber': on,
          'source': 'team_nudge',
          'action': 'send_parcel',
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeShipped,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
        'from': 'vero360_team',
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishTeamShipNudgeToMerchant: $e');
    }
  }

  /// Vero360 Team → buyer when the order is fully done (funds released).
  static Future<void> publishOrderCompletedToBuyer({
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
    final orderSeg = on.isEmpty ? 'Your order' : 'Order $on';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Vero360 Team',
        'body':
            '$orderSeg$itemSeg is complete. You can review it on Received Parcel. '
            'Thanks for shopping on Vero360.',
        'payload': {
          'type': 'order_completed',
          'orderId': orderId,
          'orderNumber': on,
          'action': 'received_parcel',
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgeReceived,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
        'from': 'vero360_team',
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishOrderCompletedToBuyer: $e');
    }
  }

  /// Vero360 Team → merchant: listing quantity is finished — take it off the shelf.
  static Future<void> publishOutOfStockShelfReminder({
    required String merchantUid,
    required String itemName,
    String? orderNumber,
    String? orderId,
    int? listingSqlId,
    String? marketplaceItemId,
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final name = itemName.trim().isEmpty ? 'your listing' : itemName.trim();
    final on = _veroOrderNo(orderNumber ?? '');
    final orderSeg = on.isEmpty ? '' : ' (order $on)';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'Vero360 Team — out of stock',
        'body':
            '“$name”$orderSeg looks sold out. Please remove it from your shelf '
            'or set quantity to 0 / turn it off so buyers cannot order it again.',
        'payload': {
          'type': 'out_of_stock_shelf',
          'action': 'manage_shelf',
          'itemName': name,
          if (orderId != null && orderId.trim().isNotEmpty) 'orderId': orderId,
          if (listingSqlId != null && listingSqlId > 0) 'listingSqlId': listingSqlId,
          if (marketplaceItemId != null && marketplaceItemId.trim().isNotEmpty)
            'marketplaceItemId': marketplaceItemId.trim(),
          NotificationStore.kPayloadBadgeRoute:
              NotificationStore.kBadgePostArrival,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
        'from': 'vero360_team',
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishOutOfStockShelfReminder: $e');
    }
  }

  /// Story owner: someone liked their story.
  static Future<void> publishStoryLiked({
    required String ownerUid,
    required String likerUid,
    required String likerName,
    required String storyId,
  }) async {
    final to = ownerUid.trim();
    final from = likerUid.trim();
    if (to.isEmpty || from.isEmpty || to == from) return;
    final name = likerName.trim().isEmpty ? 'Someone' : likerName.trim();
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': to,
        'title': 'Story like',
        'body': '$name liked your story.',
        'payload': {
          'type': 'story_liked',
          'storyId': storyId,
          'likerUid': from,
          'likerName': name,
          'merchantId': to,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishStoryLiked: $e');
    }
  }

  /// Followers: a merchant you follow posted a new story.
  static Future<void> publishStoryPostedToFollowers({
    required String merchantUid,
    required String merchantName,
    String? serviceType,
  }) async {
    final mid = merchantUid.trim();
    if (mid.isEmpty) return;
    final name =
        merchantName.trim().isEmpty ? 'A seller you follow' : merchantName.trim();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('merchant_followers')
          .doc(mid)
          .collection('followers')
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      var writes = 0;
      for (final doc in snap.docs) {
        final toUid = (doc.id).trim();
        if (toUid.isEmpty || toUid == mid) continue;
        final ref =
            FirebaseFirestore.instance.collection(collectionName).doc();
        batch.set(ref, {
          'toUid': toUid,
          'title': 'New story',
          'body': '$name posted a new story. Tap to watch it.',
          'payload': {
            'type': 'story_posted',
            'merchantId': mid,
            'merchantName': name,
            if (serviceType != null && serviceType.trim().isNotEmpty)
              'serviceType': serviceType.trim().toLowerCase(),
          },
          'createdAt': FieldValue.serverTimestamp(),
          'consumed': false,
          'read': false,
        });
        writes++;
        // Firestore batch max 500; stay under for safety.
        if (writes >= 450) break;
      }
      if (writes > 0) await batch.commit();
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishStoryPostedToFollowers: $e');
    }
  }

  /// Merchant: someone left a star review on their shop.
  static Future<void> publishNewReviewToMerchant({
    required String merchantUid,
    required int rating,
    String? reviewerName,
    String? comment,
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return;
    final stars = rating.clamp(1, 5);
    final who =
        (reviewerName ?? '').trim().isEmpty ? 'A customer' : reviewerName!.trim();
    final note = (comment ?? '').trim();
    final body = note.isEmpty
        ? '$who rated you $stars★'
        : '$who rated you $stars★: ${note.length > 80 ? '${note.substring(0, 80)}…' : note}';
    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'toUid': uid,
        'title': 'New review',
        'body': body,
        'payload': {
          'type': 'new_review',
          'rating': stars,
          'merchantId': uid,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'consumed': false,
        'read': false,
      });
    } catch (e) {
      debugPrint('[OrderPartyNotification] publishNewReviewToMerchant: $e');
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
