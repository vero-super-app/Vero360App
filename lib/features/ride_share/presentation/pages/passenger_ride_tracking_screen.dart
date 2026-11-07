import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/active_ride_controller.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/websocket_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_in_ride_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_messaging_sheet.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/features/ride_share/ride_share_no_driver_help.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
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
  List<PickupOffer> _offers = const [];
  StreamSubscription<Map<String, dynamic>>? _flexibleSub;
  StreamSubscription<Map<String, dynamic>>? _staleLocationSub;
  StreamSubscription<Map<String, dynamic>>? _driverLocationSub;
  bool _staleBannerDismissed = false;

  void _showDriverLocationStaleBanner() {
    if (!mounted || _staleBannerDismissed) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: RideShareColors.surface,
          content: const Text(
            'Driver location may be outdated. Waiting for a fresh GPS update.',
            style: TextStyle(
              color: RideShareColors.titleText,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          leading: const Icon(
            Icons.gps_off_rounded,
            color: RideShareColors.primaryDeep,
          ),
          actions: [
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                if (mounted) {
                  setState(() => _staleBannerDismissed = true);
                }
              },
              child: const Text(
                'Dismiss',
                style: TextStyle(
                  color: RideShareColors.primaryDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
  }

  void _clearDriverLocationStaleBanner() {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Hide cold-start resume banner while tracking is already open.
      ref.read(passengerResumeRideIdProvider.notifier).state = null;
      ref
          .read(rideLifecycleProvider.notifier)
          .subscribeToRideAsPassenger(widget.rideId);
      unawaited(_loadOffers());
      final http = ref.read(rideShareHttpServiceProvider);
      _flexibleSub = http.flexibleEventStream.listen((event) {
        if (!mounted) return;
        if ('${event['rideId']}' != '${widget.rideId}') return;
        unawaited(_loadOffers());
        unawaited(
          ref.read(rideLifecycleProvider.notifier).refreshActiveRide(),
        );
      });
      _staleLocationSub = http.driverLocationStaleStream.listen((event) {
        if (!mounted) return;
        final eventRideId = event['rideId'];
        if (eventRideId != null && '${eventRideId}' != '${widget.rideId}') {
          return;
        }
        setState(() => _staleBannerDismissed = false);
        _showDriverLocationStaleBanner();
      });
      _driverLocationSub = http.driverLocationStream.listen((event) {
        if (!mounted) return;
        final eventRideId = event['rideId'];
        if (eventRideId != null && '${eventRideId}' != '${widget.rideId}') {
          return;
        }
        _clearDriverLocationStaleBanner();
      });
    });
  }

  @override
  void dispose() {
    _flexibleSub?.cancel();
    _staleLocationSub?.cancel();
    _driverLocationSub?.cancel();
    try {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
    } catch (_) {}
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    try {
      final offers = await ref
          .read(rideShareHttpServiceProvider)
          .listPickupOffers(widget.rideId);
      if (!mounted) return;
      setState(() => _offers = offers);
    } catch (_) {}
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

  String _headline(RideActive state, {int? etaMinutes}) {
    final base = state.isRequested
        ? 'Finding your ride'
        : state.isDriverArrived
            ? 'Driver is here'
            : state.isInProgress
                ? 'On the way'
                : 'Driver en route';
    if (etaMinutes != null &&
        etaMinutes > 0 &&
        !state.isRequested &&
        !state.isDriverArrived) {
      return '$base · ~$etaMinutes min';
    }
    return base;
  }

  String _subtitle(Ride ride) {
    final dest = ride.dropoffAddress?.trim();
    if (dest != null && dest.isNotEmpty) return 'Heading to $dest';
    return 'Tracking your Vero Ride';
  }

  int? _passengerEtaMinutes({
    required RideActive state,
    required DriverLocation? liveDriver,
    required LatLng? driverLatLng,
  }) {
    if (liveDriver?.etaMinutes != null && liveDriver!.etaMinutes! > 0) {
      return liveDriver.etaMinutes;
    }
    if (driverLatLng == null) return null;
    final ride = state.ride;
    final targetLat = state.isInProgress
        ? ride.dropoffLatitude
        : ride.pickupLatitude;
    final targetLng = state.isInProgress
        ? ride.dropoffLongitude
        : ride.pickupLongitude;
    final km = haversineDistanceKm(
      driverLatLng.latitude,
      driverLatLng.longitude,
      targetLat,
      targetLng,
    );
    return estimateEtaMinutesFromKm(km);
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
    final dest = ride.dropoffAddress?.trim();
    final pickup = ride.pickupAddress?.trim();
    String? liveUrl;
    try {
      liveUrl =
          await ref.read(rideShareHttpServiceProvider).fetchRideShareLink(ride.id);
    } catch (_) {}
    liveUrl ??= RideShareHttpService.fallbackTripShareUrl(ride.id);

    final buffer = StringBuffer("I'm on a Vero Ride");
    if (dest != null && dest.isNotEmpty) {
      buffer.write(' heading to $dest');
    }
    buffer.write('. Ride #${ride.id}');
    if (pickup != null && pickup.isNotEmpty) {
      buffer.write('\nPickup: $pickup');
    }
    buffer.write('\nTrack live: $liveUrl');

    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Vero Ride trip',
      ),
    );
  }

  String _clock(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _isReadyNow(Ride ride) {
    final ready = ride.passengerReadyAt;
    if (ready == null) return false;
    return !ready.isAfter(DateTime.now().add(const Duration(seconds: 30)));
  }

  bool _needsFiveMore(Ride ride) {
    final ready = ride.passengerReadyAt;
    if (ready == null) return false;
    return ready.isAfter(DateTime.now().add(const Duration(seconds: 30)));
  }

  Future<void> _setWait(int minutes) async {
    try {
      final ride = await ref.read(rideShareHttpServiceProvider).updateMaxWait(
            rideId: widget.rideId,
            maxWaitMinutes: minutes,
          );
      if (!mounted) return;
      await ref.read(rideLifecycleProvider.notifier).refreshActiveRide();
      if (ride.id != widget.rideId) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.from(e))),
      );
    }
  }

  Future<void> _confirmOffer(PickupOffer offer) async {
    try {
      await ref.read(rideShareHttpServiceProvider).confirmPickupOffer(
            rideId: widget.rideId,
            offerId: offer.id,
          );
      if (!mounted) return;
      setState(() => _offers = const []);
      await ref.read(rideLifecycleProvider.notifier).refreshActiveRide();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.from(e))),
      );
    }
  }

  Future<void> _setReady(int extraMinutes) async {
    try {
      await ref.read(rideShareHttpServiceProvider).updateRideTiming(
            rideId: widget.rideId,
            passengerReadyAt:
                DateTime.now().add(Duration(minutes: extraMinutes)),
          );
      if (!mounted) return;
      await ref.read(rideLifecycleProvider.notifier).refreshActiveRide();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFacingError.from(e))),
      );
    }
  }

  Future<void> _handleCancel(
    BuildContext context, {
    String reason = 'Passenger cancelled',
  }) async {
    final lifecycleState = ref.read(rideLifecycleProvider);
    final Ride? currentRide = switch (lifecycleState) {
      RideActive(:final ride) => ride,
      RideCompleted(:final ride) => ride,
      RideCancelled(:final ride) => ride,
      _ => null,
    };
    final status = currentRide?.status ?? RideStatus.requested;

    double fee = CancelFeePreview.feeForStatus(status);
    try {
      final preview = await ref
          .read(rideShareHttpServiceProvider)
          .getCancelFeePreview(widget.rideId);
      fee = preview.cancellationFee;
    } catch (_) {
      // Keep local default table matching backend env defaults.
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason.contains('stop')
                  ? 'This cancels the trip for you and the driver. '
                      'Only the driver can complete a ride and set the fare.'
                  : 'Are you sure you want to cancel this ride request?',
            ),
            if (fee > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Cancellation fee: MK ${fee.round()}',
                style: const TextStyle(
                  color: RideShareColors.primaryDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
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
      if (!mounted) return;
      setState(() => _hasNavigatedAway = true);
      if (context.mounted) Navigator.pop(context);
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

  Future<void> _handleCancelledRide(Ride ride, String reason) async {
    if (!mounted) return;

    if (RideShareNoDriverHelp.isNoDriverReason(reason)) {
      final location = RideShareNoDriverHelp.locationLabel(
        name: null,
        address: ride.pickupAddress,
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return SafeArea(
            child: Container(
              margin: const EdgeInsets.only(top: 48),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: NoDriverHelpPanel(
                locationLabel: location,
                showHandle: true,
                onTryAgain: () => Navigator.pop(ctx),
              ),
            ),
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ride cancelled: $reason'),
          backgroundColor: Colors.red,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    if (mounted && context.mounted) Navigator.of(context).pop();
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
          if (!mounted || !context.mounted) return;
          unawaited(_handleCancelledRide(cancelledRide, lifecycleState.reason));
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
            ? _buildSheet(
                lifecycleState,
                liveDriverLocation: liveDriverLocation,
                driverLatLng: driverLatLng,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildSheet(
    RideActive state, {
    DriverLocation? liveDriverLocation,
    LatLng? driverLatLng,
  }) {
    final ride = state.ride;
    final driver = ride.driver;
    final showDriver = driver != null && !state.isRequested;
    final etaMinutes = _passengerEtaMinutes(
      state: state,
      liveDriver: liveDriverLocation,
      driverLatLng: driverLatLng,
    );

    return RideLightSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RideStatusHeadline(
            title: _headline(state, etaMinutes: etaMinutes),
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
              verified: driver.isRideShareVerified,
              subtitle: ride.taxi != null
                  ? [
                      if (ride.taxi!.model.isNotEmpty) ride.taxi!.model,
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
            Text(
              ride.searchDeadline == null
                  ? 'Searching for nearby drivers…'
                  : 'Looking until ${_clock(ride.searchDeadline!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: RideShareColors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final minutes in const [10, 20])
                  ChoiceChip(
                    label: Text('I\'ll wait $minutes min'),
                    selected: ride.maxWaitMinutes == minutes,
                    onSelected: state.isLoading
                        ? null
                        : (_) => _setWait(minutes),
                  ),
              ],
            ),
            if (_offers.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final offer in _offers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${offer.driverName} can pick you up in ${offer.etaMinutes} min',
                  ),
                  trailing: TextButton(
                    onPressed: state.isLoading ? null : () => _confirmOffer(offer),
                    child: const Text('Confirm'),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            RideSecondaryCta(
              label: 'Cancel Ride',
              icon: Icons.close,
              onPressed: state.isLoading
                  ? null
                  : () => _handleCancel(context),
            ),
          ] else ...[
            if (ride.driverDelayMinutes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ride.driverDelayMinutes == 0
                      ? 'Driver is on time'
                      : 'Driver is about ${ride.driverDelayMinutes} min late',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: RideShareColors.onSurfaceVariant),
                ),
              ),
            if (!state.isInProgress)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Ready now'),
                      selected: _isReadyNow(ride),
                      onSelected: state.isLoading ? null : (_) => _setReady(0),
                    ),
                    ChoiceChip(
                      label: const Text('Need 5 more min'),
                      selected: _needsFiveMore(ride),
                      onSelected: state.isLoading ? null : (_) => _setReady(5),
                    ),
                  ],
                ),
              ),
            RidePassengerActionGrid(
              onSafety: () => showRideSafetySheet(
                context,
                ride: ride,
                httpService: ref.read(rideShareHttpServiceProvider),
                onShareTrip: () => _shareTrip(ride),
              ),
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
