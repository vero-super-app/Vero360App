import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';

/// Same phone source as [marketplace_merchant_dashboard]: SharedPreferences 'phone'
/// for current merchant, Firestore users/{uid} for others.
class MerchantPhoneResolver {
  MerchantPhoneResolver._();

  static String _sanitizePhone(String s) {
    final t = (s).trim();
    if (t.isEmpty) return '';
    if (t.toLowerCase().startsWith('+firebase_') ||
        t.toLowerCase().contains('firebase_')) {
      return '';
    }
    return t;
  }

  /// Resolves merchant phones for orders. Uses SharedPreferences 'phone' when
  /// the current user is the merchant (same as dashboard); otherwise Firestore
  /// users/{merchantUid} when merchantUid is available.
  static Future<Map<String, String>> resolveForOrders(
    List<OrderItem> orders,
  ) async {
    final out = <String, String>{};
    if (orders.isEmpty) return out;

    final currentUid = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
    final prefs = await SharedPreferences.getInstance();
    final ourPhone = _sanitizePhone(prefs.getString('phone') ?? '');
    final firestore = FirebaseFirestore.instance;

    final uidsToFetch = <String>{};
    for (final o in orders) {
      final mUid = (o.merchantUid ?? '').trim();
      if (mUid.isEmpty) continue;
      if (mUid == currentUid) {
        if (ourPhone.isNotEmpty) out[o.id] = ourPhone;
        continue;
      }
      uidsToFetch.add(mUid);
    }

    for (final uid in uidsToFetch) {
      try {
        final doc =
            await firestore.collection('users').doc(uid).get();
        if (!doc.exists) continue;
        final data = doc.data();
        final raw = (data?['phone'] ?? '').toString().trim();
        final phone = _sanitizePhone(raw);
        if (phone.isEmpty) continue;
        for (final o in orders) {
          if ((o.merchantUid ?? '').trim() == uid) {
            out[o.id] = phone;
          }
        }
      } catch (_) {}
    }

    return out;
  }
}
