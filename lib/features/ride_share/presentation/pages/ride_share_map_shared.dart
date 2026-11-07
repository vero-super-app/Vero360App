import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';

/// Shared helpers for [RideShareMapScreen] and [BikeRideShareMapScreen].
/// Screens stay as route entry points; common map UX lives here to cut
/// duplication without a risky full unify.

void rideShareScheduleSearchFocus(FocusNode focusNode, {bool Function()? mounted}) {
  Future.delayed(const Duration(milliseconds: 50), () {
    if (mounted != null && !mounted()) return;
    if (!focusNode.hasFocus) {
      focusNode.requestFocus();
    }
  });
}

void rideShareUnfocusSearch(FocusNode focusNode) {
  if (focusNode.hasFocus) {
    focusNode.unfocus();
  }
}

/// Build a pickup [Place] from current GPS (+ optional cached/display address).
Place rideShareBuildPickupPlace({
  required double latitude,
  required double longitude,
  Place? cached,
  String address = 'Current Location',
  String name = 'Your Location',
}) {
  return cached ??
      Place(
        id: 'current_location',
        name: name,
        address: address,
        latitude: latitude,
        longitude: longitude,
        type: PlaceType.RECENT,
      );
}

/// Default Malawi-ish camera target when location is unknown.
const LatLng rideShareDefaultMapTarget = LatLng(-13.9626, 33.7741);

CameraPosition rideShareInitialCamera({
  double? latitude,
  double? longitude,
  double zoom = 14,
}) {
  if (latitude != null && longitude != null) {
    return CameraPosition(
      target: LatLng(latitude, longitude),
      zoom: zoom,
    );
  }
  return const CameraPosition(target: rideShareDefaultMapTarget, zoom: 12);
}
