import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/providers/car_hire_provider.dart';
import 'package:vero360_app/services/merchant_service.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/Pages/car_rental/widgets/status_badge_widget.dart';

class BookingRequestsPage extends ConsumerStatefulWidget {
  const BookingRequestsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<BookingRequestsPage> createState() => _BookingRequestsPageState();
}

class _BookingRequestsPageState extends ConsumerState<BookingRequestsPage> {
  final MerchantService _merchantService = MerchantService();

  Future<void> _confirmBooking(int bookingId) async {
    try {
      await _merchantService.confirmBooking(bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking confirmed'),
            backgroundColor: Colors.green,
          ),
        );
        ref.refresh(pendingBookingsFutureProvider);
      }
    } on Exception catch (e) {
      if (mounted) {
        CarHireErrorHandler.showErrorSnackbar(context, e);
      }
    }
  }

  Future<void> _rejectBooking(int bookingId) async {
    final reason = await _showRejectDialog();
    if (reason != null && reason.isNotEmpty) {
      try {
        await _merchantService.rejectBooking(bookingId, reason);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking rejected'),
              backgroundColor: Colors.orange,
            ),
          );
          ref.refresh(pendingBookingsFutureProvider);
        }
      } on Exception catch (e) {
        if (mounted) {
          CarHireErrorHandler.showErrorSnackbar(context, e);
        }
      }
    }
  }

  Future<String?> _showRejectDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Booking'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Provide a reason for rejection',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(pendingBookingsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Requests'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingBookingsFutureProvider.future),
        child: bookingsAsync.when(
          data: (bookings) {
            if (bookings.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No pending booking requests',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: bookings.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final booking = bookings[index];
                return _buildBookingRequestCard(context, booking);
              },
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, stack) => Center(
            child: Text(CarHireErrorHandler.getErrorMessage(error as Exception)),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingRequestCard(BuildContext context, dynamic booking) {
    final rentalDays = booking.endDate.difference(booking.startDate).inDays + 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Car details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${booking.carBrand} ${booking.carModel}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Booking #${booking.id}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
                StatusBadgeWidget(status: booking.status.name),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Rental period
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Date',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      Text(
                        CarHireFormatters.formatDate(booking.startDate),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
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
                        'End Date',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      Text(
                        CarHireFormatters.formatDate(booking.endDate),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
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
                        'Duration',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      Text(
                        '$rentalDays days',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cost
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Cost',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  CarHireFormatters.formatCurrency(booking.totalCost),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmBooking(booking.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rejectBooking(booking.id),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
