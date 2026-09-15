import 'package:google_maps_flutter/google_maps_flutter.dart';

/// App-wide Google Map look: 3D hybrid satellite (all screens).
abstract final class VeroMapStyle {
  /// Satellite imagery + road labels.
  static const MapType mapType = MapType.hybrid;

  /// Perspective tilt in degrees (0 = flat).
  static const double tilt = 52;

  static const double defaultZoom = 17;
  static const double cityZoom = 13.5;
  static const double countryZoom = 6.8;

  static CameraPosition camera({
    required LatLng target,
    double zoom = defaultZoom,
    double tiltDeg = tilt,
    double bearing = 0,
  }) {
    return CameraPosition(
      target: target,
      zoom: zoom,
      tilt: tiltDeg,
      bearing: bearing,
    );
  }

  static CameraUpdate cameraUpdate({
    required LatLng target,
    double zoom = defaultZoom,
    double tiltDeg = tilt,
    double bearing = 0,
  }) {
    return CameraUpdate.newCameraPosition(
      camera(
        target: target,
        zoom: zoom,
        tiltDeg: tiltDeg,
        bearing: bearing,
      ),
    );
  }
}
