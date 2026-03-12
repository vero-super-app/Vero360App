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
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';

class MapViewWidget extends ConsumerStatefulWidget {
  final Function(GoogleMapController) onMapCreated;
  final Position? initialPosition;
  final Place? pickupPlace;
  final Place? dropoffPlace;

  /// When non-null, a driver marker is drawn at this position.
  final LatLng? driverLocation;

  /// Label shown on the driver marker info window.
  final String? driverLabel;

  /// When true, nearby-vehicle fetching is skipped (used on tracking screens).
  final bool trackingMode;

  const MapViewWidget({
    required this.onMapCreated,
    this.initialPosition,
    this.pickupPlace,
    this.dropoffPlace,
    this.driverLocation,
    this.driverLabel,
    this.trackingMode = false,
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
  final MapType _mapType = MapType.normal;
  String? _mapStyleJson;
  late BitmapDescriptor _taxiMarkerIcon;

  @override
  void initState() {
    super.initState();
    _markers = {};
    _polylines = {};
    _initializeCameraPosition();

    _loadMapStyle();

    if (!widget.trackingMode) {
      _loadTaxiMarkerIcon();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (widget.pickupPlace != null && widget.dropoffPlace != null) {
        _updateRoutePolyline();
      }

      if (widget.driverLocation != null) {
        _updateDriverMarker();
      }

      if (!widget.trackingMode && widget.initialPosition != null) {
        ref.read(nearbyVehiclesProvider.notifier).fetchAndSubscribe(
              latitude: widget.initialPosition!.latitude,
              longitude: widget.initialPosition!.longitude,
              radiusKm: 5.0,
            );
      }
    });
  }

  Future<void> _loadMapStyle() async {
    try {
      final styleString = await MapStyleConstants.loadMapStyle();
      if (styleString.isNotEmpty && mounted) {
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

  Future<void> _loadTaxiMarkerIcon() async {
    try {
      // Load the custom car marker PNG (2000x2000) and scale to 120x120 for map display
      _taxiMarkerIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(120, 120)),
        'assets/icons/car-location-marker.png',
      );
      if (kDebugMode) {
        debugPrint('[MapViewWidget] Taxi marker icon loaded successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapViewWidget] Error loading taxi marker icon: $e');
      }
      // Fallback to default marker
      _taxiMarkerIcon = BitmapDescriptor.defaultMarker;
    }
  }

  @override
  void didUpdateWidget(MapViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final pickupChanged = oldWidget.pickupPlace != widget.pickupPlace;
    final dropoffChanged = oldWidget.dropoffPlace != widget.dropoffPlace;

    if (pickupChanged || dropoffChanged) {
      _updateRoutePolyline();
    }

    if (oldWidget.driverLocation != widget.driverLocation) {
      _updateDriverMarker();
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
        if (!widget.trackingMode) {
          ref.read(nearbyVehiclesProvider.notifier).fetchAndSubscribe(
                latitude: newPos.latitude,
                longitude: newPos.longitude,
                radiusKm: 5.0,
              );
        }
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

  void _updateDriverMarker() {
    _markers.removeWhere((m) => m.markerId == const MarkerId('driver'));
    if (widget.driverLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: widget.driverLocation!,
          infoWindow: InfoWindow(title: widget.driverLabel ?? 'Your Driver'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
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
      // Last resort: first-ever launch with no cached GPS — default to Lilongwe, Malawi
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
    if (mounted) {
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
  }

  void clearMarkers() {
    if (mounted) {
      setState(() {
        _markers.clear();
        _addUserMarker();
      });
    }
  }

  Future<void> _updateRoutePolyline() async {
    if (widget.pickupPlace == null || widget.dropoffPlace == null) {
      if (mounted) setState(() => _polylines.clear());
      return;
    }

    // Try cached polyline first to avoid an extra API call
    final cached = ref.read(cachedRoutePolylineProvider);
    if (cached.isNotEmpty) {
      _applyPolyline(cached);
      return;
    }

    try {
      if (GoogleMapsConfig.apiKey.isEmpty) return;

      final polylinePoints = PolylinePoints(apiKey: GoogleMapsConfig.apiKey);

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

      if (!mounted) return;

      if (response.routes.isNotEmpty) {
        final route = response.routes.first;
        final coords = (route.polylinePoints ?? [])
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        if (coords.isNotEmpty) {
          ref.read(cachedRoutePolylineProvider.notifier).state = coords;
          _applyPolyline(coords);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MapViewWidget] Error loading route: $e');
      if (mounted) {
        try {
          setState(() => _polylines.clear());
        } catch (_) {}
      }
    }
  }

  void _applyPolyline(List<LatLng> coords) {
    if (!mounted) return;
    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: coords,
          color: const Color(0xFFFF8A00),
          width: 5,
          geodesic: true,
        ),
      );
      _updatePlaceMarkers();
    });
    _fitCameraToBounds(coords);
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

  /// Update taxi markers on the map from nearby taxis data
  void _updateTaxiMarkers(List<NearbyTaxi> taxis) {
    // Remove old taxi markers (keep user, pickup, dropoff, route)
    _markers
        .removeWhere((marker) => marker.markerId.value.startsWith('taxi_'));

    // Add new taxi markers
    for (final taxi in taxis) {
      _markers.add(
        Marker(
          markerId: MarkerId('taxi_${taxi.id}'),
          position: LatLng(taxi.latitude, taxi.longitude),
          infoWindow: InfoWindow(
            title: '${taxi.make} ${taxi.model}',
            snippet:
                '${taxi.distance.toStringAsFixed(1)}km • ⭐${taxi.rating}',
          ),
          icon: _getTaxiMarkerIcon(taxi.taxiClass),
        ),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Get custom marker icon for all taxi classes
  BitmapDescriptor _getTaxiMarkerIcon(String taxiClass) {
    return _taxiMarkerIcon;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.trackingMode) {
      final nearbyTaxisState = ref.watch(nearbyVehiclesProvider);

      ref.listen(nearbyVehiclesProvider, (prev, next) {
        if (next.vehicles.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateTaxiMarkers(next.vehicles);
          });
        }
      });

      return Stack(
        children: [
          _buildGoogleMap(),
          if (nearbyTaxisState.vehicles.isNotEmpty)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    const Icon(Icons.directions_car,
                        color: Color(0xFFFF8A00), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${nearbyTaxisState.vehicles.length} nearby',
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
        ],
      );
    }

    return _buildGoogleMap();
  }

  Widget _buildGoogleMap() {
    return GoogleMap(
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
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
      super.dispose();
  }
}
