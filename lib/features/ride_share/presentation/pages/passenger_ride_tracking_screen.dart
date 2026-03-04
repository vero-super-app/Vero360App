import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_state_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeRideProvider.notifier).subscribeToRide(widget.rideId);
    });
  }

  @override
  void dispose() {
    ref.read(activeRideProvider.notifier).unsubscribeFromRide();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _updateMapMarkers(Ride ride) {
    setState(() {
      markers.clear();
      polylines.clear();

      // Pickup marker
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(ride.pickupLatitude, ride.pickupLongitude),
          infoWindow: InfoWindow(title: 'Pickup: ${ride.pickupAddress}'),
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
          infoWindow: InfoWindow(title: 'Dropoff: ${ride.dropoffAddress}'),
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
            infoWindow: const InfoWindow(title: 'Your Driver'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
          ),
        );
      }

      // Route polyline
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
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ride cancelled: ${rideState.ride?.cancellationReason}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }

    if (rideState.ride != null) {
      _updateMapMarkers(rideState.ride!);
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
                  rideState.ride?.pickupLatitude ?? 0,
                  rideState.ride?.pickupLongitude ?? 0,
                ),
                zoom: 14,
              ),
              markers: markers,
              polylines: polylines,
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
              if (state.ride != null)
                _buildRideDetails(state.ride!),
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
            onPressed: () {
              ref.read(activeRideProvider.notifier).cancelRide('Passenger cancelled');
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close),
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
            onPressed: () {
              ref.read(activeRideProvider.notifier).cancelRide('Passenger cancelled');
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close),
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
        if (state.isLoading)
          const CircularProgressIndicator()
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                ref.read(activeRideProvider.notifier).cancelRide('Passenger requested stop');
                Navigator.pop(context);
              },
              icon: const Icon(Icons.close),
              label: const Text('End Ride'),
            ),
          ),
      ],
    );
  }
}
