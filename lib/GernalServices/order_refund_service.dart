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

/// Orchestrates marketplace refunds: payments API → escrow void → order cancel.
class OrderRefundService {
  OrderRefundService._();

  static const String collectionName = 'refund_requests';
  static const int processingDays = 3;

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

    final amount = (order.price * order.quantity).toDouble();
    final txRef = (order.paymentTxRef ?? '').trim().isNotEmpty
        ? order.paymentTxRef!.trim()
        : await OrderEscrowService.fetchTxRefForOrder(order.id);

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

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final days = apiResult.processingDays > 0
        ? apiResult.processingDays
        : processingDays;

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

    await OrderEscrowService.cancelHoldForRefund(
      orderId: order.id,
      reason: trimmed,
      refundType: refundType.apiValue,
    );

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
    if (buyerUid.isNotEmpty && initiatedBySeller) {
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

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final days = apiResult.processingDays > 0
        ? apiResult.processingDays
        : processingDays;

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

    await OrderEscrowService.cancelHoldForRefund(
      orderId: escrow.orderId,
      reason: trimmed,
      refundType: 'cancel_stay',
    );

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
      for (final ref in {bookingRef, booking.id.trim(), booking.displayBookingRef.trim()}) {
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
      await OrderPartyNotificationService.publishRefundRequestedToMerchant(
        merchantUid: hostUid,
        orderNumber: bookingRef,
        itemName: stayName,
        orderId: escrow.orderId,
        refundType: 'Stay cancelled — guest changed their mind',
        reason: trimmed,
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
}
