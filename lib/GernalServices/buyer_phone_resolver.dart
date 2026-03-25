import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';

/// Resolves buyer phones from same canonical source used in app profiles:
/// SharedPreferences 'phone' for current user, Firestore users/{uid} for others.
class BuyerPhoneResolver {
  BuyerPhoneResolver._();

  static Future<Map<String, String>> resolveForOrders(
    List<OrderItem> orders,
  ) async {
    final out = <String, String>{};
    if (orders.isEmpty) return out;

    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final prefs = await SharedPreferences.getInstance();
    final myPhone = safeMerchantPhone(prefs.getString('phone'));
    final firestore = FirebaseFirestore.instance;

    final uidsToFetch = <String>{};
    for (final o in orders) {
      final buyerUid = (o.customerUid ?? '').trim();
      if (buyerUid.isEmpty) continue;
      if (buyerUid == currentUid) {
        if (myPhone != 'No phone number') out[o.id] = myPhone;
        continue;
      }
      uidsToFetch.add(buyerUid);
    }

    for (final uid in uidsToFetch) {
      try {
        final doc = await firestore.collection('users').doc(uid).get();
        if (!doc.exists) continue;
        final data = doc.data();
        final phone = safeMerchantPhone((data?['phone'] ?? '').toString());
        if (phone == 'No phone number') continue;
        for (final o in orders) {
          if ((o.customerUid ?? '').trim() == uid) {
            out[o.id] = phone;
          }
        }
      } catch (_) {}
    }

    return out;
  }
}
