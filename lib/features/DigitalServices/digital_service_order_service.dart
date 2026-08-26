import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';

/// Firestore collection for Digital Services purchases (subscriptions + gift cards).
const String kDigitalServiceOrdersCollection = 'digital_service_orders';

class DigitalServiceOrderService {
  DigitalServiceOrderService._();

  static final _col =
      FirebaseFirestore.instance.collection(kDigitalServiceOrdersCollection);

  static Future<String> createPendingOrder({
    required DigitalProduct product,
    required double amountMwk,
    required String txRef,
    required String buyerName,
    required String buyerEmail,
    required String buyerPhone,
    double? selectedUsd,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('You’re not logged in. Please sign in to continue.');
    }
    final isSubscription = product.fixedMwkPrice != null;
    final doc = _col.doc();
    await doc.set({
      'productKey': product.key,
      'productName': product.name,
      'productSubtitle': product.subtitle,
      'brandTag': product.brandTag,
      'category': product.category,
      'kind': isSubscription ? 'subscription' : 'gift_card',
      'period': isSubscription ? 'monthly' : null,
      'periodLabel': isSubscription ? '1 month' : null,
      'selectedUsd': selectedUsd,
      'amountMwk': amountMwk,
      'currency': 'MWK',
      'status': 'pending_payment',
      'txRef': txRef,
      'buyerUid': user.uid,
      'buyerName': buyerName,
      'buyerEmail': buyerEmail,
      'buyerPhone': buyerPhone,
      'platformFeeCredited': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Marks paid, credits full amount to platform (Vero main) wallet.
  static Future<void> activateAfterPayment({
    required String orderId,
    required String txRef,
  }) async {
    final ref = _col.doc(orderId);
    final snap = await ref.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final amount = (data['amountMwk'] as num?)?.toDouble() ?? 0;
    final productName =
        (data['productName'] ?? 'Digital service').toString().trim();
    final alreadyCredited = data['platformFeeCredited'] == true;

    var feeCreditedNow = false;
    if (!alreadyCredited && amount > 0) {
      try {
        await FirebaseWalletService.creditPlatformServiceFee(
          amount: amount,
          description: 'Digital service · $productName',
          reference: txRef.isNotEmpty ? txRef : 'digital:$orderId',
        );
        feeCreditedNow = true;
      } catch (_) {
        // Admin dashboard can backfill via Credit platform fee.
      }
    }

    await ref.set({
      'status': 'paid',
      'txRef': txRef,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!alreadyCredited && feeCreditedNow) ...{
        'platformFeeCredited': true,
        'platformFeeCreditedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }
}
