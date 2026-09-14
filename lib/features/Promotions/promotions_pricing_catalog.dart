import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Admin-editable promotion prices from Firestore `app_config/promotions`.
class PromotionsPricingCatalog extends ChangeNotifier {
  PromotionsPricingCatalog._();
  static final PromotionsPricingCatalog instance = PromotionsPricingCatalog._();

  static const String configPath = 'app_config/promotions';

  static const List<int> _defaultPresets = [
    3000,
    5000,
    8000,
    10000,
    15000,
    20000,
  ];

  List<int> _presets = List<int>.from(_defaultPresets);
  bool _allowCustomPrice = true;
  bool _loaded = false;
  bool _hasRemoteConfig = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  List<int> get pricePresetsMwk => List<int>.unmodifiable(_presets);
  bool get allowCustomPrice => _allowCustomPrice;
  bool get loaded => _loaded;
  bool get hasRemoteConfig => _hasRemoteConfig;

  Future<void> start() async {
    if (_sub != null) return;
    try {
      _sub = FirebaseFirestore.instance
          .doc(configPath)
          .snapshots()
          .listen(_applySnap, onError: (e) {
        if (kDebugMode) {
          debugPrint('[PromotionsPricingCatalog] listen failed: $e');
        }
        _loaded = true;
        notifyListeners();
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PromotionsPricingCatalog] start failed: $e');
      }
      _loaded = true;
      notifyListeners();
    }
  }

  void _applySnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || snap.data() == null) {
      _presets = List<int>.from(_defaultPresets);
      _allowCustomPrice = true;
      _hasRemoteConfig = false;
      _loaded = true;
      notifyListeners();
      return;
    }
    final data = snap.data()!;
    final raw = data['pricePresetsMwk'];
    final next = <int>[];
    final seen = <int>{};
    if (raw is List) {
      for (final e in raw) {
        final n = e is num
            ? e.toInt()
            : int.tryParse(e.toString().replaceAll(RegExp(r'[^\d]'), ''));
        if (n == null || n <= 0 || seen.contains(n)) continue;
        seen.add(n);
        next.add(n);
      }
    }
    next.sort();
    _presets = next.isNotEmpty ? next : List<int>.from(_defaultPresets);
    _allowCustomPrice = data['allowCustomPrice'] != false;
    _hasRemoteConfig = true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    await start();
    if (_loaded) return;
    try {
      final snap =
          await FirebaseFirestore.instance.doc(configPath).get().timeout(
                const Duration(seconds: 6),
              );
      _applySnap(snap);
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  void disposeCatalog() {
    _sub?.cancel();
    _sub = null;
  }
}
