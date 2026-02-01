import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/car_hire_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/features/car_rental/widgets/status_badge_widget.dart';
import 'package:vero360_app/features/car_rental/widgets/rating_widget.dart';

class RentalHistoryPage extends ConsumerStatefulWidget {
  final int? carId; // If provided, filter by specific car

  const RentalHistoryPage({
    Key? key,
    this.carId,
  }) : super(key: key);

  @override
  ConsumerState<RentalHistoryPage> createState() => _RentalHistoryPageState();
}

class _RentalHistoryPageState extends ConsumerState<RentalHistoryPage> {
  String _sortBy = 'DATE_DESC'; // DATE_DESC, DATE_ASC, RATING_HIGH, RATING_LOW
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    final historyAsync = widget.carId != null
        ? ref.watch(rentalHistoryFutureProvider(widget.carId!))
        : ref
            .watch(activeRentalsFutureProvider); // Fallback: use active rentals

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.carId != null ? 'Car Rental History' : 'All Rental History'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Active Filters Display
          if (_dateRange != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${CarHireFormatters.formatDate(_dateRange!.start)} - ${CarHireFormatters.formatDate(_dateRange!.end)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blue[700],
                          ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _dateRange = null);
                      },
                      child:
                          Icon(Icons.close, size: 18, color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),

          // Rental History List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => widget.carId != null
                  ? ref.refresh(
                      rentalHistoryFutureProvider(widget.carId!).future)
                  : ref.refresh(activeRentalsFutureProvider.future),
              child: historyAsync.when(
                data: (rentals) {
                  var filtered = _applyFilters(rentals);
                  var sorted = _sortRentals(filtered);

                  if (sorted.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  return ListView.builder(
                    itemCount: sorted.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final rental = sorted[index];
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

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sort By',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSortOption('DATE_DESC', 'Newest First'),
            _buildSortOption('DATE_ASC', 'Oldest First'),
            _buildSortOption('RATING_HIGH', 'Highest Rated'),
            _buildSortOption('RATING_LOW', 'Lowest Rated'),
            const SizedBox(height: 24),
            Text(
              'Date Range',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectDateRange,
                child: Text(
                  _dateRange == null
                      ? 'Select Date Range'
                      : '${CarHireFormatters.formatDate(_dateRange!.start)} - ${CarHireFormatters.formatDate(_dateRange!.end)}',
                ),
              ),
            ),
            if (_dateRange != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _dateRange = null);
                      Navigator.pop(context);
                    },
                    child: const Text('Clear Date Range'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String value, String label) {
    final isSelected = _sortBy == value;
    return RadioListTile<String>(
      title: Text(label),
      value: value,
      groupValue: _sortBy,
      onChanged: (selected) {
        if (selected != null) {
          setState(() => _sortBy = selected);
          Navigator.pop(context);
        }
      },
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
      Navigator.pop(context);
    }
  }

  List<dynamic> _applyFilters(List<dynamic> rentals) {
    var filtered = rentals;

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((rental) {
        final rentalDate = rental.startDate;
        return rentalDate.isAfter(_dateRange!.start) &&
            rentalDate.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  }

  List<dynamic> _sortRentals(List<dynamic> rentals) {
    switch (_sortBy) {
      case 'DATE_ASC':
        rentals.sort((a, b) => a.startDate.compareTo(b.startDate));
        break;
      case 'RATING_HIGH':
        rentals.sort(
            (a, b) => (b.renterRating ?? 0).compareTo(a.renterRating ?? 0));
        break;
      case 'RATING_LOW':
        rentals.sort(
            (a, b) => (a.renterRating ?? 0).compareTo(b.renterRating ?? 0));
        break;
      case 'DATE_DESC':
      default:
        rentals.sort((a, b) => b.startDate.compareTo(a.startDate));
    }
    return rentals;
  }

  Widget _buildRentalCard(BuildContext context, dynamic rental) {
    final rentalDays = rental.endDate.difference(rental.startDate).inDays + 1;
    final daysAgo = DateTime.now().difference(rental.endDate).inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to rental detail page
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                        'Booking #${rental.id}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                  StatusBadgeWidget(status: rental.status.name),
                ],
              ),
              const SizedBox(height: 12),

              // Dates
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    '${CarHireFormatters.formatDate(rental.startDate)} - ${CarHireFormatters.formatDate(rental.endDate)} ($rentalDays days)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Renter info
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rental.renterName ?? 'Unknown',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Rating
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RatingWidget(
                    rating: rental.renterRating ?? 0.0,
                    reviewCount: rental.renterReviews ?? 0,
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

              // Time ago
              const SizedBox(height: 8),
              Text(
                'Completed $daysAgo days ago',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _dateRange != null
                ? 'No rentals in this date range'
                : 'No rental history',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          if (_dateRange != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() => _dateRange = null);
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filters'),
              ),
            ),
        ],
      ),
    );
  }
}
