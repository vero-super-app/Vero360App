import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_pricing_service.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/models/car_booking_model.dart';
import 'package:vero360_app/models/rental_cost_model.dart';
import 'car_list_page.dart';

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

  @override
  void initState() {
    super.initState();
    final pricingService = CarPricingService();

    // Calculate final cost including any late fees
    final actualReturn = DateTime.now();
    _finalCost = pricingService.calculateFinalBill(
      baseCost: widget.booking.totalCost,
      dailyRate: widget.car.dailyRate,
      days: widget.booking.endDate.difference(widget.booking.startDate).inDays.abs() + 1,
      actualReturn: actualReturn,
      scheduledReturn: widget.booking.endDate,
      lateFeePerDay: widget.car.dailyRate * 0.5, // 50% of daily rate as late fee
    );
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
                  // TODO: Implement receipt/invoice download
                },
                icon: const Icon(Icons.download),
                label: const Text('Download Receipt'),
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
