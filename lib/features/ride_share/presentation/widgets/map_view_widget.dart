import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/config/map_style_constants.dart';

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
    super.key,
  });

  @override
  State<MapViewWidget> createState() => _MapViewWidgetState();
}

class _MapViewWidgetState extends State<MapViewWidget> {
  late GoogleMapController _mapController;
  late Set<Marker> _markers;
  late Set<Polyline> _polylines;
  late CameraPosition _initialCameraPosition;
  MapType _mapType = MapType.normal;
  String? _mapStyleJson;

  @override
  void initState() {
    super.initState();
    _markers = {};
    _polylines = {};
    _initializeCameraPosition();
    
    // Load map style from assets
    _loadMapStyle();

    // Initial route draw if both places are provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.pickupPlace != null && widget.dropoffPlace != null) {
        _updateRoutePolyline();
      }
    });
  }

  Future<void> _loadMapStyle() async {
    try {
      final styleString = await MapStyleConstants.loadMapStyle();
      if (styleString.isNotEmpty) {
        setState(() {
          _mapStyleJson = styleString;
        });
        if (kDebugMode) {
          debugPrint('[MapViewWidget] Map style loaded successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapViewWidget] Error loading map style: $e');
      }
    }
  }

  @override
  void didUpdateWidget(MapViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (kDebugMode) {
      debugPrint(
          '[MapViewWidget] ========== didUpdateWidget called ==========');
      debugPrint(
          '[MapViewWidget] oldPickup: ${oldWidget.pickupPlace?.name} (${oldWidget.pickupPlace?.id})');
      debugPrint(
          '[MapViewWidget] newPickup: ${widget.pickupPlace?.name} (${widget.pickupPlace?.id})');
      debugPrint(
          '[MapViewWidget] pickupChanged: ${oldWidget.pickupPlace != widget.pickupPlace}');
      debugPrint(
          '[MapViewWidget] oldDropoff: ${oldWidget.dropoffPlace?.name} (${oldWidget.dropoffPlace?.id})');
      debugPrint(
          '[MapViewWidget] newDropoff: ${widget.dropoffPlace?.name} (${widget.dropoffPlace?.id})');
      debugPrint(
          '[MapViewWidget] dropoffChanged: ${oldWidget.dropoffPlace != widget.dropoffPlace}');
    }

    final pickupChanged = oldWidget.pickupPlace != widget.pickupPlace;
    final dropoffChanged = oldWidget.dropoffPlace != widget.dropoffPlace;

    if (pickupChanged || dropoffChanged) {
      if (kDebugMode) {
        debugPrint(
            '[MapViewWidget] ✅ Places changed! Updating route polyline...');
      }
      _updateRoutePolyline();
    } else {
      if (kDebugMode) {
        debugPrint('[MapViewWidget] ❌ No changes detected');
      }
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
      if (kDebugMode) {
        debugPrint(
            '[MapViewWidget] Pickup or dropoff is null, clearing polylines');
      }
      setState(() {
        _polylines.clear();
      });
      return;
    }

    try {
      if (GoogleMapsConfig.apiKey.isEmpty) {
        if (kDebugMode) {
          debugPrint('[MapViewWidget] ERROR: Google Maps API key is empty!');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('[MapViewWidget] Starting route calculation');
        debugPrint(
            '[MapViewWidget] Pickup: ${widget.pickupPlace!.latitude}, ${widget.pickupPlace!.longitude}');
        debugPrint(
            '[MapViewWidget] Dropoff: ${widget.dropoffPlace!.latitude}, ${widget.dropoffPlace!.longitude}');
        debugPrint(
            '[MapViewWidget] API Key: ${GoogleMapsConfig.apiKey.substring(0, 10)}...');
      }

      final polylinePoints = PolylinePoints(
        apiKey: GoogleMapsConfig.apiKey,
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

      if (kDebugMode) {
        debugPrint('[MapViewWidget] Making polyline request...');
      }

      final response = await polylinePoints.getRouteBetweenCoordinatesV2(
        request: request,
      );

      if (kDebugMode) {
        debugPrint(
            '[MapViewWidget] Response received: ${response.routes.length} routes');
      }

      if (response.routes.isNotEmpty) {
        final route = response.routes.first;
        final polylineCoordinates = (route.polylinePoints ?? [])
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        if (kDebugMode) {
          debugPrint(
              '[MapViewWidget] Polyline has ${polylineCoordinates.length} points');
        }

        if (polylineCoordinates.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[MapViewWidget] Polyline added to map');
          }

          // Animate polyline drawing with smooth transitions
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
          });

          // Animate camera to fit both locations with delay for smooth UX
          _fitCameraToBounds(polylineCoordinates);
        }
      } else {
        if (kDebugMode) {
          debugPrint('[MapViewWidget] No routes returned from API');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapViewWidget] Error loading route: $e');
        debugPrint('[MapViewWidget] Stack trace: $e');
      }
      // Clear polylines on error
      setState(() {
        _polylines.clear();
      });
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

    // Smooth animation with more padding and longer duration
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _mapController.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 150),
        );
      }
    });
  }

  void animateToPosition(
    double latitude,
    double longitude, {
    double zoom = 15.0,
    Duration duration = const Duration(milliseconds: 800),
  }) {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(latitude, longitude),
              zoom: zoom,
            ),
          ),
        );
      }
    });
  }

  void _toggleMapType() {
    setState(() {
      _mapType =
          _mapType == MapType.normal ? MapType.satellite : MapType.normal;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: _initialCameraPosition,
          markers: _markers,
          polylines: _polylines,
          mapType: _mapType,
          style: _mapStyleJson,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          compassEnabled: true,
        ),
        // Satellite/Map toggle button
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.small(
            onPressed: _toggleMapType,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFFFF8A00),
            elevation: 4,
            child: Icon(
              _mapType == MapType.satellite
                  ? Icons.layers_clear_rounded
                  : Icons.satellite_alt_rounded,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
