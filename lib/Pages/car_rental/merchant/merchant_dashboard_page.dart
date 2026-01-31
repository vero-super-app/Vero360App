import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/car_hire_provider.dart';
import 'package:vero360_app/Pages/car_rental/widgets/status_badge_widget.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/error_handler.dart';

class MerchantDashboardPage extends ConsumerWidget {
  const MerchantDashboardPage({Key? key, required String email})
      : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(merchantProfileFutureProvider);
    final analyticsAsync = ref.watch(merchantAnalyticsFutureProvider);
    final pendingBookingsAsync = ref.watch(pendingBookingsFutureProvider);
    final activeRentalsAsync = ref.watch(activeRentalsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Dashboard'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.refresh(merchantProfileFutureProvider);
          ref.refresh(merchantAnalyticsFutureProvider);
          ref.refresh(pendingBookingsFutureProvider);
          ref.refresh(activeRentalsFutureProvider);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Section
              profileAsync.when(
                data: (profile) => _buildProfileCard(context, profile),
                loading: () => const _SkeletonCard(),
                error: (error, stack) => _buildErrorCard(context, error),
              ),
              const SizedBox(height: 24),

              // Analytics Cards
              analyticsAsync.when(
                data: (analytics) => _buildAnalyticsCards(context, analytics),
                loading: () => const _SkeletonAnalytics(),
                error: (error, stack) => _buildErrorCard(context, error),
              ),
              const SizedBox(height: 24),

              // Pending Bookings Section
              Text(
                'Pending Bookings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              pendingBookingsAsync.when(
                data: (bookings) => bookings.isEmpty
                    ? _buildEmptyState(context, 'No pending bookings')
                    : Column(
                        children: bookings.take(3).map((booking) {
                          return _buildBookingCard(context, booking);
                        }).toList(),
                      ),
                loading: () => const _SkeletonCard(),
                error: (error, stack) => _buildErrorCard(context, error),
              ),
              const SizedBox(height: 24),

              // Active Rentals Section
              Text(
                'Active Rentals',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              activeRentalsAsync.when(
                data: (rentals) => rentals.isEmpty
                    ? _buildEmptyState(context, 'No active rentals')
                    : Column(
                        children: rentals.take(3).map((rental) {
                          return _buildRentalCard(context, rental);
                        }).toList(),
                      ),
                loading: () => const _SkeletonCard(),
                error: (error, stack) => _buildErrorCard(context, error),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pushNamed('/merchant/add-car');
        },
        label: const Text('Add Car'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, dynamic profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.businessName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (profile.verified)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.verified,
                              color: Colors.green,
                              size: 16,
                            ),
                          ),
                        Text(
                          profile.verified ? 'Verified' : 'Unverified',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                Icon(
                  profile.verified ? Icons.check_circle : Icons.info,
                  color: profile.verified ? Colors.green : Colors.orange,
                  size: 32,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsCards(BuildContext context, dynamic analytics) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Total Cars',
                '${analytics.totalCars}',
                Icons.directions_car,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Total Bookings',
                '${analytics.totalBookings}',
                Icons.calendar_today,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Active Rentals',
                '${analytics.activeRentals}',
                Icons.drive_eta,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Total Earnings',
                CarHireFormatters.formatCurrency(analytics.totalEarnings),
                Icons.attach_money,
                Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                context,
                'Avg Rating',
                '${analytics.averageRating.toStringAsFixed(1)}',
                Icons.star,
                Colors.amber,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                context,
                'Utilization',
                CarHireFormatters.formatPercentage(analytics.utilizationRate),
                Icons.trending_up,
                Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(BuildContext context, dynamic booking) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${booking.carBrand} ${booking.carModel}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                StatusBadgeWidget(status: booking.status.name),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Booking ID: ${booking.id}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CarHireFormatters.formatDate(booking.startDate),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      CarHireFormatters.formatDate(booking.endDate),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Text(
                  CarHireFormatters.formatCurrency(booking.totalCost),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentalCard(BuildContext context, dynamic rental) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${rental.carBrand} ${rental.carModel}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Icon(Icons.location_on, color: Colors.red, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Started: ${CarHireFormatters.formatDate(rental.startDate)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, Object error) {
    final message = CarHireErrorHandler.getErrorMessage(error as Exception);
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error, color: Colors.red[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red[700],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        height: 120,
        color: Colors.grey[300],
      ),
    );
  }
}

class _SkeletonAnalytics extends StatelessWidget {
  const _SkeletonAnalytics();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SkeletonSmallCard()),
            const SizedBox(width: 12),
            Expanded(child: _SkeletonSmallCard()),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _SkeletonSmallCard()),
            const SizedBox(width: 12),
            Expanded(child: _SkeletonSmallCard()),
          ],
        ),
      ],
    );
  }
}

class _SkeletonSmallCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        height: 100,
        color: Colors.grey[300],
      ),
    );
  }
}
