import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/chat_notification_service.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';

/// Buyer can remind the merchant to ship **once per calendar day** per order.
/// Sends an inbox (order_party_alerts) ping + a chat message in their thread.
class OrderShippingReminderService {
  OrderShippingReminderService._();

  static String _dayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static String _prefKey(String orderId) =>
      'ship_remind_${orderId.trim()}_${_dayKey()}';

  static Future<bool> canRemindToday(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_prefKey(id)) ?? false);
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markReminded(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey(orderId), true);
    } catch (_) {}
  }

  /// Vero360 Team daily nudge when a merchant still has unshipped paid orders.
  static Future<bool> maybeTeamNudgeMerchant({
    required String orderId,
    required String merchantUid,
    required String orderNumber,
    required String itemName,
  }) async {
    final oid = orderId.trim();
    final mid = merchantUid.trim();
    if (oid.isEmpty || mid.isEmpty) return false;

    final key = 'team_ship_nudge_${oid}_${_dayKey()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return false;
      await OrderPartyNotificationService.publishTeamShipNudgeToMerchant(
        merchantUid: mid,
        orderNumber: orderNumber,
        itemName: itemName,
        orderId: oid,
      );
      await prefs.setBool(key, true);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[ShipReminder] team nudge failed: $e');
      return false;
    }
  }

  static String reminderChatBody(OrderItem o) {
    final on = o.orderNumber.trim();
    final shop = (o.merchantName ?? '').trim();
    final hello = shop.isEmpty || shop.contains('@') ? 'Hi' : 'Hi @$shop';
    return [
      hello,
      '',
      'Friendly reminder from me (and Vero360 Team): please ship my parcel.',
      '',
      'Order: ${on.isEmpty ? o.id : on}',
      'Item: ${o.itemName}',
      if (o.quantity > 1) 'Qty: ${o.quantity}',
      '',
      'When you ship, upload courier proof in To Ship so I can confirm receipt.',
    ].join('\n');
  }

  /// Returns a short user-facing result message.
  static Future<OrderRemindResult> remindMerchant({
    required OrderItem order,
    required String merchantUid,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (myUid.isEmpty) {
      return const OrderRemindResult(
        ok: false,
        message: 'Sign in to remind the merchant.',
      );
    }

    final buyerUid = (order.customerUid ?? '').trim();
    if (buyerUid.isNotEmpty && buyerUid != myUid) {
      return const OrderRemindResult(
        ok: false,
        message: 'Only the buyer can remind the merchant.',
      );
    }

    if (!await canRemindToday(order.id)) {
      return const OrderRemindResult(
        ok: false,
        alreadyRemindedToday: true,
        message:
            'You already reminded the merchant today. You can remind again tomorrow.',
      );
    }

    final mid = merchantUid.trim().isNotEmpty
        ? merchantUid.trim()
        : (order.merchantUid ?? '').trim();
    if (mid.isEmpty && order.merchantId <= 0 && (order.itemSqlId ?? 0) <= 0) {
      return const OrderRemindResult(
        ok: false,
        message: 'Merchant contact is not available.',
      );
    }

    try {
      // 1) Inbox / push to merchant (Vero360 Team).
      if (mid.isNotEmpty) {
        await OrderPartyNotificationService.publishShipReminderToMerchant(
          merchantUid: mid,
          orderNumber: order.orderNumber,
          itemName: order.itemName,
          orderId: order.id,
          buyerName: (order.customerName ?? '').trim(),
        );
      }

      // 2) Chat message in buyer↔merchant thread.
      try {
        await BackendChatService.warmForMarketplaceChat();
        final chat = await BackendChatService.startMerchantChat(
          sqlItemId: (order.itemSqlId ?? 0) > 0 ? order.itemSqlId : null,
          ownerId: order.merchantId > 0 ? order.merchantId : null,
          merchantId: mid.isNotEmpty ? mid : null,
        );
        final body = reminderChatBody(order);
        final day = _dayKey();
        await BackendChatService.sendMessage(
          chatId: chat.chat.id,
          content: body,
          type: 'text',
          clientMessageId: 'order-remind-${order.id}-$day',
          metadata: {
            'source': 'ship_reminder',
            'orderId': order.id,
            'auto': true,
          },
        );
        try {
          final displayName =
              (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
          await ChatNotificationService.notifyRecipientOfMessage(
            chatId: chat.chat.id,
            senderName: displayName.isEmpty ? 'Buyer' : displayName,
            body: 'Reminder: please ship order ${order.orderNumber}',
            recipientFirebaseUid: mid.isNotEmpty ? mid : null,
            recipientUserId: chat.sellerId > 0 ? chat.sellerId : null,
          );
        } catch (_) {}
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ShipReminder] chat send failed (alert still sent): $e');
        }
      }

      await _markReminded(order.id);
      return const OrderRemindResult(
        ok: true,
        message:
            'Reminder sent. The merchant was notified in their inbox. You can remind again tomorrow.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ShipReminder] failed: $e');
      return const OrderRemindResult(
        ok: false,
        message: 'Could not send reminder. Try again.',
      );
    }
  }
}

class OrderRemindResult {
  final bool ok;
  final bool alreadyRemindedToday;
  final String message;

  const OrderRemindResult({
    required this.ok,
    this.alreadyRemindedToday = false,
    this.message = '',
  });
}
