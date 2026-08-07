import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Decode-size helper for list/grid thumbnails on low-RAM devices.
/// Uses a single dimension so aspect ratio is preserved.
int thumbnailCachePx(BuildContext context, {double logical = 360}) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (logical * dpr).round().clamp(256, 1200);
}

/// Shared product/listing image with RAM-safe decode (aspect ratio preserved).
class VeroThumbImage extends StatelessWidget {
  final dynamic imageData;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double decodeLogicalPx;

  const VeroThumbImage(
    this.imageData, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.decodeLogicalPx = 360,
  });

  @override
  Widget build(BuildContext context) {
    if (imageData == null) return _placeholder();
    final raw = imageData.toString().trim();
    if (raw.isEmpty) return _placeholder();

    final cachePx = thumbnailCachePx(context, logical: decodeLogicalPx);

    try {
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        return SizedBox.expand(
          child: ResilientCachedNetworkImage(
            url: raw,
            fit: fit,
            memCacheWidth: cachePx,
            showSpinner: false,
          ),
        );
      }

      final Uint8List bytes;
      if (raw.startsWith('data:image')) {
        final base64Part = raw.contains(',') ? raw.split(',').last : raw;
        bytes = base64Decode(base64Part);
      } else {
        final base64Part = raw.contains(',') ? raw.split(',').last : raw;
        bytes = base64Decode(base64Part);
      }

      // Only width — keeps aspect ratio; BoxFit.cover fills the card.
      return SizedBox.expand(
        child: Image(
          image: ResizeImage(
            MemoryImage(bytes),
            width: cachePx,
            allowUpscaling: false,
          ),
          fit: fit,
          errorBuilder: (_, __, ___) => _placeholder(),
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF3F4F7),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_rounded, color: Colors.black26),
    );
  }
}
