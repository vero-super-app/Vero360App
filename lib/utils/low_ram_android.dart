import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Redmi 8A / 2GB Adreno 506 — keep GPU textures tiny.
class LowRamAndroid {
  LowRamAndroid._();

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Raster DPR cap. Native ~2.0 on Redmi 8A OOMs Adreno sharedmem.
  static const double maxDpr = 1.0;

  static const int imageCacheCount = 8;
  static const int imageCacheBytes = 4 << 20; // 4 MB

  static const int maxDecodePx = 512;
}
