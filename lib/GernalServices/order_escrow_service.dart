import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/config/api_config.dart';

/// Firestore: `order_escrow/{orderId}` — holds marketplace funds until buyer confirms
/// receipt or [escrowAutoReleaseDays] pass after delivery.
///
/// **Security:** Release is enforced in app logic; production should use Cloud Functions
/// + Firestore rules so funds cannot be released twice or by the wrong user.
class OrderEscrowService {
  OrderEscrowService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'order_escrow';

  /// Days after [markDelivered] when funds auto-release to the merchant if not confirmed.
  static const int escrowAutoReleaseDays = 5;

  static DocumentReference<Map<String, dynamic>> _doc(String orderId) =>
      _db.collection(_collection).doc(orderId);

  /// Creates a hold row per marketplace order (after payment + backend order creation).
  /// Does not credit the merchant — that happens on [releaseFunds].
  static Future<void> createHoldsForOrders({
    required String txRef,
    required List<CreatedOrderRef> refs,
  }) async {
    final buyerUid = FirebaseAuth.instance.currentUser?.uid;
    if (buyerUid == null || buyerUid.isEmpty) {
      throw StateError('You must be signed in to place a hold.');
    }

    const feeRate = FirebaseWalletService.serviceFeeRate;
    final batch = _db.batch();

    for (final r in refs) {
      if (!r.item.hasValidMerchant) continue;
      if (r.item.serviceType != 'marketplace') continue;

      final gross = r.item.price * r.item.quantity;
      if (gross <= 0) continue;

      final merchantAmount = gross * (1.0 - feeRate);
      final feeAmount = gross * feeRate;

      batch.set(
        _doc(r.orderId),
        {
          'buyerUid': buyerUid,
          'merchantUid': r.item.merchantId,
          'merchantName': r.item.merchantName,
          'merchantAmount': merchantAmount,
          'serviceFeeAmount': feeAmount,
          'txRef': txRef,
          'orderNumber': r.orderNumber,
          'itemName': r.item.name,
          'status': 'held',
          'deliveredAt': null,
          'releaseDueAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  /// Call when the merchant marks the order as delivered (starts the 5-day window).
  static Future<void> markDelivered(String orderId) async {
    final snap = await _doc(orderId).get();
    if (!snap.exists) return;

    final data = snap.data();
    if (data == null) return;
    if (data['status'] != 'held') return;
    if (data['deliveredAt'] != null) return;

    final now = DateTime.now();
    final due = now.add(const Duration(days: escrowAutoReleaseDays));

    await _doc(orderId).update({
      'deliveredAt': Timestamp.fromDate(now),
      'releaseDueAt': Timestamp.fromDate(due),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// If the order is delivered in the API but escrow still has no [deliveredAt], repair.
  static Future<void> repairDeliveredTimestampIfNeeded(OrderItem o) async {
    if (o.status != OrderStatus.delivered) return;
    final snap = await _doc(o.id).get();
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null) return;
    if (data['status'] != 'held') return;
    if (data['deliveredAt'] != null) return;
    await markDelivered(o.id);
  }

  static Future<OrderEscrowSnapshot?> fetchEscrow(String orderId) async {
    final snap = await _doc(orderId).get();
    if (!snap.exists || snap.data() == null) return null;
    return OrderEscrowSnapshot.fromMap(orderId, snap.data()!);
  }

  static Future<Map<String, OrderEscrowSnapshot?>> fetchEscrowForOrderIds(
    Iterable<String> orderIds,
  ) async {
    final out = <String, OrderEscrowSnapshot?>{};
    await Future.wait(orderIds.map((id) async {
      out[id] = await fetchEscrow(id);
    }));
    return out;
  }

  /// Buyer confirmed receipt ([buyerConfirmed]=true) or auto window passed ([buyerConfirmed]=false).
  static Future<void> releaseFunds({
    required String orderId,
    required bool buyerConfirmed,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in required.');
    }

    final ref = _doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('No payment hold for this order.');
    }

    final data = Map<String, dynamic>.from(snap.data()!);
    final status = (data['status'] ?? '').toString();
    if (status == 'released' || status == 'auto_released') {
      return;
    }
    if (status != 'held') {
      throw StateError('This order is not on hold.');
    }

    if (buyerConfirmed) {
      final buyerUid = (data['buyerUid'] ?? '').toString();
      if (buyerUid != uid) {
        throw StateError('Only the buyer can confirm this order.');
      }
    } else {
      final due = data['releaseDueAt'];
      if (due is! Timestamp) {
        throw StateError('Delivery date not set yet for auto-release.');
      }
      if (due.toDate().isAfter(DateTime.now())) {
        throw StateError('Auto-release is not due yet.');
      }
    }

    final merchantUid = (data['merchantUid'] ?? '').toString().trim();
    final merchantName = (data['merchantName'] ?? 'Merchant').toString();
    final amount = (data['merchantAmount'] ?? 0.0);
    final merchantAmount = amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0.0;
    final feeRaw = data['serviceFeeAmount'] ?? 0.0;
    final serviceFee = feeRaw is num ? feeRaw.toDouble() : double.tryParse('$feeRaw') ?? 0.0;
    final txRef = (data['txRef'] ?? orderId).toString();

    if (merchantUid.isEmpty || merchantAmount <= 0) {
      throw StateError('Invalid escrow data.');
    }

    await FirebaseWalletService.getOrCreateWallet(
      merchantId: merchantUid,
      merchantName: merchantName,
    );

    await FirebaseWalletService.creditWallet(
      merchantId: merchantUid,
      amount: merchantAmount,
      description: buyerConfirmed
          ? 'Marketplace sale — buyer confirmed receipt'
          : 'Marketplace sale — auto-released after $escrowAutoReleaseDays days',
      reference: txRef,
      type: 'sale_escrow',
    );

    if (serviceFee > 0) {
      await _recordServiceFeeWithAdminApi(amount: serviceFee, txRef: txRef);
    }

    await ref.update({
      'status': buyerConfirmed ? 'released' : 'auto_released',
      'releasedAt': FieldValue.serverTimestamp(),
      'releaseKind': buyerConfirmed ? 'buyer_confirm' : 'auto_5d',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (buyerConfirmed && merchantUid.isNotEmpty) {
      final orderNo = (data['orderNumber'] ?? '').toString();
      final itemNm = (data['itemName'] ?? '').toString();
      await OrderPartyNotificationService.publishFundsReleasedToMerchant(
        merchantUid: merchantUid,
        orderNumber: orderNo,
        itemName: itemNm,
        orderId: orderId,
      );
    }
  }

  static Future<void> _recordServiceFeeWithAdminApi({
    required double amount,
    required String txRef,
  }) async {
    if (!ApiConfig.isAdminApiConfigured) {
      debugPrint('[OrderEscrow] Admin API not configured; service fee not reported.');
      return;
    }
    try {
      final base = ApiConfig.adminApiBase.trim().replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse('$base/api/admin/record-service-fee');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({
          'amount': amount,
          'txRef': txRef,
          'secret': ApiConfig.adminServiceFeeSecret,
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[OrderEscrow] Service fee reported: $amount MWK');
      } else {
        debugPrint(
          '[OrderEscrow] Admin API ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[OrderEscrow] Failed to report service fee: $e');
    }
  }
}

class OrderEscrowSnapshot {
  final String orderId;
  final String status;
  final DateTime? deliveredAt;
  final DateTime? releaseDueAt;
  final DateTime? releasedAt;
  final String buyerUid;
  final String merchantUid;

  OrderEscrowSnapshot({
    required this.orderId,
    required this.status,
    this.deliveredAt,
    this.releaseDueAt,
    this.releasedAt,
    this.buyerUid = '',
    this.merchantUid = '',
  });

  bool get isHeld => status == 'held';
  bool get isReleased => status == 'released' || status == 'auto_released';

  factory OrderEscrowSnapshot.fromMap(String orderId, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return OrderEscrowSnapshot(
      orderId: orderId,
      status: (m['status'] ?? '').toString(),
      deliveredAt: ts(m['deliveredAt']),
      releaseDueAt: ts(m['releaseDueAt']),
      releasedAt: ts(m['releasedAt']),
      buyerUid: (m['buyerUid'] ?? '').toString(),
      merchantUid: (m['merchantUid'] ?? '').toString(),
    );
  }
}
