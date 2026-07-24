import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/websocket_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_in_ride_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_messaging_sheet.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

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
  bool _hasNavigatedAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(rideLifecycleProvider.notifier)
          .subscribeToRideAsPassenger(widget.rideId);
    });
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

  String _headline(RideActive state) {
    if (state.isRequested) return 'Finding your ride';
    if (state.isDriverArrived) return 'Driver is here';
    if (state.isInProgress) return 'On the way';
    return 'Driver en route';
  }

  String _subtitle(Ride ride) {
    final dest = ride.dropoffAddress?.trim();
    if (dest != null && dest.isNotEmpty) return 'Heading to $dest';
    return 'Tracking your Vero Ride';
  }

  Future<void> _recenter(LatLng? target) async {
    if (_mapController == null || target == null) return;
    await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
  }

  Future<void> _openMessaging(RideActive state) async {
    try {
      final myId = await AuthStorage.userIdFromToken();
      if (myId == null) throw Exception('User not authenticated');
      final driverName = state.ride.driver?.fullName ?? 'Driver';
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => RideMessagingSheet(
          otherUserId: state.ride.driverId!,
          otherUserName: driverName,
          myUserId: myId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _callDriver(RideActive state) async {
    final phone = state.ride.driver?.phone?.trim();
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver phone number unavailable')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareTrip(Ride ride) async {
    final dest = ride.dropoffAddress ?? 'my destination';
    await SharePlus.instance.share(
      ShareParams(
        text: 'I\'m on a Vero Ride heading to $dest. Ride #${ride.id}',
        subject: 'Vero Ride trip',
      ),
    );
  }

  Future<void> _handleCancel(
    BuildContext context, {
    String reason = 'Passenger cancelled',
  }) async {
    try {
      await ref.read(rideLifecycleProvider.notifier).cancelRide(reason);
      if (mounted && context.mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel ride: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lifecycleState = ref.watch(rideLifecycleProvider);
    final liveDriverLocation = ref.watch(driverLocationProvider).value;

    final Ride? ride = switch (lifecycleState) {
      RideActive(:final ride) => ride,
      RideCompleted(:final ride) => ride,
      RideCancelled(:final ride) => ride,
      _ => null,
    };

    if (lifecycleState is RideCompleted && !_hasNavigatedAway) {
      final completedRide = lifecycleState.ride;
      if (completedRide.id == widget.rideId) {
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
      if (cancelledRide.id == widget.rideId) {
        _hasNavigatedAway = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ride cancelled: ${lifecycleState.reason}'),
                backgroundColor: Colors.red,
              ),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && context.mounted) Navigator.of(context).pop();
            });
          }
        });
      }
    }

    final pickupPlace = ride != null
        ? _placeFromCoords(
            id: 'pickup',
            name: 'Pickup',
            address: ride.pickupAddress,
            lat: ride.pickupLatitude,
            lng: ride.pickupLongitude,
          )
        : null;

    final dropoffPlace = ride != null
        ? _placeFromCoords(
            id: 'dropoff',
            name: 'Dropoff',
            address: ride.dropoffAddress,
            lat: ride.dropoffLatitude,
            lng: ride.dropoffLongitude,
          )
        : null;

    final driverLatLng = liveDriverLocation != null
        ? LatLng(liveDriverLocation.latitude, liveDriverLocation.longitude)
        : (ride?.driver?.latitude != null && ride?.driver?.longitude != null)
            ? LatLng(ride!.driver!.latitude!, ride.driver!.longitude!)
            : null;

    return PopScope(
      canPop: false,
      child: RideInRideShell(
        map: MapViewWidget(
          onMapCreated: (c) => _mapController = c,
          pickupPlace: pickupPlace,
          dropoffPlace: dropoffPlace,
          driverLocation: driverLatLng,
          driverLabel: ride?.driver?.fullName ?? 'Your Driver',
          trackingMode: true,
        ),
        topOverlay: RideGlassTopBar(
          title: 'Vero Ride',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              lifecycleState is RideActive
                  ? rideStatusBadge(lifecycleState.ride.status)
                  : 'Trip',
              style: const TextStyle(
                color: RideShareColors.primaryDeep,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ),
        floatingActions: Positioned(
          right: 16,
          bottom: MediaQuery.of(context).size.height * 0.42,
          child: RideMapFab(
            icon: Icons.my_location,
            onTap: () => _recenter(
              driverLatLng ??
                  (pickupPlace != null
                      ? LatLng(pickupPlace.latitude, pickupPlace.longitude)
                      : null),
            ),
          ),
        ),
        bottomSheet: lifecycleState is RideActive
            ? _buildSheet(lifecycleState)
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildSheet(RideActive state) {
    final ride = state.ride;
    final driver = ride.driver;
    final fare =
        'MK${(ride.actualFare ?? ride.estimatedFare).toStringAsFixed(0)}';
    final distance = '${ride.estimatedDistance.toStringAsFixed(1)} km';

    return RideNavySheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RideStatusHeadline(
            title: _headline(state),
            badge: rideStatusBadge(ride.status),
            subtitle: _subtitle(ride),
          ),
          const SizedBox(height: 16),
          RideTripProgressBar(
            progress: rideStatusProgress(ride.status),
            leftLabel: 'Pickup',
            rightLabel: 'Dropoff',
          ),
          const SizedBox(height: 16),
          RideMetricRow(distanceLabel: distance, fareLabel: fare),
          if (driver != null && state.isAccepted) ...[
            const SizedBox(height: 14),
            RidePersonCard(
              name: driver.fullName,
              subtitle: ride.taxi != null
                  ? [
                      if (ride.taxi!.make.isNotEmpty) ride.taxi!.make,
                      if ((ride.taxi!.color ?? '').isNotEmpty) ride.taxi!.color!,
                    ].join(' • ')
                  : '${driver.completedRides} rides',
              meta: ride.taxi?.licensePlate,
              rating: driver.rating,
              initials: driver.firstName,
              actions: [
                RideCircleIconButton(
                  icon: Icons.phone,
                  onTap: () => _callDriver(state),
                ),
                if (ride.driverId != null)
                  RideCircleIconButton(
                    icon: Icons.chat_bubble_outline,
                    onTap: () => _openMessaging(state),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (state.isRequested) ...[
            Text(
              'Searching for nearby drivers…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 14),
            RideSecondaryCta(
              label: 'Cancel Ride',
              icon: Icons.close,
              onPressed: state.isLoading
                  ? null
                  : () => _handleCancel(context),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => showRideSafetySheet(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RideShareColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.emergency_share, size: 18),
                      label: const Text(
                        'Safety',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _shareTrip(ride),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text(
                        'Share',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RideSecondaryCta(
              label: state.isInProgress ? 'End Ride' : 'Cancel Ride',
              icon: Icons.close,
              onPressed: state.isLoading
                  ? null
                  : () => _handleCancel(
                        context,
                        reason: state.isInProgress
                            ? 'Passenger requested stop'
                            : 'Passenger cancelled',
                      ),
            ),
          ],
          if (!state.isRequested) ...[
            const SizedBox(height: 8),
            RideQuickActionsRow(
              onMessage: ride.driverId != null
                  ? () => _openMessaging(state)
                  : null,
              onCall: () => _callDriver(state),
              onSafety: () => showRideSafetySheet(context),
            ),
          ],
        ],
      ),
    );
  }
}
