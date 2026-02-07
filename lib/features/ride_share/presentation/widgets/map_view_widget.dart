import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/config/map_style_constants.dart';
import 'package:vero360_app/providers/ride_share/nearby_vehicles_provider.dart';
import 'package:vero360_app/GernalServices/nearby_vehicles_service.dart';

class MapViewWidget extends ConsumerStatefulWidget {
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
  ConsumerState<MapViewWidget> createState() => _MapViewWidgetState();
}

class _MapViewWidgetState extends ConsumerState<MapViewWidget> {
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
      if (mounted && widget.pickupPlace != null && widget.dropoffPlace != null) {
        _updateRoutePolyline();
      }
    });

    if (widget.initialPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(nearbyVehiclesProvider.notifier).fetchAndSubscribe(
                latitude: widget.initialPosition!.latitude,
                longitude: widget.initialPosition!.longitude,
                radiusKm: 5.0,
              );
        }
      });
    }
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
    }

    final oldPos = oldWidget.initialPosition;
    final newPos = widget.initialPosition;
    if (newPos != null &&
        (oldPos == null ||
            oldPos.latitude != newPos.latitude ||
            oldPos.longitude != newPos.longitude)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        animateToPosition(newPos.latitude, newPos.longitude);
        _updateUserMarker(newPos);
        ref.read(nearbyVehiclesProvider.notifier).fetchAndSubscribe(
              latitude: newPos.latitude,
              longitude: newPos.longitude,
              radiusKm: 5.0,
            );
      });
    }
  }

  void _updateUserMarker(Position position) {
    _markers.removeWhere((m) => m.markerId == const MarkerId('user_location'));
    _markers.add(
      Marker(
        markerId: const MarkerId('user_location'),
        position: LatLng(position.latitude, position.longitude),
        infoWindow: const InfoWindow(title: 'Your Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
    );
    if (mounted) setState(() {});
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
      if (mounted) setState(() => _polylines.clear());
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

        if (polylineCoordinates.isNotEmpty && mounted) {
          if (kDebugMode) {
            debugPrint('[MapViewWidget] Polyline added to map');
          }

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
            _updatePlaceMarkers();
          });

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
      }
      if (mounted) setState(() => _polylines.clear());
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

  /// Update vehicle markers on the map from nearby vehicles data
  void _updateVehicleMarkers(List<NearbyVehicle> vehicles) {
    // Remove old vehicle markers (keep user, pickup, dropoff, route)
    _markers.removeWhere((marker) => marker.markerId.value.startsWith('vehicle_'));

    // Add new vehicle markers
    for (final vehicle in vehicles) {
      _markers.add(
        Marker(
          markerId: MarkerId('vehicle_${vehicle.id}'),
          position: LatLng(vehicle.latitude, vehicle.longitude),
          infoWindow: InfoWindow(
            title: '${vehicle.make} ${vehicle.model}',
            snippet:
                '${vehicle.distance.toStringAsFixed(1)}km • ⭐${vehicle.rating}',
          ),
          icon: _getVehicleMarkerIcon(vehicle.vehicleClass),
        ),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Get marker color based on vehicle class
  BitmapDescriptor _getVehicleMarkerIcon(String vehicleClass) {
    switch (vehicleClass) {
      case 'BIKE':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      case 'STANDARD':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      case 'EXECUTIVE':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case 'BUSINESS':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nearbyVehiclesState = ref.watch(nearbyVehiclesProvider);

    ref.listen(nearbyVehiclesProvider, (prev, next) {
      if (next.vehicles.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateVehicleMarkers(next.vehicles);
        });
      }
    });

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: _initialCameraPosition,
          markers: _markers,
          polylines: _polylines,
          mapType: _mapType,
          style: _mapStyleJson,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          compassEnabled: true,
        ),
        // Nearby vehicles indicator
        if (nearbyVehiclesState.vehicles.isNotEmpty)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.directions_car,
                    color: Color(0xFFFF8A00),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${nearbyVehiclesState.vehicles.length} nearby',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
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
