import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/place_search_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/vehicle_type_modal.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/destination_search_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/passenger_ride_tracking_screen.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';

/// Passenger home for Vero Ride — same layout/flow as Vero Bike,
/// with Standard + Executive vehicle selection (no bike).
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
  bool _isLoadingRide = false;
  Place? _cachedPickupPlace;
  late AnimationController _fadeAnimationController;

  bool _initialising = true;
  bool _isOffline = false;
  bool _isLoggedIn = false;

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _toggleBookmarkedPlacesModal() {
    BookmarkedPlacesModal.show(context);
  }

  void _focusSearchBar() {
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

  void _clearDropoff() {
    _searchController.clear();
    ref.read(selectedDropoffPlaceProvider.notifier).state = null;
    ref.read(cachedRoutePolylineProvider.notifier).state = [];
    _focusSearchBar();
  }

  void _handleBottomButtonPressed(WidgetRef ref, Place? dropoffPlace) {
    if (dropoffPlace == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const DestinationSearchScreen(),
        ),
      );
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
    final lastKnown = ref.read(lastKnownLocationProvider);

    final position = currentLoc.maybeWhen(
          data: (p) => p,
          orElse: () => null,
        ) ??
        lastKnown.maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );

    if (position == null || dropoffPlace == null) return;

    final resolvedPickupAddress = ref.read(pickupDisplayProvider).maybeWhen(
          data: (pickup) => pickup.address,
          orElse: () => 'Current Location',
        );

    final pickupPlace = _cachedPickupPlace ??
        Place(
          id: 'current_location',
          name: 'Your Location',
          address: resolvedPickupAddress,
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
        // Default filter: Standard + Executive (no bike)
        onRideRequested: (rideId, _, __, ___) {
          setState(() => _isLoadingRide = true);
          final rideIdInt = int.tryParse(rideId) ?? 0;
          if (rideIdInt > 0) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _PassengerRideTrackingScreenWrapper(
                  rideId: rideIdInt,
                  onRideEnded: () {
                    setState(() => _isLoadingRide = false);
                    ref.read(rideLifecycleProvider.notifier).reset();
                    ref.read(cachedRoutePolylineProvider.notifier).state = [];
                  },
                ),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _initialise();
  }

  Future<void> _initialise() async {
    final results = await Future.wait([
      _checkConnectivity(),
      AuthStorage.isLoggedIn(),
    ]);

    if (!mounted) return;

    setState(() {
      _isLoggedIn = results[1];
      _initialising = false;
    });

    _fadeAnimationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!LocationPermissionHelper.isKnownGranted) {
        await LocationPermissionHelper.ensureLocationAccess(context);
      }
      if (!mounted) return;
      RecentPlacesManager.loadAndSet(ref);
      BookmarkedPlacesManager.loadAndSet(ref);
      ref.invalidate(currentLocationProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _fadeAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDropoffPlace = ref.watch(selectedDropoffPlaceProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
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
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(),
        ),
        if (selectedDropoffPlace == null)
          Positioned(
            right: 16,
            bottom: screenHeight * bottomSheetHeight + 16,
            child: _MyLocationButton(onTap: _recenterMap),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: RideBookingBottomSheet(
            dropoffPlace: selectedDropoffPlace,
            pickupPlace: _cachedPickupPlace,
            onClearDropoff: _clearDropoff,
            onRideRequested: _navigateToTracking,
            onOpenSavedPlaces: () {
              setState(() => _showBookmarkedPlaces = true);
            },
            onSetOnMap: _openMapPicker,
          ),
        ),
        if (_showBookmarkedPlaces)
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: Colors.black.withValues(alpha: 0.2),
              child: Center(
                child: Container(
                  width: double.infinity,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
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
    );
  }

  Widget _buildTopBar() {
    final pickupAsync = ref.watch(pickupDisplayProvider);
    final profilePictureUrl = pickupAsync.maybeWhen(
      data: (p) => p.profilePictureUrl,
      orElse: () => '',
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: RideShareColors.background.withValues(alpha: 0.85),
          padding: EdgeInsets.fromLTRB(
            8,
            MediaQuery.of(context).padding.top + 4,
            16,
            12,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                color: RideShareColors.titleText,
                style: IconButton.styleFrom(
                  backgroundColor: RideShareColors.surfaceContainerLow,
                  shape: const CircleBorder(),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Vero Ride',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: RideShareColors.titleText,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleBookmarkedPlacesModal,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: RideShareColors.outlineVariant),
                    image: profilePictureUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(profilePictureUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: RideShareColors.primarySoft,
                  ),
                  child: profilePictureUrl.isEmpty
                      ? const Icon(Icons.person,
                          color: RideShareColors.primary, size: 22)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(Place? selectedDropoffPlace) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Consumer(
            builder: (context, ref, _) {
              final currentLocation = ref.watch(currentLocationProvider);
              final lastKnown = ref.watch(lastKnownLocationProvider);
              final dropoffPlace = ref.watch(selectedDropoffPlaceProvider);
              final resolvedPickupAddress =
                  ref.watch(pickupDisplayProvider).maybeWhen(
                        data: (pickup) => pickup.address,
                        orElse: () => 'Current Location',
                      );

              final position = currentLocation.maybeWhen(
                    data: (p) => p,
                    orElse: () => null,
                  ) ??
                  lastKnown.maybeWhen(
                    data: (p) => p,
                    orElse: () => null,
                  );

              if (position != null &&
                  (_cachedPickupPlace == null ||
                      _cachedPickupPlace!.latitude != position.latitude ||
                      _cachedPickupPlace!.longitude != position.longitude ||
                      _cachedPickupPlace!.address != resolvedPickupAddress)) {
                _cachedPickupPlace = Place(
                  id: 'current_location',
                  name: 'Your Location',
                  address: resolvedPickupAddress,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  type: PlaceType.RECENT,
                );
              }

              return currentLocation.when(
                data: (_) => MapViewWidget(
                  onMapCreated: _onMapCreated,
                  initialPosition: position,
                  pickupPlace: _cachedPickupPlace,
                  dropoffPlace: dropoffPlace,
                ),
                loading: () => position != null
                    ? MapViewWidget(
                        onMapCreated: _onMapCreated,
                        initialPosition: position,
                        pickupPlace: _cachedPickupPlace,
                        dropoffPlace: dropoffPlace,
                      )
                    : const Center(
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please enable location services',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          flex: 2,
          child: SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 20,
                        bottom: 12,
                      ),
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
                          horizontal: 16, vertical: 12),
                      child: _buildActionButton(selectedDropoffPlace),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPickupLocationCard() {
    final pickupAsync = ref.watch(pickupDisplayProvider);
    return pickupAsync.when(
      data: (pickup) => _buildPickupCardContent(
        userName: pickup.userName,
        address: pickup.address,
      ),
      loading: () => _buildPickupCardContent(
        userName: 'Your Location',
        address: 'Detecting your location...',
      ),
      error: (_, __) => _buildPickupCardContent(
        userName: 'Your Location',
        address: 'Current Location',
      ),
    );
  }

  Widget _buildPickupCardContent({
    required String userName,
    required String address,
  }) {
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
              color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.my_location_rounded,
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
                  'Pick-up Location',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  userName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    address,
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
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    dropoffPlace.address,
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
            onTap: _clearDropoff,
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

  Widget _buildModernBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
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
      ),
    );
  }

  Widget _buildModernTitle() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Book Your Vero Ride',
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
    return Container(
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
        Icons.local_taxi_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Future<bool> _checkConnectivity() async {
    bool offline = false;
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      offline = result.isEmpty || result.first.rawAddress.isEmpty;
    } catch (_) {
      offline = true;
    }
    _isOffline = offline;
    return !offline;
  }

  Future<void> _retryConnectivity() async {
    setState(() => _initialising = true);
    _fadeAnimationController.reset();
    await _initialise();
  }

  Widget _buildNoInternetScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: Colors.red.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No internet connection',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your data or Wi‑Fi,\nthen try again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _retryConnectivity,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text(
              'Try Again',
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
            'You need to be signed in to book a Vero ride',
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
            onPressed: () => Navigator.pushNamed(context, '/login'),
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
                isReady ? Icons.arrow_forward_rounded : Icons.search,
                color: Colors.white,
                size: 24,
              ),
        label: Text(
          isReady ? 'Continue to Ride Booking' : 'Search Destination',
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

class _PassengerRideTrackingScreenWrapper extends ConsumerWidget {
  final int rideId;
  final VoidCallback? onRideEnded;

  const _PassengerRideTrackingScreenWrapper({
    required this.rideId,
    this.onRideEnded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PassengerRideTrackingScreen(
      rideId: rideId,
      onRideEnded: onRideEnded,
    );
  }
}
