import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_rental_service.dart';
import 'package:vero360_app/models/car_model.dart';
import 'car_detail_page.dart';
import 'car_map_page.dart';
import 'widgets/car_card.dart';

class CarListPage extends StatefulWidget {
  const CarListPage({super.key});

  @override
  State<CarListPage> createState() => _CarListPageState();
}

class _CarListPageState extends State<CarListPage> {
  late CarRentalService _rentalService;
  List<CarModel> _cars = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rentalService = CarRentalService();
    _loadCars();
  }

  Future<void> _loadCars() async {
    try {
      setState(() => _loading = true);
      final cars = await _rentalService.getAvailableCars();
      if (mounted) {
        setState(() {
          _cars = cars;
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
          _error = 'Error loading cars: $e';
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
        appBar: AppBar(title: const Text('Car Rental')),
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
                onPressed: _loadCars,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cars.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Car Rental')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.directions_car,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'No cars available',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCars,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Cars'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CarMapPage()),
              );
            },
            tooltip: 'View on map',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCars,
        child: ListView.builder(
          itemCount: _cars.length,
          itemBuilder: (_, i) => CarCard(
            car: _cars[i],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CarDetailPage(car: _cars[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
