import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Admin-editable Vero Ride front-desk numbers from Firestore
/// `app_config/ride_share`. Falls back to the current Help Center number.
class RideShareContactCatalog extends ChangeNotifier {
  RideShareContactCatalog._();
  static final RideShareContactCatalog instance = RideShareContactCatalog._();

  static const String configPath = 'app_config/ride_share';
  static const String defaultWhatsApp = '+265992695612';
  static const String defaultPhone = '+265992695612';

  String _frontDeskWhatsApp = defaultWhatsApp;
  String _frontDeskPhone = defaultPhone;
  bool _loaded = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  String get frontDeskWhatsApp => _frontDeskWhatsApp;
  String get frontDeskPhone => _frontDeskPhone;
  bool get loaded => _loaded;

  String get whatsAppDigits =>
      _frontDeskWhatsApp.replaceAll(RegExp(r'\D'), '');

  Future<void> ensureStarted() async {
    if (_sub != null) return;
    try {
      final ref = FirebaseFirestore.instance.doc(configPath);
      final snap = await ref.get();
      _apply(snap.data());
      _loaded = true;
      notifyListeners();

      _sub = ref.snapshots().listen((doc) {
        _apply(doc.data());
        _loaded = true;
        notifyListeners();
      }, onError: (e) {
        if (kDebugMode) {
          debugPrint('[RideShareContactCatalog] listen failed: $e');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RideShareContactCatalog] start failed: $e');
      }
      _loaded = true;
      notifyListeners();
    }
  }

  void _apply(Map<String, dynamic>? data) {
    final wa = _readPhone(data?['frontDeskWhatsApp']) ?? defaultWhatsApp;
    final phone = _readPhone(data?['frontDeskPhone']) ?? wa;
    _frontDeskWhatsApp = wa;
    _frontDeskPhone = phone;
  }

  static String? _readPhone(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return null;
    return value.startsWith('+') ? '+$digits' : value;
  }
}
