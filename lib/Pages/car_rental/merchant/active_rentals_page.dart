import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/car_hire_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/Pages/car_rental/widgets/status_badge_widget.dart';

class ActiveRentalsPage extends ConsumerStatefulWidget {
  const ActiveRentalsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<ActiveRentalsPage> createState() => _ActiveRentalsPageState();
}

class _ActiveRentalsPageState extends ConsumerState<ActiveRentalsPage> {
  String _filterStatus = 'ACTIVE'; // All, ACTIVE, OVERDUE

  Future<void> _completeRental(int bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Rental'),
        content: const Text(
          'Are you sure you want to mark this rental as completed? '
          'Make sure you have verified the car condition.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final service = ref.read(carRentalServiceProvider);
        // TODO: Implement completion with damage inspection
        // await service.completeRentalAsOwner(bookingId, dto);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rental marked as completed'),
              backgroundColor: Colors.green,
            ),
          );
          ref.refresh(activeRentalsFutureProvider);
        }
      } on Exception catch (e) {
        if (mounted) {
          CarHireErrorHandler.showErrorSnackbar(context, e);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRentalsAsync = ref.watch(activeRentalsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Rentals'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('All'),
                const SizedBox(width: 8),
                _buildFilterChip('ACTIVE'),
                const SizedBox(width: 8),
                _buildFilterChip('OVERDUE'),
              ],
            ),
          ),
          // Rentals List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(activeRentalsFutureProvider.future),
              child: activeRentalsAsync.when(
                data: (rentals) {
                  final filtered = _filterRentals(rentals);

                  if (filtered.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final rental = filtered[index];
                      return _buildRentalCard(context, rental);
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Text(
                    CarHireErrorHandler.getErrorMessage(error as Exception),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _filterStatus == label;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterStatus = label);
      },
    );
  }

  List<dynamic> _filterRentals(List<dynamic> rentals) {
    if (_filterStatus == 'All') {
      return rentals;
    }
    return rentals.where((rental) {
      if (_filterStatus == 'OVERDUE') {
        // Check if rental end date has passed
        return rental.endDate.isBefore(DateTime.now());
      }
      return rental.status.name == _filterStatus;
    }).toList();
  }

  Widget _buildRentalCard(BuildContext context, dynamic rental) {
    final rentalDays = rental.endDate.difference(rental.startDate).inDays + 1;
    final isOverdue = rental.endDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isOverdue ? 4 : 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Car info and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${rental.carBrand} ${rental.carModel}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      rental.licensePlate ?? 'N/A',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    StatusBadgeWidget(
                      status: isOverdue ? 'OVERDUE' : rental.status.name,
                    ),
                    if (isOverdue)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Overdue',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Renter Information
            Text(
              'Renter: ${rental.renterName ?? 'Unknown'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Phone: ${rental.renterPhone ?? 'N/A'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 16),

            // Rental Period
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      Text(
                        CarHireFormatters.formatDateTime(rental.startDate),
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
                        'End',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      Text(
                        CarHireFormatters.formatDateTime(rental.endDate),
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

            // GPS Tracking Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Live Tracking',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Lat: ${rental.lastLatitude?.toStringAsFixed(4) ?? "N/A"}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Long: ${rental.lastLongitude?.toStringAsFixed(4) ?? "N/A"}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (rental.lastSpeed != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Speed: ${rental.lastSpeed!.toStringAsFixed(1)} km/h',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cost Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimated Cost',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  CarHireFormatters.formatCurrency(rental.totalCost),
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

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Implement map view for GPS tracking
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Map view coming soon'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('View Map'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _completeRental(rental.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Complete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _filterStatus == 'All'
                ? 'No active rentals'
                : 'No $_filterStatus rentals',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _filterStatus = 'All');
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }
}
