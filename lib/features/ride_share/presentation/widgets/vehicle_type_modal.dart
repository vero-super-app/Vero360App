import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/models/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/services/ride_share_http_service.dart';
import 'package:vero360_app/services/auth_storage.dart';

class VehicleTypeOption {
  final String class_;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String estimatedPrice;
  final double distance;
  final String subtext;
  final int capacity;

  VehicleTypeOption({
    required this.class_,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.estimatedPrice,
    this.distance = 0.0,
    required this.subtext,
    required this.capacity,
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

class _VehicleTypeModalState extends ConsumerState<VehicleTypeModal>
    with SingleTickerProviderStateMixin {
  String? _selectedVehicleClass;
  bool _isSearching = false;
  String? _errorMessage;
  double _distance = 0.0;
  int _duration = 0; // Duration in minutes
  Map<String, dynamic> _estimatedFares = {};
  late AnimationController _animationController;
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animationController.forward();
    _calculateDistanceAndFares();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _calculateDistanceAndFares() async {
    try {
      // Get accurate distance and duration from Google Directions API
      final directionsService = ref.read(googleDirectionsServiceProvider);
      final routeInfo = await directionsService.getRouteInfo(
        originLat: widget.userLat,
        originLng: widget.userLng,
        destLat: widget.dropoffPlace.latitude,
        destLng: widget.dropoffPlace.longitude,
      );

      if (kDebugMode) {
        debugPrint('[VehicleTypeModal] Distance: ${routeInfo.distanceKm}km');
        debugPrint(
            '[VehicleTypeModal] Duration: ${routeInfo.durationMinutes}min');
      }

      setState(() {
        _distance = routeInfo.distanceKm;
        _duration = routeInfo.durationMinutes;
      });

      // Fetch all fares in parallel for better performance
      final rideShareService = ref.read(rideShareServiceProvider);
      final fareRequests = _baseVehicleTypes.map(
        (vehicleType) => rideShareService
            .estimateFare(
              pickupLatitude: widget.userLat,
              pickupLongitude: widget.userLng,
              dropoffLatitude: widget.dropoffPlace.latitude,
              dropoffLongitude: widget.dropoffPlace.longitude,
              vehicleClass: vehicleType.class_,
            )
            .then((fareEstimate) => MapEntry(vehicleType.class_, fareEstimate)),
      );

      final results = await Future.wait(fareRequests);
      final fareMap = Map<String, dynamic>.fromEntries(results);

      if (mounted) {
        setState(() {
          _estimatedFares = fareMap;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleTypeModal] Error calculating distance: $e');
      }
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to calculate fares';
        });
      }
    }
  }

  final List<VehicleTypeOption> _baseVehicleTypes = [
    VehicleTypeOption(
      class_: VehicleClass.economy,
      name: 'Bike',
      description: 'Affordable & quick',
      icon: Icons.two_wheeler,
      color: const Color(0xFF10B981),
      estimatedPrice: 'Calculating...',
      subtext: 'Quick ride',
      capacity: 1,
    ),
    VehicleTypeOption(
      class_: VehicleClass.comfort,
      name: 'Standard',
      description: 'Comfortable & reliable',
      icon: Icons.directions_car,
      color: const Color(0xFF3B82F6),
      estimatedPrice: 'Calculating...',
      subtext: 'Standard car',
      capacity: 4,
    ),
    VehicleTypeOption(
      class_: VehicleClass.premium,
      name: 'Executive',
      description: 'Premium experience',
      icon: Icons.directions_car_filled,
      color: const Color(0xFFFF8A00),
      estimatedPrice: 'Calculating...',
      subtext: 'Premium car',
      capacity: 5,
    ),
  ];

  List<VehicleTypeOption> get _filteredVehicles {
    return _baseVehicleTypes;
  }

  Future<void> _handleVehicleSelected(String vehicleClass) async {
    setState(() {
      _selectedVehicleClass = vehicleClass;
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final userId = await AuthStorage.userIdFromToken();
      if (userId == null) {
        throw Exception('User not authenticated. Please log in first.');
      }
      final userIdStr = userId.toString();

      final fareEstimate = _estimatedFares[vehicleClass];
      double estimatedFare = 0.0;

      if (fareEstimate != null) {
        final fareValue = fareEstimate['estimatedFare'];
        if (fareValue is num) {
          estimatedFare = (fareValue as num).toDouble();
        } else if (fareValue is String) {
          estimatedFare = double.tryParse(fareValue) ?? 0.0;
        }
      }

      // Use accurate distance from Google Directions API
      final distance = widget.userLat == widget.dropoffPlace.latitude &&
              widget.userLng == widget.dropoffPlace.longitude
          ? 0.0
          : _distance;

      // Use accurate duration from Google Directions API
      final duration = widget.userLat == widget.dropoffPlace.latitude &&
              widget.userLng == widget.dropoffPlace.longitude
          ? 0
          : _duration;

      if (kDebugMode) {
        debugPrint('[VehicleTypeModal] Creating ride:');
        debugPrint('  Distance: ${distance.toStringAsFixed(2)}km');
        debugPrint('  Duration: ${duration}min');
        debugPrint('  Estimated Fare: MWK $estimatedFare');
      }

      final httpService = RideShareHttpService();
      final ride = await httpService.requestRide(
        pickupLatitude: widget.userLat,
        pickupLongitude: widget.userLng,
        dropoffLatitude: widget.dropoffPlace.latitude,
        dropoffLongitude: widget.dropoffPlace.longitude,
        vehicleClass: _selectedVehicleClass ?? VehicleClass.economy,
        pickupAddress: widget.pickupPlace.address,
        dropoffAddress: widget.dropoffPlace.address,
        notes: null,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onRideRequested(ride.id.toString());
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

    return FadeTransition(
      opacity: _animationController,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(_animationController),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Content
              SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header and trip summary
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Choose Your Ride',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildTripSummary(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Vehicle types grid
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _buildVehicleList(),
                      ),

                      // Error message
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red[600], size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage ?? '',
                                    style: TextStyle(
                                        color: Colors.red[700], fontSize: 12),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // From
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.pickupPlace.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Arrow
          Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 12),
          // To
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.dropoffPlace.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Distance badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_distance.toStringAsFixed(1)}km',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF8A00),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleList() {
    final vehicles = _filteredVehicles;

    if (vehicles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No vehicles available',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: vehicles.length,
      itemBuilder: (context, index) {
        return _buildVehicleCard(vehicles[index]);
      },
    );
  }

  Widget _buildVehicleCard(VehicleTypeOption vehicleType) {
    final isSelected = _selectedVehicleClass == vehicleType.class_;
    final fareData = _estimatedFares[vehicleType.class_];

    String displayPrice = '...';
    if (fareData != null) {
      final fareValue = fareData['estimatedFare'];
      double? estimatedFare;

      if (fareValue is num) {
        estimatedFare = (fareValue as num).toDouble();
      } else if (fareValue is String) {
        estimatedFare = double.tryParse(fareValue);
      }

      if (estimatedFare != null) {
        displayPrice = 'MK ${estimatedFare.toStringAsFixed(0)}';
      }
    }

    return GestureDetector(
      onTap: () => _handleVehicleSelected(vehicleType.class_),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? vehicleType.color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
          color:
              isSelected ? vehicleType.color.withOpacity(0.06) : Colors.white,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: vehicleType.color.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icon background
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: vehicleType.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Icon(
                  vehicleType.icon,
                  color: vehicleType.color,
                  size: 26,
                ),
                // Selection indicator
                if (isSelected)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: vehicleType.color,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Name and description
            Column(
              children: [
                Text(
                  vehicleType.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  vehicleType.description,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Price
            Text(
              displayPrice,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: vehicleType.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingState() {
    final vehicleType = _baseVehicleTypes.firstWhere(
      (v) => v.class_ == _selectedVehicleClass,
      orElse: () => _baseVehicleTypes.first,
    );

    const Color primaryColor = Color(0xFFFF8A00);

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.80,
      maxChildSize: 0.80,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Drag Handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Centered content with fixed height to match waiting screen
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.65,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 400),
                      tween: Tween(begin: 0.0, end: 1.0),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.scale(
                            scale: 0.8 + (0.2 * value),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Large animated spinner
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(primaryColor),
                              ),
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Primary text
                          Text(
                            'Finding your ${vehicleType.name.toLowerCase()} ride',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 12),

                          // Secondary text
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'We\'re connecting you with nearby drivers',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[600],
                                height: 1.5,
                                fontWeight: FontWeight.w400,
                              ),
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
        );
      },
    );
  }

  Widget _buildLoadingStep(String label, bool isActive, Color color) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 2),
          ),
          child: isActive
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.black : Colors.grey[500],
          ),
        ),
      ],
    );
  }
}
