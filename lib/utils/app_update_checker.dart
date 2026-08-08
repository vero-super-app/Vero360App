import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/utils/app_version_info.dart';

/// Result of comparing the installed app version with the live store listing.
class AppUpdateCheckResult {
  final String installedVersion;
  final String? storeVersion;
  final String storeUrl;
  final bool updateAvailable;
  final String? errorMessage;

  const AppUpdateCheckResult({
    required this.installedVersion,
    required this.storeVersion,
    required this.storeUrl,
    required this.updateAvailable,
    this.errorMessage,
  });

  bool get ok => errorMessage == null;
}

/// Checks Google Play / App Store for a newer published version.
class AppUpdateChecker {
  AppUpdateChecker._();

  static const playStoreId = 'com.vero265.app';
  /// Prefer production package; keep legacy candidates for older installs.
  static const iosBundleCandidates = <String>[
    'com.vero265.app',
    'com.verosuperapp.v265',
    'com.verosuperapp.265',
    'com.vero.vero360',
    'com.example.verotechApp',
  ];

  static Future<AppUpdateCheckResult> check() async {
    final installed = AppVersionInfo.version.trim();
    const packageName = playStoreId;

    if (kIsWeb) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: playStoreUrl(playStoreId),
        updateAvailable: false,
        errorMessage: 'Store updates are not available on web.',
      );
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _checkIos(installed: installed, packageName: packageName);
      }
      return await _checkAndroid(
        installed: installed,
        packageName: packageName,
      );
    } catch (e) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: defaultTargetPlatform == TargetPlatform.iOS
            ? appStoreSearchUrl()
            : playStoreUrl(packageName),
        updateAvailable: false,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<bool> openStore(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  static String playStoreUrl(String id) =>
      'https://play.google.com/store/apps/details?id=$id';

  static String appStoreSearchUrl() =>
      'https://apps.apple.com/search?term=Vero360';

  static Future<AppUpdateCheckResult> _checkAndroid({
    required String installed,
    required String packageName,
  }) async {
    final id = packageName.isNotEmpty ? packageName : playStoreId;
    final url = playStoreUrl(id);
    final res = await http
        .get(
          Uri.parse('$url&hl=en&gl=US'),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: url,
        updateAvailable: false,
        errorMessage: 'Could not reach Play Store.',
      );
    }

    final storeVersion = _parsePlayStoreVersion(res.body);
    if (storeVersion == null || storeVersion.isEmpty) {
      return AppUpdateCheckResult(
        installedVersion: installed,
        storeVersion: null,
        storeUrl: url,
        updateAvailable: false,
        errorMessage: 'Could not read the Play Store version.',
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
  }) async {
    final candidates = <String>[
      if (packageName.isNotEmpty) packageName,
      ...iosBundleCandidates,
    ];
    final seen = <String>{};
    String? lastError;

    for (final bundleId in candidates) {
      if (!seen.add(bundleId)) continue;
      for (final country in const ['mw', 'us', '']) {
        try {
          final lookup = await _lookupIos(bundleId: bundleId, country: country);
          if (lookup == null) continue;
          final storeVersion = (lookup['version'] ?? '').toString().trim();
          final trackUrl = (lookup['trackViewUrl'] ?? '').toString().trim();
          final storeUrl = trackUrl.isNotEmpty
              ? trackUrl
              : appStoreSearchUrl();
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
      storeUrl: appStoreSearchUrl(),
      updateAvailable: false,
      errorMessage: lastError ?? 'App not found on the App Store yet.',
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

  static String? _parsePlayStoreVersion(String html) {
    final patterns = <RegExp>[
      RegExp(r'\[\[\["([\d]+(?:\.[\d]+)+)"\]\]'),
      RegExp(r'"softwareVersion"\s*:\s*"([^"]+)"'),
      RegExp(
        r'Current Version</div><span[^>]*><div[^>]*><span[^>]*>([^<]+)</span>',
      ),
      RegExp(r'\[\[\["([\d.]+?)"\]\]'),
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
