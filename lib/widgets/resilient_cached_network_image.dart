import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// HTTP(S) images with disk cache ([CachedNetworkImage]). On failure, retries the
/// other scheme (http ↔ https). Does not set disk or memory resize limits so the
/// cached file and decode stay at full resolution.
class ResilientCachedNetworkImage extends StatefulWidget {
  const ResilientCachedNetworkImage({
    required this.url,
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<ResilientCachedNetworkImage> createState() =>
      _ResilientCachedNetworkImageState();
}

class _ResilientCachedNetworkImageState
    extends State<ResilientCachedNetworkImage> {
  String get _currentUrl => _tryAlternate ? _alternateUrl : widget.url;
  late String _alternateUrl;
  bool _tryAlternate = false;

  @override
  void initState() {
    super.initState();
    _alternateUrl = _flipScheme(widget.url);
  }

  @override
  void didUpdateWidget(covariant ResilientCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _alternateUrl = _flipScheme(widget.url);
      _tryAlternate = false;
    }
  }

  static String _flipScheme(String url) {
    final u = url.trim().toLowerCase();
    if (u.startsWith('https://')) return 'http://${url.substring(8)}';
    if (u.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final u = _currentUrl;
    return CachedNetworkImage(
      imageUrl: u,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey.shade100,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, _, __) {
        if (!_tryAlternate && _flipScheme(u) != u) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _tryAlternate = true);
          });
          return Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        );
      },
    );
  }
}
