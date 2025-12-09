import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/providers/car_hire_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(merchantAnalyticsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDateRange,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(merchantAnalyticsFutureProvider.future),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: analyticsAsync.when(
            data: (analytics) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Range Display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${CarHireFormatters.formatDate(_dateRange.start)} - ${CarHireFormatters.formatDate(_dateRange.end)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        GestureDetector(
                          onTap: _selectDateRange,
                          child: Icon(Icons.edit, size: 18, color: Colors.blue[700]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Key Metrics Section
                  Text(
                    'Key Metrics',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  // Metrics Grid
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildMetricCard(
                        context,
                        'Total Cars',
                        analytics.totalCars.toString(),
                        Icons.directions_car,
                        Colors.blue,
                      ),
                      _buildMetricCard(
                        context,
                        'Total Bookings',
                        analytics.totalBookings.toString(),
                        Icons.bookmark,
                        Colors.green,
                      ),
                      _buildMetricCard(
                        context,
                        'Active Rentals',
                        analytics.activeRentals.toString(),
                        Icons.directions_run,
                        Colors.orange,
                      ),
                      _buildMetricCard(
                        context,
                        'Avg. Rating',
                        analytics.averageRating.toStringAsFixed(1),
                        Icons.star,
                        Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Revenue Section
                  Text(
                    'Revenue Overview',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Earnings',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              CarHireFormatters.formatCurrency(
                                analytics.totalEarnings,
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 12),
                        _buildRevenueRow(
                          context,
                          'This Month',
                          CarHireFormatters.formatCurrency(
                            analytics.monthlyEarnings,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Performance Metrics
                  Text(
                    'Performance',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildPerformanceRow(
                            context,
                            'Utilization Rate',
                            '${(analytics.utilizationRate * 100).toStringAsFixed(1)}%',
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Fleet Efficiency',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 100,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 100 *
                                              analytics.utilizationRate,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(analytics.utilizationRate * 100).toStringAsFixed(0)}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Car Performance Section
                  Text(
                    'Top Performing Cars',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  if (analytics.carAnalytics.isEmpty)
                    Center(
                      child: Text(
                        'No car data available',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    )
                  else
                    ListView.builder(
                      itemCount: analytics.carAnalytics.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final car = analytics.carAnalytics[index];
                        return _buildCarPerformanceCard(context, car);
                      },
                    ),

                  const SizedBox(height: 24),
                ],
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
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
        ),
      ],
    );
  }

  Widget _buildPerformanceRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildCarPerformanceCard(BuildContext context, dynamic car) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              car.carName ?? 'Unknown',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCarStatColumn(
                  context,
                  'Bookings',
                  car.bookings.toString(),
                ),
                _buildCarStatColumn(
                  context,
                  'Earnings',
                  CarHireFormatters.formatCurrency(car.earnings),
                ),
                _buildCarStatColumn(
                  context,
                  'Utilization',
                  '${(car.utilizationRate * 100).toStringAsFixed(0)}%',
                ),
                _buildCarStatColumn(
                  context,
                  'Rating',
                  car.averageRating.toStringAsFixed(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarStatColumn(
    BuildContext context,
    String label,
    String value,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
