import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/Pages/ride_share/widgets/current_location_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/map_view_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/place_search_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/Pages/ride_share/widgets/vehicle_type_modal.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';
import 'package:vero360_app/services/auth_storage.dart';

class RideShareMapScreen extends ConsumerStatefulWidget {
  const RideShareMapScreen({super.key});

  @override
  ConsumerState<RideShareMapScreen> createState() => _RideShareMapScreenState();
}

class _RideShareMapScreenState extends ConsumerState<RideShareMapScreen> {
  late GoogleMapController mapController;
  final TextEditingController _searchController = TextEditingController();
  bool _showBookmarkedPlaces = false;

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
                          ref.refresh(currentLocationProvider);
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
                      ref.refresh(currentLocationProvider);
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
                      onPressed: () {
                        final currentLoc = ref.read(currentLocationProvider);
                        currentLoc.whenData((position) {
                          if (position != null &&
                              selectedDropoffPlace != null) {
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
                                dropoffPlace: selectedDropoffPlace,
                                userLat: position.latitude,
                                userLng: position.longitude,
                              ),
                            );
                          }
                        });
                      },
                      child: const Text(
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
