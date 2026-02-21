import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/car_booking_model.dart';
import 'package:vero360_app/Gernalproviders/rental_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/features/car_rental/widgets/status_badge_widget.dart';

class RenterMyBookingsPage extends ConsumerStatefulWidget {
  const RenterMyBookingsPage({super.key});

  @override
  ConsumerState<RenterMyBookingsPage> createState() =>
      _RenterMyBookingsPageState();
}

class _RenterMyBookingsPageState extends ConsumerState<RenterMyBookingsPage> {
  BookingStatus? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(userBookingsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(userBookingsFutureProvider.future),
        child: Column(
          children: [
            // Tab navigation for filtering
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildStatusTab('All', null),
                  const SizedBox(width: 8),
                  _buildStatusTab('Pending', BookingStatus.pending),
                  const SizedBox(width: 8),
                  _buildStatusTab('Confirmed', BookingStatus.confirmed),
                  const SizedBox(width: 8),
                  _buildStatusTab('Active', BookingStatus.active),
                  const SizedBox(width: 8),
                  _buildStatusTab('Completed', BookingStatus.completed),
                ],
              ),
            ),
            // Bookings list
            Expanded(
              child: bookingsAsync.when(
                data: (bookings) {
                  // Filter bookings by selected status
                  final filteredBookings = _selectedStatus == null
                      ? bookings
                      : bookings
                          .where((b) => b.status == _selectedStatus)
                          .toList();

                  if (filteredBookings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bookmark_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedStatus == null
                                ? 'No bookings yet'
                                : 'No ${_getStatusLabel(_selectedStatus!)} bookings',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start by browsing available cars',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filteredBookings.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final booking = filteredBookings[index];
                      return _buildBookingCard(context, booking);
                    },
                  );
                },
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
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () =>
                            ref.refresh(userBookingsFutureProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTab(String label, BookingStatus? status) {
    final isSelected = _selectedStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedStatus = selected ? status : null;
        });
      },
      selectedColor: Colors.blue[100],
      backgroundColor: Colors.grey[200],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildBookingCard(BuildContext context, CarBookingModel booking) {
    final rentalDays = booking.endDate.difference(booking.startDate).inDays + 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _navigateToBookingDetail(booking.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Status and car info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Car image
                  if (booking.carImage != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        booking.carImage!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCarPlaceholder(),
                      ),
                    )
                  else
                    _buildCarPlaceholder(),
                  const SizedBox(width: 16),
                  // Car info and status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${booking.carBrand ?? 'Car'} ${booking.carModel ?? ''}',
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        StatusBadgeWidget(status: booking.statusString),
                        const SizedBox(height: 8),
                        Text(
                          '$rentalDays day${rentalDays > 1 ? 's' : ''}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Dates
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${CarHireFormatters.formatDate(booking.startDate)} - ${CarHireFormatters.formatDate(booking.endDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Cost
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Cost',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  Text(
                    CarHireFormatters.formatCurrency(booking.totalCost),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.directions_car,
        color: Colors.grey[600],
        size: 32,
      ),
    );
  }

  void _navigateToBookingDetail(int bookingId) {
    Navigator.of(context).pushNamed(
      '/rental/booking-detail',
      arguments: {'bookingId': bookingId},
    );
  }

  String _getStatusLabel(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.active:
        return 'Active';
      case BookingStatus.completed:
        return 'Completed';
    }
  }
}
