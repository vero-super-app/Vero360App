import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vero360_app/models/car_model.dart';
import 'package:vero360_app/services/car_map_service.dart';
import 'package:vero360_app/services/car_websocket_service.dart';
import 'car_detail_page.dart';

class CarMapPage extends StatefulWidget {
  const CarMapPage({super.key});

  @override
  State<CarMapPage> createState() => _CarMapPageState();
}

class _CarMapPageState extends State<CarMapPage> {
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
            onTap: () => _showCarDetails(car),
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

  void _showCarDetails(CarModel car) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CarDetailPage(car: car)),
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

  @override
  Widget build(BuildContext context) {
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
      appBar: AppBar(
        title: const Text('Car Rental Map'),
        elevation: 0,
      ),
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

  @override
  void dispose() {
    _mapController?.dispose();
    _wsService.dispose();
    super.dispose();
  }
}
