import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// WhatsApp-style inline voice note player for chat bubbles.
///
/// Play is never blocked on a full download: local/cached files play instantly,
/// otherwise we stream the URL immediately and cache in the background.
class VoiceNoteBubble extends StatefulWidget {
  final String messageId;
  final String url;
  final String? localPath;
  final int durationMs;
  final bool isMine;

  const VoiceNoteBubble({
    super.key,
    required this.messageId,
    required this.url,
    this.localPath,
    required this.durationMs,
    required this.isMine,
  });

  /// Prefetch a remote voice note into disk cache (non-blocking for UI).
  static Future<String?> warmUrl(String url) => VoiceNoteCache.warm(url);

  /// Prefetch many VNs (e.g. after chat messages load).
  static void warmUrls(Iterable<String> urls) => VoiceNoteCache.warmMany(urls);

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

/// Shared disk cache for voice notes (download once, play from file next time).
class VoiceNoteCache {
  VoiceNoteCache._();

  static Directory? _cacheDir;
  static final Map<String, String> _memory = <String, String>{};
  static final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};

  static Future<Directory> _dir() async {
    final hit = _cacheDir;
    if (hit != null) return hit;
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}/voice_notes');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  static String? peek(String url) {
    final key = url.trim();
    if (key.isEmpty) return null;
    final path = _memory[key];
    if (path != null && File(path).existsSync()) return path;
    return null;
  }

  static Future<String?> warm(String url) async {
    final key = url.trim();
    if (key.isEmpty || kIsWeb) return null;

    final mem = peek(key);
    if (mem != null) return mem;

    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = () async {
      try {
        final dir = await _dir();
        final file = File('${dir.path}/vn_${key.hashCode.abs()}.m4a');
        if (await file.exists() && await file.length() > 0) {
          _memory[key] = file.path;
          return file.path;
        }

        final res = await http
            .get(Uri.parse(key))
            .timeout(const Duration(seconds: 25));
        if (res.statusCode < 200 ||
            res.statusCode >= 300 ||
            res.bodyBytes.isEmpty) {
          return null;
        }

        // Write without flush — much faster; OS will persist soon enough.
        await file.writeAsBytes(res.bodyBytes);
        _memory[key] = file.path;
        return file.path;
      } catch (e) {
        if (kDebugMode) debugPrint('[VoiceNote] cache failed: $e');
        return null;
      } finally {
        _inflight.remove(key);
      }
    }();

    _inflight[key] = future;
    return future;
  }

  static void warmMany(Iterable<String> urls) {
    // Prefer newest notes first (callers usually pass chronological order).
    final list = urls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList()
        .reversed
        .take(12)
        .toList();
    for (final url in list) {
      unawaited(warm(url));
    }
  }
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  static AudioPlayer? _sharedPlayer;
  static String? _activeMessageId;
  static String? _loadedSourceKey;
  static bool _playerConfigured = false;
  static StreamSubscription<Duration>? _positionSub;
  static StreamSubscription<void>? _completeSub;
  static StreamSubscription<PlayerState>? _stateSub;
  static StreamSubscription<Duration>? _durationSub;

  bool _playing = false;
  bool _preparing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _cachedPath;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.durationMs);
    if (_activeMessageId == widget.messageId) {
      _playing = _sharedPlayer?.state == PlayerState.playing;
    }
    _cachedPath = VoiceNoteCache.peek(widget.url);
    unawaited(_warmInBackground());
    unawaited(_ensurePlayer());
  }

  @override
  void didUpdateWidget(covariant VoiceNoteBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.localPath != widget.localPath) {
      _cachedPath = VoiceNoteCache.peek(widget.url);
      unawaited(_warmInBackground());
    }
  }

  @override
  void dispose() {
    if (_activeMessageId == widget.messageId) {
      unawaited(_detachListeners());
    }
    super.dispose();
  }

  bool get _hasSource {
    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty) return true;
    return widget.url.trim().isNotEmpty;
  }

  Future<void> _warmInBackground() async {
    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty) {
      if (mounted) setState(() => _cachedPath = local);
      return;
    }
    final url = widget.url.trim();
    if (url.isEmpty) return;
    final path = await VoiceNoteCache.warm(url);
    if (!mounted || path == null) return;
    setState(() => _cachedPath = path);
  }

  Future<AudioPlayer> _ensurePlayer() async {
    if (_sharedPlayer != null) return _sharedPlayer!;
    final player = AudioPlayer();
    if (!_playerConfigured) {
      _playerConfigured = true;
      try {
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await AudioPlayer.global.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: false,
              contentType: AndroidContentType.speech,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gain,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {
                AVAudioSessionOptions.defaultToSpeaker,
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[VoiceNote] audio context: $e');
      }
    }
    _sharedPlayer = player;
    return player;
  }

  Future<void> _detachListeners() async {
    await _positionSub?.cancel();
    await _completeSub?.cancel();
    await _stateSub?.cancel();
    await _durationSub?.cancel();
    _positionSub = null;
    _completeSub = null;
    _stateSub = null;
    _durationSub = null;
  }

  void _attachListeners(AudioPlayer player) {
    // Fire-and-forget cancel+reattach so play isn't blocked.
    unawaited(_detachListeners().then((_) {
      if (_activeMessageId != widget.messageId) return;
      _positionSub = player.onPositionChanged.listen((pos) {
        if (!mounted || _activeMessageId != widget.messageId) return;
        setState(() => _position = pos);
      });
      _completeSub = player.onPlayerComplete.listen((_) {
        if (!mounted || _activeMessageId != widget.messageId) return;
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      });
      _stateSub = player.onPlayerStateChanged.listen((state) {
        if (!mounted || _activeMessageId != widget.messageId) return;
        setState(() => _playing = state == PlayerState.playing);
      });
      _durationSub = player.onDurationChanged.listen((d) {
        if (!mounted || _activeMessageId != widget.messageId) return;
        if (d > Duration.zero) setState(() => _duration = d);
      });
    }));
  }

  /// Prefer local/cached file; otherwise stream URL immediately (no wait).
  Source _instantSource() {
    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      return DeviceFileSource(local);
    }
    final cached =
        _cachedPath ?? VoiceNoteCache.peek(widget.url.trim());
    if (cached != null &&
        cached.isNotEmpty &&
        File(cached).existsSync()) {
      _cachedPath = cached;
      return DeviceFileSource(cached);
    }
    // Stream now — cache continues in background for next tap.
    unawaited(_warmInBackground());
    return UrlSource(widget.url.trim());
  }

  String _keyFor(Source source) {
    if (source is DeviceFileSource) return 'file:${source.path}';
    if (source is UrlSource) return 'url:${source.url}';
    return source.toString();
  }

  Future<void> _togglePlayback() async {
    if (!_hasSource) return;

    // Pause current note instantly.
    if (_playing && _activeMessageId == widget.messageId) {
      await _sharedPlayer?.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }

    // Optimistic UI — don't wait for buffering before flipping the icon.
    if (mounted) {
      setState(() {
        _playing = true;
        _preparing = true;
        _position = Duration.zero;
      });
    }

    try {
      final player = await _ensurePlayer();
      final source = _instantSource();
      final sourceKey = _keyFor(source);
      final sameNote = _activeMessageId == widget.messageId;
      final sameSource = _loadedSourceKey == sourceKey;

      _activeMessageId = widget.messageId;
      _attachListeners(player);

      if (sameNote &&
          sameSource &&
          player.state == PlayerState.paused) {
        await player.resume();
        if (mounted) setState(() => _preparing = false);
        return;
      }

      if (sameSource && player.state == PlayerState.completed) {
        await player.seek(Duration.zero);
        await player.resume();
        if (mounted) setState(() => _preparing = false);
        return;
      }

      // Stop previous note only if switching — don't dispose the player.
      if (!sameNote && _loadedSourceKey != null) {
        try {
          await player.stop();
        } catch (_) {}
      }

      _loadedSourceKey = sourceKey;
      // play() starts as soon as the player has enough buffered data.
      await player.play(source, volume: 1.0);
      if (mounted) {
        setState(() {
          _playing = true;
          _preparing = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceNote] play failed: $e');
      _loadedSourceKey = null;
      if (mounted) {
        setState(() {
          _playing = false;
          _preparing = false;
        });
      }
    }
  }

  String _fmt(Duration d) {
    final totalSec = d.inSeconds;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMine ? Colors.white : const Color(0xFF101010);
    final track = widget.isMine
        ? Colors.white.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.12);
    final active = widget.isMine ? Colors.white : const Color(0xFFFF8A00);

    final displayDuration = _playing
        ? _position
        : (_duration.inMilliseconds > 0
            ? _duration
            : Duration(milliseconds: widget.durationMs));

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Material(
            color: widget.isMine
                ? Colors.white.withValues(alpha: 0.22)
                : const Color(0xFFFF8A00).withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _hasSource ? _togglePlayback : null,
              child: SizedBox(
                width: 40,
                height: 40,
                child: _preparing && !_playing
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: fg,
                        size: 26,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (_playing || _position > Duration.zero)
                        ? _progress
                        : 0,
                    minHeight: 4,
                    backgroundColor: track,
                    valueColor: AlwaysStoppedAnimation<Color>(active),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 14,
                      color: fg.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(displayDuration),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
