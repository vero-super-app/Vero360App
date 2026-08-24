import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/GernalServices/paychangu_service.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/accommodation_occupancy_service.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/guest_booking_local_cache.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/utils/firebase_bootstrap.dart';

/// One row from Firestore [OrderRefundService.collectionName].
class RefundRequestRecord {
  final String id;
  final String orderId;
  final String orderNumber;
  final String itemName;
  final int amount;
  final String refundType;
  final String reason;
  final String status;
  final int processingDays;
  final String? serviceType;
  final DateTime? createdAt;
  final bool initiatedBySeller;

  const RefundRequestRecord({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.itemName,
    required this.amount,
    required this.refundType,
    required this.reason,
    required this.status,
    required this.processingDays,
    this.serviceType,
    this.createdAt,
    this.initiatedBySeller = false,
  });

  bool get isStay =>
      serviceType == 'accommodation' ||
      refundType == 'cancel_stay' ||
      refundType.toLowerCase().contains('stay');

  String get typeLabel {
    switch (refundType) {
      case 'cancel_order':
        return 'Cancel order and refund';
      case 'return_goods':
        return 'Return goods and refund';
      case 'cancel_stay':
        return 'Stay cancelled';
      default:
        return refundType.replaceAll('_', ' ');
    }
  }

  String get statusLabel {
    final s = status.toLowerCase().trim();
    if (s == 'success' || s == 'completed' || s == 'paid') return 'Completed';
    if (s == 'failed' || s == 'rejected') return 'Failed';
    if (s == 'processing') return 'Processing';
    return 'Pending';
  }

  /// Approximate funds-settlement deadline from request time.
  DateTime? get expectedBy {
    final start = createdAt;
    if (start == null) return null;
    final days = processingDays > 0 ? processingDays : OrderRefundService.processingDays;
    return start.add(Duration(days: days));
  }

  factory RefundRequestRecord.fromDoc(
    String id,
    Map<String, dynamic> m,
  ) {
    DateTime? created;
    final raw = m['createdAt'];
    if (raw is Timestamp) created = raw.toDate();
    return RefundRequestRecord(
      id: id,
      orderId: (m['orderId'] ?? '').toString(),
      orderNumber: (m['orderNumber'] ?? '').toString(),
      itemName: (m['itemName'] ?? '').toString(),
      amount: (m['amount'] is num)
          ? (m['amount'] as num).round()
          : int.tryParse('${m['amount']}') ?? 0,
      refundType: (m['refundType'] ?? '').toString(),
      reason: (m['reason'] ?? '').toString(),
      status: (m['status'] ?? 'pending').toString(),
      processingDays: (m['processingDays'] is num)
          ? (m['processingDays'] as num).toInt()
          : int.tryParse('${m['processingDays']}') ??
              OrderRefundService.processingDays,
      serviceType: m['serviceType']?.toString(),
      createdAt: created,
      initiatedBySeller: m['initiatedBySeller'] == true,
    );
  }
}

/// Orchestrates marketplace refunds: payments API → escrow void → order cancel.
class OrderRefundService {
  OrderRefundService._();

  static const String collectionName = 'refund_requests';
  static const int processingDays = 3;

  /// Days after receiving the parcel before return refunds are sealed.
  static const int returnWindowDays = 3;

  static const Duration returnWindowAfter =
      Duration(days: returnWindowDays);

  /// Whether a delivered order can still request “return goods”.
  ///
  /// After [returnWindowDays] from receipt (or when escrow is already released),
  /// business is sealed — no refund.
  static bool isReturnWindowOpen({
    DateTime? receivedAt,
    OrderEscrowSnapshot? escrow,
  }) {
    if (escrow != null) {
      if (escrow.isReleased || escrow.isRefunded) return false;
      final shipped = escrow.deliveredAt;
      if (shipped != null) {
        final sealAt = shipped.add(returnWindowAfter);
        if (!DateTime.now().isBefore(sealAt)) return false;
      }
      return true;
    }
    if (receivedAt == null) return true;
    final sealAt = receivedAt.add(returnWindowAfter);
    return DateTime.now().isBefore(sealAt);
  }

  static String sealedBusinessMessage() =>
      'Business is sealed. After $returnWindowDays days of receiving the parcel '
      'you can\'t refund.';

  /// Refund requests for the signed-in user (buyer, requester, or merchant).
  static Future<List<RefundRequestRecord>> fetchMyRefundRequests({
    int limit = 40,
  }) async {
    final firebaseOk = await ensureFirebaseApp();
    if (!firebaseOk) return const [];

    String uid = '';
    try {
      uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    } catch (_) {}
    if (uid.isEmpty) return const [];

    final col = FirebaseFirestore.instance.collection(collectionName);
    final byId = <String, RefundRequestRecord>{};

    Future<void> merge(Query<Map<String, dynamic>> query) async {
      try {
        final snap = await query.limit(limit).get();
        for (final doc in snap.docs) {
          byId[doc.id] =
              RefundRequestRecord.fromDoc(doc.id, doc.data());
        }
      } catch (e) {
        debugPrint('[OrderRefund] fetchMyRefundRequests query failed: $e');
      }
    }

    await Future.wait([
      merge(col.where('requestedByUid', isEqualTo: uid)),
      merge(col.where('buyerUid', isEqualTo: uid)),
      merge(col.where('merchantUid', isEqualTo: uid)),
    ]);

    final list = byId.values.toList()
      ..sort((a, b) {
        final aa = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bb.compareTo(aa);
      });
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  /// Submit a refund for [order].
  ///
  /// 1) Calls `POST /payments/refund` (PayChangu via backend)
  /// 2) Queues a Firestore [collectionName] row (status pending, 3-day SLA)
  /// 3) Voids escrow so the merchant is not paid
  /// 4) Cancels the order for cancel / return flows
  static Future<PaymentRefundResponse> submit({
    required OrderItem order,
    required PaymentRefundType refundType,
    required String reason,
    bool initiatedBySeller = false,
    OrderEscrowSnapshot? escrow,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw Exception('Please enter a reason for the refund.');
    }

    if (order.paymentStatus != PaymentStatus.paid &&
        order.status != OrderStatus.confirmed) {
      throw Exception('This order is not eligible for a refund.');
    }

    if (order.status == OrderStatus.cancelled) {
      throw Exception('This order is already cancelled.');
    }

    if (refundType == PaymentRefundType.cancelOrder &&
        order.status == OrderStatus.delivered) {
      throw Exception(
        'This order was already delivered. Choose “Return goods and refund”.',
      );
    }

    if (refundType == PaymentRefundType.returnGoods &&
        order.status != OrderStatus.delivered) {
      throw Exception(
        'Return goods is only available after delivery. '
        'Choose “Cancel order and refund”.',
      );
    }

    if (refundType == PaymentRefundType.returnGoods) {
      final esc = escrow ??
          await OrderEscrowService.fetchEscrowResolvingOrderId(order);
      if (!isReturnWindowOpen(
        receivedAt: esc?.deliveredAt ?? order.orderDate,
        escrow: esc,
      )) {
        throw Exception(sealedBusinessMessage());
      }
    }

    final amount = (order.price * order.quantity).toDouble();
    final txRef = (order.paymentTxRef ?? '').trim().isNotEmpty
        ? order.paymentTxRef!.trim()
        : await OrderEscrowService.fetchTxRefForOrder(order.id);

    final firebaseOk = await ensureFirebaseApp();
    if (!firebaseOk) {
      throw Exception(
        'App is still connecting. Please wait a moment and try the refund again.',
      );
    }

    PaymentRefundResponse apiResult;
    try {
      apiResult = await PaymentsService.requestRefund(
        orderId: order.id,
        orderNumber: order.orderNumber,
        amount: amount,
        refundType: refundType,
        reason: trimmed,
        txRef: txRef,
        itemName: order.itemName,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final endpointMissing = msg.contains('not available') ||
          msg.contains('404') ||
          msg.contains('not found');
      if (!endpointMissing) rethrow;

      // Backend refund route may not be deployed yet — queue locally.
      debugPrint('[OrderRefund] API missing, queuing locally: $e');
      apiResult = PaymentRefundResponse(
        status: 'pending',
        message:
            'Refund request queued. Funds are processed within $processingDays days.',
        txRef: txRef,
        processingDays: processingDays,
      );
    }

    String uid = '';
    try {
      uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {}
    final days = apiResult.processingDays > 0
        ? apiResult.processingDays
        : processingDays;

    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'orderId': order.id,
        'orderNumber': order.orderNumber,
        'itemName': order.itemName,
        'amount': amount.round(),
        'currency': 'MWK',
        'refundType': refundType.apiValue,
        'reason': trimmed,
        'txRef': txRef,
        'status': (apiResult.status ?? 'pending').toString(),
        'refundId': apiResult.refundId,
        'processingDays': days,
        'initiatedBySeller': initiatedBySeller,
        'requestedByUid': uid,
        'buyerUid': order.customerUid,
        'merchantUid': order.merchantUid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[OrderRefund] refund_requests write failed (continuing): $e');
    }

    try {
      await OrderEscrowService.cancelHoldForRefund(
        orderId: order.id,
        reason: trimmed,
        refundType: refundType.apiValue,
      );
    } catch (e) {
      debugPrint('[OrderRefund] escrow void failed (continuing): $e');
    }

    // Both refund types end the order so it leaves active shipping queues.
    try {
      await OrderService().cancelOrMarkCancelled(order.id);
    } catch (e) {
      debugPrint('[OrderRefund] cancel order failed (continuing): $e');
    }

    final merchantUid = (order.merchantUid ?? '').trim();
    if (merchantUid.isNotEmpty && !initiatedBySeller) {
      await OrderPartyNotificationService.publishRefundRequestedToMerchant(
        merchantUid: merchantUid,
        orderNumber: order.orderNumber,
        itemName: order.itemName,
        orderId: order.id,
        refundType: refundType.label,
        reason: trimmed,
      );
    }

    final buyerUid = (order.customerUid ?? '').trim();
    if (buyerUid.isNotEmpty) {
      await OrderPartyNotificationService.publishRefundUpdateToBuyer(
        buyerUid: buyerUid,
        orderNumber: order.orderNumber,
        itemName: order.itemName,
        orderId: order.id,
        refundType: refundType.label,
        processingDays: days,
      );
    }

    return PaymentRefundResponse(
      status: apiResult.status ?? 'pending',
      message: apiResult.message ??
          'Refund submitted. Funds are processed within $days days.',
      refundId: apiResult.refundId,
      txRef: apiResult.txRef ?? txRef,
      processingDays: days,
    );
  }

  /// Guest cancelled a paid stay before check-in / arrival confirmation.
  ///
  /// Voids host escrow, queues PayChangu refund (typically 3 days), and
  /// cancels the booking so those nights are free again.
  static Future<PaymentRefundResponse> submitStayCancellation({
    required BookingItem booking,
    required OrderEscrowSnapshot escrow,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw Exception('Please enter a reason for the refund.');
    }
    if (booking.status == BookingStatus.cancelled) {
      throw Exception('This stay is already cancelled.');
    }
    if (!escrow.isHeld) {
      throw Exception(
        escrow.isReleased
            ? 'Payment was already released to the host, so this stay cannot be refunded.'
            : escrow.isRefunded
                ? 'A refund was already requested for this stay.'
                : 'This stay is not eligible for a refund.',
      );
    }

    final start = booking.bookingDate;
    if (start != null) {
      final today = DateTime.now();
      final checkIn = DateTime(start.year, start.month, start.day);
      final d = DateTime(today.year, today.month, today.day);
      if (!d.isBefore(checkIn)) {
        throw Exception(
          'Refunds are only available before check-in day. '
          'After that, confirm arrival or contact support.',
        );
      }
    }

    // Must be ready before Auth/Firestore — otherwise we crash with core/no-app
    // after the payments API may already have cancelled the stay.
    final firebaseOk = await ensureFirebaseApp();
    if (!firebaseOk) {
      throw Exception(
        'App is still connecting. Please wait a moment and try the refund again.',
      );
    }

    final amount = booking.total.toDouble();
    if (amount <= 0) {
      throw Exception('Invalid refund amount.');
    }

    final txRef = await OrderEscrowService.fetchTxRefForOrder(escrow.orderId);
    final bookingRef = (booking.bookingNumber ?? booking.displayBookingRef)
        .trim()
        .isNotEmpty
        ? (booking.bookingNumber ?? booking.displayBookingRef).trim()
        : booking.id.trim();
    final stayName = (booking.accommodationName ?? 'Stay').trim();

    PaymentRefundResponse apiResult;
    try {
      apiResult = await PaymentsService.requestRefund(
        orderId: escrow.orderId,
        orderNumber: bookingRef,
        amount: amount,
        refundType: PaymentRefundType.cancelOrder,
        reason: trimmed,
        txRef: txRef,
        itemName: stayName,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final endpointMissing = msg.contains('not available') ||
          msg.contains('404') ||
          msg.contains('not found');
      if (!endpointMissing) rethrow;
      debugPrint('[OrderRefund] Stay refund API missing, queuing locally: $e');
      apiResult = PaymentRefundResponse(
        status: 'pending',
        message:
            'Refund request queued. Funds are processed within $processingDays days.',
        txRef: txRef,
        processingDays: processingDays,
      );
    }

    String uid = '';
    try {
      uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {}

    final days = apiResult.processingDays > 0
        ? apiResult.processingDays
        : processingDays;

    try {
      await FirebaseFirestore.instance.collection(collectionName).add({
        'orderId': escrow.orderId,
        'bookingId': booking.id,
        'orderNumber': bookingRef,
        'itemName': stayName,
        'amount': amount.round(),
        'currency': 'MWK',
        'refundType': 'cancel_stay',
        'serviceType': 'accommodation',
        'reason': trimmed,
        'txRef': txRef,
        'status': (apiResult.status ?? 'pending').toString(),
        'refundId': apiResult.refundId,
        'processingDays': days,
        'initiatedBySeller': false,
        'requestedByUid': uid,
        'buyerUid': escrow.buyerUid,
        'merchantUid': escrow.merchantUid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[OrderRefund] refund_requests write failed (continuing): $e');
    }

    try {
      await OrderEscrowService.cancelHoldForRefund(
        orderId: escrow.orderId,
        reason: trimmed,
        refundType: 'cancel_stay',
      );
    } catch (e) {
      debugPrint('[OrderRefund] escrow void failed (continuing): $e');
    }

    try {
      final id = booking.id.trim();
      if (id.isNotEmpty) {
        await MyBookingService().cancelOrDelete(id);
      }
    } catch (e) {
      debugPrint('[OrderRefund] cancel stay booking failed (continuing): $e');
    }

    try {
      await GuestBookingLocalCache.removeStay(booking);
    } catch (e) {
      debugPrint('[OrderRefund] local stay cache remove failed: $e');
    }

    final accId = booking.accommodationId;
    if (accId != null && accId > 0) {
      final occ = AccommodationOccupancyService();
      for (final ref in {
        bookingRef,
        booking.id.trim(),
        booking.displayBookingRef.trim()
      }) {
        if (ref.isEmpty) continue;
        try {
          await occ.releaseCancelledStay(
            accommodationId: accId,
            bookingRef: ref,
          );
        } catch (e) {
          debugPrint('[OrderRefund] occupancy release failed: $e');
        }
      }
    }

    final hostUid = escrow.merchantUid.trim();
    if (hostUid.isNotEmpty) {
      try {
        await OrderPartyNotificationService.publishRefundRequestedToMerchant(
          merchantUid: hostUid,
          orderNumber: bookingRef,
          itemName: stayName,
          orderId: escrow.orderId,
          refundType: 'Stay cancelled — guest changed their mind',
          reason: trimmed,
        );
      } catch (e) {
        debugPrint('[OrderRefund] host notify failed: $e');
      }
    }

    final guestUid = escrow.buyerUid.trim().isNotEmpty
        ? escrow.buyerUid.trim()
        : uid;
    if (guestUid.isNotEmpty) {
      try {
        await OrderPartyNotificationService.publishRefundUpdateToBuyer(
          buyerUid: guestUid,
          orderNumber: bookingRef,
          itemName: stayName,
          orderId: escrow.orderId,
          refundType: 'Stay cancelled — refund requested',
          processingDays: days,
        );
      } catch (e) {
        debugPrint('[OrderRefund] guest refund notify failed: $e');
      }
    }

    try {
      await NotificationService.instance.showManualNotification(
        title: 'Stay refund requested',
        body:
            'Your stay at $stayName was cancelled. Refund for booking $bookingRef '
            'is processing (within $days days).',
        payload:
            '{"type":"refund_update","orderId":"${escrow.orderId}","bookingRef":"$bookingRef"}',
      );
    } catch (e) {
      debugPrint('[OrderRefund] local guest notification failed: $e');
    }

    return PaymentRefundResponse(
      status: apiResult.status ?? 'pending',
      message: apiResult.message ??
          'Refund submitted. Funds are processed within $days days.',
      refundId: apiResult.refundId,
      txRef: apiResult.txRef ?? txRef,
      processingDays: days,
    );
  }
}
