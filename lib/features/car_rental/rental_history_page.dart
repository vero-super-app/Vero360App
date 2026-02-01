import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/car_rental_service.dart';
import 'package:vero360_app/GeneralModels/car_booking_model.dart';

class RentalHistoryPage extends StatefulWidget {
  const RentalHistoryPage({super.key});

  @override
  State<RentalHistoryPage> createState() => _RentalHistoryPageState();
}

class _RentalHistoryPageState extends State<RentalHistoryPage> {
  late CarRentalService _rentalService;
  List<CarBookingModel> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rentalService = CarRentalService();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    try {
      setState(() => _loading = true);
      final bookings = await _rentalService.getUserBookings();
      if (mounted) {
        setState(() {
          _bookings = bookings;
          _loading = false;
          _error = null;
        });
      }
    } on CarRentalException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading bookings: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Rentals')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadBookings,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_bookings.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Rentals')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.history,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'No rental history',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Browse Cars'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rentals'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadBookings,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _bookings.length,
          itemBuilder: (_, i) {
            final booking = _bookings[i];
            return _RentalCard(booking: booking);
          },
        ),
      ),
    );
  }
}

class _RentalCard extends StatelessWidget {
  final CarBookingModel booking;

  const _RentalCard({required this.booking});

  Color _getStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return Colors.amber;
      case BookingStatus.confirmed:
        return Colors.blue;
      case BookingStatus.active:
        return Colors.green;
      case BookingStatus.completed:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with car name and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (booking.carBrand != null && booking.carModel != null)
                        Text(
                          '${booking.carBrand} ${booking.carModel}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        const Text(
                          'Car Rental',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Booking #${booking.id}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(booking.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    booking.statusString,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),

            // Rental details
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 16, color: Color(0xFFFF8A00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${booking.startDate.toString().split(' ')[0]} to ${booking.endDate.toString().split(' ')[0]}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.attach_money,
                    size: 16, color: Color(0xFFFF8A00)),
                const SizedBox(width: 8),
                Text(
                  'MWK${booking.totalCost.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.timer, size: 16, color: Color(0xFFFF8A00)),
                const SizedBox(width: 8),
                Text(
                  '${booking.endDate.difference(booking.startDate).inDays} day(s)',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),

            // Timestamps
            const SizedBox(height: 12),
            Text(
              'Booked on ${booking.createdAt.toString().split(' ')[0]}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),

            // Action buttons
            if (booking.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Navigate to active rental page
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: Colors.green,
                    ),
                    child: const Text(
                      'View Active Rental',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              )
            else if (booking.isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Implement trip details view
                        },
                        icon: const Icon(Icons.map),
                        label: const Text('Trip Details'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Implement receipt download
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Receipt'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
