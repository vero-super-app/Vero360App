import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';

import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_in_ride_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_messaging_sheet.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

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
  GoogleMapController? _mapController;
  bool _hasNavigatedAway = false;
  String? _lastActionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(rideLifecycleProvider.notifier)
          .subscribeToRideAsDriver(widget.rideId);
    });
  }

  @override
  void dispose() {
    ref.read(rideLifecycleProvider.notifier).detachScreen();
    _mapController?.dispose();
    super.dispose();
  }

  Place _placeFromRide({
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

  String _bannerTitle(RideActive state) {
    if (state.isAccepted) return 'Head to pickup';
    if (state.isDriverArrived) return 'Waiting for passenger';
    if (state.isInProgress) {
      final dest = state.ride.dropoffAddress?.trim();
      if (dest != null && dest.isNotEmpty) return dest;
      return 'En route to dropoff';
    }
    return 'Active ride';
  }

  String _bannerEyebrow(RideActive state) {
    if (state.isAccepted) return 'Next step';
    if (state.isDriverArrived) return 'At pickup';
    if (state.isInProgress) return 'Destination';
    return 'Status';
  }

  IconData _bannerIcon(RideActive state) {
    if (state.isAccepted) return Icons.navigation;
    if (state.isDriverArrived) return Icons.person_pin_circle;
    return Icons.flag;
  }

  Future<void> _openMessaging(RideActive state) async {
    try {
      final myId = await AuthStorage.userIdFromToken();
      if (myId == null) throw Exception('User not authenticated');
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => RideMessagingSheet(
          otherUserId: state.ride.passengerId,
          otherUserName: state.ride.passengerName?.trim().isNotEmpty == true
              ? state.ride.passengerName!
              : 'Passenger',
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

  Future<void> _handleCancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: const Text(
          'Are you sure you want to cancel this ride? The passenger will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep Ride'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref
            .read(rideLifecycleProvider.notifier)
            .cancelRide('Driver cancelled');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(UserFacingError.from(e, fallback: 'Failed to cancel')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
      if (completedRide.id == widget.rideId) {
        _hasNavigatedAway = true;
        final r = completedRide;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => _DriverRideCompletionScreen(
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

    if (lifecycleState is RideActive &&
        lifecycleState.actionError != null &&
        lifecycleState.actionError != _lastActionError) {
      _lastActionError = lifecycleState.actionError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lifecycleState.actionError!),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }

    final pickupPlace = ride != null
        ? _placeFromRide(
            id: 'pickup',
            name: 'Pickup',
            address: ride.pickupAddress,
            lat: ride.pickupLatitude,
            lng: ride.pickupLongitude,
          )
        : null;

    final dropoffPlace = ride != null
        ? _placeFromRide(
            id: 'dropoff',
            name: 'Dropoff',
            address: ride.dropoffAddress,
            lat: ride.dropoffLatitude,
            lng: ride.dropoffLongitude,
          )
        : null;

    return PopScope(
      canPop: false,
      child: RideInRideShell(
        map: MapViewWidget(
          onMapCreated: (c) => _mapController = c,
          pickupPlace: pickupPlace,
          dropoffPlace: dropoffPlace,
          trackingMode: true,
        ),
        topOverlay: lifecycleState is RideActive
            ? RideNavBanner(
                eyebrow: _bannerEyebrow(lifecycleState),
                title: _bannerTitle(lifecycleState),
                icon: _bannerIcon(lifecycleState),
                trailing: rideStatusBadge(lifecycleState.ride.status),
              )
            : null,
        bottomSheet: switch (lifecycleState) {
          RideActive() => _buildSheet(lifecycleState),
          RideIdle() || RideRequesting() => const RideLightSheet(
              floating: true,
              showHandle: false,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation(RideShareColors.primary),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading ride details…',
                      style: TextStyle(
                        color: RideShareColors.titleText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _buildSheet(RideActive state) {
    final ride = state.ride;
    final fare =
        'MK${(ride.actualFare ?? ride.estimatedFare).toStringAsFixed(0)}';
    final distance = '${ride.estimatedDistance.toStringAsFixed(1)} km';
    final passengerName = ride.passengerName?.trim().isNotEmpty == true
        ? ride.passengerName!
        : 'Passenger';

    final destinationLabel = state.isAccepted
        ? (ride.pickupAddress?.trim().isNotEmpty == true
            ? ride.pickupAddress!
            : 'Pickup location')
        : (ride.dropoffAddress?.trim().isNotEmpty == true
            ? ride.dropoffAddress!
            : 'Dropoff location');

    final destinationEyebrow =
        state.isAccepted || state.isDriverArrived ? 'Pickup' : 'Destination';

    return RideLightSheet(
      floating: true,
      showHandle: false,
      contentPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destinationEyebrow.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: RideShareColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.isAccepted
                                ? 'Heading to pickup'
                                : state.isDriverArrived
                                    ? 'Waiting at pickup'
                                    : 'Heading to $destinationLabel',
                            style: const TextStyle(
                              color: RideShareColors.titleText,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$distance remaining · $fare',
                            style: const TextStyle(
                              color: RideShareColors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    RidePassengerMiniCard(name: passengerName),
                  ],
                ),
                if (ride.passengerNotes != null &&
                    ride.passengerNotes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: RideShareColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: RideShareColors.outlineVariant
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Note: ${ride.passengerNotes}',
                      style: const TextStyle(
                        color: RideShareColors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (state.isAccepted) ...[
                  RidePrimaryCta(
                    label: 'Mark as Arrived',
                    icon: Icons.check_circle,
                    isLoading: state.isLoading,
                    onPressed: () =>
                        ref.read(rideLifecycleProvider.notifier).markArrived(),
                  ),
                  const SizedBox(height: 10),
                  RideSecondaryCta(
                    label: 'Cancel Ride',
                    icon: Icons.close,
                    onPressed: state.isLoading ? null : _handleCancelRide,
                  ),
                ] else if (state.isDriverArrived) ...[
                  RidePrimaryCta(
                    label: 'Start Ride',
                    icon: Icons.play_arrow,
                    isLoading: state.isLoading,
                    onPressed: () =>
                        ref.read(rideLifecycleProvider.notifier).startRide(),
                  ),
                  const SizedBox(height: 10),
                  RideSecondaryCta(
                    label: 'Cancel Ride',
                    icon: Icons.close,
                    onPressed: state.isLoading ? null : _handleCancelRide,
                  ),
                ] else if (state.isInProgress) ...[
                  RideSwipeToComplete(
                    label: 'Swipe to Complete Ride',
                    enabled: !state.isLoading,
                    onCompleted: () async {
                      await ref
                          .read(rideLifecycleProvider.notifier)
                          .completeRide();
                      final next = ref.read(rideLifecycleProvider);
                      return next is RideCompleted &&
                          next.ride.id == widget.rideId;
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          RideQuickActionsRow(
            onMessage: () => _openMessaging(state),
            onSafety: () => showRideSafetySheet(context),
            onCall: null,
          ),
        ],
      ),
    );
  }
}

/// Summary screen shown to the driver after completing a ride.
class _DriverRideCompletionScreen extends ConsumerStatefulWidget {
  final Ride ride;
  final VoidCallback onDone;

  const _DriverRideCompletionScreen({
    required this.ride,
    required this.onDone,
  });

  @override
  ConsumerState<_DriverRideCompletionScreen> createState() =>
      _DriverRideCompletionScreenState();
}

class _DriverRideCompletionScreenState
    extends ConsumerState<_DriverRideCompletionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  Timer? _pollTimer;
  Ride? _ride;
  bool _finishing = false;
  bool _confirmingCash = false;
  String? _actionError;

  Ride _resolveRide(RideLifecycleState lifecycle) {
    final fromLifecycle =
        lifecycle is RideCompleted && lifecycle.ride.id == widget.ride.id
            ? lifecycle.ride
            : null;
    final local = _ride;
    if (local != null && (local.isPaid || local.isCashPayment)) return local;
    return fromLifecycle ?? local ?? widget.ride;
  }

  @override
  void initState() {
    super.initState();
    _ride = widget.ride;
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshRide());
    });
    unawaited(_refreshRide());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  RideShareHttpService get _http => ref.read(rideShareHttpServiceProvider);

  Future<void> _refreshRide() async {
    try {
      final fresh = await _http.getRideDetails(widget.ride.id);
      if (!mounted) return;
      setState(() => _ride = fresh);
    } catch (_) {}
  }

  Future<void> _confirmCash() async {
    if (_confirmingCash) return;
    setState(() {
      _confirmingCash = true;
      _actionError = null;
    });
    try {
      final updated = await _http.confirmCashPayment(widget.ride.id);
      if (!mounted) return;
      setState(() {
        _ride = updated;
        _confirmingCash = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cash confirmed — commission added to your settlement balance.',
          ),
          backgroundColor: RideShareColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirmingCash = false;
        _actionError = UserFacingError.from(
          e,
          fallback: 'Could not confirm cash payment',
        );
      });
    }
  }

  void _handleDone() {
    final ride = _resolveRide(ref.read(rideLifecycleProvider));
    if (!ride.isPaid || _finishing) return;
    setState(() => _finishing = true);

    // Capture navigator before callbacks that may dispose this route.
    final navigator = Navigator.of(context, rootNavigator: true);
    try {
      widget.onDone();
    } catch (_) {}
    try {
      ref.read(rideLifecycleProvider.notifier).reset();
    } catch (_) {}

    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lifecycle = ref.watch(rideLifecycleProvider);
    final r = _resolveRide(lifecycle);
    final totalFare = r.actualFare ?? r.estimatedFare;
    final distance = r.actualDistance ?? r.estimatedDistance;
    final platformFee = r.platformFee ?? (totalFare * 0.025);
    final paid = r.isPaid;
    final cash = r.isCashPayment;
    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              const Color(0xFF4CAF50).withValues(alpha: 0.1),
                          border: Border.all(
                            color: const Color(0xFF4CAF50),
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 60,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Ride Complete!',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: RideShareColors.titleText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Great job on this trip',
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: RideShareColors.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Trip Summary',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (r.startTime != null && r.endTime != null)
                                  Text(
                                    '${r.endTime!.difference(r.startTime!).inMinutes} mins',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _summaryRow(
                              'Distance',
                              '${distance.toStringAsFixed(1)} km',
                            ),
                            const SizedBox(height: 12),
                            _summaryRow(
                              'Pickup',
                              r.pickupAddress ?? 'Unknown',
                            ),
                            const SizedBox(height: 8),
                            _summaryRow(
                              'Dropoff',
                              r.dropoffAddress ?? 'Unknown',
                            ),
                            const Divider(height: 28),
                            _summaryRow(
                              paid && cash ? 'Fare collected' : 'Fare',
                              'MK${totalFare.toStringAsFixed(0)}',
                              emphasize: !cash,
                            ),
                            if (paid && cash) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                'Platform commission',
                                'MK${platformFee.toStringAsFixed(0)}',
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Commission was added to your settlement balance. The passenger paid you in cash.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!paid) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: RideShareColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: RideShareColors.primary
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            cash
                                ? 'Passenger chose cash. Confirm when you have received MK${totalFare.toStringAsFixed(0)}.'
                                : 'Waiting for digital payment, or confirm cash if the passenger paid you directly.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: RideShareColors.primaryDeep,
                            ),
                          ),
                        ),
                        if (_actionError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _actionError!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Pinned outside ScaleTransition so taps always hit the button
            // (also clear of the system gesture inset via SafeArea).
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  if (!paid)
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: RideShareColors.primary,
                          disabledBackgroundColor:
                              RideShareColors.primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _confirmingCash ? null : _confirmCash,
                        child: _confirmingCash
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Confirm cash received',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: RideShareColors.primary,
                          disabledBackgroundColor:
                              RideShareColors.primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _finishing ? null : _handleDone,
                        child: _finishing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Done',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize
                  ? RideShareColors.primary
                  : RideShareColors.titleText,
              fontSize: emphasize ? 18 : 14,
            ),
          ),
        ),
      ],
    );
  }
}
