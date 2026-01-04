import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vero360_app/models/place_model.dart';

class MapViewWidget extends StatefulWidget {
  final Function(GoogleMapController) onMapCreated;
  final Position? initialPosition;
  final Place? pickupPlace;
  final Place? dropoffPlace;

  const MapViewWidget({
    required this.onMapCreated,
    this.initialPosition,
    this.pickupPlace,
    this.dropoffPlace,
    Key? key,
  }) : super(key: key);

  @override
  State<MapViewWidget> createState() => _MapViewWidgetState();
}

class _MapViewWidgetState extends State<MapViewWidget> {
  late GoogleMapController _mapController;
  late Set<Marker> _markers;
  late Set<Polyline> _polylines;
  late CameraPosition _initialCameraPosition;

  @override
  void initState() {
    super.initState();
    _markers = {};
    _polylines = {};
    _initializeCameraPosition();
  }

  @override
  void didUpdateWidget(MapViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Redraw route if pickup or dropoff places changed
    if (oldWidget.pickupPlace != widget.pickupPlace ||
        oldWidget.dropoffPlace != widget.dropoffPlace) {
      _updateRoutePolyline();
    }
  }

  void _initializeCameraPosition() {
    if (widget.initialPosition != null) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(
          widget.initialPosition!.latitude,
          widget.initialPosition!.longitude,
        ),
        zoom: 15,
      );
      _addUserMarker();
    } else {
      // Default to Lilongwe, Malawi
      _initialCameraPosition = const CameraPosition(
        target: LatLng(-13.9626, 33.7707),
        zoom: 12,
      );
    }
  }

  void _addUserMarker() {
    if (widget.initialPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(
            widget.initialPosition!.latitude,
            widget.initialPosition!.longitude,
          ),
          infoWindow: const InfoWindow(
            title: 'Your Location',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    widget.onMapCreated(controller);
  }

  void addMarker({
    required String markerId,
    required double latitude,
    required double longitude,
    required String title,
    String? snippet,
  }) {
    setState(() {
      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: LatLng(latitude, longitude),
          infoWindow: InfoWindow(
            title: title,
            snippet: snippet,
          ),
        ),
      );
    });
  }

  void clearMarkers() {
    setState(() {
      _markers.clear();
      _addUserMarker();
    });
  }

  Future<void> _updateRoutePolyline() async {
    if (widget.pickupPlace == null || widget.dropoffPlace == null) {
      setState(() {
        _polylines.clear();
      });
      return;
    }

    try {
      final polylinePoints = PolylinePoints(
        apiKey: 'AIzaSyB7W-KbHpMHDN7n_MJuV5pS0dTl_rN0H84',
      );

      final request = RoutesApiRequest(
        origin: PointLatLng(
          widget.pickupPlace!.latitude,
          widget.pickupPlace!.longitude,
        ),
        destination: PointLatLng(
          widget.dropoffPlace!.latitude,
          widget.dropoffPlace!.longitude,
        ),
        travelMode: TravelMode.driving,
        routingPreference: RoutingPreference.trafficAware,
      );

      final response = await polylinePoints.getRouteBetweenCoordinatesV2(
        request: request,
      );

      if (response.routes.isNotEmpty) {
        final route = response.routes.first;
        final polylineCoordinates = (route.polylinePoints ?? [])
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        if (polylineCoordinates.isNotEmpty) {
          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: polylineCoordinates,
                color: const Color(0xFFFF8A00),
                width: 5,
                geodesic: true,
              ),
            );

            // Add markers for pickup and dropoff
            _updatePlaceMarkers();

            // Animate camera to fit both locations
            _fitCameraToBounds(polylineCoordinates);
          });
        }
      }
    } catch (e) {
      print('Error loading route: $e');
    }
  }

  void _updatePlaceMarkers() {
    // Remove old place markers
    _markers.removeWhere((marker) =>
        marker.markerId.value == 'pickup' ||
        marker.markerId.value == 'dropoff');

    // Add pickup marker
    if (widget.pickupPlace != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            widget.pickupPlace!.latitude,
            widget.pickupPlace!.longitude,
          ),
          infoWindow: InfoWindow(
            title: 'Pickup: ${widget.pickupPlace!.name}',
            snippet: widget.pickupPlace!.address,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    // Add dropoff marker
    if (widget.dropoffPlace != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(
            widget.dropoffPlace!.latitude,
            widget.dropoffPlace!.longitude,
          ),
          infoWindow: InfoWindow(
            title: 'Dropoff: ${widget.dropoffPlace!.name}',
            snippet: widget.dropoffPlace!.address,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );
    }
  }

  void _fitCameraToBounds(List<LatLng> coordinates) {
    if (coordinates.isEmpty) return;

    double minLat = coordinates[0].latitude;
    double maxLat = coordinates[0].latitude;
    double minLng = coordinates[0].longitude;
    double maxLng = coordinates[0].longitude;

    for (final coord in coordinates) {
      minLat = (coord.latitude < minLat) ? coord.latitude : minLat;
      maxLat = (coord.latitude > maxLat) ? coord.latitude : maxLat;
      minLng = (coord.longitude < minLng) ? coord.longitude : minLng;
      maxLng = (coord.longitude > maxLng) ? coord.longitude : maxLng;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  void animateToPosition(double latitude, double longitude) {
    _mapController.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(latitude, longitude),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: _initialCameraPosition,
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      compassEnabled: true,
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
