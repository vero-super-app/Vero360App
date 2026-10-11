import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/utils/app_version_info.dart';

/// Result of comparing the installed app version with the live store listing.
class AppUpdateCheckResult {
  final String installedVersion;
  final String? storeVersion;
  final String? storeBuild;
  final String storeUrl;
  final bool updateAvailable;
  final String? errorMessage;

  const AppUpdateCheckResult({
    required this.installedVersion,
    required this.storeVersion,
    this.storeBuild,
    required this.storeUrl,
    required this.updateAvailable,
    this.errorMessage,
  });

  bool get ok => errorMessage == null;
}

/// Checks for a newer published version.
///
/// Order:
/// 1. Firestore `app_config/app_version` (works while listings are private /
///    not yet live — set `latestVersion` + store URLs / `appleAppId` there)
/// 2. Live Google Play HTML / iTunes lookup (once the app is public)
class AppUpdateChecker {
  AppUpdateChecker._();

  static const playStoreId = 'com.vero265.app';
  static const iosBundleId = 'com.vero265.app';

  /// Prefer production package; keep legacy candidates for older installs.
  static const iosBundleCandidates = <String>[
    iosBundleId,
    'com.verosuperapp.v265',
    'com.verosuperapp.265',
    'com.vero.vero360',
    'com.example.verotechApp',
  ];

  /// Firestore doc admins maintain when store pages are private or scrape fails.
  /// Example fields:
  /// ```
  /// latestVersion: "1.1.5"
  /// latestBuild: "10027" (optional; reminds when the version matches but the build is older)
  /// androidVersion / iosVersion: optional overrides
  /// androidPackageId / iosBundleId / appleAppId
  /// playStoreUrl / appStoreUrl
  /// ```
  static const firestoreConfigPath = 'app_config/app_version';
  static const _promptPrefKey = 'app_update_daily_prompt_v1';
  static bool _promptInFlight = false;

  /// Shows an update reminder at most once per day while this install is behind
  /// the published version (or build, when Firestore sets `latestBuild`).
  static Future<void> maybeRemindOncePerDay(BuildContext context) async {
    if (_promptInFlight || kIsWeb) return;
    _promptInFlight = true;
    try {
      final result = await check();
      if (!result.updateAvailable || !context.mounted) return;

      final target =
          '${result.storeVersion ?? ''}+${result.storeBuild ?? ''}'.trim();
      final today = _todayKey();
      final prefs = await SharedPreferences.getInstance();
      final stamp = prefs.getString(_promptPrefKey) ?? '';
      if (stamp == '$today|$target') return;
      if (!context.mounted) return;

      await prefs.setString(_promptPrefKey, '$today|$target');

      final lang = prefs.getString('pref_language_code') ?? 'en';
      final ny = lang == 'ny';
      final installed = result.installedVersion.trim();
      final build = AppVersionInfo.buildNumber.trim();
      final store = (result.storeVersion ?? '').trim();
      final storeBuild = (result.storeBuild ?? '').trim();
      final storeLabel = storeBuild.isEmpty ? 'v$store' : 'v$store ($storeBuild)';
      final hereLabel = build.isEmpty ? 'v$installed' : 'v$installed (build $build)';
      if (!context.mounted) return;

      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Color(0xFFFF8A00),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  ny ? 'Sinthani Vero360' : 'Update Vero360',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF101010),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ny
                      ? 'Pulogalamu yanu ndi yakale. $storeLabel ili pa sitolo. Muli pa $hereLabel. Sinthani kuti maoda, mauthenga, ndi malipiro agwire ntchito bwino.'
                      : 'This install is behind the latest build. $storeLabel is on the store. You are on $hereLabel. Update so orders, chats, and payments keep working.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          ny ? 'Pambuyo' : 'Not now',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8A00),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          ny ? 'Sinthani' : 'Update',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (go == true) {
        await openStore(result.storeUrl);
      }
    } catch (_) {
    } finally {
      _promptInFlight = false;
    }
  }

  static String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  static Future<AppUpdateCheckResult> check() async {
    await AppVersionInfo.ensureLoaded();
    final installed = AppVersionInfo.version.trim();

    if (kIsWeb) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: playStoreUrl(playStoreId),
        updateAvailable: false,
        errorMessage: 'Store updates are not available on web.',
      );
    }

    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final remote = await _loadRemoteConfig();

    // Prefer remote config — reliable even when Play/App Store pages 404.
    final remoteVersion = isIos
        ? (remote?.iosVersion ?? remote?.latestVersion)
        : (remote?.androidVersion ?? remote?.latestVersion);
    final remoteUrl = isIos
        ? (remote?.appStoreUrl ??
            (remote?.appleAppId != null && remote!.appleAppId!.isNotEmpty
                ? appStoreUrlForId(remote.appleAppId!)
                : null))
        : (remote?.playStoreUrl ??
            playStoreUrl(remote?.androidPackageId ?? playStoreId));

    if (remoteVersion != null && remoteVersion.isNotEmpty) {
      final storeUrl = (remoteUrl ?? defaultStoreUrl(isIos: isIos)).trim();
      final remoteBuild = isIos
          ? (remote?.iosBuild ?? remote?.latestBuild)
          : (remote?.androidBuild ?? remote?.latestBuild);
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: remoteVersion,
        storeBuild: remoteBuild,
        storeUrl: storeUrl,
        updateAvailable: _isBehind(
          installedVersion: installed,
          installedBuild: AppVersionInfo.buildNumber,
          storeVersion: remoteVersion,
          storeBuild: remoteBuild,
        ),
      );
    }

    try {
      if (isIos) {
        return await _checkIos(
          installed: installed,
          packageName: remote?.iosBundleId ?? iosBundleId,
          appleAppId: remote?.appleAppId,
          fallbackUrl: remoteUrl,
        );
      }
      return await _checkAndroid(
        installed: installed,
        packageName: remote?.androidPackageId ?? playStoreId,
        fallbackUrl: remoteUrl,
      );
    } catch (e) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: remoteUrl ?? defaultStoreUrl(isIos: isIos),
        updateAvailable: false,
        errorMessage: e.toString(),
      );
    }
  }

  static String defaultStoreUrl({required bool isIos}) =>
      isIos ? appStoreSearchUrl() : playStoreUrl(playStoreId);

  /// Open Play Store (Android) or App Store (iOS) for this install.
  /// Prefers Firestore `app_config/app_version` URLs when set.
  static Future<bool> openStoreForThisPlatform() async {
    if (kIsWeb) return false;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final remote = await _loadRemoteConfig();
    String url;
    if (isIos) {
      url = (remote?.appStoreUrl ?? '').trim();
      if (url.isEmpty &&
          remote?.appleAppId != null &&
          remote!.appleAppId!.trim().isNotEmpty) {
        url = appStoreUrlForId(remote.appleAppId!.trim());
      }
      if (url.isEmpty) url = appStoreSearchUrl();
    } else {
      url = (remote?.playStoreUrl ?? '').trim();
      if (url.isEmpty) {
        url = playStoreUrl(remote?.androidPackageId ?? playStoreId);
      }
    }
    return openStore(url);
  }

  static Future<bool> openStore(String url) async {
    final raw = url.trim();
    if (raw.isEmpty) return false;

    // Prefer native store schemes; fall back to https.
    final candidates = <Uri>[];
    final https = Uri.tryParse(raw);
    if (https != null) candidates.add(https);

    final playIdMatch = RegExp(r'[?&]id=([A-Za-z0-9._]+)').firstMatch(raw);
    if (playIdMatch != null) {
      candidates.insert(
        0,
        Uri.parse('market://details?id=${playIdMatch.group(1)}'),
      );
    }
    final appleIdMatch =
        RegExp(r'apps\.apple\.com/.*?/id(\d+)').firstMatch(raw);
    if (appleIdMatch != null) {
      candidates.insert(
        0,
        Uri.parse('itms-apps://itunes.apple.com/app/id${appleIdMatch.group(1)}'),
      );
    }

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static String playStoreUrl(String id) =>
      'https://play.google.com/store/apps/details?id=$id';

  static String appStoreUrlForId(String appleAppId) =>
      'https://apps.apple.com/app/id$appleAppId';

  static String appStoreSearchUrl() =>
      'https://apps.apple.com/search?term=Vero360%20Malawi';

  static Future<_RemoteVersionConfig?> _loadRemoteConfig() async {
    try {
      final snap = await FirebaseFirestore.instance
          .doc(firestoreConfigPath)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return _RemoteVersionConfig.fromMap(data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppUpdateChecker] remote config failed: $e');
      }
      return null;
    }
  }

  static Future<AppUpdateCheckResult> _checkAndroid({
    required String installed,
    required String packageName,
    String? fallbackUrl,
  }) async {
    final id = packageName.isNotEmpty ? packageName : playStoreId;
    final url = (fallbackUrl != null && fallbackUrl.trim().isNotEmpty)
        ? fallbackUrl.trim()
        : playStoreUrl(id);

    // Try a few locales — listing may be country-gated.
    String? storeVersion;
    String? lastError;
    for (final gl in const ['MW', 'ZA', 'US', 'GB', '']) {
      final pageUrl = gl.isEmpty
          ? playStoreUrl(id)
          : '${playStoreUrl(id)}&hl=en&gl=$gl';
      try {
        final res = await http
            .get(
              Uri.parse(pageUrl),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode == 404) {
          lastError = 'Play Store listing not found for $id.';
          continue;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastError = 'Could not reach Play Store (${res.statusCode}).';
          continue;
        }

        storeVersion = _parsePlayStoreVersion(res.body);
        if (storeVersion != null && storeVersion.isNotEmpty) break;
        lastError = 'Could not read the Play Store version.';
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (storeVersion == null || storeVersion.isEmpty) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: url,
        updateAvailable: false,
        errorMessage: lastError ??
            'Play Store listing not found. Set $firestoreConfigPath '
                'in Firestore (latestVersion + playStoreUrl).',
      );
    }

    return AppUpdateCheckResult(
      installedVersion: installed,
      storeVersion: storeVersion,
      storeUrl: url,
      updateAvailable: isNewerVersion(storeVersion, installed),
    );
  }

  static Future<AppUpdateCheckResult> _checkIos({
    required String installed,
    required String packageName,
    String? appleAppId,
    String? fallbackUrl,
  }) async {
    // Direct lookup by numeric App Store id when known.
    final appleId = (appleAppId ?? '').trim();
    if (appleId.isNotEmpty) {
      for (final country in const ['mw', 'us', 'za', '']) {
        try {
          final lookup = await _lookupIosById(id: appleId, country: country);
          if (lookup == null) continue;
          final storeVersion = (lookup['version'] ?? '').toString().trim();
          final trackUrl = (lookup['trackViewUrl'] ?? '').toString().trim();
          final storeUrl = trackUrl.isNotEmpty
              ? trackUrl
              : (fallbackUrl?.trim().isNotEmpty == true
                  ? fallbackUrl!.trim()
                  : appStoreUrlForId(appleId));
          if (storeVersion.isEmpty) continue;
          return AppUpdateCheckResult(
            installedVersion: installed,
            storeVersion: storeVersion,
            storeUrl: storeUrl,
            updateAvailable: isNewerVersion(storeVersion, installed),
          );
        } catch (_) {}
      }
    }

    final candidates = <String>[
      if (packageName.isNotEmpty) packageName,
      ...iosBundleCandidates,
    ];
    final seen = <String>{};
    String? lastError;

    for (final bundleId in candidates) {
      if (!seen.add(bundleId)) continue;
      for (final country in const ['mw', 'za', 'us', '']) {
        try {
          final lookup = await _lookupIos(bundleId: bundleId, country: country);
          if (lookup == null) continue;
          final storeVersion = (lookup['version'] ?? '').toString().trim();
          final trackUrl = (lookup['trackViewUrl'] ?? '').toString().trim();
          final storeUrl = trackUrl.isNotEmpty
              ? trackUrl
              : (fallbackUrl?.trim().isNotEmpty == true
                  ? fallbackUrl!.trim()
                  : appStoreSearchUrl());
          if (storeVersion.isEmpty) {
            lastError = 'App Store listing has no version.';
            continue;
          }
          return AppUpdateCheckResult(
            installedVersion: installed,
            storeVersion: storeVersion,
            storeUrl: storeUrl,
            updateAvailable: isNewerVersion(storeVersion, installed),
          );
        } catch (e) {
          lastError = e.toString();
        }
      }
    }

    return AppUpdateCheckResult(
      installedVersion: installed,
      storeVersion: null,
      storeUrl: fallbackUrl?.trim().isNotEmpty == true
          ? fallbackUrl!.trim()
          : (appleId.isNotEmpty
              ? appStoreUrlForId(appleId)
              : appStoreSearchUrl()),
      updateAvailable: false,
      errorMessage: lastError ??
          'App not found on the App Store yet. Set $firestoreConfigPath '
              'in Firestore (latestVersion + appleAppId / appStoreUrl).',
    );
  }

  static Future<Map<String, dynamic>?> _lookupIos({
    required String bundleId,
    required String country,
  }) async {
    final params = <String, String>{'bundleId': bundleId};
    if (country.isNotEmpty) params['country'] = country;
    final uri = Uri.https('itunes.apple.com', '/lookup', params);
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    return Map<String, dynamic>.from(first);
  }

  static Future<Map<String, dynamic>?> _lookupIosById({
    required String id,
    required String country,
  }) async {
    final params = <String, String>{'id': id};
    if (country.isNotEmpty) params['country'] = country;
    final uri = Uri.https('itunes.apple.com', '/lookup', params);
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    return Map<String, dynamic>.from(first);
  }

  static String? _parsePlayStoreVersion(String html) {
    final patterns = <RegExp>[
      // Modern Play Store AF_initDataCallback blobs.
      RegExp(r'\[\[\["([\d]+(?:\.[\d]+)+)"\]\]'),
      RegExp(r'"softwareVersion"\s*:\s*"([^"]+)"'),
      RegExp(r'itemprop="softwareVersion"\s*[^>]*>\s*([^<]+)\s*<'),
      RegExp(
        r'Current Version</div><span[^>]*><div[^>]*><span[^>]*>([^<]+)</span>',
      ),
      RegExp(r'\[\[\["([\d.]+?)"\]\]'),
      RegExp(r'\\"(\d+\.\d+(?:\.\d+)?)\\"\]\s*,\s*\[\s*\[\s*\[\s*\\"?\d'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      final v = m?.group(1)?.trim();
      if (v != null && v.isNotEmpty && RegExp(r'^\d').hasMatch(v)) {
        return v;
      }
    }
    return null;
  }

  static bool _isBehind({
    required String installedVersion,
    required String installedBuild,
    required String storeVersion,
    String? storeBuild,
  }) {
    if (isNewerVersion(storeVersion, installedVersion)) return true;
    if (isNewerVersion(installedVersion, storeVersion)) return false;
    final remote = int.tryParse((storeBuild ?? '').trim());
    final local = int.tryParse(installedBuild.trim());
    if (remote == null || local == null) return false;
    return remote > local;
  }

  /// True when [candidate] is strictly newer than [current].
  static bool isNewerVersion(String candidate, String current) {
    final a = _versionParts(candidate);
    final b = _versionParts(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x > y) return true;
      if (x < y) return false;
    }
    return false;
  }

  static List<int> _versionParts(String raw) {
    final core = raw.trim().split(RegExp(r'[-+]')).first;
    return core
        .split('.')
        .map((p) => int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '') ?? 0)
        .toList();
  }
}

class _RemoteVersionConfig {
  final String? latestVersion;
  final String? androidVersion;
  final String? iosVersion;
  final String? androidPackageId;
  final String? iosBundleId;
  final String? appleAppId;
  final String? playStoreUrl;
  final String? appStoreUrl;
  final String? latestBuild;
  final String? androidBuild;
  final String? iosBuild;

  const _RemoteVersionConfig({
    this.latestVersion,
    this.androidVersion,
    this.iosVersion,
    this.androidPackageId,
    this.iosBundleId,
    this.appleAppId,
    this.playStoreUrl,
    this.appStoreUrl,
    this.latestBuild,
    this.androidBuild,
    this.iosBuild,
  });

  factory _RemoteVersionConfig.fromMap(Map<String, dynamic> data) {
    String? s(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return _RemoteVersionConfig(
      latestVersion: s(data['latestVersion'] ?? data['version']),
      androidVersion: s(data['androidVersion'] ?? data['playStoreVersion']),
      iosVersion: s(data['iosVersion'] ?? data['appStoreVersion']),
      androidPackageId: s(data['androidPackageId'] ?? data['playStoreId']),
      iosBundleId: s(data['iosBundleId'] ?? data['bundleId']),
      appleAppId: s(data['appleAppId'] ?? data['iosAppId'] ?? data['trackId']),
      playStoreUrl: s(data['playStoreUrl'] ?? data['androidStoreUrl']),
      appStoreUrl: s(data['appStoreUrl'] ?? data['iosStoreUrl']),
      latestBuild: s(data['latestBuild'] ?? data['buildNumber']),
      androidBuild: s(data['androidBuild'] ?? data['androidBuildNumber']),
      iosBuild: s(data['iosBuild'] ?? data['iosBuildNumber']),
    );
  }
}
