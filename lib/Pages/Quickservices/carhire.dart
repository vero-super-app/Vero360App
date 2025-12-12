import 'package:flutter/material.dart';
import 'package:vero360_app/services/car_rental_service.dart';
import 'package:vero360_app/models/car_model.dart';
import '../car_rental/car_detail_page.dart';
import '../car_rental/widgets/car_card.dart';

class CarHirePage extends StatefulWidget {
  const CarHirePage({super.key});

  @override
  State<CarHirePage> createState() => _CarHirePageState();
}

class _CarHirePageState extends State<CarHirePage> {
  late CarRentalService _rentalService;
  List<CarModel> _cars = [];
  bool _loading = true;
  String? _error;

  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandOrangeSoft = Color(0xFFFFE3C2);

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
      return Scaffold(
        appBar: AppBar(
          title: const Text('Car Hire'),
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Car Hire'),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_cars.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Car Hire'),
          elevation: 0,
        ),
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
        title: const Text('Car Hire'),
        elevation: 0,
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_brandOrangeSoft, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadCars,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _cars.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: CarCard(
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
        ),
      ),
    );
  }
}
