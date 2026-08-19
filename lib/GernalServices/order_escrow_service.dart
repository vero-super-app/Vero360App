import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/GernalServices/delivery_proof_service.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/GernalServices/order_party_notification_service.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/config/api_config.dart';

/// Params for [OrderEscrowService.createHoldForAccommodationBooking] — ties PayChangu
/// success to host escrow shown on [MerchantWalletPage].
class AccommodationEscrowParams {
  final String hostMerchantUid;
  final String hostDisplayName;
  final String bookingRef;
  final String propertyName;

  const AccommodationEscrowParams({
    required this.hostMerchantUid,
    required this.hostDisplayName,
    required this.bookingRef,
    required this.propertyName,
  });
}

/// Firestore: `order_escrow/{orderId}` — holds marketplace (and accommodation) funds
/// until release rules apply.
///
/// **Release paths:**
/// - Buyer confirms receipt in the app → credits wallet + merchant notification
/// - App open / wallet refresh after `releaseDueAt` → auto-release
/// - Cloud Function `releaseDueEscrowHolds` (hourly) → auto-release even if nobody
///   opens the app; `onEscrowReleased` sends FCM for app-side releases
///
/// **Security:** Prefer Cloud Functions for production crediting; app paths remain
/// as a fallback. Firestore rules should prevent arbitrary client credit of wallets.
class OrderEscrowService {
  OrderEscrowService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'order_escrow';

  /// Set `true` only while testing auto-release. Flip back to `false` for production (7 days).
  static const bool escrowTestMode = false;

  /// Production hold window after shipment.
  static const int escrowAutoReleaseDays = 7;

  /// Test hold window after shipment (used when [escrowTestMode] is true).
  static const Duration escrowTestReleaseAfter = Duration(minutes: 2);

  /// Effective auto-release delay after [markDelivered].
  static Duration get escrowAutoReleaseAfter =>
      escrowTestMode ? escrowTestReleaseAfter : const Duration(days: escrowAutoReleaseDays);

  /// Short label for UI ("2 min" / "7 days").
  static String get escrowAutoReleaseLabel {
    if (!escrowTestMode) {
      return '$escrowAutoReleaseDays days';
    }
    final m = escrowTestReleaseAfter.inMinutes;
    if (m > 0 && escrowTestReleaseAfter.inSeconds == m * 60) {
      return '$m min';
    }
    return '${escrowTestReleaseAfter.inSeconds}s';
  }

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

    const feeRate = FirebaseWalletService.marketplaceServiceFeeRate;
    final batch = _db.batch();

    for (final r in refs) {
      if (!r.item.hasValidMerchant) continue;
      if (r.item.serviceType != 'marketplace') continue;

      final gross = r.item.price * r.item.quantity;
      if (gross <= 0) continue;

      final merchantAmount = gross * (1.0 - feeRate);
      final feeAmount = gross * feeRate;

      // Always clear delivery fields so a reused/merged doc cannot keep an old
      // shipped date (e.g. "Shipped Jul 27" on a purchase made today).
      batch.set(
        _doc(r.orderId),
        {
          'buyerUid': buyerUid,
          'merchantUid': r.item.merchantId,
          'merchantName': r.item.merchantName,
          'merchantAmount': merchantAmount,
          'serviceFeeAmount': feeAmount,
          'feeRate': feeRate,
          'serviceType': 'marketplace',
          'grossAmount': gross,
          'txRef': txRef,
          'orderNumber': r.orderNumber,
          'itemName': r.item.name,
          'status': 'held',
          'deliveredAt': FieldValue.delete(),
          'releaseDueAt': FieldValue.delete(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  /// Escrow hold for a paid food order (10% platform fee, same as marketplace).
  /// Doc id = [orderId] from `food_orders`.
  static Future<void> createHoldForFoodOrder({
    required String orderId,
    required String txRef,
    required String merchantUid,
    required String merchantName,
    required String foodName,
    required double grossAmountMwk,
    String? orderNumber,
  }) async {
    final mid = merchantUid.trim();
    final oid = orderId.trim();
    if (mid.isEmpty || oid.isEmpty) return;

    final buyerUid = FirebaseAuth.instance.currentUser?.uid;
    if (buyerUid == null || buyerUid.isEmpty) {
      debugPrint('[OrderEscrowService] Skip food hold: buyer not signed in');
      return;
    }

    final gross = grossAmountMwk;
    if (gross <= 0) return;

    const feeRate = FirebaseWalletService.marketplaceServiceFeeRate;
    final merchantAmount = gross * (1.0 - feeRate);
    final feeAmount = gross * feeRate;

    await _doc(oid).set(
      {
        'buyerUid': buyerUid,
        'merchantUid': mid,
        'merchantName':
            merchantName.trim().isEmpty ? 'Kitchen' : merchantName.trim(),
        'merchantAmount': merchantAmount,
        'serviceFeeAmount': feeAmount,
        'feeRate': feeRate,
        'grossAmount': gross,
        'txRef': txRef,
        'orderNumber': (orderNumber ?? oid).trim(),
        'itemName': foodName.trim().isEmpty ? 'Food order' : foodName.trim(),
        'status': 'held',
        'serviceType': 'food',
        'deliveredAt': FieldValue.delete(),
        'releaseDueAt': FieldValue.delete(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Food kitchen marks delivered/completed → credit kitchen + 10% platform fee.
  static Future<void> releaseFoodOrderByMerchant(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in required.');
    }

    final oid = orderId.trim();
    if (oid.isEmpty) return;

    final ref = _doc(oid);
    final snap = await ref.get();
    if (!snap.exists) {
      debugPrint('[OrderEscrow] No food escrow hold for $oid');
      return;
    }

    final data = Map<String, dynamic>.from(snap.data()!);
    final status = (data['status'] ?? '').toString();
    if (status == 'released' || status == 'auto_released') return;
    if (status != 'held') {
      throw StateError('This food order is not on hold.');
    }

    final serviceType =
        (data['serviceType'] ?? '').toString().trim().toLowerCase();
    if (serviceType != 'food') {
      throw StateError('Not a food escrow hold.');
    }

    final merchantUid = (data['merchantUid'] ?? '').toString().trim();
    if (merchantUid.isEmpty || merchantUid != uid.trim()) {
      throw StateError('Only the kitchen merchant can release this order.');
    }

    // Stamp delivery then release (merchant fulfillment = paid).
    await markDelivered(oid);
    await _creditAndCloseEscrow(
      orderId: oid,
      data: data,
      buyerConfirmed: true,
      releaseKind: 'merchant_delivered',
      releaseSource: 'food_merchant',
    );
  }

  /// Escrow row for a paid accommodation booking (guest checkout via PayChangu).
  /// Document id is derived from [params.bookingRef] so retries don’t duplicate.
  static Future<void> createHoldForAccommodationBooking({
    required String txRef,
    required double grossAmountMwk,
    required AccommodationEscrowParams params,
  }) async {
    final hostUid = params.hostMerchantUid.trim();
    if (hostUid.isEmpty) return;

    final buyerUid = FirebaseAuth.instance.currentUser?.uid;
    if (buyerUid == null || buyerUid.isEmpty) {
      debugPrint(
          '[OrderEscrowService] Skip accommodation hold: buyer not signed in');
      return;
    }

    final gross = grossAmountMwk;
    if (gross <= 0) return;

    const feeRate = FirebaseWalletService.serviceFeeRate;
    final merchantAmount = gross * (1.0 - feeRate);
    final feeAmount = gross * feeRate;

    final safeId = params.bookingRef
        .trim()
        .replaceAll(RegExp(r'[/\s.#$[\]]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (safeId.isEmpty) return;

    final docId = 'acc_$safeId';

    await _doc(docId).set(
      {
        'buyerUid': buyerUid,
        'merchantUid': hostUid,
        'merchantName': params.hostDisplayName.trim().isEmpty
            ? 'Host'
            : params.hostDisplayName.trim(),
        'merchantAmount': merchantAmount,
        'serviceFeeAmount': feeAmount,
        'txRef': txRef,
        'orderNumber': params.bookingRef,
        'itemName': params.propertyName,
        'status': 'held',
        'serviceType': 'accommodation',
        'deliveredAt': FieldValue.delete(),
        'releaseDueAt': FieldValue.delete(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Sanitize booking ref the same way [createHoldForAccommodationBooking] does.
  static String sanitizeAccommodationEscrowId(String bookingRef) {
    return bookingRef
        .trim()
        .replaceAll(RegExp(r'[/\s.#$[\]]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  static String accommodationEscrowDocId(String bookingRef) {
    final safe = sanitizeAccommodationEscrowId(bookingRef);
    if (safe.isEmpty) return '';
    return 'acc_$safe';
  }

  /// Resolve held/released escrow for a guest stay (doc id `acc_…` or orderNumber).
  static Future<OrderEscrowSnapshot?> fetchEscrowForAccommodationBooking({
    required String bookingId,
    String? bookingNumber,
  }) async {
    final candidates = <String>{};
    void addRaw(String? raw) {
      final t = (raw ?? '').trim();
      if (t.isEmpty) return;
      candidates.add(t);
      final docId = accommodationEscrowDocId(t);
      if (docId.isNotEmpty) candidates.add(docId);
      // VERO / vero variants used in guest UI vs payment refs.
      final lower = t.toLowerCase();
      if (lower.startsWith('vero') && t.length > 4) {
        final rest = t.substring(4).trim();
        if (rest.isNotEmpty) {
          candidates.add(rest);
          final d = accommodationEscrowDocId(rest);
          if (d.isNotEmpty) candidates.add(d);
          candidates.add('VERO$rest');
          final dv = accommodationEscrowDocId('VERO$rest');
          if (dv.isNotEmpty) candidates.add(dv);
        }
      } else {
        candidates.add('VERO$t');
        final dv = accommodationEscrowDocId('VERO$t');
        if (dv.isNotEmpty) candidates.add(dv);
      }
    }

    addRaw(bookingNumber);
    addRaw(bookingId);

    for (final id in candidates) {
      final esc = await fetchEscrow(id);
      if (esc != null) return esc;
      // Also try any-status resolve (released stays should show as released).
      final anyId = await _resolveEscrowDocIdAny(id);
      if (anyId == null) continue;
      final snap = await _doc(anyId).get();
      if (!snap.exists || snap.data() == null) continue;
      return OrderEscrowSnapshot.fromMap(anyId, snap.data()!);
    }
    return null;
  }

  /// Payment tx_ref stored on the escrow hold (used for PayChangu refunds).
  static Future<String?> fetchTxRefForOrder(String orderId) async {
    final escrowDocId = await _resolveEscrowDocIdAny(orderId);
    if (escrowDocId == null) return null;
    final snap = await _doc(escrowDocId).get();
    if (!snap.exists) return null;
    final ref = (snap.data()?['txRef'] ?? snap.data()?['tx_ref'] ?? '')
        .toString()
        .trim();
    return ref.isEmpty ? null : ref;
  }

  /// Stops merchant payout when a refund is requested / approved.
  ///
  /// - `held` → `refunded` (funds never release to merchant)
  /// - already released → marks `refundRequested` so ops can claw back
  static Future<void> cancelHoldForRefund({
    required String orderId,
    required String reason,
    required String refundType,
  }) async {
    final escrowDocId = await _resolveEscrowDocIdAny(orderId);
    if (escrowDocId == null) return;

    final snap = await _doc(escrowDocId).get();
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null) return;

    final status = (data['status'] ?? '').toString();
    final patch = <String, dynamic>{
      'refundReason': reason.trim(),
      'refundType': refundType,
      'refundRequestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == 'held') {
      patch['status'] = 'refunded';
      patch['releasedAt'] = FieldValue.serverTimestamp();
      patch['releaseDueAt'] = FieldValue.delete();
    } else if (status == 'released' || status == 'auto_released') {
      patch['refundAfterRelease'] = true;
    } else if (status == 'refunded') {
      // Already voided for refund.
      await _doc(escrowDocId).update(patch);
      return;
    }

    await _doc(escrowDocId).update(patch);
  }

  /// Resolve escrow doc for any status (held, released, refunded, …).
  static Future<String?> _resolveEscrowDocIdAny(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return null;

    final direct = await _doc(id).get();
    if (direct.exists) return id;

    final qs = await _db
        .collection(_collection)
        .where('orderNumber', isEqualTo: id)
        .limit(1)
        .get();
    if (qs.docs.isNotEmpty) return qs.docs.first.id;

    for (final variant in orderNumberLookupVariants(id)) {
      if (variant == id) continue;
      final vq = await _db
          .collection(_collection)
          .where('orderNumber', isEqualTo: variant)
          .limit(1)
          .get();
      if (vq.docs.isNotEmpty) return vq.docs.first.id;
    }

    // Fall back to held-only resolver (order id may differ from doc id).
    return _resolveEscrowDocId(orderId);
  }

  /// Call when the merchant marks the order as delivered (starts the escrow window).
  ///
  /// [deliveredAt] defaults to now; pass an earlier date when repairing old shipments
  /// so auto-release can run immediately if the window has already passed.
  static Future<void> markDelivered(
    String orderId, {
    DateTime? deliveredAt,
  }) async {
    final escrowDocId = await _resolveEscrowDocId(orderId);
    if (escrowDocId == null) return;

    final snap = await _doc(escrowDocId).get();
    if (!snap.exists) return;

    final data = snap.data();
    if (data == null) return;
    if (data['status'] != 'held') return;

    final existingDelivered = data['deliveredAt'];
    if (existingDelivered is Timestamp && deliveredAt == null) {
      await _ensureReleaseDueAt(escrowDocId, existingDelivered.toDate());
      return;
    }

    final shipped = deliveredAt ?? DateTime.now();
    final due = shipped.add(escrowAutoReleaseAfter);

    await _doc(escrowDocId).update({
      'deliveredAt': Timestamp.fromDate(shipped),
      'releaseDueAt': Timestamp.fromDate(due),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Resolves escrow doc id (canonical order id or migrated stray doc).
  static Future<String?> _resolveEscrowDocId(String orderId) async {
    final id = orderId.trim();
    if (id.isEmpty) return null;

    final direct = await _doc(id).get();
    if (direct.exists && direct.data()?['status'] == 'held') return id;

    final qs = await _db
        .collection(_collection)
        .where('orderNumber', isEqualTo: id)
        .where('status', isEqualTo: 'held')
        .limit(1)
        .get();
    if (qs.docs.isNotEmpty) return qs.docs.first.id;

    for (final variant in orderNumberLookupVariants(id)) {
      if (variant == id) continue;
      final vq = await _db
          .collection(_collection)
          .where('orderNumber', isEqualTo: variant)
          .where('status', isEqualTo: 'held')
          .limit(1)
          .get();
      if (vq.docs.isNotEmpty) return vq.docs.first.id;
    }
    return null;
  }

  /// Like [markDelivered] but resolves escrow via [fetchEscrowResolvingOrderId] first.
  static Future<void> markDeliveredForOrder(
    OrderItem o, {
    DateTime? deliveredAt,
  }) async {
    final esc = await fetchEscrowResolvingOrderId(o);
    final docId = esc?.orderId ?? o.id;
    await markDelivered(docId, deliveredAt: deliveredAt);
  }

  /// Best-effort shipment time for escrow repair.
  /// Only accepts proof uploaded *after* this hold was created — older proofs
  /// belong to a previous order that shared an id / were wrongly attached.
  static Future<DateTime?> _resolveShippedAtForOrder(OrderItem o) async {
    DateTime? holdCreatedAt;
    try {
      final escSnap = await _doc(o.id).get();
      final c = escSnap.data()?['createdAt'];
      if (c is Timestamp) holdCreatedAt = c.toDate();
    } catch (_) {}

    try {
      final proofSnap = await _db
          .collection(DeliveryProofService.collection)
          .doc(o.id)
          .get();
      if (proofSnap.exists) {
        final u = proofSnap.data()?['updatedAt'];
        if (u is Timestamp) {
          final proofAt = u.toDate();
          if (holdCreatedAt == null ||
              !proofAt.isBefore(holdCreatedAt.subtract(const Duration(minutes: 5)))) {
            return proofAt;
          }
          debugPrint(
            '[OrderEscrow] Ignoring stale proof for ${o.id}: '
            'proof=$proofAt holdCreated=$holdCreatedAt',
          );
        }
      }
    } catch (e) {
      debugPrint('[OrderEscrow] proof read ${o.id}: $e');
    }

    // Never backdate to an orderDate older than the hold (causes "shipped Jul 27"
    // on a purchase made today). If the API says delivered, start the window now.
    final orderDate = o.orderDate;
    if (orderDate != null &&
        (holdCreatedAt == null ||
            !orderDate.isBefore(holdCreatedAt.subtract(const Duration(minutes: 5))))) {
      return orderDate;
    }
    return DateTime.now();
  }

  /// If the order is delivered in the API but escrow still has no [deliveredAt], repair.
  static Future<void> repairDeliveredTimestampIfNeeded(OrderItem o) async {
    if (o.status != OrderStatus.delivered) return;
    final esc = await fetchEscrowResolvingOrderId(o);
    if (esc == null || !esc.isHeld) return;

    await _clearBogusDeliveryTimestamps(esc.orderId);

    final refreshed = await fetchEscrow(esc.orderId);
    if (refreshed == null || !refreshed.isHeld) return;

    if (refreshed.deliveredAt != null) {
      await _ensureReleaseDueAt(refreshed.orderId, refreshed.deliveredAt!);
      return;
    }

    final shippedAt = await _resolveShippedAtForOrder(o);
    await markDelivered(refreshed.orderId, deliveredAt: shippedAt);
  }

  /// Clears [deliveredAt] when it predates the hold (stale merge / wrong proof).
  static Future<bool> _clearBogusDeliveryTimestamps(String escrowDocId) async {
    final snap = await _doc(escrowDocId).get();
    if (!snap.exists) return false;
    final data = snap.data();
    if (data == null || data['status'] != 'held') return false;

    final deliveredRaw = data['deliveredAt'];
    if (deliveredRaw is! Timestamp) return false;
    final deliveredAt = deliveredRaw.toDate();

    final createdRaw = data['createdAt'];
    DateTime? createdAt;
    if (createdRaw is Timestamp) createdAt = createdRaw.toDate();

    // Shipped before the payment hold existed → leftover from an old order.
    if (createdAt != null &&
        deliveredAt.isBefore(createdAt.subtract(const Duration(minutes: 5)))) {
      debugPrint(
        '[OrderEscrow] Clearing bogus deliveredAt on $escrowDocId '
        '(delivered=$deliveredAt created=$createdAt)',
      );
      await _doc(escrowDocId).update({
        'deliveredAt': FieldValue.delete(),
        'releaseDueAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    }
    return false;
  }

  /// Backfill [releaseDueAt] from [deliveredAt] when missing or shorter than policy.
  ///
  /// Always upgrades short windows (e.g. old 5-day holds) to the full
  /// [escrowAutoReleaseDays] while status is still `held` — even if the old
  /// due date has already passed — so funds are never auto-released early.
  static Future<void> _ensureReleaseDueAt(
    String escrowDocId,
    DateTime deliveredAt, {
    Map<String, dynamic>? knownData,
  }) async {
    Map<String, dynamic>? data = knownData;
    if (data == null) {
      final snap = await _doc(escrowDocId).get();
      if (!snap.exists) return;
      data = snap.data();
    }
    if (data == null || data['status'] != 'held') return;

    final correctDue = deliveredAt.add(escrowAutoReleaseAfter);
    final existing = data['releaseDueAt'];
    if (existing is Timestamp) {
      final existingDue = existing.toDate();
      // Already at or beyond the current policy window.
      if (!existingDue.isBefore(correctDue)) return;
    }

    await _doc(escrowDocId).update({
      'releaseDueAt': Timestamp.fromDate(correctDue),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Repair a held escrow row using delivery proof when API order context is unavailable.
  static Future<void> repairHeldEscrowDeliveryTimestamp(String escrowDocId) async {
    // Fix "bought today / shipped last week" leftovers first.
    if (await _clearBogusDeliveryTimestamps(escrowDocId)) return;

    final snap = await _doc(escrowDocId).get();
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null || data['status'] != 'held') return;

    final deliveredRaw = data['deliveredAt'];
    if (deliveredRaw is Timestamp) {
      await _ensureReleaseDueAt(
        escrowDocId,
        deliveredRaw.toDate(),
        knownData: data,
      );
      return;
    }

    DateTime? holdCreatedAt;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) holdCreatedAt = createdRaw.toDate();

    DateTime? shippedAt;
    try {
      final proofSnap = await _db
          .collection(DeliveryProofService.collection)
          .doc(escrowDocId)
          .get();
      if (proofSnap.exists) {
        final u = proofSnap.data()?['updatedAt'];
        if (u is Timestamp) {
          final proofAt = u.toDate();
          if (holdCreatedAt == null ||
              !proofAt.isBefore(holdCreatedAt.subtract(const Duration(minutes: 5)))) {
            shippedAt = proofAt;
          } else {
            debugPrint(
              '[OrderEscrow] Ignoring stale proof on $escrowDocId: '
              'proof=$proofAt holdCreated=$holdCreatedAt',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[OrderEscrow] proof read $escrowDocId: $e');
    }

    if (shippedAt != null) {
      await markDelivered(escrowDocId, deliveredAt: shippedAt);
    }
  }

  /// Releases escrow when [releaseDueAt] has passed. Returns true if funds were credited.
  static Future<bool> tryAutoReleaseIfDue(String orderId) async {
    final docId = await _resolveEscrowDocId(orderId);
    if (docId == null) return false;

    final esc = await fetchEscrow(docId);
    if (esc == null || !esc.isHeld) return false;
    if (esc.deliveredAt == null || esc.releaseDueAt == null) return false;
    if (DateTime.now().isBefore(esc.releaseDueAt!)) return false;
    await releaseFunds(orderId: docId, buyerConfirmed: false);
    return true;
  }

  /// Buyer order list: repair timestamps, then auto-release any holds past due.
  static Future<void> processDueAutoReleasesForOrders(Iterable<OrderItem> orders) async {
    final candidates = orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            o.paymentStatus == PaymentStatus.paid)
        .toList();
    if (candidates.isEmpty) return;

    for (final o in candidates) {
      await repairBuyerUidIfNeeded(o);
      await repairDeliveredTimestampIfNeeded(o);
    }

    for (final o in candidates) {
      try {
        await tryAutoReleaseIfDue(o.id);
      } catch (e) {
        debugPrint('[OrderEscrow] auto-release ${o.id}: $e');
      }
    }
  }

  /// App open / resume: auto-release escrow when [releaseDueAt] has passed and the
  /// buyer did not confirm receipt. Works for the signed-in user as merchant or buyer.
  static Future<int> processDueAutoReleasesForSignedInUser() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return 0;

    var released = 0;
    try {
      List<OrderItem>? orders;
      try {
        orders = await OrderService().getMyOrders();
      } catch (e) {
        debugPrint('[OrderEscrow] getMyOrders for auto-release: $e');
      }

      released += await processDueAutoReleasesForMerchant(
        uid,
        merchantOrders: orders,
      );

      if (orders != null && orders.isNotEmpty) {
        await processDueAutoReleasesForOrders(orders);
      }

      final buyerHeld = await _db
          .collection(_collection)
          .where('buyerUid', isEqualTo: uid)
          .where('status', isEqualTo: 'held')
          .get();
      for (final doc in buyerHeld.docs) {
        try {
          await repairHeldEscrowDeliveryTimestamp(doc.id);
          if (await tryAutoReleaseIfDue(doc.id)) released++;
        } catch (e) {
          debugPrint('[OrderEscrow] buyer auto-release ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('[OrderEscrow] processDueAutoReleasesForSignedInUser: $e');
    }
    return released;
  }

  /// Merchant wallet / ship screen: repair delivery timestamps from [merchantOrders],
  /// then release all held rows for [merchantUid] that are past due.
  static Future<int> processDueAutoReleasesForMerchant(
    String merchantUid, {
    Iterable<OrderItem>? merchantOrders,
  }) async {
    final uid = merchantUid.trim();
    if (uid.isEmpty) return 0;

    if (merchantOrders != null) {
      for (final o in merchantOrders) {
        if (o.status != OrderStatus.delivered) continue;
        final esc = await fetchEscrow(o.id);
        if (esc != null &&
            esc.merchantUid.isNotEmpty &&
            esc.merchantUid != uid) {
          continue;
        }
        await repairDeliveredTimestampIfNeeded(o);
      }
    }

    final qs = await _db
        .collection(_collection)
        .where('merchantUid', isEqualTo: uid)
        .where('status', isEqualTo: 'held')
        .get();

    var released = 0;
    for (final doc in qs.docs) {
      try {
        await repairHeldEscrowDeliveryTimestamp(doc.id);
        if (await tryAutoReleaseIfDue(doc.id)) released++;
      } catch (e) {
        debugPrint('[OrderEscrow] merchant auto-release ${doc.id}: $e');
      }
    }
    return released;
  }

  /// Older holds may lack [buyerUid]. When the signed-in user matches the order’s
  /// [OrderItem.customerUid], backfill so the buyer can confirm receipt and [releaseFunds].
  static Future<void> repairBuyerUidIfNeeded(OrderItem o) async {
    final myUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (myUid.isEmpty) return;
    final cust = (o.customerUid ?? '').trim();
    if (cust.isEmpty || cust != myUid) return;

    final ref = _doc(o.id);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data();
    if (data == null) return;
    if (data['status'] != 'held') return;
    final existing = (data['buyerUid'] ?? '').toString().trim();
    if (existing.isNotEmpty) return;

    await ref.update({
      'buyerUid': cust,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  /// Values to match Firestore field [orderNumber] when the escrow doc id ≠ API [OrderItem.id].
  ///
  /// Intentionally does **not** match bare digit fragments (e.g. `"123"` from
  /// `"VERO-12345"`) — that caused wrong escrow docs (and old ship dates) to be
  /// attached to newer orders.
  static List<String> orderNumberLookupVariants(String raw) {
    final s = raw.trim();
    final out = <String>{};
    void add(String x) {
      final t = x.trim();
      if (t.isNotEmpty) out.add(t);
    }

    add(s);
    add(s.replaceFirst(RegExp(r'^#+\s*'), ''));
    final lower = s.toLowerCase();
    final veroIdx = lower.indexOf('vero');
    if (veroIdx >= 0 && veroIdx + 4 < s.length) {
      add(s.substring(veroIdx + 4).trim());
    }
    return out.toList();
  }

  static Future<void> _migrateEscrowToCanonicalId({
    required String canonicalOrderId,
    required String strayFirestoreDocId,
  }) async {
    if (canonicalOrderId.isEmpty || strayFirestoreDocId == canonicalOrderId) {
      return;
    }
    final srcRef = _doc(strayFirestoreDocId);
    final dstRef = _doc(canonicalOrderId);
    await _db.runTransaction((transaction) async {
      final src = await transaction.get(srcRef);
      if (!src.exists || src.data() == null) return;
      final dst = await transaction.get(dstRef);
      if (dst.exists) return;
      transaction.set(dstRef, src.data()!, SetOptions(merge: true));
      transaction.delete(srcRef);
    });
  }

  /// Resolves escrow when the hold was stored under a wrong document id (common if POST /orders
  /// omitted id and the app used a temporary key). Finds by [orderNumber] + buyer, then moves
  /// the doc to [order.id] so shipment / release use one id.
  static Future<OrderEscrowSnapshot?> fetchEscrowResolvingOrderId(OrderItem order) async {
    final direct = await fetchEscrow(order.id);
    if (direct != null) return direct;

    final myUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (order.paymentStatus != PaymentStatus.paid || myUid.isEmpty) return null;

    final variants = orderNumberLookupVariants(order.orderNumber);
    if (variants.isEmpty) return null;

    DocumentSnapshot<Map<String, dynamic>>? match;
    for (var i = 0; i < variants.length; i += 10) {
      final chunk = variants.skip(i).take(10).toList();
      if (chunk.isEmpty) break;
      final qs = await _db
          .collection(_collection)
          .where('orderNumber', whereIn: chunk)
          .limit(25)
          .get();
      for (final doc in qs.docs) {
        final data = doc.data();
        final bu = (data['buyerUid'] ?? '').toString().trim();
        final st = (data['status'] ?? '').toString();
        // Only migrate still-held docs — never attach an old released sale.
        if (st != 'held') continue;
        if (bu.isNotEmpty && bu != myUid) continue;
        match = doc;
        break;
      }
      if (match != null) break;
    }
    if (match == null || !match.exists) return null;

    final strayId = match.id;
    if (strayId != order.id) {
      try {
        await _migrateEscrowToCanonicalId(
          canonicalOrderId: order.id,
          strayFirestoreDocId: strayId,
        );
      } catch (e) {
        debugPrint('[OrderEscrow] migrate doc $strayId -> ${order.id} failed: $e');
      }
    }
    return await fetchEscrow(order.id);
  }

  /// Like [fetchEscrowForOrderIds] but runs [fetchEscrowResolvingOrderId] when a direct read misses.
  static Future<Map<String, OrderEscrowSnapshot?>> fetchEscrowForOrdersResolved(
    Iterable<OrderItem> orders,
  ) async {
    final list = orders.toList();
    final initial = await fetchEscrowForOrderIds(list.map((e) => e.id));
    final out = Map<String, OrderEscrowSnapshot?>.from(initial);
    for (final o in list) {
      if (out[o.id] != null) continue;
      out[o.id] = await fetchEscrowResolvingOrderId(o);
    }
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
      final buyerUid = (data['buyerUid'] ?? '').toString().trim();
      final me = uid.trim();
      if (buyerUid.isNotEmpty && buyerUid != me) {
        throw StateError('Only the buyer can confirm this order.');
      }
      if (buyerUid.isEmpty) {
        throw StateError(
          'Payment hold is missing buyer information. Pull to refresh, then try again.',
        );
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

    await _creditAndCloseEscrow(
      orderId: orderId,
      data: data,
      buyerConfirmed: buyerConfirmed,
      releaseKind: buyerConfirmed ? 'buyer_confirm' : 'auto_7d',
      releaseSource: 'app',
    );
  }

  static Future<void> _creditAndCloseEscrow({
    required String orderId,
    required Map<String, dynamic> data,
    required bool buyerConfirmed,
    required String releaseKind,
    required String releaseSource,
  }) async {
    final ref = _doc(orderId);
    final merchantUid = (data['merchantUid'] ?? '').toString().trim();
    final merchantName = (data['merchantName'] ?? 'Merchant').toString();
    final amount = (data['merchantAmount'] ?? 0.0);
    final merchantAmount =
        amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0.0;
    final feeRaw = data['serviceFeeAmount'] ?? 0.0;
    final serviceFee =
        feeRaw is num ? feeRaw.toDouble() : double.tryParse('$feeRaw') ?? 0.0;
    final txRef = (data['txRef'] ?? orderId).toString();
    final serviceType =
        (data['serviceType'] ?? '').toString().trim().toLowerCase();

    if (merchantUid.isEmpty || merchantAmount <= 0) {
      throw StateError('Invalid escrow data.');
    }

    await FirebaseWalletService.getOrCreateWallet(
      merchantId: merchantUid,
      merchantName: merchantName,
    );

    final isAcc = serviceType == 'accommodation';
    final isFood = serviceType == 'food';

    await FirebaseWalletService.creditWallet(
      merchantId: merchantUid,
      amount: merchantAmount,
      description: () {
        if (isFood) {
          return buyerConfirmed
              ? 'Food order — kitchen marked delivered'
              : 'Food order — auto-released after $escrowAutoReleaseLabel';
        }
        if (buyerConfirmed) {
          return isAcc
              ? 'Stay payment — guest confirmed arrival'
              : 'Marketplace sale — buyer confirmed receipt';
        }
        return isAcc
            ? 'Stay payment — auto-released after $escrowAutoReleaseLabel'
            : 'Marketplace sale — auto-released after $escrowAutoReleaseLabel';
      }(),
      reference: txRef,
      type: 'sale_escrow',
    );

    if (serviceFee > 0) {
      try {
        await FirebaseWalletService.creditPlatformServiceFee(
          amount: serviceFee,
          description: isFood
              ? 'Food service fee 10% ($txRef)'
              : isAcc
                  ? 'Stay service fee ($txRef)'
                  : 'Marketplace service fee 10% ($txRef)',
          reference: txRef,
        );
        await ref.set({
          'platformFeeCredited': true,
          'platformFeeCreditedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[OrderEscrow] Platform fee credit failed: $e');
        await ref.set({
          'platformFeeCredited': false,
          'platformFeeError': e.toString(),
        }, SetOptions(merge: true));
      }
      await _recordServiceFeeWithAdminApi(amount: serviceFee, txRef: txRef);
    } else {
      await ref.set({
        'platformFeeCredited': true,
      }, SetOptions(merge: true));
    }

    await ref.update({
      'status': buyerConfirmed ? 'released' : 'auto_released',
      'releasedAt': FieldValue.serverTimestamp(),
      'releaseKind': releaseKind,
      'releaseSource': releaseSource,
      'merchantNotifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (merchantUid.isNotEmpty) {
      final orderNo = (data['orderNumber'] ?? '').toString();
      final itemNm = (data['itemName'] ?? '').toString();
      await OrderPartyNotificationService.publishFundsReleasedToMerchant(
        merchantUid: merchantUid,
        orderNumber: orderNo,
        itemName: itemNm,
        orderId: orderId,
        buyerConfirmed: buyerConfirmed,
        autoReleaseLabel: escrowAutoReleaseLabel,
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
  bool get isRefunded => status == 'refunded';

  bool get isAutoReleaseDue {
    if (!isHeld || releaseDueAt == null) return false;
    return !DateTime.now().isBefore(releaseDueAt!);
  }

  /// True when shipped but the buyer has not confirmed and auto-release is not due yet.
  bool get isAwaitingBuyerOrAutoRelease =>
      isHeld && deliveredAt != null && !isAutoReleaseDue;

  /// True when the merchant has not shipped / marked delivered yet.
  bool get isAwaitingShipment => isHeld && deliveredAt == null;

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
