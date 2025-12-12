import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_pricing_service.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/models/car_booking_model.dart';
import 'package:vero360_app/models/rental_cost_model.dart';
import 'package:vero360_app/Pages/car_rental/widgets/rating_widget.dart';
import 'car_list_page.dart';

// Extension for payment row color coding
class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _PaymentRow(this.label, this.value, this.valueColor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class RentalCompletePage extends StatefulWidget {
  final CarBookingModel booking;
  final double totalDistance;
  final int elapsedSeconds;
  final CarModel car;

  const RentalCompletePage({
    required this.booking,
    required this.totalDistance,
    required this.elapsedSeconds,
    required this.car,
    Key? key,
  }) : super(key: key);

  @override
  State<RentalCompletePage> createState() => _RentalCompletePageState();
}

class _RentalCompletePageState extends State<RentalCompletePage> {
  late RentalCostModel _finalCost;
  double _carRating = 0;
  double _ownerRating = 0;
  late TextEditingController _reviewController;
  bool _showRatingSection = false;

  @override
  void initState() {
    super.initState();
    _reviewController = TextEditingController();
    final pricingService = CarPricingService();

    // Calculate final cost including any late fees
    final actualReturn = DateTime.now();
    _finalCost = pricingService.calculateFinalBill(
      baseCost: widget.booking.totalCost,
      dailyRate: widget.car.dailyRate,
      days: widget.booking.endDate
              .difference(widget.booking.startDate)
              .inDays
              .abs() +
          1,
      actualReturn: actualReturn,
      scheduledReturn: widget.booking.endDate,
      lateFeePerDay:
          widget.car.dailyRate * 0.5, // 50% of daily rate as late fee
    );
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _backToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CarListPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wasLate = DateTime.now().isAfter(widget.booking.endDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Complete'),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Success icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 80,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'Rental Completed Successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Late fee warning if applicable
            if (wasLate)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  'Late return fee applied: ${_finalCost.lateFeeFormatted}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Trip summary card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 24),
                    _SummaryRow(
                      'Vehicle',
                      '${widget.car.brand} ${widget.car.model}',
                    ),
                    _SummaryRow(
                      'License Plate',
                      widget.car.licensePlate,
                    ),
                    _SummaryRow(
                      'Rental Period',
                      '${widget.booking.startDate.toString().split(' ')[0]} to ${widget.booking.endDate.toString().split(' ')[0]}',
                    ),
                    _SummaryRow(
                      'Duration',
                      _formatDuration(widget.elapsedSeconds),
                    ),
                    _SummaryRow(
                      'Distance Traveled',
                      '${widget.totalDistance.toStringAsFixed(2)} km',
                    ),
                    if (widget.totalDistance > 0)
                      _SummaryRow(
                        'Avg. Speed',
                        '${(widget.totalDistance / (widget.elapsedSeconds / 3600)).toStringAsFixed(1)} km/h',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Cost breakdown card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Final Bill',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Base Rental Cost'),
                        Text(_finalCost.baseFormatted),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_finalCost.lateFee > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Late Return Fee'),
                            Text(
                              _finalCost.lateFeeFormatted,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    if (_finalCost.otherCharges > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Other Charges'),
                            Text(
                              'MWK${_finalCost.otherCharges.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount Due',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _finalCost.totalFormatted,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFFFF8A00),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Payment confirmation section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Confirmation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 24),
                    _PaymentRow(
                      'Status',
                      'Paid',
                      Colors.green,
                    ),
                    _PaymentRow(
                      'Transaction ID',
                      'TXN${DateTime.now().millisecondsSinceEpoch}',
                      Colors.grey,
                    ),
                    _PaymentRow(
                      'Payment Method',
                      'Debit Card',
                      Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Car condition report
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Car Condition Report',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Owner\'s Inspection Notes:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Vehicle returned in good condition. No visible damages. All systems functioning properly.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[300]!),
                      ),
                      child: Text(
                        '✓ Claim Status: No claims',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Rating and review section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Rate Your Experience',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_showRatingSection)
                          GestureDetector(
                            onTap: () {
                              setState(() =>
                                  _showRatingSection = !_showRatingSection);
                            },
                            child: const Icon(Icons.edit, color: Colors.blue),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (_showRatingSection) ...[
                      Text(
                        'How would you rate the car?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),
                      StarRatingInput(
                        initialRating: _carRating,
                        onRatingChanged: (rating) {
                          setState(() => _carRating = rating);
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'How would you rate the owner?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),
                      StarRatingInput(
                        initialRating: _ownerRating,
                        onRatingChanged: (rating) {
                          setState(() => _ownerRating = rating);
                        },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _reviewController,
                        decoration: InputDecoration(
                          hintText: 'Write your review (optional)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _showRatingSection = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Thank you for your review!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          child: const Text('Submit Review'),
                        ),
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Car Rating',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (_carRating > 0)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _carRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  'Not rated',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Owner Rating',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (_ownerRating > 0)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _ownerRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  'Not rated',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _backToHome,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: const Color(0xFFFF8A00),
                ),
                child: const Text(
                  'Back to Home',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Receipt downloaded successfully')),
                  );
                },
                icon: const Icon(Icons.download),
                label: const Text('Download Receipt'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Receipt sent to email')),
                  );
                },
                icon: const Icon(Icons.email),
                label: const Text('Email Receipt'),
              ),
            ),
            const SizedBox(height: 24),

            // Footer text
            Center(
              child: Text(
                'Thank you for using our car rental service!',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
