import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/Pages/ride_share/widgets/current_location_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/map_view_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/place_search_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';

class RideShareMapScreen extends ConsumerStatefulWidget {
  const RideShareMapScreen({Key? key}) : super(key: key);

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
    final selectedPickupPlace = ref.watch(selectedPickupPlaceProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Map View
          currentLocation.when(
            data: (position) {
              return MapViewWidget(
                onMapCreated: _onMapCreated,
                initialPosition: position,
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
            top: 120,
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

          // Continue to Booking Button (if place selected)
          if (selectedPickupPlace != null)
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
                    // Navigate to vehicle type selection
                    // TODO: Implement navigation to vehicle type modal
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
      ),
    );
  }
}
