import 'package:flutter/material.dart';
import 'package:vero360_app/services/firebase_ride_share_service.dart';

class RideActiveDialog extends StatefulWidget {
  final Driver driver;
  final VoidCallback onRideCompleted;

  const RideActiveDialog({
    required this.driver,
    required this.onRideCompleted,
  });

  @override
  State<RideActiveDialog> createState() => _RideActiveDialogState();
}

class _RideActiveDialogState extends State<RideActiveDialog>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  int _currentStep = 0;

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

    // Auto-progress through steps
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _currentStep < 2) {
        setState(() => _currentStep++);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey[50]!,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close Button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                      ),
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Driver Avatar
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF8A00),
                      width: 3,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundImage: widget.driver.avatar.isNotEmpty
                        ? NetworkImage(widget.driver.avatar)
                        : null,
                    child: widget.driver.avatar.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 50,
                            color: Color(0xFFFF8A00),
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 20),

                // Driver Name & Rating
                Text(
                  widget.driver.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: Colors.amber[600],
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.driver.rating.toStringAsFixed(1)} (${widget.driver.completedRides} rides)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Vehicle Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF8A00).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_car,
                        size: 32,
                        color: const Color(0xFFFF8A00),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.driver.vehicleType.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.driver.vehiclePlate,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Progress Steps
                _buildProgressSteps(),
                const SizedBox(height: 28),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          // Call driver
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(
                            color: Color(0xFFFF8A00),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.call,
                              color: Color(0xFFFF8A00),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Call',
                              style: TextStyle(
                                color: Color(0xFFFF8A00),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Open chat or message
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8A00),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.message,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Message',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Complete Ride Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _currentStep == 2
                        ? () {
                            widget.onRideCompleted();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _currentStep == 2 ? Colors.green : Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _currentStep == 2 ? 'Complete Ride' : 'En Route...',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSteps() {
    final steps = [
      ('Driver Arriving', Icons.directions_car),
      ('Driver Arrived', Icons.check_circle),
      ('Complete Ride', Icons.flag),
    ];

    return Column(
      children: List.generate(steps.length, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Column(
          children: [
            Row(
              children: [
                // Step Circle
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted || isCurrent
                        ? const Color(0xFFFF8A00)
                        : Colors.grey[300],
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 20,
                          )
                        : AnimatedBuilder(
                            animation: _animController,
                            builder: (context, child) {
                              if (isCurrent) {
                                return Transform.scale(
                                  scale: 1 - (_animController.value * 0.2),
                                  child: Icon(
                                    steps[index].$2,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                );
                              }
                              return Icon(
                                steps[index].$2,
                                color: Colors.grey[500],
                                size: 20,
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 16),

                // Step Text
                Expanded(
                  child: Text(
                    steps[index].$1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCompleted || isCurrent
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isCompleted || isCurrent
                          ? Colors.black87
                          : Colors.grey[400],
                    ),
                  ),
                ),
              ],
            ),
            if (index < steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Container(
                  width: 2,
                  height: 20,
                  color: isCurrent ? const Color(0xFFFF8A00) : Colors.grey[300],
                ),
              ),
          ],
        );
      }),
    );
  }
}
