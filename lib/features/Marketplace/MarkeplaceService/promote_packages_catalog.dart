import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Admin-editable promote package prices from Firestore `app_config/promote_packages`.
class PromotePackagesCatalog extends ChangeNotifier {
  PromotePackagesCatalog._();
  static final PromotePackagesCatalog instance = PromotePackagesCatalog._();

  static const String configPath = 'app_config/promote_packages';

  static const Map<String, _DefaultPkg> defaults = {
    'top_24h': _DefaultPkg(
      key: 'top_24h',
      label: '24 hours on top',
      kind: 'feed_top',
      priceMwk: 2000,
      durationHours: 24,
    ),
    'top_7d': _DefaultPkg(
      key: 'top_7d',
      label: '1 week on top',
      kind: 'feed_top',
      priceMwk: 5000,
      durationHours: 168,
    ),
    'fb_3d_local': _DefaultPkg(
      key: 'fb_3d_local',
      label: 'Facebook ads · 3 days',
      kind: 'facebook_ads',
      priceMwk: 7500,
      durationHours: 72,
      reachLabel: 'Local · ~1k–5k people',
      subtitle: 'Local reach · Vero360 runs the campaign for you',
    ),
    'fb_7d_wider': _DefaultPkg(
      key: 'fb_7d_wider',
      label: 'Facebook ads · 7 days',
      kind: 'facebook_ads',
      priceMwk: 15000,
      durationHours: 168,
      reachLabel: 'Wider · ~5k–15k people',
      subtitle: 'Wider reach · Vero360 runs the campaign for you',
    ),
  };

  final Map<String, PromotePackageLive> _byKey = {
    for (final e in defaults.entries)
      e.key: PromotePackageLive.fromDefault(e.value),
  };

  bool _loaded = false;
  bool _hasRemote = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  bool get loaded => _loaded;
  bool get hasRemoteConfig => _hasRemote;

  PromotePackageLive package(String key) {
    return _byKey[key] ??
        PromotePackageLive.fromDefault(
          defaults[key] ?? defaults.values.first,
        );
  }

  Future<void> start() async {
    if (_sub != null) return;
    try {
      _sub = FirebaseFirestore.instance.doc(configPath).snapshots().listen(
        _applySnap,
        onError: (e) {
          if (kDebugMode) {
            debugPrint('[PromotePackagesCatalog] listen failed: $e');
          }
          _loaded = true;
          notifyListeners();
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PromotePackagesCatalog] start failed: $e');
      }
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> ensureLoaded() async {
    await start();
    if (_loaded) return;
    try {
      final snap = await FirebaseFirestore.instance
          .doc(configPath)
          .get()
          .timeout(const Duration(seconds: 6));
      _applySnap(snap);
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  void _applySnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    // Reset to defaults first, then overlay remote.
    for (final e in defaults.entries) {
      _byKey[e.key] = PromotePackageLive.fromDefault(e.value);
    }

    if (!snap.exists || snap.data() == null) {
      _hasRemote = false;
      _loaded = true;
      notifyListeners();
      return;
    }

    final raw = snap.data()!['packages'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final key = (map['key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        final def = defaults[key];
        final price = _asInt(map['priceMwk'], def?.priceMwk ?? 0);
        final hours = _asInt(map['durationHours'], def?.durationHours ?? 24)
            .clamp(1, 24 * 365);
        final active = map['active'] != false;
        _byKey[key] = PromotePackageLive(
          key: key,
          label: (map['label'] ?? def?.label ?? key).toString(),
          subtitle: (map['subtitle'] ?? def?.subtitle ?? '').toString(),
          kind: (map['kind'] ?? def?.kind ?? 'feed_top').toString(),
          priceMwk: price,
          durationHours: hours,
          reachLabel: (map['reachLabel'] ?? def?.reachLabel ?? '').toString(),
          active: active,
        );
      }
    }

    _hasRemote = true;
    _loaded = true;
    notifyListeners();
  }

  static int _asInt(dynamic v, int fallback) {
    if (v is num) return v.round();
    return int.tryParse(v?.toString().replaceAll(RegExp(r'[^\d]'), '') ?? '') ??
        fallback;
  }

  void disposeCatalog() {
    _sub?.cancel();
    _sub = null;
  }
}

class PromotePackageLive {
  final String key;
  final String label;
  final String subtitle;
  final String kind;
  final int priceMwk;
  final int durationHours;
  final String reachLabel;
  final bool active;

  const PromotePackageLive({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.kind,
    required this.priceMwk,
    required this.durationHours,
    this.reachLabel = '',
    this.active = true,
  });

  factory PromotePackageLive.fromDefault(_DefaultPkg d) => PromotePackageLive(
        key: d.key,
        label: d.label,
        subtitle: d.subtitle,
        kind: d.kind,
        priceMwk: d.priceMwk,
        durationHours: d.durationHours,
        reachLabel: d.reachLabel,
        active: true,
      );
}

class _DefaultPkg {
  final String key;
  final String label;
  final String subtitle;
  final String kind;
  final int priceMwk;
  final int durationHours;
  final String reachLabel;

  const _DefaultPkg({
    required this.key,
    required this.label,
    required this.kind,
    required this.priceMwk,
    required this.durationHours,
    this.subtitle = '',
    this.reachLabel = '',
  });
}
