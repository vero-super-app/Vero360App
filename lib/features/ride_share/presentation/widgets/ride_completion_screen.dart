import 'package:flutter/material.dart';

class RideCompletionScreen extends StatefulWidget {
  final double baseFare;
  final double distanceFare;
  final double totalFare;
  final double distance;
  final int duration;
  final String driverName;
  final double driverRating;
  final VoidCallback onPaymentCompleted;

  const RideCompletionScreen({
    required this.baseFare,
    required this.distanceFare,
    required this.totalFare,
    required this.distance,
    required this.duration,
    required this.driverName,
    required this.driverRating,
    required this.onPaymentCompleted,
  });

  @override
  State<RideCompletionScreen> createState() => _RideCompletionScreenState();
}

class _RideCompletionScreenState extends State<RideCompletionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isProcessingPayment = false;

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

  void _handleProceedToPayment() {
    setState(() => _isProcessingPayment = true);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        widget.onPaymentCompleted();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ScaleTransition(
        scale: _scaleAnimation,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Checkmark animation
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

                // Title
                const Text(
                  'Ride Complete!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),

                // Driver info
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Thanks to ${widget.driverName}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Colors.amber[600],
                    ),
                    Text(
                      widget.driverRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Trip Summary Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Trip details
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Trip Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          Text(
                            '${widget.duration} mins',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Distance row
                      _buildDetailRow(
                        label: 'Distance',
                        value: '${widget.distance.toStringAsFixed(2)} km',
                      ),
                      const SizedBox(height: 12),

                      // Divider
                      Container(
                        height: 1,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),

                      // Fare breakdown
                      Text(
                        'Fare Breakdown',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildFareRow(
                        label: 'Base Fare',
                        value: 'MK${widget.baseFare.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 8),

                      _buildFareRow(
                        label: 'Distance (${widget.distance.toStringAsFixed(2)} km)',
                        value: 'MK${widget.distanceFare.toStringAsFixed(0)}',
                      ),
                      const SizedBox(height: 12),

                      Container(
                        height: 1,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),

                      // Total fare
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Fare',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'MK${widget.totalFare.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF8A00),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Action buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isProcessingPayment ? null : _handleProceedToPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessingPayment
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Proceed to Payment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Skip button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFFFF8A00),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Rate Driver',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF8A00),
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

  Widget _buildDetailRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildFareRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
