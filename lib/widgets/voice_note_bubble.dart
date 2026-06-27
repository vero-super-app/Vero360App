import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// WhatsApp-style inline voice note player for chat bubbles.
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

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  static AudioPlayer? _sharedPlayer;
  static String? _activeMessageId;
  static StreamSubscription<Duration>? _positionSub;
  static StreamSubscription<void>? _completeSub;
  static StreamSubscription<PlayerState>? _stateSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.durationMs);
    if (_activeMessageId == widget.messageId) {
      _playing = _sharedPlayer?.state == PlayerState.playing;
    }
  }

  @override
  void dispose() {
    if (_activeMessageId == widget.messageId) {
      unawaited(_stopShared());
    }
    super.dispose();
  }

  String get _sourcePath {
    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty) return local;
    return widget.url.trim();
  }

  bool get _hasSource => _sourcePath.isNotEmpty;

  Future<void> _stopShared() async {
    await _positionSub?.cancel();
    await _completeSub?.cancel();
    await _stateSub?.cancel();
    _positionSub = null;
    _completeSub = null;
    _stateSub = null;
    await _sharedPlayer?.stop();
    await _sharedPlayer?.dispose();
    _sharedPlayer = null;
    _activeMessageId = null;
  }

  Future<void> _togglePlayback() async {
    if (!_hasSource) return;

    if (_playing && _activeMessageId == widget.messageId) {
      await _sharedPlayer?.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }

    if (_activeMessageId != widget.messageId) {
      await _stopShared();
    }

    _sharedPlayer ??= AudioPlayer();
    _activeMessageId = widget.messageId;

    final local = widget.localPath?.trim();
    final source = (local != null && local.isNotEmpty)
        ? DeviceFileSource(local)
        : UrlSource(widget.url.trim());

    await _positionSub?.cancel();
    await _completeSub?.cancel();
    await _stateSub?.cancel();

    _positionSub = _sharedPlayer!.onPositionChanged.listen((pos) {
      if (!mounted || _activeMessageId != widget.messageId) return;
      setState(() => _position = pos);
    });

    _completeSub = _sharedPlayer!.onPlayerComplete.listen((_) {
      if (!mounted || _activeMessageId != widget.messageId) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });

    _stateSub = _sharedPlayer!.onPlayerStateChanged.listen((state) {
      if (!mounted || _activeMessageId != widget.messageId) return;
      setState(() => _playing = state == PlayerState.playing);
    });

    _durationSub();
    await _sharedPlayer!.play(source);
    if (mounted) setState(() => _playing = true);
  }

  void _durationSub() {
    _sharedPlayer!.onDurationChanged.listen((d) {
      if (!mounted || _activeMessageId != widget.messageId) return;
      if (d > Duration.zero) {
        setState(() => _duration = d);
      }
    });
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

    final displayDuration =
        _playing ? _position : (_duration.inMilliseconds > 0 ? _duration : Duration(milliseconds: widget.durationMs));

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
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
                    Icon(Icons.mic_rounded, size: 14, color: fg.withValues(alpha: 0.85)),
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
