import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk cache for reel videos so swipes start instantly and watched reels
/// play without a connection. Files live in app support storage (not wiped
/// by the OS like the temp dir) and the oldest are evicted past [maxBytes].
class ReelVideoCache {
  ReelVideoCache._(this._folder, this.maxBytes);
  static final ReelVideoCache instance = ReelVideoCache._('reel_cache', 600 * 1024 * 1024);

  /// Separate store for 24h stories so reel scrolling never cancels them.
  static final ReelVideoCache stories = ReelVideoCache._('story_cache', 200 * 1024 * 1024);

  final String _folder;
  final int maxBytes;
  static const _maxConcurrent = 3;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Directory? _dir;
  Future<Directory>? _dirFuture;
  final Set<String> _ready = <String>{};
  final Map<String, CancelToken> _running = <String, CancelToken>{};
  final List<String> _queue = <String>[];
  final Map<String, List<Completer<File?>>> _waiters = <String, List<Completer<File?>>>{};
  DateTime _lastTrim = DateTime.fromMillisecondsSinceEpoch(0);

  String _key(String url) => sha1.convert(utf8.encode(url)).toString();

  Future<Directory> _directory() {
    return _dirFuture ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/$_folder');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      try {
        for (final e in dir.listSync()) {
          if (e is! File) continue;
          final name = e.uri.pathSegments.last;
          if (name.endsWith('.part')) {
            e.deleteSync();
          } else if (name.endsWith('.mp4')) {
            _ready.add(name.substring(0, name.length - 4));
          }
        }
      } catch (_) {}
      _dir = dir;
      return dir;
    }();
  }

  /// Warm up the index early so the first reel can check the cache synchronously.
  Future<void> init() async => _directory();

  File _fileFor(Directory dir, String key) => File('${dir.path}/$key.mp4');

  /// Cached file if it's fully downloaded; null otherwise. Never hits the network.
  File? cachedSync(String url) {
    final dir = _dir;
    if (dir == null || url.isEmpty) return null;
    final key = _key(url);
    if (!_ready.contains(key)) return null;
    final f = _fileFor(dir, key);
    if (!f.existsSync()) {
      _ready.remove(key);
      return null;
    }
    return f;
  }

  Future<File?> cached(String url) async {
    if (url.isEmpty) return null;
    await _directory();
    final f = cachedSync(url);
    if (f != null) {
      try {
        f.setLastModifiedSync(DateTime.now());
      } catch (_) {}
    }
    return f;
  }

  bool isCached(String url) => cachedSync(url) != null;

  /// Stores a local copy of [source] as the cached video for [url].
  Future<void> adopt(String url, File source) async {
    if (url.isEmpty) return;
    try {
      final dir = await _directory();
      final key = _key(url);
      if (_ready.contains(key)) return;
      final part = File('${dir.path}/$key.adopt.part');
      await source.copy(part.path);
      await part.rename(_fileFor(dir, key).path);
      _ready.add(key);
      unawaited(_trim());
    } catch (e) {
      if (kDebugMode) debugPrint('[Reels] cache adopt failed: $e');
    }
  }

  /// Queues a background download. [priority] jumps the queue (the reel on screen).
  void prefetch(String url, {bool priority = false}) {
    if (url.isEmpty) return;
    final key = _key(url);
    if (_ready.contains(key) || _running.containsKey(key)) return;
    _queue.remove(url);
    if (priority) {
      _queue.insert(0, url);
    } else {
      _queue.add(url);
    }
    _pump();
  }

  /// Stores the next few videos while the feed is open so swipes hit disk.
  void prefetchMany(Iterable<String> urls, {int limit = 8}) {
    var n = 0;
    for (final url in urls) {
      if (n >= limit) break;
      if (url.isEmpty) continue;
      prefetch(url, priority: n < 2);
      n++;
    }
  }

  /// Resolves when [url] is cached (or the download fails / is cancelled).
  Future<File?> whenCached(String url) async {
    final existing = await cached(url);
    if (existing != null) return existing;
    final c = Completer<File?>();
    (_waiters[_key(url)] ??= <Completer<File?>>[]).add(c);
    prefetch(url, priority: true);
    return c.future;
  }

  /// Drops queued downloads that are no longer near the screen.
  /// In-flight files are left to finish so they stay cached for the next swipe.
  void keepOnly(Iterable<String> urls) {
    final keep = urls.where((u) => u.isNotEmpty).map(_key).toSet();
    _queue.removeWhere((u) => !keep.contains(_key(u)));
  }

  void _pump() {
    while (_running.length < _maxConcurrent && _queue.isNotEmpty) {
      final url = _queue.removeAt(0);
      final key = _key(url);
      if (_ready.contains(key) || _running.containsKey(key)) continue;
      final token = CancelToken();
      _running[key] = token;
      unawaited(_download(url, key, token));
    }
  }

  Future<void> _download(String url, String key, CancelToken token) async {
    File? result;
    File? part;
    try {
      final dir = await _directory();
      part = File('${dir.path}/$key.part');
      await _dio.download(url, part.path, cancelToken: token, deleteOnError: true);
      final target = _fileFor(dir, key);
      await part.rename(target.path);
      _ready.add(key);
      result = target;
      unawaited(_trim());
    } catch (e) {
      if (kDebugMode && !(e is DioException && CancelToken.isCancel(e))) {
        debugPrint('[Reels] cache download failed: $e');
      }
      try {
        if (part != null && part.existsSync()) part.deleteSync();
      } catch (_) {}
    } finally {
      _running.remove(key);
      final waiters = _waiters.remove(key);
      if (waiters != null) {
        for (final c in waiters) {
          if (!c.isCompleted) c.complete(result);
        }
      }
      _pump();
    }
  }

  Future<void> _trim() async {
    final now = DateTime.now();
    if (now.difference(_lastTrim) < const Duration(minutes: 1)) return;
    _lastTrim = now;
    final dir = _dir;
    if (dir == null) return;
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp4'))
          .map((f) => (file: f, stat: f.statSync()))
          .toList()
        ..sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      var total = files.fold<int>(0, (sum, e) => sum + e.stat.size);
      for (final e in files) {
        if (total <= maxBytes) break;
        final name = e.file.uri.pathSegments.last;
        final key = name.substring(0, name.length - 4);
        try {
          e.file.deleteSync();
          _ready.remove(key);
          total -= e.stat.size;
        } catch (_) {}
      }
    } catch (_) {}
  }
}
