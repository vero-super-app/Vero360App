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
          _errorMessage = 'Failed to calculate fares';
        });
      }
    }
  }

  final List<VehicleTypeOption> _baseVehicleTypes = [
    VehicleTypeOption(
      class_: VehicleClass.economy,
      name: 'Economy',
      description: 'Budget-friendly',
      icon: Icons.directions_car,
      color: const Color(0xFF10B981),
      estimatedPrice: 'Calculating...',
      subtext: 'Standard ride',
      capacity: 4,
    ),
    VehicleTypeOption(
      class_: VehicleClass.comfort,
      name: 'Comfort',
      description: 'More spacious',
      icon: Icons.airport_shuttle,
      color: const Color(0xFF3B82F6),
      estimatedPrice: 'Calculating...',
      subtext: 'Extra legroom',
      capacity: 4,
    ),
    VehicleTypeOption(
      class_: VehicleClass.premium,
      name: 'Premium',
      description: 'Luxury experience',
      icon: Icons.directions_car_filled,
      color: const Color(0xFFFF8A00),
      estimatedPrice: 'Calculating...',
      subtext: 'Premium car',
      capacity: 4,
    ),
    VehicleTypeOption(
      class_: VehicleClass.business,
      name: 'Business',
      description: 'Executive transport',
      icon: Icons.business_center,
      color: const Color(0xFF8B5CF6),
      estimatedPrice: 'Calculating...',
      subtext: 'Full-size vehicle',
      capacity: 6,
    ),
  ];

  List<VehicleTypeOption> get _filteredVehicles {
    if (_filterType == 'all') return _baseVehicleTypes;
    if (_filterType == 'budget') {
      return _baseVehicleTypes
          .where((v) => v.class_ == VehicleClass.economy)
          .toList();
    }
    if (_filterType == 'premium') {
      return _baseVehicleTypes
          .where((v) =>
              v.class_ == VehicleClass.premium ||
              v.class_ == VehicleClass.business)
          .toList();
    }
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
      final estimatedFare = fareEstimate != null
          ? (fareEstimate['estimatedFare'] as num?)?.toDouble() ?? 0.0
          : 0.0;

      final distance = widget.userLat == widget.dropoffPlace.latitude &&
              widget.userLng == widget.dropoffPlace.longitude
          ? 0.0
          : _distance;

      final passengerName =
          await AuthStorage.userNameFromToken() ?? 'Passenger';

      final rideId = await FirebaseRideShareService.createRideRequest(
        passengerId: userIdStr,
        passengerName: passengerName,
        pickupLat: widget.userLat,
        pickupLng: widget.userLng,
        dropoffLat: widget.dropoffPlace.latitude,
        dropoffLng: widget.dropoffPlace.longitude,
        pickupAddress: widget.pickupPlace.address,
        dropoffAddress: widget.dropoffPlace.address,
        estimatedTime: 25,
        estimatedDistance: distance,
        estimatedFare: estimatedFare,
      );

      if (mounted) {
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
              // Handle bar (fixed, not scrolling)
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Choose Your Ride',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildTripSummary(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Filter tabs
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildFilterTabs(),
                      ),

                      const SizedBox(height: 16),

                      // Vehicle types list
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildVehicleList(),
                      ),

                      // Error message
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red[600], size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage ?? '',
                                    style: TextStyle(
                                        color: Colors.red[700], fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),
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

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Budget', 'budget'),
          const SizedBox(width: 8),
          _buildFilterChip('Premium', 'premium'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF8A00) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF8A00) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
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
            'No vehicles available in this category',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Column(
      children: vehicles.asMap().entries.map((entry) {
        final index = entry.key;
        final vehicleType = entry.value;

        return Padding(
          padding:
              EdgeInsets.only(bottom: index < vehicles.length - 1 ? 12 : 0),
          child: _buildVehicleCard(vehicleType),
        );
      }).toList(),
    );
  }

  Widget _buildVehicleCard(VehicleTypeOption vehicleType) {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? vehicleType.color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
          color:
              isSelected ? vehicleType.color.withOpacity(0.04) : Colors.white,
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
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          children: [
            // Top row: Icon, details, selection indicator
            Row(
              children: [
                // Large icon in colored background
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: vehicleType.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    vehicleType.icon,
                    color: vehicleType.color,
                    size: 28,
                  ),
                ),

                const SizedBox(width: 12),

                // Vehicle info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicleType.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehicleType.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '${vehicleType.capacity} passengers',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Selection indicator
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected ? vehicleType.color : Colors.grey[300]!,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    color: isSelected ? vehicleType.color : Colors.white,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Divider
            Container(height: 1, color: Colors.grey[200]),

            const SizedBox(height: 10),

            // Bottom row: Price and details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated fare',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayPrice,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: vehicleType.color,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: vehicleType.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        vehicleType.subtext,
                        style: TextStyle(
                          fontSize: 10,
                          color: vehicleType.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '~10 min',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
