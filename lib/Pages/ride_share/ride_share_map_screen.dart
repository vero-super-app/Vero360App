import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async' show unawaited;
import 'package:vero360_app/Pages/ride_share/widgets/map_view_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/place_search_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/Pages/ride_share/widgets/trip_selector_card.dart';
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
  Place? _cachedPickupPlace;

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _toggleBookmarkedPlacesModal() {
    setState(() {
      _showBookmarkedPlaces = !_showBookmarkedPlaces;
    });
  }

  /// FIXED FOCUS HANDLER
  void _focusSearchBar() {
    // Use a slight delay to ensure any competing gestures complete first
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _unfocusKeyboard() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
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

        _unfocusKeyboard();

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withOpacity(0.3),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => VehicleTypeModal(
            pickupPlace: pickupPlace,
            dropoffPlace: dropoffPlace,
            userLat: position.latitude,
            userLng: position.longitude,
            onRideRequested: (rideId) {
              setState(() => _isLoadingRide = true);
              _showWaitingForDriverScreen(rideId);
            },
          ),
        );
      }
    });
  }

  void _showWaitingForDriverScreen(String rideId) {
    _unfocusKeyboard();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => RideWaitingScreen(
        rideId: rideId,
        onRideAccepted: (driver) {
          setState(() => _isLoadingRide = false);
          _showUserAwaitingDriverScreen(driver, rideId);
        },
        onCancelRide: () {
          setState(() => _isLoadingRide = false);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showUserAwaitingDriverScreen(Driver driver, String rideId) {
    final selectedDropoffPlace = ref.read(selectedDropoffPlaceProvider);
    final currentLoc = ref.read(currentLocationProvider);

    currentLoc.whenData((position) {
      if (mounted && position != null && selectedDropoffPlace != null) {
        if (Navigator.canPop(context)) Navigator.pop(context);

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
              estimatedFare: 250.0,
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
            _showRideCompletionScreen(driverName, driverRating);
          },
        ),
      ),
    );
  }

  void _showRideCompletionScreen(String driverName, double driverRating) {
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Only unfocus if the search field currently has focus
        if (_searchFocusNode.hasFocus) {
          _unfocusKeyboard();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: FutureBuilder<bool>(
          future: AuthStorage.isLoggedIn(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!(authSnapshot.data ?? false)) {
              return _buildAuthRequiredScreen();
            }

            return Stack(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final currentLocation = ref.watch(currentLocationProvider);
                    final dropoffPlace =
                        ref.watch(selectedDropoffPlaceProvider);

                    return currentLocation.when(
                      data: (position) {
                        // Cache pickup place to ensure object identity
                        if (position != null &&
                            (_cachedPickupPlace == null ||
                                _cachedPickupPlace!.latitude !=
                                    position.latitude ||
                                _cachedPickupPlace!.longitude !=
                                    position.longitude)) {
                          _cachedPickupPlace = Place(
                            id: 'current_location',
                            name: 'Your Location',
                            address: 'Current Location',
                            latitude: position.latitude,
                            longitude: position.longitude,
                            type: PlaceType.RECENT,
                          );
                        }

                        return MapViewWidget(
                          onMapCreated: _onMapCreated,
                          initialPosition: position,
                          pickupPlace: _cachedPickupPlace,
                          dropoffPlace: dropoffPlace,
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => const Center(
                        child: Text('Unable to load location'),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {}, // Absorb taps to prevent unfocus
                          child: TripSelectorCard(
                            currentLocation: 'Your Location',
                            selectedDropoffPlace: selectedDropoffPlace,
                            onSelectDropoff: _focusSearchBar,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {}, // Absorb taps to prevent unfocus
                          child: PlaceSearchWidget(
                            searchController: _searchController,
                            focusNode: _searchFocusNode,
                            onToggleBookmarkedPlaces:
                                _toggleBookmarkedPlacesModal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showBookmarkedPlaces)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: BookmarkedPlacesModal(
                      onClose: _toggleBookmarkedPlacesModal,
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {}, // Absorb taps to prevent unfocus
                    child: _buildModernBottomSheet(selectedDropoffPlace),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAuthRequiredScreen() {
    return const Center(
      child: Text('Sign in to continue'),
    );
  }

  Widget _buildModernBottomSheet(Place? selectedDropoffPlace) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8A00),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _isLoadingRide
                    ? null
                    : () =>
                        _handleBottomButtonPressed(ref, selectedDropoffPlace),
                icon: _isLoadingRide
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        selectedDropoffPlace == null
                            ? Icons.search
                            : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                label: Text(
                  selectedDropoffPlace == null
                      ? 'Search Destination'
                      : 'Continue to Booking',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
