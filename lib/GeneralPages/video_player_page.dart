// lib/Pages/video_player_page.dart
import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Kept so older call sites compile. Playback now starts only when the slide is on screen.
class ListingVideoPool {
  static void warm(Iterable<String> urls) {}

  static void release(Iterable<String> urls) {}
}

class VideoPlayerPage extends StatelessWidget {
  final String url;
  const VideoPlayerPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // Replace with video_player + chewie as needed
    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_fill, size: 80),
            const SizedBox(height: 12),
            Text('Play video:\n$url', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Plays a listing video in place. [play] is true only for the visible slide.
class InlineAutoplayVideo extends StatefulWidget {
  final String url;
  final bool play;

  const InlineAutoplayVideo({
    super.key,
    required this.url,
    this.play = true,
  });

  @override
  State<InlineAutoplayVideo> createState() => _InlineAutoplayVideoState();
}

class _InlineAutoplayVideoState extends State<InlineAutoplayVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _ready = false;
  int _openToken = 0;

  @override
  void initState() {
    super.initState();
    _open(widget.url);
  }

  @override
  void didUpdateWidget(InlineAutoplayVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _failed = false;
      _ready = false;
      _open(widget.url);
      return;
    }
    _syncPlay();
  }

  Future<void> _open(String raw) async {
    final token = ++_openToken;
    final url = raw.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    final network = VideoPlayerController.networkUrl(uri);
    final ok = await _start(network, token);
    if (!mounted || token != _openToken) {
      if (!ok) await _disposeOne(network);
      return;
    }
    if (ok) return;
    await _disposeOne(network);

    if (kIsWeb) {
      if (mounted && token == _openToken) setState(() => _failed = true);
      return;
    }

    try {
      final file = await _downloadVideo(uri);
      if (!mounted || token != _openToken) return;
      final local = VideoPlayerController.file(file);
      final played = await _start(local, token);
      if (!played) {
        await _disposeOne(local);
        if (mounted && token == _openToken) setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted && token == _openToken) setState(() => _failed = true);
    }
  }

  Future<bool> _start(VideoPlayerController controller, int token) async {
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (!mounted || token != _openToken || !identical(_controller, controller)) {
        return false;
      }
      if (controller.value.hasError || !controller.value.isInitialized) {
        return false;
      }
      await controller.setLooping(true);
      if (!mounted || token != _openToken) return false;
      setState(() {
        _ready = true;
        _failed = false;
      });
      _syncPlay();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> _downloadVideo(Uri uri) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vero_listing_${uri.hashCode.abs()}.mp4');
    if (file.existsSync() && file.lengthSync() > 0) return file;
    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Video download failed (${response.statusCode})');
      }
      sink = file.openWrite();
      await response.pipe(sink);
      sink = null;
      return file;
    } catch (_) {
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
      try {
        await sink?.close();
      } catch (_) {}
    }
  }

  void _syncPlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.play) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  Future<void> _disposeOne(VideoPlayerController controller) async {
    if (identical(_controller, controller)) _controller = null;
    await controller.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _ready = false;
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo = _ready &&
        !_failed &&
        controller != null &&
        controller.value.isInitialized &&
        !controller.value.hasError;
    if (!showVideo) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    final size = controller.value.size;
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width <= 0 ? 16 : size.width,
          height: size.height <= 0 ? 9 : size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
