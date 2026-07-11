import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the customer profile photo on disk so the UI can show it without
/// re-downloading from the API/CDN every visit.
class ProfilePhotoCache {
  static const prefsRemoteUrlKey = 'profilepicture';
  static const _prefsLocalPathKey = 'profilepicture_local_path';
  static const _prefsCachedForUrlKey = 'profilepicture_cached_for_url';

  static const _fileName = 'customer_profile_avatar.jpg';

  /// Instant path from prefs (may be stale if file was deleted).
  static Future<String?> peekLocalPath() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final path = (prefs.getString(_prefsLocalPathKey) ?? '').trim();
    if (path.isEmpty) return null;
    if (!File(path).existsSync()) {
      await prefs.remove(_prefsLocalPathKey);
      await prefs.remove(_prefsCachedForUrlKey);
      return null;
    }
    return path;
  }

  static Future<File> _targetFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Returns a local [File] for [remoteUrl], downloading only when needed.
  static Future<File?> ensureCached(String remoteUrl) async {
    if (kIsWeb) return null;
    final url = remoteUrl.trim();
    if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedFor = (prefs.getString(_prefsCachedForUrlKey) ?? '').trim();
    final existingPath = (prefs.getString(_prefsLocalPathKey) ?? '').trim();

    if (cachedFor == url && existingPath.isNotEmpty) {
      final existing = File(existingPath);
      if (await existing.exists()) return existing;
    }

    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty) return null;
      return saveBytes(response.bodyBytes, remoteUrl: url);
    } catch (_) {
      // Keep previous local file if download fails.
      if (existingPath.isNotEmpty) {
        final existing = File(existingPath);
        if (await existing.exists()) return existing;
      }
      return null;
    }
  }

  /// Persist raw image bytes (e.g. right after picking/uploading).
  static Future<File?> saveBytes(
    Uint8List bytes, {
    required String remoteUrl,
  }) async {
    if (kIsWeb || bytes.isEmpty) return null;
    try {
      final file = await _targetFile();
      await file.writeAsBytes(bytes, flush: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLocalPathKey, file.path);
      await prefs.setString(_prefsCachedForUrlKey, remoteUrl.trim());
      if (remoteUrl.trim().isNotEmpty) {
        await prefs.setString(prefsRemoteUrlKey, remoteUrl.trim());
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final path = (prefs.getString(_prefsLocalPathKey) ?? '').trim();
    await prefs.remove(_prefsLocalPathKey);
    await prefs.remove(_prefsCachedForUrlKey);
    if (path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    try {
      final f = await _targetFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
