import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/models/ride_model.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';
import 'package:vero360_app/services/firebase_ride_share_service.dart';
import 'package:vero360_app/services/auth_storage.dart';

class VehicleTypeOption {
  final String class_;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String estimatedPrice;
  final double distance;

  VehicleTypeOption({
    required this.class_,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.estimatedPrice,
    this.distance = 0.0,
  });
}

class VehicleTypeModal extends ConsumerStatefulWidget {
  final Place pickupPlace;
  final Place dropoffPlace;
  final double userLat;
  final double userLng;
  final Function(String) onRideRequested;

  const VehicleTypeModal({
    required this.pickupPlace,
    required this.dropoffPlace,
    required this.userLat,
    required this.userLng,
    required this.onRideRequested,
    Key? key,
  }) : super(key: key);

  @override
  ConsumerState<VehicleTypeModal> createState() => _VehicleTypeModalState();
}

class _VehicleTypeModalState extends ConsumerState<VehicleTypeModal> {
  String? _selectedVehicleClass;
  bool _isSearching = false;
  String? _errorMessage;
  double _distance = 0.0;
  Map<String, dynamic> _estimatedFares = {};

  @override
  void initState() {
    super.initState();
    _calculateDistanceAndFares();
  }

  Future<void> _calculateDistanceAndFares() async {
    try {
      final placeService = ref.read(placeServiceProvider);
      final distance = placeService.calculateDistance(
        widget.userLat,
        widget.userLng,
        widget.dropoffPlace.latitude,
        widget.dropoffPlace.longitude,
      );

      setState(() {
        _distance = distance;
      });

      // Fetch fare estimates for each vehicle class
      for (final vehicleType in _baseVehicleTypes) {
        final fareEstimate =
            await ref.read(rideShareServiceProvider).estimateFare(
                  pickupLatitude: widget.userLat,
                  pickupLongitude: widget.userLng,
                  dropoffLatitude: widget.dropoffPlace.latitude,
                  dropoffLongitude: widget.dropoffPlace.longitude,
                  vehicleClass: vehicleType.class_,
                );

        if (mounted) {
          setState(() {
            _estimatedFares[vehicleType.class_] = fareEstimate;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to calculate fares: $e';
        });
      }
    }
  }

  final List<VehicleTypeOption> _baseVehicleTypes = [
    VehicleTypeOption(
      class_: VehicleClass.economy,
      name: 'Economy',
      description: 'Affordable & comfortable',
      icon: Icons.directions_car,
      color: const Color(0xFF4CAF50),
      estimatedPrice: 'Calculating...',
    ),
    VehicleTypeOption(
      class_: VehicleClass.comfort,
      name: 'Comfort',
      description: 'Premium comfort ride',
      icon: Icons.airport_shuttle,
      color: const Color(0xFF2196F3),
      estimatedPrice: 'Calculating...',
    ),
    VehicleTypeOption(
      class_: VehicleClass.premium,
      name: 'Premium',
      description: 'Luxury experience',
      icon: Icons.directions_car_filled,
      color: const Color(0xFFFF9800),
      estimatedPrice: 'Calculating...',
    ),
    VehicleTypeOption(
      class_: VehicleClass.business,
      name: 'Business',
      description: 'Executive transport',
      icon: Icons.business_center,
      color: const Color(0xFF9C27B0),
      estimatedPrice: 'Calculating...',
    ),
  ];

  Future<void> _handleVehicleSelected(String vehicleClass) async {
    setState(() {
      _selectedVehicleClass = vehicleClass;
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      // Get current user ID from your existing auth system (JWT token)
      final userId = await AuthStorage.userIdFromToken();
      if (userId == null) {
        throw Exception('User not authenticated. Please log in first.');
      }
      final userIdStr = userId.toString();

      // Get fare estimate
      final fareEstimate = _estimatedFares[vehicleClass];
      final estimatedFare = fareEstimate != null
          ? (fareEstimate['estimatedFare'] as num?)?.toDouble() ?? 0.0
          : 0.0;

      // Calculate distance
      final distance = widget.userLat == widget.dropoffPlace.latitude &&
              widget.userLng == widget.dropoffPlace.longitude
          ? 0.0
          : _distance;

      // Get passenger name from storage or use default
      final passengerName = await AuthStorage.userNameFromToken() ?? 'Passenger';

      // Create Firebase ride request
      final rideId = await FirebaseRideShareService.createRideRequest(
        passengerId: userIdStr,
        passengerName: passengerName,
        pickupLat: widget.userLat,
        pickupLng: widget.userLng,
        dropoffLat: widget.dropoffPlace.latitude,
        dropoffLng: widget.dropoffPlace.longitude,
        pickupAddress: widget.pickupPlace.address,
        dropoffAddress: widget.dropoffPlace.address,
        estimatedTime: 25, // TODO: calculate based on distance
        estimatedDistance: distance,
        estimatedFare: estimatedFare,
      );

      if (mounted) {
        // Close modal and trigger callback
        Navigator.pop(context);
        widget.onRideRequested(rideId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSearching) {
      return _buildSearchingState();
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Vehicle Type',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'From: ${widget.pickupPlace.name}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'To: ${widget.dropoffPlace.name}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8A00).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_distance.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF8A00),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Vehicle types grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              child: Column(
                children: _baseVehicleTypes.map((vehicleType) {
                  return _buildVehicleTypeCard(vehicleType);
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Error message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage ?? '',
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildVehicleTypeCard(VehicleTypeOption vehicleType) {
    final isSelected = _selectedVehicleClass == vehicleType.class_;
    final fareData = _estimatedFares[vehicleType.class_];

    String displayPrice = 'Calculating...';
    if (fareData != null) {
      final estimatedFare = fareData['estimatedFare'] as num?;
      if (estimatedFare != null) {
        displayPrice = 'MK ${estimatedFare.toStringAsFixed(0)}';
      }
    }

    return GestureDetector(
      onTap: () => _handleVehicleSelected(vehicleType.class_),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? vehicleType.color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? vehicleType.color.withValues(alpha: 0.1)
              : Colors.white,
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: vehicleType.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                vehicleType.icon,
                color: vehicleType.color,
                size: 28,
              ),
            ),

            const SizedBox(width: 16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicleType.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vehicleType.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    displayPrice,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: vehicleType.color,
                    ),
                  ),
                ],
              ),
            ),

            // Checkbox
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? vehicleType.color : Colors.grey[300]!,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
                color: isSelected ? vehicleType.color : Colors.white,
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingState() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 48),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFFFF8A00),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Finding ${_selectedVehicleClass ?? 'drivers'}...',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          // Animated dots
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Looking for available drivers in your area',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
