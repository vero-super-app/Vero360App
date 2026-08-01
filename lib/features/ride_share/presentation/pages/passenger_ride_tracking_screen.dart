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
import 'package:vero360_app/utils/user_facing_error.dart';

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
        SnackBar(content: Text(UserFacingError.from(e))),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: Text(
          reason.contains('stop')
              ? 'This cancels the trip for you and the driver. '
                  'Only the driver can complete a ride and set the fare.'
              : 'Are you sure you want to cancel this ride request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(rideLifecycleProvider.notifier).cancelRide(reason);
      if (mounted && context.mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.from(e, fallback: 'Failed to cancel ride')),
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
        topOverlay: const RideGlassTopBar(
          title: 'Vero Ride',
        ),
        floatingActions: Positioned(
          right: 16,
          bottom: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RideMapFab(
                icon: Icons.my_location,
                onTap: () => _recenter(
                  driverLatLng ??
                      (pickupPlace != null
                          ? LatLng(pickupPlace.latitude, pickupPlace.longitude)
                          : null),
                ),
              ),
            ],
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
    final showDriver = driver != null && !state.isRequested;

    return RideLightSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RideStatusHeadline(
            title: _headline(state),
            badge: rideStatusBadge(ride.status),
            subtitle: _subtitle(ride),
          ),
          const SizedBox(height: 20),
          RideTripProgressBar(
            progress: rideStatusProgress(ride.status),
            leftLabel: 'Pickup',
            rightLabel: 'Dropoff',
          ),
          if (showDriver) ...[
            const SizedBox(height: 20),
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
          const SizedBox(height: 20),
          if (state.isRequested) ...[
            const Text(
              'Searching for nearby drivers…',
              textAlign: TextAlign.center,
              style: TextStyle(color: RideShareColors.onSurfaceVariant),
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
            RidePassengerActionGrid(
              onSafety: () => showRideSafetySheet(context),
              onShare: () => _shareTrip(ride),
            ),
            const SizedBox(height: 12),
            RideSecondaryCta(
              label: 'Cancel Ride',
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
        ],
      ),
    );
  }
}
