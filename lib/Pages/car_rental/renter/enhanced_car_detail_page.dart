import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/Pages/car_rental/widgets/rating_widget.dart';
import 'package:vero360_app/Pages/car_rental/widgets/cost_breakdown_widget.dart';
import 'package:vero360_app/Pages/car_rental/utils/car_rental_colors.dart';

class EnhancedCarDetailPage extends ConsumerStatefulWidget {
  final CarModel car;

  const EnhancedCarDetailPage({
    Key? key,
    required this.car,
  }) : super(key: key);

  @override
  ConsumerState<EnhancedCarDetailPage> createState() =>
      _EnhancedCarDetailPageState();
}

class _EnhancedCarDetailPageState extends ConsumerState<EnhancedCarDetailPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _includeInsurance = false;

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

  void _proceedToPayment() {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select rental dates')),
      );
      return;
    }

    // TODO: Navigate to payment page
    Navigator.of(context).pushNamed(
      '/rental/payment',
      arguments: {
        'car': widget.car,
        'startDate': _startDate,
        'endDate': _endDate,
        'includeInsurance': _includeInsurance,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rentalDays = _startDate != null && _endDate != null
        ? _endDate!.difference(_startDate!).inDays + 1
        : 0;
    
    final totalCost = rentalDays > 0
        ? (widget.car.dailyRate * rentalDays).toInt() +
            (_includeInsurance ? 5000 * rentalDays : 0)
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Car Details'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Car Image
            Container(
              width: double.infinity,
              height: 250,
              color: Colors.grey[300],
              child: widget.car.imageUrl != null
                  ? Image.network(widget.car.imageUrl!, fit: BoxFit.cover)
                  : Icon(Icons.directions_car, size: 100, color: Colors.grey[600]),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Car Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.car.brand} ${widget.car.model}',
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                          Text(
                            widget.car.licensePlate,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: CarRentalColors.successLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Available',
                          style: TextStyle(
                            color: CarRentalColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Daily Rate
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daily Rate',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        CarHireFormatters.formatCurrency(widget.car.dailyRate),
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: CarRentalColors.brandOrange,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Owner Information Section
                  Text(
                    'Owner Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CarRentalColors.brandOrangePale,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: CarRentalColors.brandOrange,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.car.ownerName ?? 'Car Owner',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                RatingWidget(
                                  rating: widget.car.rating ?? 4.5,
                                  reviewCount: widget.car.reviews ?? 12,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Response time: 2 hours',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CarRentalColors.successLight,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(
                              Icons.verified,
                              color: CarRentalColors.success,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Implement contact owner
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Contact feature coming soon'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.mail),
                      label: const Text('Contact Owner'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Car Specifications
                  Text(
                    'Specifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSpecCard(
                        context,
                        'Seats',
                        '${widget.car.seats}',
                        Icons.person,
                      ),
                      _buildSpecCard(
                        context,
                        'Fuel Type',
                        widget.car.fuelType,
                        Icons.local_gas_station,
                      ),
                      _buildSpecCard(
                        context,
                        'Year',
                        widget.car.year.toString(),
                        Icons.calendar_today,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    'About This Car',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.car.description ?? 'No description provided',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Reviews Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Reviews',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: Navigate to all reviews
                        },
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Sample Review
                  _buildReviewCard(
                    context,
                    'John Doe',
                    5.0,
                    'Excellent car! Very clean and well-maintained. Highly recommended.',
                    '2 weeks ago',
                  ),
                  const SizedBox(height: 8),
                  _buildReviewCard(
                    context,
                    'Jane Smith',
                    4.5,
                    'Good experience. Responsive owner and reliable car.',
                    '1 month ago',
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Rental Period Selection
                  Text(
                    'Select Rental Period',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  // Start Date
                  GestureDetector(
                    onTap: _selectStartDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start Date',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              Text(
                                _startDate != null
                                    ? CarHireFormatters.formatDate(_startDate!)
                                    : 'Select date',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Icon(Icons.calendar_today, color: CarRentalColors.brandOrange),
                          ],
                          ),
                          ),
                          ),
                          const SizedBox(height: 12),

                          // End Date
                          GestureDetector(
                          onTap: _selectEndDate,
                          child: Container(
                          padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                          ),
                          decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'End Date',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              Text(
                                _endDate != null
                                    ? CarHireFormatters.formatDate(_endDate!)
                                    : 'Select date',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Icon(Icons.calendar_today, color: CarRentalColors.brandOrange),
                        ],
                      ),
                    ),
                  ),
                  if (rentalDays > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                        '$rentalDays days selected',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: CarRentalColors.brandOrange),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Insurance Option
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _includeInsurance,
                            onChanged: (value) {
                              setState(() => _includeInsurance = value ?? false);
                            },
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add Insurance Coverage',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'MWK 5,000/day - Full coverage',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Cost Breakdown (if dates selected)
                  if (rentalDays > 0) ...[
                    Text(
                      'Cost Summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Daily Rate × $rentalDays days',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium),
                                Text(
                                  CarHireFormatters.formatCurrency(
                                    widget.car.dailyRate * rentalDays,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            if (_includeInsurance) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Insurance × $rentalDays days',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                  Text(
                                    CarHireFormatters.formatCurrency(5000 *
                                        rentalDays.toDouble()),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  CarHireFormatters.formatCurrency(
                                    totalCost.toDouble(),
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Book Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          rentalDays > 0 ? _proceedToPayment : null,
                      child: const Text('Proceed to Payment'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 28, color: CarRentalColors.brandOrange),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(
    BuildContext context,
    String name,
    double rating,
    String review,
    String timeAgo,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  timeAgo,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            RatingWidget(rating: rating, reviewCount: 0),
            const SizedBox(height: 8),
            Text(
              review,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
