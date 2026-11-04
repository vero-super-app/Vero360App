import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/native/local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vero360_app/native/gallery_saver.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';

class ReelDownloadProgress {
  /// Server is still adding the watermark.
  final bool preparing;

  /// 0.0–1.0 once the file is downloading.
  final double progress;

  const ReelDownloadProgress({required this.preparing, required this.progress});
}

class ReelDownloadResult {
  final String reelId;
  final bool ok;
  final String message;

  const ReelDownloadResult(this.reelId, this.ok, this.message);
}

/// Runs reel downloads outside any widget so they keep going while the user
/// scrolls or leaves Reels; progress shows in the notification shade.
class ReelDownloadManager {
  ReelDownloadManager._();
  static final ReelDownloadManager instance = ReelDownloadManager._();

  static const _channel = AndroidNotificationChannel(
    'reel_downloads',
    'Reel downloads',
    description: 'Progress of reels you are saving to your gallery',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _channelReady = false;

  final ValueNotifier<Map<String, ReelDownloadProgress>> active = ValueNotifier(const {});
  final _results = StreamController<ReelDownloadResult>.broadcast();

  Stream<ReelDownloadResult> get results => _results.stream;

  bool isDownloading(String reelId) => active.value.containsKey(reelId);

  /// Starts a download; returns false if this reel is already downloading.
  bool start(Reel reel) {
    if (isDownloading(reel.id)) return false;
    _set(reel.id, const ReelDownloadProgress(preparing: true, progress: 0));
    unawaited(_run(reel));
    return true;
  }

  void _set(String id, ReelDownloadProgress? p) {
    final next = Map<String, ReelDownloadProgress>.from(active.value);
    if (p == null) {
      next.remove(id);
    } else {
      next[id] = p;
    }
    active.value = next;
  }

  int _notifId(String reelId) => 0x5E000000 ^ (reelId.hashCode & 0x00FFFFFF);

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    _channelReady = true;
    try {
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (_) {}
  }

  Future<void> _notify(
    String reelId,
    String title,
    String body, {
    int? percent,
    bool indeterminate = false,
    bool ongoing = false,
  }) async {
    try {
      await _ensureChannel();
      final showProgress = indeterminate || percent != null;
      await _notifications.show(
        _notifId(reelId),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: ongoing ? Importance.low : Importance.defaultImportance,
            priority: ongoing ? Priority.low : Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            onlyAlertOnce: true,
            ongoing: ongoing,
            autoCancel: !ongoing,
            showProgress: showProgress,
            indeterminate: indeterminate,
            maxProgress: 100,
            progress: percent ?? 0,
          ),
          iOS: DarwinNotificationDetails(presentSound: false, presentAlert: !ongoing),
        ),
      );
    } catch (_) {}
  }

  Future<void> _run(Reel reel) async {
    final id = reel.id;
    final who = reel.ownerName;
    File? file;
    try {
      unawaited(_notify(id, 'Preparing reel', 'Adding watermark to $who\'s reel',
          indeterminate: true, ongoing: true));

      final dir = await getTemporaryDirectory();
      final name = 'vero360_reel_${id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      file = File('${dir.path}/$name');

      final url = await ReelService.instance.downloadSourceUrl(reel);
      var lastPct = -1;
      await Dio().download(
        url,
        file.path,
        onReceiveProgress: (got, total) {
          if (total <= 0) return;
          final p = got / total;
          final pct = (p * 100).floor();
          if (pct == lastPct) return;
          lastPct = pct;
          _set(id, ReelDownloadProgress(preparing: false, progress: p));
          if (pct % 5 == 0) {
            unawaited(_notify(id, 'Downloading reel', '$pct%', percent: pct, ongoing: true));
          }
        },
      );
      if (!file.existsSync() || file.lengthSync() <= 0) {
        throw Exception('Could not download the video. Try again.');
      }
      _set(id, const ReelDownloadProgress(preparing: false, progress: 1));

      var saved = await _save(file.path, name);
      if (!saved.isSuccess) {
        await _requestGalleryAccess();
        saved = await _save(file.path, name);
      }
      if (saved.isSuccess) {
        await _notify(id, 'Reel saved', '$who\'s reel is in your gallery');
        _results.add(ReelDownloadResult(id, true, 'Video saved to your gallery'));
      } else {
        final why = (saved.errorMessage ?? '').trim();
        final msg = why.isEmpty
            ? 'Could not save video. Allow gallery access and try again.'
            : why;
        await _notify(id, 'Could not save reel', msg);
        _results.add(ReelDownloadResult(id, false, msg));
      }
    } on Exception catch (e) {
      final msg = e is DioException
          ? 'Download failed. Check your connection.'
          : e.toString().replaceFirst('Exception: ', '');
      await _notify(id, 'Reel download failed', msg);
      _results.add(ReelDownloadResult(id, false, msg));
    } finally {
      try {
        if (file != null && file.existsSync()) file.deleteSync();
      } catch (_) {}
      _set(id, null);
    }
  }

  static const _gallery = MethodChannel('vero360.app/gallery');

  Future<void> _requestGalleryAccess() async {
    try {
      if (Platform.isIOS) {
        var status = await Permission.photosAddOnly.request();
        if (!status.isGranted && !status.isLimited) {
          await Permission.photos.request();
        }
      } else if (Platform.isAndroid) {
        await Permission.storage.request();
      }
    } catch (_) {}
  }

  bool _savedDespiteScanError(String? message) {
    final m = (message ?? '').toLowerCase();
    return m.contains('could not be scanned') ||
        m.contains('could not be found') ||
        m.contains('file null could not');
  }

  Future<SaveResult> _save(String path, String name) async {
    if (Platform.isAndroid) {
      try {
        await _gallery.invokeMethod<bool>('saveVideo', {
          'path': path,
          'fileName': name,
        });
        return SaveResult(true, null);
      } on PlatformException catch (e) {
        if (kDebugMode) debugPrint('[Reels] native gallery save: ${e.code} ${e.message}');
      } catch (e) {
        if (kDebugMode) debugPrint('[Reels] native gallery save: $e');
      }
    }

    for (final folder in const ['Movies/Vero360', 'Movies']) {
      final saved = await SaverGallery.saveFile(
        filePath: path,
        fileName: name,
        androidRelativePath: folder,
        skipIfExists: false,
      );
      if (saved.isSuccess || _savedDespiteScanError(saved.errorMessage)) {
        return SaveResult(true, null);
      }
      if (kDebugMode) {
        debugPrint('[Reels] SaverGallery $folder: ${saved.errorMessage}');
      }
    }
    return SaveResult(false, 'Could not save video to your gallery.');
  }
}
