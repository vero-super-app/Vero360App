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
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';

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
  Place? _cachedPickupPlace;
  late AnimationController _bottomSheetAnimationController;
  late AnimationController _fadeAnimationController;

  /// Initialisation state — resolved once in initState, never re-created.
  bool _initialising = true;
  bool _isOffline = false;
  bool _isLoggedIn = false;

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
            onRideRequested: (rideId, fare, distKm, durMin) {
              _navigateToTracking(int.tryParse(rideId) ?? 0);
            },
          ),
        );
      }
    });
  }

  void _navigateToTracking(int rideId) {
    if (rideId <= 0) return;
    _unfocusKeyboard();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PassengerRideTrackingScreenWrapper(
          rideId: rideId,
          onRideEnded: () {
            ref.read(rideLifecycleProvider.notifier).reset();
            ref.read(cachedRoutePolylineProvider.notifier).state = [];
            Navigator.pop(context);
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
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _initialise();
  }

  Future<void> _initialise() async {
    // Run connectivity + auth in parallel, then reveal UI once.
    final results = await Future.wait([
      _checkConnectivity(),
      AuthStorage.isLoggedIn(),
    ]);

    if (!mounted) return;

    final loggedIn = results[1];

    setState(() {
      _isLoggedIn = loggedIn;
      _initialising = false;
    });

    _fadeAnimationController.forward();

    // Load recent places & GPS after frame to avoid jank
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RecentPlacesManager.loadAndSet(ref);
      ref.invalidate(currentLocationProvider);
    });
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
        if (_searchFocusNode.hasFocus) _unfocusKeyboard();
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
        body: _buildBody(selectedDropoffPlace),
      ),
    );
  }

  Widget _buildBody(Place? selectedDropoffPlace) {
    // ---------- still initialising (connectivity + auth) ----------
    if (_initialising) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A00)),
        ),
      );
    }

    // ---------- resolved: offline / not-logged-in / ready ----------
    return FadeTransition(
      opacity: _fadeAnimationController,
      child: _isOffline
          ? _buildNoInternetScreen()
          : !_isLoggedIn
              ? _buildAuthRequiredScreen()
              : _buildMainContent(selectedDropoffPlace),
    );
  }

  Widget _buildMainContent(Place? selectedDropoffPlace) {
    return Column(
      children: [
        // ---- Map section (always rendered; shows default position while GPS loads) ----
        Expanded(
          flex: 3,
          child: _buildMapSection(),
        ),
        // ---- Booking section ----
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.white,
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                                      builder: (_) =>
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
                if (_showBookmarkedPlaces)
                  Positioned.fill(
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
                                color: Colors.black.withValues(alpha: 0.12),
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
  }

  /// Always renders the map — shows the default position immediately while GPS
  /// resolves, then smoothly pans to the user's location once available.
  Widget _buildMapSection() {
    return Consumer(
      builder: (context, ref, _) {
        final currentLocation = ref.watch(currentLocationProvider);
        final lastKnown = ref.watch(lastKnownLocationProvider);
        final dropoffPlace = ref.watch(selectedDropoffPlaceProvider);

        // Use live GPS if available, otherwise fall back to last persisted location
        final position = currentLocation.maybeWhen(
          data: (p) => p,
          orElse: () => null,
        ) ?? lastKnown.maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );

        if (position != null &&
            (_cachedPickupPlace == null ||
                _cachedPickupPlace!.latitude != position.latitude ||
                _cachedPickupPlace!.longitude != position.longitude)) {
          _cachedPickupPlace = Place(
            id: 'current_location',
            name: 'Your Location',
            address: 'Current Location',
            latitude: position.latitude,
            longitude: position.longitude,
            type: PlaceType.RECENT,
          );
        }

        return Stack(
          children: [
            MapViewWidget(
              onMapCreated: _onMapCreated,
              initialPosition: position,
              pickupPlace: _cachedPickupPlace,
              dropoffPlace: dropoffPlace,
            ),
            // Subtle GPS-loading indicator overlay instead of replacing the map
            if (currentLocation.isLoading)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF8A00)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Detecting your location…',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Location error chip
            if (currentLocation.hasError)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_outlined,
                            size: 16, color: Colors.grey[500]),
                        const SizedBox(width: 8),
                        Text(
                          'Enable location services',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPickupLocationCard() {
    final pickupAsync = ref.watch(pickupDisplayProvider);
    return pickupAsync.when(
      // Defensive null coalescing for async provider (avoids runtime Null subtype of String)
      data: (pickup) => _buildPickupCardContent(
        userName:
            pickup.userName, // ignore: unnecessary_null_in_if_null_operators
        address:
            pickup.address, // ignore: unnecessary_null_in_if_null_operators
        profilePictureUrl: pickup
            .profilePictureUrl, // ignore: unnecessary_null_in_if_null_operators
      ),
      loading: () => _buildPickupCardContent(
        userName: 'Your Location',
        address: 'Detecting your location...',
        profilePictureUrl: '',
      ),
      error: (_, __) => _buildPickupCardContent(
        userName: 'Your Location',
        address: 'Current Location',
        profilePictureUrl: '',
      ),
    );
  }

  Widget _buildPickupCardContent({
    required String userName,
    required String address,
    String profilePictureUrl = '',
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
          // Profile picture (from profile) or placeholder
          // CircleAvatar(
          //   radius: 22,
          //   backgroundColor: Color(0xFFFF8A00).withValues(alpha: 0.12),
          //   backgroundImage: profilePictureUrl.isNotEmpty
          //       ? NetworkImage(profilePictureUrl)
          //       : null,
          //   child: profilePictureUrl.isEmpty
          //       ? const Icon(
          //           Icons.person_rounded,
          //           color: Color(0xFFFF8A00),
          //           size: 24,
          //         )
          //       : null,
          // ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFFF8A00).withValues(alpha: 0.12),
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
            onTap: () {
              _searchController.clear();
              ref.read(selectedDropoffPlaceProvider.notifier).state = null;
              ref.read(cachedRoutePolylineProvider.notifier).state = [];
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
    final rideState = ref.watch(rideLifecycleProvider);
    final isBusy = rideState is RideRequesting;

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
          elevation: isBusy ? 4 : 2,
          shadowColor: const Color(0xFFFF8A00).withValues(alpha: 0.4),
        ),
        onPressed: isBusy
            ? null
            : () => _handleBottomButtonPressed(ref, selectedDropoffPlace),
        icon: isBusy
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
          isReady ? 'Continue to Booking' : 'Search Destination',
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

/// Wrapper to provide Riverpod context for the passenger tracking screen
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
