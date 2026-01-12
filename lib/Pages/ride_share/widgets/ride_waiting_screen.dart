import 'package:flutter/material.dart';
import 'package:vero360_app/services/firebase_ride_share_service.dart';

class RideWaitingScreen extends StatefulWidget {
  final String rideId;
  final Function(Driver) onRideAccepted;
  final VoidCallback onCancelRide;

  const RideWaitingScreen({
    required this.rideId,
    required this.onRideAccepted,
    required this.onCancelRide,
  });

  @override
  State<RideWaitingScreen> createState() => _RideWaitingScreenState();
}

class _RideWaitingScreenState extends State<RideWaitingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dotController;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _dotController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RideRequest?>(
      stream: FirebaseRideShareService.getRideRequestStream(widget.rideId),
      builder: (context, snapshot) {
        final ride = snapshot.data;

        // If driver accepted the ride
        if (ride != null &&
            ride.driverId != null &&
            ride.status == 'accepted') {
          return StreamBuilder<Driver?>(
            stream:
                FirebaseRideShareService.getDriverProfileStream(ride.driverId!),
            builder: (context, driverSnapshot) {
              if (driverSnapshot.hasData && driverSnapshot.data != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.onRideAccepted(driverSnapshot.data!);
                  Navigator.pop(context);
                });
              }
              return const SizedBox.shrink();
            },
          );
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.4,
          maxChildSize: 0.6,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Drag Handle
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Animated Search Pulse
                      ScaleTransition(
                        scale: Tween<double>(begin: 1, end: 1.3).animate(
                          CurvedAnimation(
                            parent: _pulseController,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF8A00).withOpacity(0.1),
                          ),
                          child: const Icon(
                            Icons.car_rental,
                            size: 40,
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Status Text
                      const Text(
                        'Finding Driver',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Loading Dots
                      SizedBox(
                        height: 20,
                        child: LoadingDots(controller: _dotController),
                      ),
                      const SizedBox(height: 32),

                      // Ride Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey[200]!,
                          ),
                        ),
                        child: Column(
                          children: [
                            if (ride != null) ...[
                              _buildInfoRow(
                                'Pickup',
                                ride.pickupAddress,
                                Icons.location_on_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                'Dropoff',
                                ride.dropoffAddress,
                                Icons.location_on,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                'Estimated Fare',
                                'MWK${ride.estimatedFare.toStringAsFixed(2)}',
                                Icons.wallet_outlined,
                              ),
                              const SizedBox(height: 12),
                              _buildInfoRow(
                                'Estimated Time',
                                '${ride.estimatedTime} mins',
                                Icons.schedule,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Cancel Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _isCancelling
                              ? null
                              : () {
                                  setState(() => _isCancelling = true);
                                  FirebaseRideShareService.cancelRideRequest(
                                    widget.rideId,
                                  ).then((_) {
                                    widget.onCancelRide();
                                  }).catchError((_) {
                                    if (mounted) {
                                      setState(() => _isCancelling = false);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Failed to cancel ride. Please try again.',
                                          ),
                                        ),
                                      );
                                    }
                                  });
                                },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFFFF8A00),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isCancelling
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
                              : const Text(
                                  'Cancel Ride',
                                  style: TextStyle(
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
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: const Color(0xFFFF8A00),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
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
}

class LoadingDots extends StatelessWidget {
  final AnimationController controller;

  const LoadingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final offset = index * 0.2;
        return ScaleTransition(
          scale: Tween<double>(begin: 0.5, end: 1).animate(
            CurvedAnimation(
              parent: controller,
              curve: Interval(
                offset,
                offset + 0.6,
                curve: Curves.easeInOut,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF8A00),
              ),
            ),
          ),
        );
      }),
    );
  }
}
