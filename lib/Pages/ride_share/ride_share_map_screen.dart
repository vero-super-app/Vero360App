import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/Pages/ride_share/widgets/map_view_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/place_search_widget.dart';
import 'package:vero360_app/Pages/ride_share/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/Pages/ride_share/widgets/vehicle_type_modal.dart';
import 'package:vero360_app/Pages/ride_share/widgets/ride_waiting_screen.dart';
import 'package:vero360_app/Pages/ride_share/widgets/user_awaiting_driver_screen.dart';
import 'package:vero360_app/Pages/ride_share/widgets/ride_in_progress_screen.dart';
import 'package:vero360_app/Pages/ride_share/widgets/ride_completion_screen.dart';
import 'package:vero360_app/Pages/ride_share/destination_search_screen.dart';
import 'package:vero360_app/models/place_model.dart';
import 'package:vero360_app/models/ride_model.dart';
import 'package:vero360_app/providers/ride_share_provider.dart';
import 'package:vero360_app/services/auth_storage.dart';

class RideShareMapScreen extends ConsumerStatefulWidget {
  const RideShareMapScreen({super.key});

  @override
  ConsumerState<RideShareMapScreen> createState() => _RideShareMapScreenState();
}

class _RideShareMapScreenState extends ConsumerState<RideShareMapScreen>
    with TickerProviderStateMixin {
  GoogleMapController? mapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showBookmarkedPlaces = false;
  bool _isLoadingRide = false;
  Place? _cachedPickupPlace;
  late AnimationController _bottomSheetAnimationController;
  late AnimationController _fadeAnimationController;

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
          barrierColor: Colors.black.withValues(alpha: 0.3),
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
      barrierColor: Colors.black.withValues(alpha: 0.3),
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

  void _showUserAwaitingDriverScreen(DriverInfo driver, String rideId) {
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
              vehicleType: driver.vehicleType ?? 'Standard',
              vehiclePlate: driver.vehiclePlate ?? 'N/A',
              driverRating: driver.rating,
              completedRides: driver.completedRides,
              pickupAddress: 'Your Location',
              pickupLat: position.latitude,
              pickupLng: position.longitude,
              dropoffLat: selectedDropoffPlace.latitude,
              dropoffLng: selectedDropoffPlace.longitude,
              estimatedFare: 250.0,
              driverLocation:
                  LatLng(driver.latitude ?? 0.0, driver.longitude ?? 0.0),
              onStartRide: () {
                _showRideInProgressScreen(
                  rideId,
                  driver.id.toString(),
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
  void initState() {
    super.initState();
    _bottomSheetAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _bottomSheetAnimationController.dispose();
    _fadeAnimationController.dispose();
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
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildModernBackButton(),
                  _buildModernTitle(),
                  _buildModernActionButton(),
                ],
              ),
            ),
          ),
        ),
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: FutureBuilder<bool>(
          future: AuthStorage.isLoggedIn(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A00)),
                ),
              );
            }

            if (!(authSnapshot.data ?? false)) {
              return _buildAuthRequiredScreen();
            }

            return Column(
              children: [
                // Map view - 60% of screen
                Expanded(
                  flex: 3,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final currentLocation =
                          ref.watch(currentLocationProvider);
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
                        loading: () => const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF8A00)),
                          ),
                        ),
                        error: (error, __) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Unable to load location',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Please enable location services',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Search and booking section - 45% of screen
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.white,
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 16, top: 20, bottom: 12),
                              child: Column(
                                children: [
                                  _buildPickupLocationCard(),
                                  const SizedBox(height: 14),
                                  if (selectedDropoffPlace == null)
                                    PlaceSearchWidget(
                                      searchController: _searchController,
                                      focusNode: _searchFocusNode,
                                      onToggleBookmarkedPlaces:
                                          _toggleBookmarkedPlacesModal,
                                      readOnly: true,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const DestinationSearchScreen(),
                                          ),
                                        );
                                      },
                                    )
                                  else
                                    _buildDropoffLocationCard(selectedDropoffPlace),
                                  ],
                                  ),
                                  ),
                                  Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              child: _buildActionButton(selectedDropoffPlace),
                            ),
                          ],
                        ),
                        // Search results popup overlay
                        if (_showBookmarkedPlaces)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            top: 0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                              ),
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 40),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                            alpha: 0.12),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BookmarkedPlacesModal(
                                      onClose: _toggleBookmarkedPlacesModal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPickupLocationCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick-up Location',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your Location',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Current Location',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropoffLocationCard(Place dropoffPlace) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF8A00).withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Color(0xFFFF8A00),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drop-off Location',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  dropoffPlace.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dropoffPlace.address != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      dropoffPlace.address!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[500],
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _searchController.clear();
              setState(() {
                ref.read(selectedDropoffPlaceProvider.notifier).state = null;
              });
              _focusSearchBar();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Edit',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_searchController.text.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Places',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _buildPlaceItem(
                    'Home',
                    '123 Main Street, Downtown',
                    Icons.home_outlined,
                  ),
                  _buildPlaceItem(
                    'Office',
                    '456 Business Ave, Tech Park',
                    Icons.business_outlined,
                  ),
                  _buildPlaceItem(
                    'Favorite Spot',
                    '789 Park Lane, Downtown',
                    Icons.favorite_outline,
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                _buildSearchResultItem(
                  'Downtown Station',
                  '0.5 km away',
                  Icons.location_on_outlined,
                ),
                _buildSearchResultItem(
                  'Central Market',
                  '1.2 km away',
                  Icons.location_on_outlined,
                ),
                _buildSearchResultItem(
                  'Airport Terminal',
                  '8.5 km away',
                  Icons.location_on_outlined,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceItem(String title, String subtitle, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFF8A00),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(String title, String subtitle, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFF8A00),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        builder: (context, value, child) {
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.black87,
              size: 18,
            ),
          );
        },
      ),
    );
  }

  Widget _buildModernTitle() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Book Your Ride',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.3,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          height: 2.5,
          width: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF8A00),
                const Color(0xFFFF8A00).withValues(alpha: 0.4),
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildModernActionButton() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFF8A00),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.favorite_border,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildAuthRequiredScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: Color(0xFFFF8A00),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Sign in to continue',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'You need to be signed in to book a ride',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pushNamed(context, '/login');
            },
            icon: const Icon(Icons.login_rounded, color: Colors.white),
            label: const Text(
              'Go to Sign In',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(Place? selectedDropoffPlace) {
    final isReady = selectedDropoffPlace != null;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8A00),
          disabledBackgroundColor:
              const Color(0xFFFF8A00).withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isLoadingRide ? 4 : 2,
          shadowColor: const Color(0xFFFF8A00).withValues(alpha: 0.4),
        ),
        onPressed: _isLoadingRide
            ? null
            : () => _handleBottomButtonPressed(ref, selectedDropoffPlace),
        icon: _isLoadingRide
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(
                isReady
                    ? Icons.arrow_forward_rounded
                    : Icons.search,
                color: Colors.white,
                size: 24,
              ),
        label: Text(
          isReady
              ? 'Continue to Booking'
              : 'Search Destination',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
