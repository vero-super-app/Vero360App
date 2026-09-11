import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';

/// Loads admin-editable USD→MWK rate + product prices from
/// Firestore `app_config/digital_services` and merges onto the local catalog.
class DigitalServicesCatalog extends ChangeNotifier {
  DigitalServicesCatalog._();
  static final DigitalServicesCatalog instance = DigitalServicesCatalog._();

  static const String configPath = 'app_config/digital_services';

  double _usdToMwkRate = kUsdToMwkRate;
  List<DigitalProduct> _homepage = List<DigitalProduct>.from(kDigitalProducts);
  List<DigitalProduct> _all = List<DigitalProduct>.from(kAllDigitalProducts);
  bool _loaded = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  double get usdToMwkRate => _usdToMwkRate;
  List<DigitalProduct> get homepageProducts =>
      List<DigitalProduct>.unmodifiable(_homepage);
  List<DigitalProduct> get allProducts =>
      List<DigitalProduct>.unmodifiable(_all);
  bool get loaded => _loaded;

  /// Start listening (idempotent). Safe to call from homepage / gift cards.
  Future<void> ensureStarted() async {
    if (_sub != null) return;
    try {
      final ref =
          FirebaseFirestore.instance.doc(configPath);
      // One-shot first so UI gets prices quickly.
      final snap = await ref.get();
      _applySnapshot(snap.data());
      _loaded = true;
      notifyListeners();

      _sub = ref.snapshots().listen((doc) {
        _applySnapshot(doc.data());
        _loaded = true;
        notifyListeners();
      }, onError: (e) {
        if (kDebugMode) {
          debugPrint('[DigitalServicesCatalog] listen failed: $e');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DigitalServicesCatalog] start failed: $e');
      }
      _loaded = true;
      notifyListeners();
    }
  }

  void _applySnapshot(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      _usdToMwkRate = kUsdToMwkRate;
      digitalServicesUsdToMwkRate = kUsdToMwkRate;
      _homepage = List<DigitalProduct>.from(kDigitalProducts);
      _all = List<DigitalProduct>.from(kAllDigitalProducts);
      return;
    }

    final rateRaw = data['usdToMwkRate'];
    final rate = rateRaw is num
        ? rateRaw.toDouble()
        : double.tryParse('$rateRaw') ?? kUsdToMwkRate;
    _usdToMwkRate = rate.clamp(100, 100000);
    digitalServicesUsdToMwkRate = _usdToMwkRate;

    final byKey = <String, Map<String, dynamic>>{};
    final rawProducts = data['products'];
    if (rawProducts is List) {
      for (final item in rawProducts) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        final key = (m['key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        byKey[key] = m;
      }
    }

    DigitalProduct merge(DigitalProduct base) {
      final cfg = byKey[base.key];
      if (cfg == null) return base;

      final active = cfg['active'] != false;
      if (!active) {
        // Keep in merge map as inactive — filtered below.
        return base.copyWith(active: false);
      }

      final name = (cfg['name'] ?? '').toString().trim();
      final subtitle = (cfg['subtitle'] ?? '').toString().trim();
      final brandTag = (cfg['brandTag'] ?? '').toString().trim();

      double? fixed;
      final fixedRaw = cfg['fixedMwkPrice'];
      if (fixedRaw != null && '$fixedRaw'.trim().isNotEmpty) {
        final n = fixedRaw is num
            ? fixedRaw.toDouble()
            : double.tryParse('$fixedRaw');
        if (n != null && n > 0) fixed = n;
      }

      List<double>? amounts;
      final amountsRaw = cfg['usdAmounts'];
      if (amountsRaw is List) {
        amounts = amountsRaw
            .map((e) => e is num ? e.toDouble() : double.tryParse('$e') ?? 0)
            .where((e) => e > 0)
            .toList();
      } else if (amountsRaw is String && amountsRaw.trim().isNotEmpty) {
        amounts = amountsRaw
            .split(RegExp(r'[,\s]+'))
            .map((e) => double.tryParse(e.trim()) ?? 0)
            .where((e) => e > 0)
            .toList();
      }

      final isSub =
          base.category == 'streaming' || base.category == 'subscription';

      return base.copyWith(
        name: name.isNotEmpty ? name : null,
        subtitle: subtitle.isNotEmpty ? subtitle : null,
        brandTag: brandTag.isNotEmpty ? brandTag : null,
        fixedMwkPrice: isSub ? (fixed ?? base.fixedMwkPrice) : base.fixedMwkPrice,
        usdAmounts: !isSub && amounts != null && amounts.isNotEmpty
            ? amounts
            : null,
        active: true,
      );
    }

    bool isActive(DigitalProduct p) {
      final cfg = byKey[p.key];
      if (cfg == null) return true;
      return cfg['active'] != false;
    }

    _homepage = kDigitalProducts.map(merge).where(isActive).toList();
    _all = kAllDigitalProducts.map(merge).where(isActive).toList();

    // Ensure homepage streaming list stays non-empty.
    if (_homepage.isEmpty) {
      _homepage = List<DigitalProduct>.from(kDigitalProducts);
    }
    if (_all.isEmpty) {
      _all = List<DigitalProduct>.from(kAllDigitalProducts);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

/// Convert USD → MWK using the live admin rate (falls back to [kUsdToMwkRate]).
/// Prefer importing [usdToMwk] from `digital_product.dart` at call sites.
