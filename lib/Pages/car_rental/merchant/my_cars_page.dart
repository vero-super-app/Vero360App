import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/providers/ride_share/car_hire_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';

class MyCarsPage extends ConsumerStatefulWidget {
  const MyCarsPage({Key? key}) : super(key: key);

  @override
  ConsumerState<MyCarsPage> createState() => _MyCarsPageState();
}

class _MyCarsPageState extends ConsumerState<MyCarsPage> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final carsAsync = ref.watch(myCarsFutureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cars'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              decoration: InputDecoration(
                hintText: 'Search cars by make, model, plate...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          // Cars list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(myCarsFutureProvider.future),
              child: carsAsync.when(
                data: (cars) {
                  final filtered = cars.where((car) {
                    final query = _searchQuery.toLowerCase();
                    return car.brand.toLowerCase().contains(query) ||
                        car.model.toLowerCase().contains(query) ||
                        car.licensePlate.toLowerCase().contains(query);
                  }).toList();

                  if (filtered.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final car = filtered[index];
                      return _buildCarCard(context, car);
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Text(
                      CarHireErrorHandler.getErrorMessage(error as Exception)),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pushNamed('/merchant/add-car').then((_) {
            ref.refresh(myCarsFutureProvider);
          });
        },
        label: const Text('Add Car'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCarCard(BuildContext context, dynamic car) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to car detail page
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Car image or placeholder
              Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: car.imageUrl != null
                    ? Image.network(car.imageUrl!, fit: BoxFit.cover)
                    : Icon(Icons.directions_car,
                        size: 64, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              // Car details
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${car.brand} ${car.model}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        car.licensePlate,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          car.isAvailable ? Colors.green[100] : Colors.red[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      car.isAvailable ? 'Available' : 'Unavailable',
                      style: TextStyle(
                        color: car.isAvailable ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Daily rate and rating
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    CarHireFormatters.formatCurrency(car.dailyRate) + ' / day',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${car.rating.toStringAsFixed(1)} (${car.reviews})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          '/merchant/edit-car',
                          arguments: car.id,
                        );
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          '/merchant/car-rentals',
                          arguments: car.id,
                        );
                      },
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('History'),
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No cars added yet'
                : 'No cars match your search',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/merchant/add-car');
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Car'),
            ),
          ],
        ],
      ),
    );
  }
}
