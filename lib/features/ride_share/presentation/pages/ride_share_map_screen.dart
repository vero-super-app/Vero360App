import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/bookmarked_places_modal.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_booking_bottom_sheet.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/passenger_ride_tracking_screen.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/map_location_picker_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

class RideShareMapScreen extends ConsumerStatefulWidget {
  const RideShareMapScreen({super.key});

  @override
  ConsumerState<RideShareMapScreen> createState() => _RideShareMapScreenState();
}

class _RideShareMapScreenState extends ConsumerState<RideShareMapScreen>
    with TickerProviderStateMixin {
  GoogleMapController? mapController;
  bool _showBookmarkedPlaces = false;
  Place? _cachedPickupPlace;
  late AnimationController _fadeAnimationController;

  bool _initialising = true;
  bool _isOffline = false;
  bool _isLoggedIn = false;

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _toggleBookmarkedPlacesModal() {
    setState(() => _showBookmarkedPlaces = !_showBookmarkedPlaces);
  }

  Future<void> _openMapPicker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MapLocationPickerScreen(),
      ),
    );
  }

  void _recenterMap() {
    final pickup = _cachedPickupPlace;
    if (mapController != null && pickup != null) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pickup.latitude, pickup.longitude),
          15,
        ),
      );
    } else {
      ref.invalidate(currentLocationProvider);
    }
  }

  void _navigateToTracking(int rideId) {
    if (rideId <= 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PassengerRideTrackingScreenWrapper(
          rideId: rideId,
          onRideEnded: () {
            ref.read(rideLifecycleProvider.notifier).reset();
            ref.read(cachedRoutePolylineProvider.notifier).state = [];
          },
        ),
      ),
    );
  }

  void _clearDropoff() {
    ref.read(selectedDropoffPlaceProvider.notifier).state = null;
    ref.read(cachedRoutePolylineProvider.notifier).state = [];
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
    _fadeAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialising) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(RideShareColors.primary),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimationController,
      child: _isOffline
          ? _buildNoInternetScreen()
          : !_isLoggedIn
              ? _buildAuthRequiredScreen()
              : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    final selectedDropoffPlace = ref.watch(selectedDropoffPlaceProvider);
    final bottomSheetHeight = selectedDropoffPlace != null ? 0.55 : 0.28;
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        Positioned.fill(child: _buildMapSection()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: screenHeight * 0.15,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    RideShareColors.background.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
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

  Widget _buildMapSection() {
    return Consumer(
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

        return Stack(
          children: [
            MapViewWidget(
              onMapCreated: _onMapCreated,
              initialPosition: position,
              pickupPlace: _cachedPickupPlace,
              dropoffPlace: dropoffPlace,
            ),
            if (currentLocation.isLoading)
              Positioned(
                top: MediaQuery.of(context).padding.top + 72,
                left: 0,
                right: 0,
                child: Center(child: _LocationChip(label: 'Detecting your location…')),
              ),
            if (currentLocation.hasError)
              Positioned(
                top: MediaQuery.of(context).padding.top + 72,
                left: 0,
                right: 0,
                child: Center(
                  child: _LocationChip(
                    label: 'Enable location services',
                    icon: Icons.location_off_outlined,
                  ),
                ),
              ),
          ],
        );
      },
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
              backgroundColor: RideShareColors.primary,
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
              color: RideShareColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: RideShareColors.primary,
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
              backgroundColor: RideShareColors.primary,
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
}

class _MyLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MyLocationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideShareColors.surface,
      elevation: 4,
      shadowColor: RideShareColors.primaryContainer.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: RideShareColors.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: const Icon(
            Icons.my_location,
            color: RideShareColors.titleText,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _LocationChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          if (icon != null)
            Icon(icon, size: 16, color: Colors.grey[500])
          else
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(RideShareColors.primary),
              ),
            ),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
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
