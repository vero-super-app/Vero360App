import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';

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
  static const Color primaryColor = Color(0xFFFF8A00);
  bool _hasNavigatedAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideLifecycleProvider.notifier).subscribeToRide(widget.rideId);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
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
      _hasNavigatedAway = true;
      final r = lifecycleState.ride;
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

    if (lifecycleState is RideCancelled && !_hasNavigatedAway) {
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

    if (lifecycleState is RideActive && lifecycleState.actionError != null) {
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

    final String title = switch (lifecycleState) {
      RideActive(:final ride) => _getStateTitle(ride.status),
      RideCompleted() => 'Ride Completed',
      RideCancelled() => 'Ride Cancelled',
      _ => 'Ride Status',
    };

    final Place? pickupPlace = ride != null
        ? _placeFromRide(
            id: 'pickup',
            name: 'Pickup',
            address: ride.pickupAddress,
            lat: ride.pickupLatitude,
            lng: ride.pickupLongitude,
          )
        : null;

    final Place? dropoffPlace = ride != null
        ? _placeFromRide(
            id: 'dropoff',
            name: 'Dropoff',
            address: ride.dropoffAddress,
            lat: ride.dropoffLatitude,
            lng: ride.dropoffLongitude,
          )
        : null;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          leading: const SizedBox.shrink(),
          centerTitle: true,
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: primaryColor,
        ),
        body: Stack(
          children: [
            MapViewWidget(
              onMapCreated: _onMapCreated,
              pickupPlace: pickupPlace,
              dropoffPlace: dropoffPlace,
              trackingMode: true,
            ),
            if (lifecycleState is RideActive)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildActionPanel(context, lifecycleState),
              ),
            if (lifecycleState is RideIdle || lifecycleState is RideRequesting)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildLoadingPanel(),
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

  Widget _buildLoadingPanel() {
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
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
            const SizedBox(height: 24),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading ride details...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel(BuildContext context, RideActive state) {
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
              const SizedBox(height: 16),
              _buildLifecycleStepper(state.ride.status),
              const SizedBox(height: 16),
              _buildAddressRows(state.ride),
              const SizedBox(height: 12),
              _buildRideDetails(state.ride),
              const SizedBox(height: 16),
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

  Widget _buildLifecycleStepper(String currentStatus) {
    final steps = [
      _StepData('Accepted', Icons.check_circle_outline, RideStatus.accepted),
      _StepData('Arrived', Icons.location_on, RideStatus.driverArrived),
      _StepData('In Progress', Icons.directions_car, RideStatus.inProgress),
      _StepData('Completed', Icons.flag, RideStatus.completed),
    ];

    int currentIndex = steps.indexWhere((s) => s.status == currentStatus);
    if (currentIndex < 0) currentIndex = 0;

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftStepIndex = i ~/ 2;
          final isCompleted = leftStepIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 3,
              color: isCompleted ? primaryColor : Colors.grey[300],
            ),
          );
        }

        final stepIndex = i ~/ 2;
        final step = steps[stepIndex];
        final isCompleted = stepIndex < currentIndex;
        final isCurrent = stepIndex == currentIndex;

        final Color circleColor;
        final Color iconColor;
        if (isCompleted) {
          circleColor = primaryColor;
          iconColor = Colors.white;
        } else if (isCurrent) {
          circleColor = primaryColor.withOpacity(0.15);
          iconColor = primaryColor;
        } else {
          circleColor = Colors.grey[200]!;
          iconColor = Colors.grey[400]!;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleColor,
                border: isCurrent
                    ? Border.all(color: primaryColor, width: 2)
                    : null,
              ),
              child: Icon(
                isCompleted ? Icons.check : step.icon,
                size: 16,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step.label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent
                    ? primaryColor
                    : isCompleted
                        ? Colors.black87
                        : Colors.grey[400],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildAddressRows(Ride ride) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ride.pickupAddress ?? 'Pickup Location',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 2,
              height: 20,
              color: Colors.grey[300],
            ),
          ),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ride.dropoffAddress ?? 'Dropoff Location',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
                  'MK${(ride.actualFare ?? ride.estimatedFare).toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          if (ride.passengerNotes != null &&
              ride.passengerNotes!.isNotEmpty) ...[
            Container(width: 1, height: 40, color: Colors.grey[300]),
            Flexible(
              child: Column(
                children: [
                  Text('Notes',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(ride.passengerNotes!,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAcceptedStateActions(BuildContext context, RideActive state) {
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
        _buildActionButton(
          label: 'Mark as Arrived',
          icon: Icons.check_circle,
          isLoading: state.isLoading,
          onPressed: () async {
            await ref.read(rideLifecycleProvider.notifier).markArrived();
          },
        ),
        const SizedBox(height: 10),
        _buildCancelButton(state),
      ],
    );
  }

  Widget _buildArrivedStateActions(BuildContext context, RideActive state) {
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
                  'Waiting for passenger to board',
                  style: TextStyle(color: Colors.green[700]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          label: 'Start Ride',
          icon: Icons.play_arrow,
          isLoading: state.isLoading,
          onPressed: () async {
            await ref.read(rideLifecycleProvider.notifier).startRide();
          },
        ),
        const SizedBox(height: 10),
        _buildCancelButton(state),
      ],
    );
  }

  Widget _buildInProgressStateActions(BuildContext context, RideActive state) {
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
              Icon(Icons.directions_car, color: Colors.orange[700], size: 20),
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
        _buildActionButton(
          label: 'Complete Ride',
          icon: Icons.flag,
          isLoading: state.isLoading,
          onPressed: () async {
            await ref.read(rideLifecycleProvider.notifier).completeRide();
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildCancelButton(RideActive state) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: state.isLoading
            ? null
            : () => _handleCancelRide(context),
        icon: const Icon(Icons.close, size: 20),
        label: const Text(
          'Cancel Ride',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _handleCancelRide(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: const Text(
            'Are you sure you want to cancel this ride? The passenger will be notified.'),
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
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

/// Summary screen shown to the driver after completing a ride.
class _DriverRideCompletionScreen extends StatefulWidget {
  final Ride ride;
  final VoidCallback onDone;

  const _DriverRideCompletionScreen({
    required this.ride,
    required this.onDone,
  });

  @override
  State<_DriverRideCompletionScreen> createState() =>
      _DriverRideCompletionScreenState();
}

class _DriverRideCompletionScreenState
    extends State<_DriverRideCompletionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  static const Color primaryColor = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final totalFare = r.actualFare ?? r.estimatedFare;
    final distance = r.actualDistance ?? r.estimatedDistance;

    return Scaffold(
      body: ScaleTransition(
        scale: _scaleAnimation,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 60),

                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
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
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Great job on this trip',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Trip Summary',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
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

                      _summaryRow('Distance',
                          '${distance.toStringAsFixed(1)} km'),
                      const SizedBox(height: 12),

                      _summaryRow('Pickup',
                          r.pickupAddress ?? 'Unknown'),
                      const SizedBox(height: 8),
                      _summaryRow('Dropoff',
                          r.dropoffAddress ?? 'Unknown'),

                      const SizedBox(height: 12),
                      Container(height: 1, color: Colors.grey[300]),
                      const SizedBox(height: 16),

                      Text(
                        'Earnings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),

                      _summaryRow('Base Fare',
                          'MK${(totalFare * 0.2).toStringAsFixed(0)}'),
                      const SizedBox(height: 8),
                      _summaryRow(
                          'Distance (${distance.toStringAsFixed(1)} km)',
                          'MK${(totalFare * 0.8).toStringAsFixed(0)}'),

                      const SizedBox(height: 12),
                      Container(height: 1, color: Colors.grey[300]),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Earned',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'MK${totalFare.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onDone();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _StepData {
  final String label;
  final IconData icon;
  final String status;
  const _StepData(this.label, this.icon, this.status);
}
