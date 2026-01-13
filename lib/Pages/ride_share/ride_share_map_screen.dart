import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async' show unawaited;
import 'package:vero360_app/Pages/ride_share/widgets/current_location_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/map_view_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/place_search_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/Pages/ride_share/widgets/vehicle_type_modal.dart';
import 'package:vero360_app/Pages/ride_share/widgets/ride_waiting_screen.dart';
import 'package:vero360_app/Pages/ride_share/widgets/user_awaiting_driver_screen.dart';
import 'package:vero360_app/Pages/ride_share/widgets/ride_in_progress_screen.dart';
import 'package:vero360_app/Pages/ride_share/widgets/ride_completion_screen.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';
import 'package:vero360_app/services/auth_storage.dart';
import 'package:vero360_app/services/firebase_ride_share_service.dart';

class RideShareMapScreen extends ConsumerStatefulWidget {
  const RideShareMapScreen({super.key});

  @override
  ConsumerState<RideShareMapScreen> createState() => _RideShareMapScreenState();
}

class _RideShareMapScreenState extends ConsumerState<RideShareMapScreen> {
  GoogleMapController? mapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showBookmarkedPlaces = false;
  bool _isLoadingRide = false;

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _toggleBookmarkedPlacesModal() {
    setState(() {
      _showBookmarkedPlaces = !_showBookmarkedPlaces;
    });
  }

  void _focusSearchBar() {
    if (!_searchFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }
  }

  void _handleBottomButtonPressed(WidgetRef ref, Place? dropoffPlace) {
    if (dropoffPlace == null) {
      _focusSearchBar();
    } else {
      _handleContinueToBooking(ref, dropoffPlace);
    }
  }

  Future<void> _handleContinueToBooking(
    WidgetRef ref,
    Place? dropoffPlace,
  ) async {
    _searchController.clear();

    final currentLoc = ref.read(currentLocationProvider);

    currentLoc.whenData((position) {
      if (position != null && dropoffPlace != null) {
        final pickupPlace = Place(
          id: 'current_location',
          name: 'Your Location',
          address: 'Current Location',
          latitude: position.latitude,
          longitude: position.longitude,
          type: PlaceType.RECENT,
        );

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withOpacity(0.3),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          builder: (_) => VehicleTypeModal(
            pickupPlace: pickupPlace,
            dropoffPlace: dropoffPlace,
            userLat: position.latitude,
            userLng: position.longitude,
            onRideRequested: (rideId) {
              setState(() {
                _isLoadingRide = true;
              });
              _showWaitingForDriverScreen(rideId);
            },
          ),
        );
      }
    });
  }

  void _showWaitingForDriverScreen(String rideId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => RideWaitingScreen(
        rideId: rideId,
        onRideAccepted: (driver) {
          setState(() {
            _isLoadingRide = false;
          });
          _showUserAwaitingDriverScreen(driver, rideId);
        },
        onCancelRide: () {
          setState(() {
            _isLoadingRide = false;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showUserAwaitingDriverScreen(Driver driver, String rideId) {
    final selectedDropoffPlace = ref.read(selectedDropoffPlaceProvider);
    final currentLoc = ref.read(currentLocationProvider);

    print('DEBUG: Driver accepted - ${driver.name}');
    print('DEBUG: Selected dropoff place - ${selectedDropoffPlace?.name}');

    currentLoc.whenData((position) {
      print('DEBUG: Current position - ${position?.latitude}, ${position?.longitude}');
      
      if (mounted && position != null && selectedDropoffPlace != null) {
        print('DEBUG: Navigating to UserAwaitingDriverScreen');
        
        if (Navigator.canPop(context)) {
          Navigator.pop(context); // Close waiting screen
        }
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserAwaitingDriverScreen(
              rideId: rideId,
              driverName: driver.name,
              vehicleType: driver.vehicleType,
              vehiclePlate: driver.vehiclePlate,
              driverRating: driver.rating,
              completedRides: driver.completedRides,
              pickupAddress: 'Your Location',
              pickupLat: position.latitude,
              pickupLng: position.longitude,
              dropoffLat: selectedDropoffPlace.latitude,
              dropoffLng: selectedDropoffPlace.longitude,
              estimatedFare: 250.0, // Get from ride request
              driverLocation: LatLng(driver.latitude, driver.longitude),
              onStartRide: () {
                _showRideInProgressScreen(
                  rideId,
                  driver.id,
                  driver.name,
                  'Your Location',
                  selectedDropoffPlace.name,
                  250.0,
                  25,
                  driver.rating,
                );
              },
            ),
          ),
        );
      } else {
        print('DEBUG: Navigation blocked - mounted: $mounted, position: $position, dropoff: $selectedDropoffPlace');
      }
    });
  }

  void _showRideInProgressScreen(
    String rideId,
    String driverId,
    String driverName,
    String pickupAddress,
    String dropoffAddress,
    double estimatedFare,
    int estimatedTime,
    double driverRating,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RideInProgressScreen(
          rideId: rideId,
          driverId: driverId,
          passengerName: driverName,
          pickupAddress: pickupAddress,
          dropoffAddress: dropoffAddress,
          estimatedFare: estimatedFare,
          estimatedTime: estimatedTime,
          onRideCompleted: () {
            _showRideCompletionScreen(
              driverName,
              driverRating,
            );
          },
        ),
      ),
    );
  }

  void _showRideCompletionScreen(
    String driverName,
    double driverRating,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RideCompletionScreen(
          baseFare: 50.0,
          distanceFare: 200.0,
          totalFare: 250.0,
          distance: 5.2,
          duration: 12,
          driverName: driverName,
          driverRating: driverRating,
          onPaymentCompleted: () {
            Navigator.pushNamed(context, '/payment');
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDropoffPlace = ref.watch(selectedDropoffPlaceProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true, // ✅ Keeps keyboard from hiding
      body: FutureBuilder<bool>(
        future: AuthStorage.isLoggedIn(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!(authSnapshot.data ?? false)) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 24),
                  const Text(
                    'Authentication Required',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please sign up or log in to use the ride-sharing service',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Go to Login',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              // ✅ Isolated map rebuilds to prevent keyboard loss
              Consumer(
                builder: (context, ref, _) {
                  final currentLocation = ref.watch(currentLocationProvider);
                  return currentLocation.when(
                    data: (position) {
                      final pickupPlace = position != null
                          ? Place(
                              id: 'current_location',
                              name: 'Your Location',
                              address: 'Current Location',
                              latitude: position.latitude,
                              longitude: position.longitude,
                              type: PlaceType.RECENT,
                            )
                          : null;

                      return MapViewWidget(
                        onMapCreated: _onMapCreated,
                        initialPosition: position,
                        pickupPlace: pickupPlace,
                        dropoffPlace: selectedDropoffPlace,
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Error loading location'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              unawaited(
                                ref.refresh(currentLocationProvider.future),
                              );
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Top container
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: CurrentLocationWidget(
                    onRefresh: () {
                      unawaited(ref.refresh(currentLocationProvider.future));
                    },
                  ),
                ),
              ),

              // ✅ Stable Search Bar (does not rebuild)
              Positioned(
                top: 130,
                left: 16,
                right: 16,
                child: PlaceSearchWidget(
                  searchController: _searchController,
                  focusNode: _searchFocusNode,
                  onToggleBookmarkedPlaces: _toggleBookmarkedPlacesModal,
                ),
              ),

              // Bookmarked places modal
              if (_showBookmarkedPlaces)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: BookmarkedPlacesModal(
                    onClose: _toggleBookmarkedPlacesModal,
                  ),
                ),

              // Continue / Search Button
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    onPressed: _isLoadingRide
                        ? null
                        : () => _handleBottomButtonPressed(
                            ref, selectedDropoffPlace),
                    icon: _isLoadingRide
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            selectedDropoffPlace == null
                                ? Icons.search
                                : Icons.arrow_forward_rounded,
                            color: Colors.white,
                          ),
                    label: Text(
                      selectedDropoffPlace == null
                          ? 'Search Destination'
                          : 'Continue to Booking',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
