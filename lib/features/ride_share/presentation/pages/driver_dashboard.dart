import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_history_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_online_session.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/map_view_widget.dart';
import 'package:vero360_app/GernalServices/driver_service.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/Home/post_story_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/notification_badge.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/driver_dashboard_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_history_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'driver_request_screen.dart';
import 'become_driver_page.dart';
import 'edit_taxi_screen.dart';
import 'ride_history_screen.dart';
import 'ride_history_detail_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_skeleton_loaders.dart';
import 'package:vero360_app/GernalServices/location_permission_helper.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';

class DriverDashboard extends ConsumerStatefulWidget {
  const DriverDashboard({super.key});

  @override
  ConsumerState<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends ConsumerState<DriverDashboard> {
  static const Color primaryColor = Color(0xFFFF8A00);
  GoogleMapController? mapController;
  Timer? _mapCenteringTimer;
  final DriverService _driverService = DriverService();
  final RideShareHttpService _http = RideShareHttpService();
  final NumberFormat _money = NumberFormat('#,##0', 'en');
  Future<DriverEarningsSummary>? _earningsFuture;
  Future<List<Ride>>? _recentRidesFuture;

  bool get _isOnline => ref.watch(driverOnlineSessionProvider).isOnline;

  Position? get _lastPosition =>
      ref.watch(driverOnlineSessionProvider).lastPosition;

  bool get _hasActiveTrip {
    final lifecycle = ref.read(rideLifecycleProvider);
    return lifecycle is RideActive &&
        (lifecycle.isAccepted ||
            lifecycle.isDriverArrived ||
            lifecycle.isInProgress);
  }

  void _reloadDashboardData({bool notify = true}) {
    final earnings = _http.getDriverEarningsSummary();
    final recent = _http
        .getDriverRideHistory(status: 'COMPLETED', limit: 5)
        .then((page) => page.rides);
    if (notify && mounted) {
      setState(() {
        _earningsFuture = earnings;
        _recentRidesFuture = recent;
      });
    } else {
      _earningsFuture = earnings;
      _recentRidesFuture = recent;
    }
  }

  @override
  void initState() {
    super.initState();
    _reloadDashboardData(notify: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await LocationPermissionHelper.ensureLocationAccess(context);
      if (!mounted) return;
      await _ensureDriverActive();
      await _syncOnlineSessionFromProfile();
      _startMapCentering();
    });
  }

  @override
  void dispose() {
    // Do NOT go offline here — leaving the page must not drop availability
    // or stop the keepAlive [driverOnlineSessionProvider] broadcast.
    mapController?.dispose();
    _stopMapCentering();
    _http.dispose();
    super.dispose();
  }

  /// Ensure driver is marked as active in the backend while the app is open.
  /// Availability for matching still requires the online toggle / session.
  Future<void> _ensureDriverActive() async {
    try {
      final driverProfile = await ref.read(myDriverProfileProvider.future);
      if (driverProfile['id'] != null) {
        await _driverService
            .activateDriver(int.parse(driverProfile['id'].toString()));
        if (kDebugMode) {
          print('[DriverDashboard] ✓ Driver activated successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DriverDashboard] ✗ Error activating driver: $e');
      }
    }
  }

  Future<void> _syncOnlineSessionFromProfile() async {
    try {
      final driver = await ref.read(myDriverProfileProvider.future);
      if (!mounted) return;
      await ref
          .read(driverOnlineSessionProvider.notifier)
          .syncFromDriverProfile(
            driver,
            hasActiveTrip: _hasActiveTrip,
          );
    } catch (e) {
      if (kDebugMode) {
        print('[DriverDashboard] ✗ Error syncing online session: $e');
      }
    }
  }

  /// Start auto-centering map on driver location
  void _startMapCentering() {
    _mapCenteringTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final last = ref.read(driverOnlineSessionProvider).lastPosition;
      if (mapController != null && last != null) {
        await mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(last.latitude, last.longitude),
              zoom: 15.0,
            ),
          ),
        );
      }
    });
  }

  /// Stop map auto-centering
  void _stopMapCentering() {
    _mapCenteringTimer?.cancel();
    _mapCenteringTimer = null;
  }

  /// Story entry + avatar (matches [marketplace_merchant_dashboard] app bar).
  Widget _buildStoryProfileAppBarAction() {
    final user = FirebaseAuth.instance.currentUser;
    final asyncProfile = ref.watch(myDriverProfileProvider);

    String? imageUrl = asyncProfile.maybeWhen(
      data: (driver) {
        final p = driver['user']?['profilepicture']?.toString();
        if (p != null && p.trim().isNotEmpty) return p.trim();
        return null;
      },
      orElse: () => null,
    );
    imageUrl ??= user?.photoURL;

    ImageProvider? backgroundImage;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        backgroundImage = NetworkImage(imageUrl);
      }
    }

    final merchantName = asyncProfile.maybeWhen(
          data: (driver) => driver['user']?['name']?.toString(),
          orElse: () => null,
        ) ??
        user?.displayName ??
        'Ride Driver';

    return Tooltip(
      message: 'Post story (24h)',
      child: GestureDetector(
        onTap: () {
          final uid = user?.uid;
          if (uid == null) {
            ToastHelper.showCustomToast(
              context,
              'Please sign in to post a story',
              isSuccess: false,
              errorMessage: '',
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => PostStoryPage(
                merchantId: uid,
                merchantName: merchantName,
                merchantImageUrl: imageUrl,
                serviceType: 'ride',
              ),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF58529),
                    Color(0xFFDD2A7B),
                    Color(0xFF8134AF),
                    Color(0xFF515BD4),
                  ],
                ),
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: backgroundImage,
                child: backgroundImage == null
                    ? const Icon(Icons.person, size: 18, color: Colors.grey)
                    : null,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 14,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ref.watch(myDriverProfileProvider).when(
                    loading: () => const SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: DriverDashboardSheetSkeleton(),
                    ),
                    error: (error, _) {
                      final errorStr = error.toString().toLowerCase();
                      if (errorStr.contains('404') ||
                          errorStr.contains('not found')) {
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [_buildNoDriverProfile()],
                        );
                      }
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red.shade400, size: 40),
                              const SizedBox(height: 12),
                              const Text(
                                'Could not load driver profile',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () =>
                                    ref.invalidate(myDriverProfileProvider),
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    data: (driver) {
                      if (driver.isEmpty || driver['id'] == null) {
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [_buildNoDriverProfile()],
                        );
                      }
                      return RefreshIndicator(
                        color: RideShareColors.primary,
                        onRefresh: () async {
                          ref.invalidate(myDriverProfileProvider);
                          _reloadDashboardData();
                          await Future.wait([
                            _earningsFuture ?? Future.value(null),
                            _recentRidesFuture ?? Future.value(null),
                            ref.read(myDriverProfileProvider.future),
                          ]);
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          children: [
                            _buildEarningsRow(),
                            const SizedBox(height: 16),
                            _buildDemandMapSection(driver),
                            const SizedBox(height: 16),
                            _buildGoalsAndRating(driver),
                            const SizedBox(height: 18),
                            _buildRecentActivitySection(),
                            const SizedBox(height: 18),
                            _buildActionsSectionContent(context, driver),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      decoration: const BoxDecoration(
        color: RideShareColors.background,
        border: Border(
          bottom: BorderSide(color: RideShareColors.outlineVariant, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop();
              }
            },
            icon: const Icon(Icons.arrow_back),
            color: RideShareColors.titleText,
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: RideShareColors.surfaceContainerLow,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Vero Ride',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: RideShareColors.titleText,
              ),
            ),
          ),
          DriverOnlineToggle(
            isOnline: _isOnline,
            onToggle: _handleOnlineToggle,
          ),
          const SizedBox(width: 10),
          _buildStoryProfileAppBarAction(),
        ],
      ),
    );
  }

  Future<void> _handleOnlineToggle() async {
    final session = ref.read(driverOnlineSessionProvider);
    if (session.isOnline) {
      try {
        await ref.read(driverOnlineSessionProvider.notifier).goOffline();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not go offline: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
      return;
    }
    try {
      final driver = await ref.read(myDriverProfileProvider.future);
      if (!mounted) return;
      final hasTaxi =
          driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;
      final isVerified = _getBoolValue(driver['isVerified']);
      final taxiId = _primaryTaxiId(driver);
      final taxi = _primaryTaxi(driver);
      final taxiActive = (taxi?['status']?.toString() ?? '') == 'ACTIVE';
      if (!hasTaxi || taxiId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Submit vehicle documents first. Open verification to continue.',
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            backgroundColor: Colors.orange.shade800,
            action: SnackBarAction(
              label: 'Verify',
              textColor: Colors.white,
              onPressed: () => _openVerificationWizard(),
            ),
          ),
        );
        return;
      }
      if (!isVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Complete driver verification before going online.',
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            backgroundColor: Colors.orange.shade800,
            action: SnackBarAction(
              label: 'Verify',
              textColor: Colors.white,
              onPressed: () => _openVerificationWizard(),
            ),
          ),
        );
        return;
      }
      if (!taxiActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Your vehicle is still pending operator approval.',
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            backgroundColor: Colors.orange.shade800,
            action: SnackBarAction(
              label: 'Status',
              textColor: Colors.white,
              onPressed: () => _openVerificationWizard(),
            ),
          ),
        );
        return;
      }
      final granted =
          await LocationPermissionHelper.ensureLocationAccess(context);
      if (!mounted || !granted) return;
      await ref.read(driverOnlineSessionProvider.notifier).goOnline(
            taxiId: taxiId,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.from(e, fallback: 'Could not go online')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Widget _buildEarningsRow() {
    return FutureBuilder<DriverEarningsSummary>(
      future: _earningsFuture,
      builder: (context, snap) {
        final todayEarnings = snap.data?.today.earnings ?? 0;
        final todayTrips = snap.data?.today.trips ?? 0;
        final weekTrips = snap.data?.thisWeek.trips ?? 0;
        final trend = weekTrips > 0
            ? '$weekTrips trips this week'
            : 'Go online to start earning';

        return Column(
          children: [
            DriverEarningsSummaryCard(
              amountLabel: formatRideMoney(todayEarnings, _money),
              trendLabel: trend,
            ),
            const SizedBox(height: 12),
            DriverTripsProgressCard(trips: todayTrips),
          ],
        );
      },
    );
  }

  Widget _buildDemandMapSection(Map<String, dynamic> driver) {
    final isVerified = _getBoolValue(driver['isVerified']);
    final hasTaxis =
        driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Demand Map',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: RideShareColors.titleText,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Live coverage around you',
                    style: TextStyle(
                      fontSize: 13,
                      color: RideShareColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final pos = ref
                        .read(driverOnlineSessionProvider)
                        .lastPosition ??
                    await LocationPermissionHelper.getCurrentPositionIfGranted(
                      timeLimit: const Duration(seconds: 4),
                    );
                if (pos != null && mapController != null) {
                  await mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(pos.latitude, pos.longitude),
                      15,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text(
                'Recenter',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: RideShareColors.primaryDeep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RideShareColors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: RideShareColors.primaryContainer.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              MapViewWidget(
                onMapCreated: (controller) {
                  mapController = controller;
                },
                initialPosition: _lastPosition,
                // Nearby taxis are a passenger-facing feature.
                showNearbyVehicles: false,
              ),
              Positioned(
                top: 14,
                left: 14,
                child: DriverGlassChip(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              _isOnline ? RideShareColors.primary : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isOnline
                            ? 'You\'re live, waiting for requests'
                            : 'Go online to receive ride offers',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: RideShareColors.titleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Column(
                  children: [
                    Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        onPressed: () {
                          // Map type toggle placeholder — keeps chrome parity with mock.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Map layers coming soon'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.layers_outlined),
                        color: RideShareColors.titleText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: RideShareColors.primary,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: NotificationBadge(
                        child: IconButton(
                          onPressed: isVerified && hasTaxis
                              ? () => _navigateToRideRequests(context)
                              : null,
                          icon: const Icon(Icons.bolt, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoalsAndRating(Map<String, dynamic> driver) {
    final rating = (_getNumericValue(driver['rating']) as num).toDouble();
    final totalRides = (_getNumericValue(driver['totalRides']) as num).toInt();
    final isVerified = _getBoolValue(driver['isVerified']);

    return FutureBuilder<DriverEarningsSummary>(
      future: _earningsFuture,
      builder: (context, snap) {
        final weekEarned = snap.data?.thisWeek.earnings ?? 0;
        final weekGoal = weekEarned <= 0
            ? 50000.0
            : (weekEarned < 50000
                ? 50000.0
                : (weekEarned / 0.85).ceilToDouble());

        return Column(
          children: [
            DriverWeeklyGoalCard(
              earned: weekEarned,
              goal: weekGoal,
              money: _money,
            ),
            const SizedBox(height: 12),
            DriverRatingCard(
              rating: rating,
              totalRides: totalRides,
              isVerified: isVerified,
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: RideShareColors.titleText,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RideHistoryScreen(
                      mode: RideHistoryMode.driver,
                    ),
                  ),
                );
              },
              child: const Text(
                'View History',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: RideShareColors.primaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Ride>>(
          future: _recentRidesFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Container(
                height: 96,
                decoration: BoxDecoration(
                  color: RideShareColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            }
            final rides = snap.data ?? const <Ride>[];
            if (rides.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: RideShareColors.outlineVariant),
                ),
                child: const Text(
                  'No completed trips yet. Your recent rides will show up here.',
                  style: TextStyle(color: RideShareColors.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: [
                for (final ride in rides.take(3)) ...[
                  DriverRecentActivityTile(
                    title: ride.dropoffAddress?.split(',').first.trim() ??
                        ride.routeLabel,
                    subtitle:
                        'Completed • ${formatRideWhen(ride.endTime ?? ride.createdAt)}',
                    amountLabel: formatRideMoney(
                      ride.tripSummary?.driverEarnings ??
                          ride.driverEarnings ??
                          ride.resolvedFare,
                      _money,
                    ),
                    metaLeft: '${ride.resolvedDistance.toStringAsFixed(1)} km',
                    metaRight: () {
                      if (ride.startTime != null && ride.endTime != null) {
                        final mins =
                            ride.endTime!.difference(ride.startTime!).inMinutes;
                        return '$mins mins';
                      }
                      return null;
                    }(),
                    badge: ride.taxi?.vehicleClass ?? 'Vero Ride',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideHistoryDetailScreen(
                            ride: ride,
                            perspective: RideHistoryPerspective.driver,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoDriverProfile() {
    return Container(
      decoration: BoxDecoration(
        color: RideShareColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: RideShareColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.person_add_outlined,
              size: 48,
              color: RideShareColors.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Driver Profile Not Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: RideShareColors.titleText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You need to create a driver profile to access the driver dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openVerificationWizard,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Start verification'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper to safely get numeric values (handles both int and string)
  dynamic _getNumericValue(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

  /// Helper to safely get boolean values (handles various types)
  bool _getBoolValue(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is num) return value != 0;
    return false;
  }

  /// One vehicle per driver — returns the registered vehicle if any.
  Map<String, dynamic>? _primaryTaxi(Map<String, dynamic> driver) {
    final raw = driver['taxis'];
    if (raw is! List || raw.isEmpty) return null;
    final first = raw.first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
  }

  int? _primaryTaxiId(Map<String, dynamic> driver) {
    final taxi = _primaryTaxi(driver);
    if (taxi == null) return null;
    return int.tryParse('${taxi['id']}');
  }

  Widget _buildActionsSectionContent(
    BuildContext context,
    Map<String, dynamic> driver,
  ) {
    final isVerified = _getBoolValue(driver['isVerified']);
    final hasTaxis =
        driver['taxis'] is List && (driver['taxis'] as List).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Driver Tools',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: RideShareColors.titleText,
          ),
        ),
        const SizedBox(height: 12),
        if (!isVerified || !hasTaxis)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: RideShareColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: RideShareColors.primaryDeep),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Complete setup to start receiving rides',
                    style: TextStyle(
                      fontSize: 13,
                      color: RideShareColors.primaryDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!hasTaxis)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DriverQuickActionButton(
              label: 'Submit Vehicle Docs',
              icon: Icons.add_circle_outline,
              color: RideShareColors.primary,
              onPressed: _openVerificationWizard,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DriverQuickActionButton(
              label: 'Manage Vehicle',
              icon: Icons.directions_car,
              color: RideShareColors.primaryContainer,
              onPressed: () {
                final taxi = _primaryTaxi(driver);
                if (taxi != null) {
                  _showTaxiDetailsDialog(context, taxi);
                }
              },
            ),
          ),
        if (!isVerified)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DriverQuickActionButton(
              label: 'Complete Verification',
              icon: Icons.verified_user,
              color: const Color(0xFF2E7D32),
              onPressed: _openVerificationWizard,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NotificationBadge(
            child: DriverQuickActionButton(
              label: 'View Ride Requests',
              icon: Icons.local_taxi_outlined,
              color: RideShareColors.primary,
              onPressed: isVerified && hasTaxis
                  ? () => _navigateToRideRequests(context)
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DriverQuickActionButton(
            label: 'Trip History & Earnings',
            icon: Icons.history_rounded,
            color: RideShareColors.primaryContainer,
            outlined: true,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RideHistoryScreen(
                    mode: RideHistoryMode.driver,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openVerificationWizard() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BecomeDriverPage()),
    );
    if (mounted) ref.invalidate(myDriverProfileProvider);
  }

  void _showTaxiDetailsDialog(BuildContext context, Map<String, dynamic> taxi) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => EditTaxiScreen(taxi: taxi),
      ),
    )
        .then((result) {
      if (result == true && mounted) {
        ref.invalidate(myDriverProfileProvider);
      }
    });
  }

  void _showQuickAvailabilityToggle(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dev: Quick Availability Toggle'),
        content: const Text(
          'Set your taxi availability status for testing purposes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _toggleTaxiAvailability(false, 'Dev: Manually unavailable');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Set Unavailable'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _toggleTaxiAvailability(true, 'Dev: Manually available');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Set Available'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTaxiAvailability(
    bool isAvailable,
    String reason,
  ) async {
    try {
      final driverProfile = await ref.read(myDriverProfileProvider.future);
      final taxiId = _primaryTaxiId(driverProfile);

      if (taxiId != null) {
        final session = ref.read(driverOnlineSessionProvider.notifier);
        if (isAvailable) {
          await session.goOnline(taxiId: taxiId);
        } else {
          await session.goOffline();
        }
        if (mounted) {
          ref.invalidate(myDriverProfileProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Taxi set to ${isAvailable ? 'available' : 'unavailable'}\nReason: $reason'),
              backgroundColor: isAvailable ? Colors.green : Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.from(e, fallback: 'Error toggling availability')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _navigateToRideRequests(BuildContext context) async {
    try {
      // Get driver profile to extract driver ID and vehicle ID
      final driverProfile = await ref.read(myDriverProfileProvider.future);

      if (driverProfile['id'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Driver profile not found'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }

      // Handle both string and int types for ID
      final driverId = driverProfile['id'].toString();
      final driverName =
          (driverProfile['user']?['name'] ?? 'Driver').toString();
      final driverPhone = (driverProfile['user']?['phone'] ?? '').toString();
      final driverAvatar = driverProfile['user']?['profilepicture']?.toString();

      // Extract taxi ID from taxis list
      int? taxiId;
      final primaryTaxi = _primaryTaxi(driverProfile);
      if (primaryTaxi != null && primaryTaxi.containsKey('id')) {
        taxiId = int.tryParse('${primaryTaxi['id']}');
      }

      if (kDebugMode) {
        print('[DriverDashboard] Navigating to ride requests:');
        print('  Driver ID: $driverId');
        print('  Driver Name: $driverName');
        print('  Taxi ID: $taxiId');
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DriverRequestScreen(
              driverId: driverId,
              driverName: driverName,
              driverPhone: driverPhone,
              driverAvatar: driverAvatar,
              taxiId: taxiId,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[DriverDashboard] Error navigating to ride requests: $e');
        print('StackTrace: $stackTrace');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.from(e, fallback: 'Error loading driver data')),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }
}
