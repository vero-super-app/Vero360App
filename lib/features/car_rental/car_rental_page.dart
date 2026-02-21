import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/GeneralModels/car_model.dart';
import 'package:vero360_app/GernalServices/car_map_service.dart';
import 'package:vero360_app/GernalServices/car_websocket_service.dart';
import 'car_detail_page.dart';

// App Colors (matching homepage design)
class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const brandOrangeSoft = Color(0xFFFFEAD1);
  static const brandOrangePale = Color(0xFFFFF4E6);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const chip = Color(0xFFF9F5EF);
  static const card = Color(0xFFFFFFFF);
  static const bgBottom = Color(0xFFFFFFFF);
}

/// Combined Car Map & List Page
/// Shows user's location on map with available cars around them
/// Tap a car marker to see details in a bottom sheet modal
class CarRentalPage extends StatefulWidget {
  const CarRentalPage({super.key});

  @override
  State<CarRentalPage> createState() => _CarRentalPageState();
}

class _CarRentalPageState extends State<CarRentalPage> {
  late CarMapService _mapService;
  late CarWebSocketService _wsService;
  GoogleMapController? _mapController;
  Set<Marker> _carMarkers = {};
  Map<int, CarModel> _carMap = {}; // Map for fast updates
  List<CarModel> _cars = [];
  bool _loading = true;
  bool _useRealTime = true; // Toggle real-time updates
  String? _error;
  Position? _userPosition;
  CarModel? _selectedCar; // For bottom sheet
  bool _showListView = false; // Toggle between map and list view

  // Default location: Lilongwe city center
  static const LatLng _defaultLocation = LatLng(-13.963, 33.770);

  @override
  void initState() {
    super.initState();
    _mapService = CarMapService();
    _wsService = CarWebSocketService();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      // Get user location
      _userPosition = await _mapService.getUserLocation();

      // Load cars
      final cars = await _mapService.getAvailableCarsWithLocation();

      if (mounted) {
        setState(() {
          _cars = cars;
          _carMap = {for (var car in cars) car.id: car};
          _loading = false;
        });
        _createMarkers();

        // Start real-time updates
        if (_useRealTime) {
          _setupRealtimeUpdates();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading map: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setupRealtimeUpdates() async {
    try {
      // Subscribe to car location updates
      final carIds = _cars.map((c) => c.id).toList();
      await _wsService.subscribeToCars(carIds);

      // Listen to real-time updates
      _wsService.carUpdates.listen((updatedCars) {
        if (!mounted) return;

        // Update car map with new data
        for (var car in updatedCars) {
          _carMap[car.id] = car;
        }

        // Rebuild markers with updated car data
        _createMarkers();
      }, onError: (error) {
        print('WebSocket error: $error');
        // Fall back to REST if WebSocket fails
      });
    } catch (e) {
      print('Error setting up real-time updates: $e');
      // Gracefully fall back to static updates
    }
  }

  void _createMarkers() {
    final markers = <Marker>{};

    // Add car markers using updated car map (with real-time data)
    for (var car in _carMap.values) {
      if (car.latitude != null && car.longitude != null) {
        markers.add(
          Marker(
            markerId: MarkerId('car_${car.id}'),
            position: LatLng(car.latitude!, car.longitude!),
            icon: car.isAvailable
                ? BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen)
                : BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: '${car.brand} ${car.model}',
              snippet: car.isAvailable
                  ? 'Available - MK${car.dailyRate.toStringAsFixed(2)}/day'
                  : 'Not Available',
            ),
            onTap: () => _showCarModal(car),
          ),
        );
      }
    }

    // Add user location marker
    if (_userPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userPosition!.latitude, _userPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    if (mounted) {
      setState(() => _carMarkers = markers);
    }
  }

  void _showCarModal(CarModel car) {
    setState(() => _selectedCar = car);
    _showCarDetailsBottomSheet(car);
  }

  void _showCarDetailsBottomSheet(CarModel car) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CarDetailModal(car: car),
    );
  }

  Future<void> _centerOnUser() async {
    if (_userPosition == null) {
      _userPosition = await _mapService.getUserLocation();
      _createMarkers();
    }

    if (_userPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_userPosition!.latitude, _userPosition!.longitude),
            zoom: 15,
          ),
        ),
      );
    }
  }

  void _refreshMap() {
    setState(() => _loading = true);
    _initializeMap();
  }

  void _toggleRealTime() {
    setState(() => _useRealTime = !_useRealTime);

    if (_useRealTime) {
      _setupRealtimeUpdates();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Real-time updates enabled')),
      );
    } else {
      _wsService.disconnect();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Real-time updates disabled')),
      );
    }
  }

  void _toggleListView() {
    setState(() => _showListView = !_showListView);
  }

  @override
  Widget build(BuildContext context) {
    // Show list view if toggled
    if (_showListView) {
      return _buildListView();
    }

    // Show map view (default)
    return _buildMapView();
  }

  Widget _buildMapView() {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Car Rental Map')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Car Rental Map')),
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
                onPressed: _refreshMap,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _userPosition != null
              ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
              : _defaultLocation,
          zoom: 14,
        ),
        onMapCreated: (controller) => _mapController = controller,
        markers: _carMarkers,
        compassEnabled: true,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'realtime_toggle',
            backgroundColor: _useRealTime ? Colors.green : Colors.grey,
            onPressed: _toggleRealTime,
            tooltip: _useRealTime
                ? 'Disable real-time updates'
                : 'Enable real-time updates',
            child: Icon(_useRealTime ? Icons.live_tv : Icons.tv_off_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'center_location',
            onPressed: _centerOnUser,
            tooltip: 'Center on my location',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Available Cars')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Available Cars')),
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
                onPressed: _refreshMap,
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
        appBar: AppBar(title: const Text('Available Cars')),
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
                onPressed: _refreshMap,
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
            onPressed: _toggleListView,
            tooltip: 'View Map',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshMap(),
        child: ListView.builder(
          itemCount: _cars.length,
          itemBuilder: (_, i) {
            final car = _cars[i];
            return CarListTile(
              car: car,
              onTap: () => _showCarModal(car),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _wsService.dispose();
    super.dispose();
  }
}

/// Car List Tile for list view
class CarListTile extends StatelessWidget {
  final CarModel car;
  final VoidCallback onTap;

  const CarListTile({
    required this.car,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Car image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[300],
                  child: car.imageUrl != null
                      ? Image.network(
                          car.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.directions_car),
                        )
                      : const Icon(Icons.directions_car, size: 40),
                ),
              ),
              const SizedBox(width: 12),
              // Car info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${car.brand} ${car.model}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      car.licensePlate,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'MK${car.dailyRate.toStringAsFixed(2)}/day',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: car.isAvailable ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            car.isAvailable ? 'Available' : 'Unavailable',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Car Detail Modal (Bottom Sheet) - Modern Design
class CarDetailModal extends StatelessWidget {
  final CarModel car;

  const CarDetailModal({required this.car, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modern handle bar
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.brandOrangeSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Car image with gradient overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 220,
                      color: AppColors.chip,
                      child: car.imageUrl != null
                          ? Image.network(
                              car.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.directions_car,
                                    size: 100, color: Colors.grey[300]),
                              ),
                            )
                          : Center(
                              child: Icon(Icons.directions_car,
                                  size: 100, color: Colors.grey[300]),
                            ),
                    ),
                    // Availability badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: car.isAvailable
                              ? Colors.green
                              : Colors.red.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x30000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              car.isAvailable
                                  ? Icons.check_circle
                                  : Icons.block,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              car.isAvailable ? 'Available' : 'Unavailable',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Car name and license plate
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${car.brand} ${car.model}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.title,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        car.licensePlate,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Rating
                if (car.rating > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brandOrangePale,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.brandOrangeSoft,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: AppColors.brandOrange),
                        const SizedBox(width: 4),
                        Text(
                          car.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Details grid
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.brandOrangePale.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.brandOrangeSoft.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Year',
                    value: car.year.toString(),
                    icon: Icons.calendar_today,
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Color',
                    value: car.color ?? 'Unknown',
                    icon: Icons.palette,
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Fuel Type',
                    value: car.fuelType,
                    icon: Icons.local_gas_station,
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Seats',
                    value: '${car.seats}',
                    icon: Icons.event_seat,
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Daily Rate',
                    value: 'MK${car.dailyRate.toStringAsFixed(2)}',
                    icon: Icons.attach_money,
                    isHighlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location info (if available)
            if (car.latitude != null && car.longitude != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFBBDEFB),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        size: 18,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Location',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${car.latitude!.toStringAsFixed(4)}, ${car.longitude!.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.title,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.chip,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                          color: AppColors.brandOrangeSoft,
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: AppColors.title,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: car.isAvailable
                        ? () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('🎉 Booking feature coming soon!'),
                                backgroundColor: AppColors.brandOrange,
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: car.isAvailable
                          ? AppColors.brandOrange
                          : Colors.grey[300],
                      elevation: car.isAvailable ? 4 : 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      car.isAvailable ? 'Book Now' : 'Not Available',
                      style: TextStyle(
                        color:
                            car.isAvailable ? Colors.white : Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Modern detail row for car info
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool isHighlight;

  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: isHighlight ? AppColors.brandOrange : AppColors.body,
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.body,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: isHighlight ? AppColors.brandOrange : AppColors.title,
                  fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
