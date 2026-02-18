import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/driver_request_service.dart';
import 'package:vero360_app/GernalServices/driver_messaging_service.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_pickup_route_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_ride_active_screen.dart';

class DriverRequestAcceptDialog extends StatefulWidget {
  final DriverRideRequest request;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String? driverAvatar;
  final int? vehicleId;
  final Function()? onAccepted;
  final Function()? onRejected;

  const DriverRequestAcceptDialog({
    Key? key,
    required this.request,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    this.driverAvatar,
    this.vehicleId,
    this.onAccepted,
    this.onRejected,
  }) : super(key: key);

  @override
  State<DriverRequestAcceptDialog> createState() =>
      _DriverRequestAcceptDialogState();
}

class _DriverRequestAcceptDialogState extends State<DriverRequestAcceptDialog>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isAccepting = false;
  bool _isRejecting = false;
  static const Color primaryColor = Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptRequest() async {
    setState(() => _isAccepting = true);

    try {
      await DriverRequestService.acceptRideRequest(
        rideId: widget.request.id,
        driverId: widget.driverId,
        driverName: widget.driverName,
        driverPhone: widget.driverPhone,
        driverAvatar: widget.driverAvatar,
        vehicleId: widget.vehicleId,
      );

      // Try to create ride thread and send message, but don't fail if they error
      try {
        await DriverMessagingService.ensureRideThread(
          rideId: widget.request.id,
          passengerId: widget.request.passengerId,
          driverId: widget.driverId,
          passengerName: widget.request.passengerName,
          driverName: widget.driverName,
          passengerAvatar: null,
          driverAvatar: widget.driverAvatar,
        );

        await DriverMessagingService.sendSystemMessage(
          rideId: widget.request.id,
          message: '${widget.driverName} accepted your ride request',
        );
      } catch (e) {
        // Log but don't fail - messaging is non-critical
        print('Warning: Failed to create messaging thread: $e');
      }

      if (mounted) {
        Navigator.of(context).pop(true);

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DriverPickupRouteScreen(
              rideId: widget.request.id,
              passengerName: widget.request.passengerName,
              passengerPhone: widget.driverPhone,
              pickupAddress: widget.request.pickupAddress,
              pickupLat: widget.request.pickupLat,
              pickupLng: widget.request.pickupLng,
              driverLat: 0.0,
              driverLng: 0.0,
              estimatedFare: widget.request.estimatedFare,
              onArrived: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => DriverRideActiveScreen(
                      rideId: widget.request.id,
                      passengerName: widget.request.passengerName,
                      pickupAddress: widget.request.pickupAddress,
                      dropoffAddress: widget.request.dropoffAddress,
                      pickupLat: widget.request.pickupLat,
                      pickupLng: widget.request.pickupLng,
                      dropoffLat: widget.request.dropoffLat,
                      dropoffLng: widget.request.dropoffLng,
                      estimatedFare: widget.request.estimatedFare,
                      onRideCompleted: () {
                        widget.onAccepted?.call();
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ride request accepted! Navigate to pickup.'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept ride: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest() async {
    setState(() => _isRejecting = true);

    try {
      await DriverRequestService.rejectRideRequest(widget.request.id);

      if (mounted) {
        Navigator.of(context).pop(false);
        widget.onRejected?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ride request rejected'),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRejecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject ride: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top colored header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Animated Icon
                  ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 1.15).animate(
                      CurvedAnimation(
                        parent: _pulseController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      child: const Icon(
                        Icons.local_taxi,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'New Ride Request',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Passenger Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor.withOpacity(0.1),
                              ),
                              child: Icon(
                                Icons.person,
                                color: primaryColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.request.passengerName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Passenger',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(height: 1, color: Colors.grey[200]),
                        const SizedBox(height: 16),
                        _buildLocationRow(
                          icon: Icons.location_on_outlined,
                          label: 'Pickup',
                          address: widget.request.pickupAddress,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 12),
                        _buildLocationRow(
                          icon: Icons.location_on,
                          label: 'Dropoff',
                          address: widget.request.dropoffAddress,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Metrics Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.wallet_outlined,
                          label: 'Estimated Fare',
                          value:
                              'MK${widget.request.estimatedFare.toStringAsFixed(0)}',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.schedule,
                          label: 'Est. Time',
                          value: '${widget.request.estimatedTime} min',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.straighten,
                          label: 'Distance',
                          value:
                              '${widget.request.estimatedDistance.toStringAsFixed(1)} km',
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isAccepting || _isRejecting ? null : _acceptRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: _isAccepting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isAccepting ? 'Accepting...' : 'Accept Ride',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed:
                          _isAccepting || _isRejecting ? null : _rejectRequest,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _isRejecting ? Colors.grey : primaryColor,
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledForegroundColor: Colors.grey,
                      ),
                      icon: _isRejecting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(
                                  primaryColor,
                                ),
                              ),
                            )
                          : const Icon(Icons.close_outlined),
                      label: Text(
                        _isRejecting ? 'Rejecting...' : 'Reject Ride',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _isRejecting ? Colors.grey : primaryColor,
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

  Widget _buildLocationRow({
    required IconData icon,
    required String label,
    required String address,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
