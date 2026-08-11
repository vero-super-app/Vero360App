import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/utils/low_ram_android.dart';

/// HTTP(S) images with disk cache ([CachedNetworkImage]). On failure, retries the
/// other scheme (http ↔ https). Pass [memCacheWidth] **or** [memCacheHeight]
/// (prefer one) for thumbnails so Flutter does not decode full-resolution bitmaps.
///
/// On Android, when callers omit mem-cache sizes, we infer a tight decode
/// budget from layout size so 2GB devices do not GPU-OOM on full images.
class ResilientCachedNetworkImage extends StatefulWidget {
  const ResilientCachedNetworkImage({
    required this.url,
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.showSpinner = true,
    this.placeholderColor,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final bool showSpinner;
  final Color? placeholderColor;

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
    final placeholderBg =
        widget.placeholderColor ?? Colors.grey.shade100;
    final low = LowRamAndroid.isAndroid;
    final dpr = MediaQuery.devicePixelRatioOf(context)
        .clamp(1.0, low ? LowRamAndroid.maxDpr : 3.0);

    // Prefer caller values. Only auto-size from *finite* layout size, and only
    // set ONE mem dimension so aspect ratio stays correct (avoids "shrunk" tiles).
    // On low-end Android, infer a tighter decode budget when sizes are omitted.
    int? memW = widget.memCacheWidth;
    int? memH = widget.memCacheHeight;
    if (memW == null && memH == null) {
      final maxPx = low ? LowRamAndroid.maxDecodePx : 1200;
      if (widget.width != null && widget.width!.isFinite && widget.width! > 0) {
        memW = (widget.width! * dpr).round().clamp(64, maxPx);
      } else if (widget.height != null &&
          widget.height!.isFinite &&
          widget.height! > 0) {
        memH = (widget.height! * dpr).round().clamp(64, maxPx);
      } else if (low) {
        final layoutW = MediaQuery.sizeOf(context).width;
        memW = (layoutW * dpr).round().clamp(48, maxPx);
      }
    }
    if (low) {
      if (memW != null) memW = memW!.clamp(48, LowRamAndroid.maxDecodePx);
      if (memH != null) memH = memH!.clamp(48, LowRamAndroid.maxDecodePx);
    }

    Widget placeholder() => Container(
          width: widget.width,
          height: widget.height,
          color: placeholderBg,
          alignment: Alignment.center,
          child: widget.showSpinner
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        );

    return CachedNetworkImage(
      imageUrl: u,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      memCacheWidth: memW,
      memCacheHeight: memH,
      maxWidthDiskCache: low ? LowRamAndroid.maxDecodePx : null,
      maxHeightDiskCache: low ? LowRamAndroid.maxDecodePx : null,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, _) => placeholder(),
      errorWidget: (context, _, __) {
        if (!_tryAlternate && _flipScheme(u) != u) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _tryAlternate = true);
          });
          return placeholder();
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
