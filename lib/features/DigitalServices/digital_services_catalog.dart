import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/features/DigitalServices/chatgpt_plans.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/netflix_plans.dart';

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
  bool _hasRemoteConfig = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  double get usdToMwkRate => _usdToMwkRate;
  List<DigitalProduct> get homepageProducts =>
      List<DigitalProduct>.unmodifiable(_homepage);
  List<DigitalProduct> get allProducts =>
      List<DigitalProduct>.unmodifiable(_all);
  bool get loaded => _loaded;
  /// True once Firestore `app_config/digital_services` has been applied.
  bool get hasRemoteConfig => _hasRemoteConfig;

  /// Resolve the live admin-priced product (never trust a stale checkout snapshot).
  DigitalProduct? productByKey(String key) {
    final k = key.trim();
    if (k.isEmpty) return null;
    for (final p in _all) {
      if (p.key == k && p.active) return p;
    }
    for (final p in _homepage) {
      if (p.key == k && p.active) return p;
    }
    return null;
  }

  /// Start listening (idempotent). Safe to call from homepage / gift cards.
  Future<void> ensureStarted() async {
    if (_sub != null) return;
    try {
      final ref = FirebaseFirestore.instance.doc(configPath);
      // One-shot first so UI gets prices quickly.
      final snap = await ref.get();
      _applySnapshot(snap.data(), docExists: snap.exists);
      _loaded = true;
      notifyListeners();

      _sub = ref.snapshots().listen((doc) {
        _applySnapshot(doc.data(), docExists: doc.exists);
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

  static List<String> _asStringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'[\n,]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static bool _asHub(dynamic value, String key) {
    if (value == true) return true;
    return key == 'chatgpt' || key == 'netflix';
  }

  static bool _asActive(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = '$value'.trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off' || s == 'inactive') {
      return false;
    }
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on' || s == 'active') {
      return true;
    }
    return true;
  }

  static Map<String, Map<String, dynamic>> _parseProducts(dynamic rawProducts) {
    final byKey = <String, Map<String, dynamic>>{};
    Iterable<dynamic> items = const [];
    if (rawProducts is List) {
      items = rawProducts;
    } else if (rawProducts is Map) {
      items = rawProducts.values;
    }
    for (final item in items) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(
        item.map((k, v) => MapEntry(k.toString(), v)),
      );
      final key = (m['key'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      byKey[key] = m;
    }
    return byKey;
  }

  static Map<String, String> _skuByUsd(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = '$k'.trim();
      final sku = '$v'.trim();
      if (key.isNotEmpty && sku.isNotEmpty) out[key] = sku;
    });
    return out;
  }

  static String _codeType(dynamic raw) {
    return '$raw'.trim().toUpperCase() == 'SCAN' ? 'SCAN' : 'TEXT';
  }

  static Set<String> _parseDisabledKeys(dynamic raw, Map<String, Map<String, dynamic>> byKey) {
    final disabled = <String>{};
    if (raw is List) {
      for (final e in raw) {
        final k = '$e'.trim();
        if (k.isNotEmpty) disabled.add(k);
      }
    }
    for (final entry in byKey.entries) {
      if (!_asActive(entry.value['active'])) {
        disabled.add(entry.key);
      }
    }
    return disabled;
  }

  void _applySnapshot(Map<String, dynamic>? data, {required bool docExists}) {
    if (!docExists || data == null || data.isEmpty) {
      _hasRemoteConfig = false;
      _usdToMwkRate = kUsdToMwkRate;
      digitalServicesUsdToMwkRate = kUsdToMwkRate;
      // Never show baked-in MWK — wait for admin config.
      _homepage = kDigitalProducts
          .map((p) => p.copyWith(clearFixedMwkPrice: true, active: true))
          .where((p) => !p.isChildPlan)
          .toList();
      _all = [
        ...kAllDigitalProducts.map(
          (p) => p.category == 'streaming' || p.category == 'subscription'
              ? p.copyWith(clearFixedMwkPrice: true, active: true)
              : p,
        ),
      ];
      return;
    }

    _hasRemoteConfig = true;

    final rateRaw = data['usdToMwkRate'];
    final rate = rateRaw is num
        ? rateRaw.toDouble()
        : double.tryParse('$rateRaw') ?? kUsdToMwkRate;
    _usdToMwkRate = rate.clamp(100, 100000);
    digitalServicesUsdToMwkRate = _usdToMwkRate;

    final byKey = _parseProducts(data['products']);
    final disabledKeys = _parseDisabledKeys(data['disabledProductKeys'], byKey);

    DigitalProduct merge(DigitalProduct base) {
      final cfg = byKey[base.key];
      final active = !disabledKeys.contains(base.key) &&
          (cfg == null || _asActive(cfg['active']));

      if (!active) {
        return base.copyWith(active: false, clearFixedMwkPrice: true);
      }

      final isSub =
          base.category == 'streaming' || base.category == 'subscription';

      if (cfg == null) {
        // No admin row → no subscription price (do not keep hardcoded seeds).
        // ChatGPT plans keep their listed MWK prices.
        return base.copyWith(
          active: true,
          clearFixedMwkPrice: isSub && !base.isChatGptPlan,
        );
      }

      final name = (cfg['name'] ?? '').toString().trim();
      final subtitle = (cfg['subtitle'] ?? '').toString().trim();
      final brandTag = (cfg['brandTag'] ?? '').toString().trim();
      final imageUrl = (cfg['imageUrl'] ?? '').toString().trim();
      final unitLabel = (cfg['unitLabel'] ?? '').toString().trim();

      double? fixed;
      final fixedRaw = cfg['fixedMwkPrice'];
      if (fixedRaw != null && '$fixedRaw'.trim().isNotEmpty) {
        final n = fixedRaw is num
            ? fixedRaw.toDouble()
            : double.tryParse('$fixedRaw');
        if (n != null && n > 0) fixed = n;
      }
      // Old admin default was MWK 35,000 for a single ChatGPT Plus plan.
      if (base.isChatGptPlan &&
          base.fixedMwkPrice != null &&
          base.fixedMwkPrice! > 0 &&
          (fixed == null || (base.key == 'chatgpt_plus' && fixed == 35000))) {
        fixed = base.fixedMwkPrice;
      }

      double? mwkPerUnit;
      final rateRawUnit = cfg['mwkPerUnit'];
      if (rateRawUnit != null && '$rateRawUnit'.trim().isNotEmpty) {
        final n = rateRawUnit is num
            ? rateRawUnit.toDouble()
            : double.tryParse('$rateRawUnit');
        if (n != null && n > 0) mwkPerUnit = n;
      }

      double? maxOtherAmount;
      final maxRaw = cfg['maxOtherAmount'];
      if (maxRaw != null && '$maxRaw'.trim().isNotEmpty) {
        final n = maxRaw is num
            ? maxRaw.toDouble()
            : double.tryParse('$maxRaw');
        if (n != null && n > 0) maxOtherAmount = n;
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

      Map<String, String>? pfSkus;
      String? pfRegion;
      bool? pfEnabled;
      String? pfCodeType;
      final pfRaw = cfg['prepaidForge'];
      if (pfRaw is Map) {
        pfEnabled = pfRaw['enabled'] == true;
        final region = (pfRaw['region'] ?? '').toString().trim();
        pfRegion = region.isEmpty ? null : region;
        pfSkus = _skuByUsd(pfRaw['skuByUsd']);
        pfCodeType = _codeType(pfRaw['preferredCodeType'] ?? pfRaw['codeType']);
      }

      return base.copyWith(
        name: name.isEmpty ? null : name,
        subtitle: subtitle.isEmpty ||
                (base.isChatGptPlan && subtitle == '1-month subscription')
            ? null
            : subtitle,
        brandTag: brandTag.isEmpty ||
                (base.isChatGptPlan && brandTag == 'GPT')
            ? null
            : brandTag,
        fixedMwkPrice: isSub
            ? (fixed ?? (base.isChatGptPlan ? base.fixedMwkPrice : null))
            : base.fixedMwkPrice,
        clearFixedMwkPrice:
            isSub && fixed == null && !base.isChatGptPlan,
        usdAmounts: !isSub && amounts != null && amounts.isNotEmpty
            ? amounts
            : null,
        mwkPerUnit: !isSub ? (mwkPerUnit ?? base.mwkPerUnit) : base.mwkPerUnit,
        unitLabel: unitLabel.isNotEmpty ? unitLabel : null,
        maxOtherAmount: !isSub ? maxOtherAmount : null,
        clearMaxOtherAmount: !isSub && maxOtherAmount == null,
        imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        active: true,
        isHub: _asHub(cfg['isHub'], base.key) || base.isHub,
        hubKey: (cfg['hubKey'] ?? '').toString().trim().isNotEmpty
            ? (cfg['hubKey'] ?? '').toString().trim()
            : base.hubKey,
        planBadge: (cfg['planBadge'] ?? '').toString().trim().isNotEmpty
            ? (cfg['planBadge'] ?? '').toString().trim()
            : base.planBadge,
        featureLines: _asStringList(cfg['featureLines']).isNotEmpty
            ? _asStringList(cfg['featureLines'])
            : base.featureLines,
        recommended: cfg['recommended'] == true || base.recommended,
        prepaidForgeEnabled: pfEnabled,
        prepaidForgeRegion: pfRegion,
        prepaidForgeSkuByUsd: pfSkus,
        prepaidForgeCodeType: pfCodeType,
      );
    }

    DigitalProduct fromRemoteOnly(String key, Map<String, dynamic> cfg) {
      final name = (cfg['name'] ?? key).toString().trim();
      final subtitle = (cfg['subtitle'] ?? '').toString().trim();
      final brandTag = (cfg['brandTag'] ?? '').toString().trim();
      final category = (cfg['category'] ?? 'crypto').toString().trim();
      final imageUrl = (cfg['imageUrl'] ?? '').toString().trim();
      final unitLabel = (cfg['unitLabel'] ?? '').toString().trim();

      double? fixed;
      final fixedRaw = cfg['fixedMwkPrice'];
      if (fixedRaw != null && '$fixedRaw'.trim().isNotEmpty) {
        final n = fixedRaw is num
            ? fixedRaw.toDouble()
            : double.tryParse('$fixedRaw');
        if (n != null && n > 0) fixed = n;
      }

      double? mwkPerUnit;
      final rateRawUnit = cfg['mwkPerUnit'];
      if (rateRawUnit != null && '$rateRawUnit'.trim().isNotEmpty) {
        final n = rateRawUnit is num
            ? rateRawUnit.toDouble()
            : double.tryParse('$rateRawUnit');
        if (n != null && n > 0) mwkPerUnit = n;
      }

      double? maxOtherAmount;
      final maxRaw = cfg['maxOtherAmount'];
      if (maxRaw != null && '$maxRaw'.trim().isNotEmpty) {
        final n = maxRaw is num
            ? maxRaw.toDouble()
            : double.tryParse('$maxRaw');
        if (n != null && n > 0) maxOtherAmount = n;
      }

      List<double> amounts = const [];
      final amountsRaw = cfg['usdAmounts'];
      if (amountsRaw is List) {
        amounts = amountsRaw
            .map((e) => e is num ? e.toDouble() : double.tryParse('$e') ?? 0)
            .where((e) => e > 0)
            .toList();
      }

      final isSub = category == 'streaming' || category == 'subscription';
      Map<String, String> pfSkus = const {};
      String? pfRegion;
      var pfEnabled = false;
      var pfCodeType = 'TEXT';
      final pfRaw = cfg['prepaidForge'];
      if (pfRaw is Map) {
        pfEnabled = pfRaw['enabled'] == true;
        final region = (pfRaw['region'] ?? '').toString().trim();
        pfRegion = region.isEmpty ? null : region;
        pfSkus = _skuByUsd(pfRaw['skuByUsd']);
        pfCodeType = _codeType(pfRaw['preferredCodeType'] ?? pfRaw['codeType']);
      }
      return DigitalProduct(
        key: key,
        name: name.isNotEmpty ? name : key,
        subtitle: subtitle.isNotEmpty
            ? subtitle
            : (unitLabel.isNotEmpty ? '$unitLabel digital card' : 'Digital card'),
        category: category.isNotEmpty ? category : 'crypto',
        accent: const Color(0xFF0F766E),
        brandTag: brandTag.isNotEmpty
            ? brandTag
            : (unitLabel.isNotEmpty ? unitLabel : name),
        usdAmounts: isSub ? const [] : amounts,
        fixedMwkPrice: isSub ? fixed : null,
        mwkPerUnit: isSub ? null : mwkPerUnit,
        unitLabel: unitLabel.isNotEmpty ? unitLabel : null,
        maxOtherAmount: isSub ? null : maxOtherAmount,
        imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        icon: isSub
            ? Icons.workspace_premium_outlined
            : Icons.currency_exchange_rounded,
        active: true,
        isHub: _asHub(cfg['isHub'], key),
        hubKey: (cfg['hubKey'] ?? '').toString().trim(),
        planBadge: (cfg['planBadge'] ?? '').toString().trim(),
        featureLines: _asStringList(cfg['featureLines']),
        recommended: cfg['recommended'] == true,
        prepaidForgeEnabled: pfEnabled,
        prepaidForgeRegion: pfRegion,
        prepaidForgeSkuByUsd: pfSkus,
        prepaidForgeCodeType: pfCodeType,
      );
    }

    // Always hide disabled / out-of-stock products. Never restore the full
    // local catalog when remote config exists — that was re-showing Spotify etc.
    final localKeys = {
      ...kDigitalProducts.map((p) => p.key),
      ...kAllDigitalProducts.map((p) => p.key),
    };

    _homepage = kDigitalProducts
        .map(merge)
        .where((p) => p.active && !disabledKeys.contains(p.key))
        .where((p) => !p.isChildPlan)
        .toList();
    _all = [
      ...kAllDigitalProducts
          .map(merge)
          .where((p) => p.active && !disabledKeys.contains(p.key)),
    ];
    // Ensure Netflix plan products are always mergeable even if omitted from spread.
    for (final base in [...kNetflixPlanProducts, ...kChatGptPlanProducts]) {
      if (_all.any((p) => p.key == base.key)) continue;
      final merged = merge(base);
      if (merged.active && !disabledKeys.contains(merged.key)) {
        _all = [..._all, merged];
      }
    }

    // Append admin-created cards (USDT, Yuan, BNB, …) that are not in the
    // baked-in Flutter catalog.
    for (final entry in byKey.entries) {
      final key = entry.key;
      if (localKeys.contains(key)) continue;
      if (disabledKeys.contains(key)) continue;
      if (!_asActive(entry.value['active'])) continue;
      final remote = fromRemoteOnly(key, entry.value);
      if (!_all.any((p) => p.key == key)) {
        _all = [..._all, remote];
      }
      // Hubs and gift/crypto cards on the homepage; hide child plans.
      if (!remote.isChildPlan && !_homepage.any((p) => p.key == key)) {
        _homepage = [..._homepage, remote];
      }
    }

    if (kDebugMode && disabledKeys.isNotEmpty) {
      debugPrint(
        '[DigitalServicesCatalog] hidden (out of stock): ${disabledKeys.join(', ')} '
        '(remote=$_hasRemoteConfig homepage=${_homepage.length} all=${_all.length})',
      );
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
