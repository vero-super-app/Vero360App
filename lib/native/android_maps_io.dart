import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

Future<void> configureAndroidGoogleMaps() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is! GoogleMapsFlutterAndroid) return;
    try {
      await mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
    } catch (_) {}
    mapsImplementation.useAndroidViewSurface = false;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[GoogleMaps] Android configure failed: $e');
    }
  }
}
