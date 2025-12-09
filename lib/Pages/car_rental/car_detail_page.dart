import 'package:flutter/material.dart';
import 'package:vero360_app/models/car_model.dart';
import 'booking_confirmation_page.dart';

class CarDetailPage extends StatefulWidget {
  final CarModel car;

  const CarDetailPage({
    required this.car,
    super.key,
  });

  @override
  State<CarDetailPage> createState() => _CarDetailPageState();
}

class _CarDetailPageState extends State<CarDetailPage> {
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start date first')),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate!.add(const Duration(days: 1)),
      firstDate: _startDate!.add(const Duration(days: 1)),
      lastDate: _startDate!.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  void _proceedToBooking() {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both dates')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingConfirmationPage(
          car: widget.car,
          startDate: _startDate!,
          endDate: _endDate!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.car.brand} ${widget.car.model}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Car Image
            if (widget.car.imageUrl != null && widget.car.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.car.imageUrl!,
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.directions_car, size: 120),
                    );
                  },
                ),
              )
            else
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_car, size: 120),
              ),
            const SizedBox(height: 24),

            // Car Details Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.car.brand} ${widget.car.model}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'License Plate: ${widget.car.licensePlate}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const Divider(height: 24),
                    _DetailRow('Seats', '${widget.car.seats}'),
                    _DetailRow('Fuel Type', widget.car.fuelType),
                    _DetailRow(
                      'Daily Rate',
                      'MWK${widget.car.dailyRate.toStringAsFixed(0)}',
                      highlighted: true,
                    ),
                    _DetailRow(
                      'GPS Tracker',
                      widget.car.gpsTrackerId.isNotEmpty ? 'Enabled' : 'N/A',
                    ),
                    if (widget.car.rating > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.car.rating.toStringAsFixed(1)} (${widget.car.reviews} reviews)',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Date Selection
            const Text(
              'Select Rental Dates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Start Date
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Start Date'),
                subtitle: Text(
                  _startDate == null
                      ? 'Not selected'
                      : _startDate!.toString().split(' ')[0],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _selectStartDate,
              ),
            ),
            const SizedBox(height: 12),

            // End Date
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('End Date'),
                subtitle: Text(
                  _endDate == null
                      ? 'Not selected'
                      : _endDate!.toString().split(' ')[0],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _selectEndDate,
              ),
            ),
            const SizedBox(height: 32),

            // Proceed Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _proceedToBooking,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: const Color(0xFFFF8A00),
                ),
                child: const Text(
                  'Proceed to Booking',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlighted;

  const _DetailRow(
    this.label,
    this.value, {
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
              fontSize: highlighted ? 16 : 14,
              color: highlighted ? const Color(0xFFFF8A00) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
