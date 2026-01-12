import 'package:flutter/material.dart';
import 'package:vero360_app/services/driver_request_service.dart';
import 'package:vero360_app/services/driver_messaging_service.dart';

class DriverRequestAcceptDialog extends StatefulWidget {
  final DriverRideRequest request;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String? driverAvatar;
  final Function()? onAccepted;
  final Function()? onRejected;

  const DriverRequestAcceptDialog({
    Key? key,
    required this.request,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    this.driverAvatar,
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
      // Accept the ride request
      await DriverRequestService.acceptRideRequest(
        rideId: widget.request.id,
        driverId: widget.driverId,
        driverName: widget.driverName,
        driverPhone: widget.driverPhone,
        driverAvatar: widget.driverAvatar,
      );

      // Create messaging thread
      await DriverMessagingService.ensureRideThread(
        rideId: widget.request.id,
        passengerId: widget.request.passengerId,
        driverId: widget.driverId,
        passengerName: widget.request.passengerName,
        driverName: widget.driverName,
        passengerAvatar: null,
        driverAvatar: widget.driverAvatar,
      );

      // Send system message
      await DriverMessagingService.sendSystemMessage(
        rideId: widget.request.id,
        message: '${widget.driverName} accepted your ride request',
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onAccepted?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride request accepted')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept ride: ${e.toString()}'),
            backgroundColor: Colors.red,
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
          const SnackBar(content: Text('Ride request rejected')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRejecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject ride: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Alert Icon with pulse animation
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 1.2).animate(
                  CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF8A00).withOpacity(0.1),
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    size: 40,
                    color: Color(0xFFFF8A00),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'New Ride Request',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Passenger Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.grey[50],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Passenger name
                      Text(
                        'Passenger: ${widget.request.passengerName}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Pickup
                      _buildLocationRow(
                        icon: Icons.location_on_outlined,
                        label: 'Pickup',
                        address: widget.request.pickupAddress,
                      ),
                      const SizedBox(height: 12),

                      // Dropoff
                      _buildLocationRow(
                        icon: Icons.location_on,
                        label: 'Dropoff',
                        address: widget.request.dropoffAddress,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Fare and Time Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildInfoBox(
                      icon: Icons.wallet_outlined,
                      label: 'Estimated Fare',
                      value: 'MWK${widget.request.estimatedFare.toStringAsFixed(2)}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoBox(
                      icon: Icons.schedule,
                      label: 'Est. Time',
                      value: '${widget.request.estimatedTime} mins',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Distance info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildInfoBox(
                icon: Icons.straighten,
                label: 'Distance',
                value: '${widget.request.estimatedDistance.toStringAsFixed(2)} km',
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Accept Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isAccepting || _isRejecting
                          ? null
                          : _acceptRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A00),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isAccepting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isAccepting ? 'Accepting...' : 'Accept Ride',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reject Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isAccepting || _isRejecting
                          ? null
                          : _rejectRequest,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFFF8A00),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isRejecting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Color(0xFFFF8A00),
                                ),
                              ),
                            )
                          : const Icon(Icons.close_outlined),
                      label: Text(
                        _isRejecting ? 'Rejecting...' : 'Reject Ride',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF8A00),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFFF8A00)),
        const SizedBox(width: 8),
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
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 12,
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

  Widget _buildInfoBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFF8A00)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
