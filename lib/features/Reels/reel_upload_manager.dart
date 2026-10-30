import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vero360_app/features/Reels/reel_model.dart';
import 'package:vero360_app/features/Reels/reel_service.dart';

class ReelUpload {
  final String filePath;
  final String caption;
  final Duration duration;
  final ReelProduct? product;
  final ReelMusic? music;

  /// 0.0–1.0 while uploading.
  final double progress;

  /// Set when the upload failed; the upload can be retried.
  final String? error;

  const ReelUpload({
    required this.filePath,
    required this.caption,
    required this.duration,
    this.product,
    this.music,
    this.progress = 0,
    this.error,
  });

  bool get failed => error != null;

  ReelUpload copyWith({double? progress, String? error, bool clearError = false}) => ReelUpload(
        filePath: filePath,
        caption: caption,
        duration: duration,
        product: product,
        music: music,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
      );
}

class ReelUploadResult {
  final bool ok;
  final String? reelId;
  final String message;

  const ReelUploadResult({required this.ok, this.reelId, required this.message});
}

/// Posts reels outside any widget so the user can keep watching the feed
/// while the video uploads; progress shows on Reels and in the notification shade.
class ReelUploadManager {
  ReelUploadManager._();
  static final ReelUploadManager instance = ReelUploadManager._();

  static const _notifId = 0x5E100001;
  static const _channel = AndroidNotificationChannel(
    'reel_uploads',
    'Reel uploads',
    description: 'Progress of reels you are posting',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _channelReady = false;

  /// The upload in progress (or the last failed one), null when idle.
  final ValueNotifier<ReelUpload?> current = ValueNotifier(null);
  final _results = StreamController<ReelUploadResult>.broadcast();

  Stream<ReelUploadResult> get results => _results.stream;

  bool get isUploading => current.value != null && !current.value!.failed;

  /// Starts posting; returns false if another reel is still uploading.
  bool start({
    required String filePath,
    required String caption,
    required Duration duration,
    ReelProduct? product,
    ReelMusic? music,
  }) {
    if (isUploading) return false;
    if (!ReelService.instance.isSignedIn) return false;
    current.value = ReelUpload(
      filePath: filePath,
      caption: caption,
      duration: duration,
      product: product,
      music: music,
    );
    unawaited(_run());
    return true;
  }

  void retry() {
    final job = current.value;
    if (job == null || !job.failed) return;
    current.value = job.copyWith(progress: 0, clearError: true);
    unawaited(_run());
  }

  void dismiss() {
    if (current.value?.failed == true) current.value = null;
  }

  Future<void> _ensureChannel() async {
    if (_channelReady) return;
    _channelReady = true;
    try {
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (_) {}
  }

  Future<void> _notify(String title, String body, {int? percent, bool ongoing = false}) async {
    try {
      await _ensureChannel();
      await _notifications.show(
        _notifId,
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
            showProgress: percent != null,
            maxProgress: 100,
            progress: percent ?? 0,
          ),
          iOS: DarwinNotificationDetails(presentSound: false, presentAlert: !ongoing),
        ),
      );
    } catch (_) {}
  }

  Future<void> _run() async {
    final job = current.value;
    if (job == null) return;
    var lastPct = -1;
    unawaited(_notify('Posting your reel', '0%', percent: 0, ongoing: true));
    try {
      final id = await ReelService.instance.postReel(
        filePath: job.filePath,
        caption: job.caption,
        duration: job.duration,
        product: job.product,
        music: job.music,
        onProgress: (p) {
          final pct = (p * 100).floor();
          if (pct == lastPct) return;
          lastPct = pct;
          final now = current.value;
          if (now != null) current.value = now.copyWith(progress: p);
          if (pct % 5 == 0) {
            unawaited(_notify('Posting your reel', '$pct%', percent: pct, ongoing: true));
          }
        },
      );
      current.value = null;
      await _notify('Reel posted', 'Your reel is live on Vero360');
      _results.add(ReelUploadResult(ok: true, reelId: id, message: 'Reel posted'));
    } catch (e) {
      if (kDebugMode) debugPrint('[Reels] upload failed: $e');
      final raw = e.toString().replaceFirst('Exception: ', '');
      final msg = raw.length > 120 ? 'Could not post reel. Check your connection.' : raw;
      current.value = job.copyWith(error: msg);
      await _notify('Reel not posted', msg);
      _results.add(ReelUploadResult(ok: false, message: msg));
    }
  }
}
