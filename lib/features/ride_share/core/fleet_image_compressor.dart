import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Compress fleet document photos before multipart upload.
class FleetImageCompressor {
  FleetImageCompressor._();

  static const int maxEdge = 1280;
  static const int quality = 62;

  static Future<String> compressForUpload(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;

      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return sourcePath;

      img.Image resized = decoded;
      final longest = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      if (longest > maxEdge) {
        resized = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxEdge : null,
          height: decoded.height > decoded.width ? maxEdge : null,
        );
      }

      final jpg = img.encodeJpg(resized, quality: quality);
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/vero_upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final out = File(targetPath);
      await out.writeAsBytes(jpg, flush: true);

      final originalSize = await source.length();
      final compressedSize = await out.length();
      if (compressedSize > 0 && compressedSize < originalSize) {
        return out.path;
      }
      return sourcePath;
    } catch (_) {
      return sourcePath;
    }
  }
}
