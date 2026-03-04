import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_state_notifier.dart';

class DriverRideExecutionScreen extends ConsumerStatefulWidget {
  final int rideId;
  final VoidCallback? onRideEnded;

  const DriverRideExecutionScreen({
    super.key,
    required this.rideId,
    this.onRideEnded,
  });

  @override
  ConsumerState<DriverRideExecutionScreen> createState() =>
      _DriverRideExecutionScreenState();
}

class _DriverRideExecutionScreenState
    extends ConsumerState<DriverRideExecutionScreen> {
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
          Navigator.of(context).pop();
          widget.onRideEnded?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ride completed successfully!'),
              backgroundColor: Colors.green,
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
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
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
            // Bottom action panel
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionPanel(context, rideState),
            ),
          ],
        ),
      ),
    );
  }

  String _getStateTitle(String status) {
    switch (status) {
      case RideStatus.accepted:
        return 'Head to Pickup';
      case RideStatus.driverArrived:
        return 'At Pickup Location';
      case RideStatus.inProgress:
        return 'En Route to Dropoff';
      case RideStatus.completed:
        return 'Ride Completed';
      default:
        return 'Ride Status';
    }
  }

  Widget _buildActionPanel(BuildContext context, RideStateVM state) {
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
              // Drag handle
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Passenger info card
              if (state.ride != null)
                _buildPassengerCard(state.ride!),
              const SizedBox(height: 20),
              // State-specific content
              if (state.isAccepted)
                _buildAcceptedStateActions(context, state)
              else if (state.isDriverArrived)
                _buildArrivedStateActions(context, state)
              else if (state.isInProgress)
                _buildInProgressStateActions(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerCard(Ride ride) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Passenger avatar placeholder
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withOpacity(0.2),
            ),
            child: const Center(
              child: Icon(
                Icons.person,
                size: 24,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.pickupAddress ?? 'Pickup Location',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'to ${ride.dropoffAddress ?? 'Dropoff Location'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedStateActions(BuildContext context, RideStateVM state) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.navigation, color: Colors.blue[700], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Head to pickup location',
                  style: TextStyle(color: Colors.blue[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isLoading
                ? null
                : () async {
                    await ref.read(activeRideProvider.notifier).markArrived();
                  },
            icon: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: const Text('Mark as Arrived'),
          ),
        ),
      ],
    );
  }

  Widget _buildArrivedStateActions(BuildContext context, RideStateVM state) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.check, color: Colors.green[700], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Passenger is boarding',
                  style: TextStyle(color: Colors.green[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isLoading
                ? null
                : () async {
                    await ref.read(activeRideProvider.notifier).startRide();
                  },
            icon: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('Start Ride'),
          ),
        ),
      ],
    );
  }

  Widget _buildInProgressStateActions(BuildContext context, RideStateVM state) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.directions_run, color: Colors.orange[700], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'En route to dropoff',
                  style: TextStyle(color: Colors.orange[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: state.isLoading
                ? null
                : () async {
                    await ref.read(activeRideProvider.notifier).completeRide();
                  },
            icon: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.flag),
            label: const Text('Complete Ride'),
          ),
        ),
      ],
    );
  }
}
