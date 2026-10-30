import 'package:package_info_plus/package_info_plus.dart';

/// Installed app version. Comes from the build (`pubspec.yaml` version),
/// not a number typed into this file.
class AppVersionInfo {
  AppVersionInfo._();

  static String version = '1.3.2';
  static String buildNumber = '10029';
  static bool ready = false;

  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (v.isNotEmpty) version = v;
      if (b.isNotEmpty) buildNumber = b;
    } catch (_) {}
    ready = true;
  }
}
