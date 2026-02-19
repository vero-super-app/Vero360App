import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';

class RideWaitingScreen extends StatefulWidget {
  final String rideId;
  final Function(DriverInfo) onRideAccepted;
  final VoidCallback onCancelRide;
  final double? pickupLat;
  final double? pickupLng;
  final RideShareHttpService? httpService;

  const RideWaitingScreen({
    super.key,
    required this.rideId,
    required this.onRideAccepted,
    required this.onCancelRide,
    this.pickupLat,
    this.pickupLng,
    this.httpService,
  });

  @override
  State<RideWaitingScreen> createState() => _RideWaitingScreenState();
}

class _RideWaitingScreenState extends State<RideWaitingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dotController;
  bool _isCancelling = false;
  bool _callbackTriggered = false;

  static const Color primaryColor = Color(0xFFFF8A00);

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
    final httpService = widget.httpService ?? RideShareHttpService();
    final rideId = int.tryParse(widget.rideId) ?? 0;

    return StreamBuilder<Ride>(
      stream: httpService.rideUpdateStream,
      builder: (context, snapshot) {
        final ride = snapshot.data;
        
        print('[RideWaitingScreen] Stream update: ride=$ride, hasData=${snapshot.hasData}, error=${snapshot.error}');
        if (ride != null) {
          print('[RideWaitingScreen] Ride received: id=${ride.id}, status=${ride.status}, driverId=${ride.driverId}');
        }

        // If driver accepted the ride
        if (ride != null &&
            ride.driverId != null &&
            ride.status == RideStatus.accepted) {
          print('[RideWaitingScreen] ✅ Driver accepted! Triggering callback...');
          if (!_callbackTriggered && ride.driver != null) {
            _callbackTriggered = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                print('[RideWaitingScreen] Calling onRideAccepted with driver: ${ride.driver!.name}');
                // Pop first, then trigger callback to avoid context issues
                Navigator.pop(context);
                // Small delay to ensure modal is fully dismissed
                Future.delayed(const Duration(milliseconds: 100), () {
                  widget.onRideAccepted(ride.driver!);
                });
              }
            });
          }
          return const SizedBox.shrink();
        }

        return PopScope(
          canPop: false,
          child: GestureDetector(
            onTap: () {}, // Prevent dismissal by tapping outside
            child: DraggableScrollableSheet(
              initialChildSize: 0.80,
              minChildSize: 0.80,
              maxChildSize: 0.80,
              builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                   BoxShadow(
                     color: Colors.black.withValues(alpha: 0.1),
                     blurRadius: 24,
                     offset: const Offset(0, -4),
                   ),
                 ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Drag Handle
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Main content
                      Column(
                        children: [
                          // Title
                          const Text(
                            'Finding your driver',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 24),

                          // Animated Search Pulse with larger size
                          ScaleTransition(
                            scale: Tween<double>(begin: 1, end: 1.2).animate(
                              CurvedAnimation(
                                parent: _pulseController,
                                curve: Curves.easeInOut,
                              ),
                            ),
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: primaryColor.withValues(alpha: 0.08),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.15),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.directions_car_rounded,
                                size: 48,
                                color: primaryColor,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Loading Dots
                          SizedBox(
                            height: 12,
                            child: LoadingDots(controller: _dotController),
                          ),

                          const SizedBox(height: 20),

                          // Subtitle
                          Text(
                            'We\'re searching for nearby drivers',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 32),

                          // Ride Info Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                if (ride != null) ...[
                                  _buildInfoRow(
                                    'Pickup Location',
                                    ride.pickupAddress ?? 'Pickup Location',
                                    Icons.location_on_rounded,
                                    primaryColor,
                                  ),
                                  const SizedBox(height: 16),
                                  Divider(color: Colors.grey[200]),
                                  const SizedBox(height: 16),
                                  _buildInfoRow(
                                    'Dropoff Location',
                                    ride.dropoffAddress ?? 'Dropoff Location',
                                    Icons.location_on_rounded,
                                    primaryColor,
                                  ),
                                  const SizedBox(height: 16),
                                  Divider(color: Colors.grey[200]),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildInfoRow(
                                          'Estimated Fare',
                                          'MK${ride.estimatedFare.toStringAsFixed(0)}',
                                          Icons.wallet_giftcard_rounded,
                                          primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: _buildInfoRow(
                                          'Estimated Distance',
                                          '${ride.estimatedDistance.toStringAsFixed(1)} km',
                                          Icons.schedule_rounded,
                                          primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Cancel Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isCancelling
                                  ? null
                                  : () {
                                      setState(() => _isCancelling = true);
                                      httpService
                                          .cancelRide(rideId)
                                          .then((_) {
                                        widget.onCancelRide();
                                      }).catchError((_) {
                                        if (mounted) {
                                          setState(() => _isCancelling = false);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                  'Failed to cancel ride',
                                                ),
                                                backgroundColor: Colors.red[400],
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                margin: const EdgeInsets.all(16),
                                              ),
                                            );
                                          }
                                        }
                                      });
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: primaryColor,
                                    width: 2,
                                  ),
                                ),
                                disabledBackgroundColor: Colors.grey[100],
                              ),
                              child: _isCancelling
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
                                  : const Text(
                                      'Cancel Ride',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: primaryColor,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: iconColor,
          ),
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
 
   const LoadingDots({super.key, required this.controller});

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
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Container(
              width: 10,
              height: 10,
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
