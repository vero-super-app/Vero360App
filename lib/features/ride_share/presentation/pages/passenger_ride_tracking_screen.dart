import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_state_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/config/google_maps_config.dart';
import 'package:vero360_app/config/map_style_constants.dart';

class PassengerRideTrackingScreen extends ConsumerStatefulWidget {
  final int rideId;
  final VoidCallback? onRideEnded;

  const PassengerRideTrackingScreen({
    super.key,
    required this.rideId,
    this.onRideEnded,
  });

  @override
  ConsumerState<PassengerRideTrackingScreen> createState() =>
      _PassengerRideTrackingScreenState();
}

class _PassengerRideTrackingScreenState
    extends ConsumerState<PassengerRideTrackingScreen> {
  GoogleMapController? mapController;
  final Set<Marker> markers = {};
  final Set<Polyline> polylines = {};
  static const Color primaryColor = Color(0xFFFF8A00);
  String? _mapStyleJson;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeRideProvider.notifier).subscribeToRide(widget.rideId);
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
          debugPrint('[PassengerRideTracking] Map style loaded successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PassengerRideTracking] Error loading map style: $e');
      }
    }
  }

  @override
  void dispose() {
    try {
      ref.read(activeRideProvider.notifier).unsubscribeFromRide();
    } catch (e) {
      print('[PassengerRideTrackingScreen] Error unsubscribing from ride: $e');
    }
    try {
      mapController?.dispose();
    } catch (e) {
      print('[PassengerRideTrackingScreen] Error disposing map controller: $e');
    }
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _updateMapMarkers(Ride ride) {
    setState(() {
      markers.clear();

      // Pickup marker
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(ride.pickupLatitude, ride.pickupLongitude),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: ride.pickupAddress,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );

      // Dropoff marker
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(ride.dropoffLatitude, ride.dropoffLongitude),
          infoWindow: InfoWindow(
            title: 'Dropoff',
            snippet: ride.dropoffAddress,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );

      // Driver location if available
      if (ride.driver?.latitude != null && ride.driver?.longitude != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: LatLng(ride.driver!.latitude!, ride.driver!.longitude!),
            infoWindow: InfoWindow(
              title: ride.driver?.fullName ?? 'Your Driver',
              snippet: '${ride.driver?.completedRides ?? 0} rides',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
          ),
        );
      }
    });

    // Update route polyline asynchronously
    _updateRoutePolyline(ride);
  }

  Future<void> _updateRoutePolyline(Ride ride) async {
    try {
      if (GoogleMapsConfig.apiKey.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[PassengerRideTracking] ERROR: Google Maps API key is empty!');
        }
        return;
      }

      final polylinePoints = PolylinePoints(
        apiKey: GoogleMapsConfig.apiKey,
      );

      final request = RoutesApiRequest(
        origin: PointLatLng(ride.pickupLatitude, ride.pickupLongitude),
        destination: PointLatLng(ride.dropoffLatitude, ride.dropoffLongitude),
        travelMode: TravelMode.driving,
        routingPreference: RoutingPreference.trafficAware,
      );

      if (kDebugMode) {
        debugPrint('[PassengerRideTracking] Requesting polyline route...');
      }

      final response = await polylinePoints.getRouteBetweenCoordinatesV2(
        request: request,
      );

      // Check if widget is still mounted after async operation
      if (!mounted) {
        if (kDebugMode) {
          debugPrint(
              '[PassengerRideTracking] Widget unmounted, skipping polyline update');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
            '[PassengerRideTracking] Response received: ${response.routes.length} routes');
      }

      if (response.routes.isNotEmpty) {
        final route = response.routes.first;
        final polylineCoordinates = (route.polylinePoints ?? [])
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        if (kDebugMode) {
          debugPrint(
              '[PassengerRideTracking] Polyline has ${polylineCoordinates.length} points');
        }

        if (polylineCoordinates.isNotEmpty) {
          setState(() {
            polylines.clear();
            polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: polylineCoordinates,
                color: primaryColor,
                width: 5,
                geodesic: true,
              ),
            );
          });

          _fitCameraToBounds(polylineCoordinates);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PassengerRideTracking] Error loading route: $e');
      }
      // Fallback to simple polyline if API fails
      if (mounted) {
        setState(() {
          polylines.clear();
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: [
                LatLng(ride.pickupLatitude, ride.pickupLongitude),
                LatLng(ride.dropoffLatitude, ride.dropoffLongitude),
              ],
              color: primaryColor,
              width: 5,
              geodesic: true,
            ),
          );
        });
      }
    }
  }

  void _fitCameraToBounds(List<LatLng> coordinates) {
    if (coordinates.isEmpty || mapController == null) return;

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

    // Smooth animation with padding and delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && mapController != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 150),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rideState = ref.watch(activeRideProvider);

    // Handle ride completion
    if (rideState.isCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => RideCompletionScreen(
                baseFare: (rideState.ride?.estimatedFare ?? 0.0) * 0.2,
                distanceFare: (rideState.ride?.estimatedFare ?? 0.0) * 0.8,
                totalFare: rideState.ride?.actualFare ??
                    rideState.ride?.estimatedFare ??
                    0.0,
                distance: rideState.ride?.actualDistance ??
                    rideState.ride?.estimatedDistance ??
                    0.0,
                duration: 15,
                driverName: rideState.ride?.driver?.fullName ?? 'Driver',
                driverRating: rideState.ride?.driver?.rating ?? 0.0,
                onPaymentCompleted: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          );
        }
      });
    }

    // Handle ride cancellation
    if (rideState.isCancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          try {
            final reason = rideState.ride?.cancellationReason ?? 'Unknown reason';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ride cancelled: $reason'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
            // Delay pop to allow snackbar to show
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && context.mounted) {
                Navigator.of(context).pop();
              }
            });
          } catch (e) {
            print('[PassengerRideTrackingScreen] Error handling cancellation: $e');
            if (mounted && context.mounted) {
              Navigator.of(context).pop();
            }
          }
        }
      });
    }

    // Only update markers if ride is still active
    if (rideState.ride != null && !rideState.isCancelled && !rideState.isCompleted) {
      try {
        _updateMapMarkers(rideState.ride!);
      } catch (e) {
        print('[PassengerRideTrackingScreen] Error updating markers: $e');
      }
    }

    return WillPopScope(
      onWillPop: () async => false, // Prevent back during active ride
      child: Scaffold(
        appBar: AppBar(
          leading: const SizedBox.shrink(),
          centerTitle: true,
          title: Text(
            _getStateTitle(rideState.status),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: primaryColor,
        ),
        body: Stack(
          children: [
            // Map
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  rideState.ride?.pickupLatitude ?? -13.9626,
                  rideState.ride?.pickupLongitude ?? 33.7707,
                ),
                zoom: 14,
              ),
              markers: markers,
              polylines: polylines,
              style: _mapStyleJson,
              mapType: MapType.normal,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              compassEnabled: true,
            ),
            // Bottom state-specific content
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildStateContent(context, rideState),
            ),
          ],
        ),
      ),
    );
  }

  String _getStateTitle(String status) {
    switch (status) {
      case RideStatus.requested:
        return 'Finding Drivers...';
      case RideStatus.accepted:
        return 'Driver Accepted';
      case RideStatus.driverArrived:
        return 'Driver Arriving...';
      case RideStatus.inProgress:
        return 'Ride in Progress';
      case RideStatus.completed:
        return 'Ride Completed';
      default:
        return 'Ride Status';
    }
  }

  Widget _buildStateContent(BuildContext context, RideStateVM state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status indicator
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Driver info card (for accepted/arrived/in-progress)
              if (state.ride?.driver != null && state.isAccepted)
                _buildDriverCard(state),
              // ETA and distance
              if (state.ride != null) _buildRideDetails(state.ride!),
              const SizedBox(height: 20),
              // Action buttons based on state
              if (state.isRequested)
                _buildRequestingState(context, state)
              else if (state.isAccepted || state.isDriverArrived)
                _buildWaitingState(context, state)
              else if (state.isInProgress)
                _buildInProgressState(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverCard(RideStateVM state) {
    final driver = state.ride?.driver;
    if (driver == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Driver avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withOpacity(0.2),
            ),
            child: Center(
              child: Text(
                driver.firstName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Driver info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.fullName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      '${driver.rating.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${driver.completedRides} rides',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Vehicle badge
          if (state.ride?.taxi != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                state.ride!.taxi!.licensePlate,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRideDetails(Ride ride) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text(
                'Distance',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${ride.estimatedDistance.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey[300],
          ),
          Column(
            children: [
              Text(
                'Fare',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'MK${(ride.actualFare ?? ride.estimatedFare).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestingState(BuildContext context, RideStateVM state) {
    return Column(
      children: [
        Text(
          'Searching for drivers in your area...',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isLoading ? null : () => _handleCancelRide(context),
            icon: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.close),
            label: const Text('Cancel Ride'),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingState(BuildContext context, RideStateVM state) {
    final isArrived = state.isDriverArrived;
    return Column(
      children: [
        Text(
          isArrived ? 'Driver is here!' : 'Driver is on the way...',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isLoading ? null : () => _handleCancelRide(context),
            icon: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.close),
            label: const Text('Cancel Ride'),
          ),
        ),
      ],
    );
  }

  Widget _buildInProgressState(BuildContext context, RideStateVM state) {
    return Column(
      children: [
        Text(
          'On the way to dropoff...',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isLoading ? null : () => _handleCancelRide(context, reason: 'Passenger requested stop'),
            icon: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.close),
            label: const Text('End Ride'),
          ),
        ),
      ],
    );
  }

  Future<void> _handleCancelRide(BuildContext context, {String reason = 'Passenger cancelled'}) async {
    try {
      await ref
          .read(activeRideProvider.notifier)
          .cancelRide(reason);
      
      if (mounted && context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel ride: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
