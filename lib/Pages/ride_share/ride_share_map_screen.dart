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
import 'package:vero360_app/Pages/ride_share/widgets/ride_active_dialog.dart';
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
  late GoogleMapController mapController;
  final TextEditingController _searchController = TextEditingController();
  bool _showBookmarkedPlaces = false;
  bool _isLoadingRide = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _toggleBookmarkedPlacesModal() {
    setState(() {
      _showBookmarkedPlaces = !_showBookmarkedPlaces;
    });
  }

  Future<void> _handleContinueToBooking(
      WidgetRef ref, Place? dropoffPlace) async {
    // Clear search controller to prevent disposal issues
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
          barrierColor: Colors.black.withValues(alpha: 0.3),
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
          _showRideActiveScreen(driver);
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

  void _showRideActiveScreen(Driver driver) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RideActiveDialog(
        driver: driver,
        onRideCompleted: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation = ref.watch(currentLocationProvider);
    final selectedDropoffPlace = ref.watch(selectedDropoffPlaceProvider);

    return Scaffold(
      body: FutureBuilder<bool>(
        future: AuthStorage.isLoggedIn(),
        builder: (context, authSnapshot) {
          // Check if user is logged in
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!(authSnapshot.data ?? false)) {
            // User is not logged in
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

          // User is logged in, show ride-share UI
          return Stack(
            children: [
              // Map View
              currentLocation.when(
                data: (position) {
                  // Create pickup place from current location
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
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stackTrace) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Error loading location'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          unawaited(
                              ref.refresh(currentLocationProvider.future));
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),

              // Top Container - Current Location
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

              // Search Bar
              Positioned(
                top: 130,
                left: 16,
                right: 16,
                child: PlaceSearchWidget(
                  searchController: _searchController,
                  onToggleBookmarkedPlaces: _toggleBookmarkedPlacesModal,
                ),
              ),

              // Bookmarked Places Modal (Bottom Sheet)
              if (_showBookmarkedPlaces)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: BookmarkedPlacesModal(
                    onClose: _toggleBookmarkedPlacesModal,
                  ),
                ),

              // Continue to Booking Button (if destination selected)
              if (selectedDropoffPlace != null)
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A00),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      onPressed: _isLoadingRide
                          ? null
                          : () => _handleContinueToBooking(
                              ref, selectedDropoffPlace),
                      child: _isLoadingRide
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Continue to Booking',
                              style: TextStyle(
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
