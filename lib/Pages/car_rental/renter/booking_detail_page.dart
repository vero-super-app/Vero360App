import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/providers/rental_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/Pages/car_rental/widgets/status_badge_widget.dart';
import 'package:vero360_app/Pages/car_rental/widgets/cost_breakdown_widget.dart';
import 'package:vero360_app/Pages/car_rental/widgets/rating_widget.dart';
import 'package:vero360_app/models/car_booking_model.dart';

class BookingDetailPage extends ConsumerWidget {
  final int bookingId;

  const BookingDetailPage({
    Key? key,
    required this.bookingId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(bookingDetailsFutureProvider(bookingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
        elevation: 0,
      ),
      body: bookingAsync.when(
        data: (booking) => SingleChildScrollView(
          child: Column(
            children: [
              // Header section with status
              _buildHeader(context, booking),
              // Car information
              _buildCarSection(context, booking),
              // Rental period
              _buildRentalPeriodSection(context, booking),
              // Cost breakdown
              _buildCostSection(context, booking),
              // Status timeline
              _buildStatusTimeline(context, booking),
              // Trip information (if active/completed)
              if (booking.isActive || booking.isCompleted)
                _buildTripInfoSection(context),
              // Actions
              _buildActionsSection(context, booking),
              const SizedBox(height: 32),
            ],
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                CarHireErrorHandler.getErrorMessage(error as Exception),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CarBookingModel booking) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Booking #${booking.id}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              StatusBadgeWidget(status: booking.statusString),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Created: ${CarHireFormatters.formatDateTime(booking.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarSection(BuildContext context, CarBookingModel booking) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Car Information',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          if (booking.carImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                booking.carImage!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildImagePlaceholder(),
              ),
            )
          else
            _buildImagePlaceholder(),
          const SizedBox(height: 16),
          Text(
            '${booking.carBrand ?? 'Unknown'} ${booking.carModel ?? ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // Owner info (placeholder - would need owner data in model)
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[300],
                child: Icon(Icons.person, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Owner Information',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View owner details',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.star, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text('4.8', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.directions_car,
        color: Colors.grey[400],
        size: 64,
      ),
    );
  }

  Widget _buildRentalPeriodSection(BuildContext context, CarBookingModel booking) {
    final rentalDays = booking.endDate.difference(booking.startDate).inDays + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rental Period',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CarHireFormatters.formatDateTime(booking.startDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CarHireFormatters.formatDateTime(booking.endDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Total: $rentalDays day${rentalDays > 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostSection(BuildContext context, CarBookingModel booking) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: CostBreakdownWidget(
        baseCost: booking.totalCost * 0.85,
        insurance: booking.totalCost * 0.10,
        surcharges: booking.totalCost * 0.05,
        total: booking.totalCost,
      ),
    );
  }

  Widget _buildStatusTimeline(BuildContext context, CarBookingModel booking) {
    final statuses = [
      ('Created', booking.createdAt),
      ('Confirmed', booking.status.index >= BookingStatus.confirmed.index
          ? booking.updatedAt
          : null),
      ('Started', booking.isActive || booking.isCompleted
          ? booking.createdAt.add(const Duration(days: 1))
          : null),
      ('Completed', booking.isCompleted ? booking.updatedAt : null),
    ];

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status Timeline',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: statuses.length,
            separatorBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 20,
                width: 2,
                color: statuses[index + 1].$2 != null
                    ? Colors.green
                    : Colors.grey[300],
              ),
            ),
            itemBuilder: (context, index) {
              final (label, timestamp) = statuses[index];
              final isCompleted = timestamp != null;

              return Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted ? Colors.green : Colors.grey[300],
                      border: Border.all(
                        color: isCompleted ? Colors.green : Colors.grey[400]!,
                        width: 2,
                      ),
                    ),
                    child: isCompleted
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 14,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (timestamp != null)
                          Text(
                            CarHireFormatters.formatDateTime(timestamp),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfoSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip Information',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _tripInfoRow(context, 'Total KM Driven', '285 km'),
          const SizedBox(height: 12),
          _tripInfoRow(context, 'Trip Duration', '4h 32m'),
          const SizedBox(height: 12),
          _tripInfoRow(context, 'Fuel Status', '75%'),
        ],
      ),
    );
  }

  Widget _tripInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildActionsSection(BuildContext context, CarBookingModel booking) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (booking.isPending)
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Booking cancelled')),
                    );
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel Booking'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            )
          else if (booking.isConfirmed)
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rental started')),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Rental'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 48),
              ),
            )
          else if (booking.isActive)
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rental ended')),
                );
              },
              icon: const Icon(Icons.stop),
              label: const Text('End Rental'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(double.infinity, 48),
              ),
            )
          else if (booking.isCompleted)
            Column(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    // Show rating dialog
                    _showRatingDialog(context);
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('Rate Owner'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Receipt downloading...')),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download Receipt'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showRatingDialog(BuildContext context) {
    double _rating = 0;
    final reviewController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Rate Your Experience'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text('How would you rate this car?'),
              const SizedBox(height: 12),
              StarRatingInput(
                initialRating: _rating,
                onRatingChanged: (rating) {
                  setState(() => _rating = rating);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reviewController,
                decoration: InputDecoration(
                  hintText: 'Write a review (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                reviewController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                reviewController.dispose();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Thank you for your review!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
