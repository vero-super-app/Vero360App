import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_messaging_sheet.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';

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
  GoogleMapController? _mapController;
  static const Color primaryColor = Color(0xFFFF8A00);
  bool _hasNavigatedAway = false;

  @override
  void initState() {
    super.initState();
    // Must not call reset/subscribe synchronously during build; child's initState
    // runs while the route's ConsumerWidget is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(rideLifecycleProvider.notifier).reset();
      ref.read(rideLifecycleProvider.notifier).subscribeToRide(widget.rideId);
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Place _placeFromCoords({
    required String id,
    required String name,
    String? address,
    required double lat,
    required double lng,
  }) {
    return Place(
      id: id,
      name: name,
      address: address ?? '',
      latitude: lat,
      longitude: lng,
      type: PlaceType.RECENT,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lifecycleState = ref.watch(rideLifecycleProvider);

    final Ride? ride = switch (lifecycleState) {
      RideActive(:final ride) => ride,
      RideCompleted(:final ride) => ride,
      RideCancelled(:final ride) => ride,
      _ => null,
    };

    if (lifecycleState is RideCompleted && !_hasNavigatedAway) {
      final completedRide = lifecycleState.ride;
      if (completedRide.id != widget.rideId) {
        // Stale completion from another ride; wait for subscribeToRide.
      } else {
        _hasNavigatedAway = true;
        final r = completedRide;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RideCompletionScreen(
                  ride: r,
                  onDone: () => widget.onRideEnded?.call(),
                ),
              ),
            );
          }
        });
      }
    }

    if (lifecycleState is RideCancelled && !_hasNavigatedAway) {
      final cancelledRide = lifecycleState.ride;
      if (cancelledRide.id != widget.rideId) {
        // Stale cancel from another ride.
      } else {
        _hasNavigatedAway = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ride cancelled: ${lifecycleState.reason}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && context.mounted) Navigator.of(context).pop();
            });
          }
        });
      }
    }

    final String title = switch (lifecycleState) {
      RideActive(:final ride) => _getStateTitle(ride.status),
      RideCompleted() => 'Ride Completed',
      RideCancelled() => 'Ride Cancelled',
      _ => 'Ride Status',
    };

    // Build Place objects from ride data so MapViewWidget can draw markers & polyline
    final Place? pickupPlace = ride != null
        ? _placeFromCoords(
            id: 'pickup',
            name: 'Pickup',
            address: ride.pickupAddress,
            lat: ride.pickupLatitude,
            lng: ride.pickupLongitude,
          )
        : null;

    final Place? dropoffPlace = ride != null
        ? _placeFromCoords(
            id: 'dropoff',
            name: 'Dropoff',
            address: ride.dropoffAddress,
            lat: ride.dropoffLatitude,
            lng: ride.dropoffLongitude,
          )
        : null;

    final LatLng? driverLatLng =
        (ride?.driver?.latitude != null && ride?.driver?.longitude != null)
            ? LatLng(ride!.driver!.latitude!, ride.driver!.longitude!)
            : null;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          leading: const SizedBox.shrink(),
          centerTitle: true,
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: primaryColor,
        ),
        body: Stack(
          children: [
            MapViewWidget(
              onMapCreated: _onMapCreated,
              pickupPlace: pickupPlace,
              dropoffPlace: dropoffPlace,
              driverLocation: driverLatLng,
              driverLabel: ride?.driver?.fullName ?? 'Your Driver',
              trackingMode: true,
            ),
            if (lifecycleState is RideActive)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildStateContent(context, lifecycleState),
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

  Future<void> _openMessaging(
      BuildContext context, RideActive state) async {
    try {
      final myId = await AuthStorage.userIdFromToken();
      if (myId == null) throw Exception('User not authenticated');
      final driverName = state.ride.driver?.fullName ?? 'Driver';
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => RideMessagingSheet(
          otherUserId: state.ride.driverId!,
          otherUserName: driverName,
          myUserId: myId,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Widget _buildStateContent(BuildContext context, RideActive state) {
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
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              if (state.ride.driver != null && state.isAccepted)
                _buildDriverCard(state),
              _buildRideDetails(state.ride),
              const SizedBox(height: 20),
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

  Widget _buildDriverCard(RideActive state) {
    final driver = state.ride.driver;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.fullName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text('${driver.rating.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 12),
                    Text('${driver.completedRides} rides',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ),
          if (state.ride.taxi != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                state.ride.taxi!.licensePlate,
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
              Text('Distance',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              const SizedBox(height: 4),
              Text('${ride.estimatedDistance.toStringAsFixed(1)} km',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          Column(
            children: [
              Text('Fare',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                  'MK${(ride.actualFare ?? ride.estimatedFare).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageButton(BuildContext context, RideActive state) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: Color(0xFFFF8A00)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () => _openMessaging(context, state),
        icon: const Icon(Icons.message, size: 20),
        label: const Text(
          'Message Driver',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildCancelButton(RideActive state, {String label = 'Cancel Ride', String reason = 'Passenger cancelled'}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed:
            state.isLoading ? null : () => _handleCancelRide(context, reason: reason),
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
        label: Text(label),
      ),
    );
  }

  Widget _buildRequestingState(BuildContext context, RideActive state) {
    return Column(
      children: [
        Text('Searching for drivers in your area...',
            style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 16),
        _buildCancelButton(state),
      ],
    );
  }

  Widget _buildWaitingState(BuildContext context, RideActive state) {
    return Column(
      children: [
        Text(
          state.isDriverArrived
              ? 'Driver is here!'
              : 'Driver is on the way...',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        if (state.ride.driverId != null) ...[
          _buildMessageButton(context, state),
          const SizedBox(height: 10),
        ],
        _buildCancelButton(state),
      ],
    );
  }

  Widget _buildInProgressState(BuildContext context, RideActive state) {
    return Column(
      children: [
        Text('On the way to dropoff...',
            style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 16),
        if (state.ride.driverId != null) ...[
          _buildMessageButton(context, state),
          const SizedBox(height: 10),
        ],
        _buildCancelButton(state, label: 'End Ride', reason: 'Passenger requested stop'),
      ],
    );
  }

  Future<void> _handleCancelRide(BuildContext context,
      {String reason = 'Passenger cancelled'}) async {
    try {
      await ref.read(rideLifecycleProvider.notifier).cancelRide(reason);
      if (mounted && context.mounted) Navigator.pop(context);
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
