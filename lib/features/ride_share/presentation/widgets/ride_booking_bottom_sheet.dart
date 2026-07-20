import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/destination_search_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';

/// Bottom sheet on the taxi home screen — search bar, ride options, confirm.
class RideBookingBottomSheet extends ConsumerStatefulWidget {
  final Place? dropoffPlace;
  final Place? pickupPlace;
  final void Function(int rideId) onRideRequested;
  final VoidCallback? onClearDropoff;

  const RideBookingBottomSheet({
    required this.dropoffPlace,
    required this.pickupPlace,
    required this.onRideRequested,
    this.onClearDropoff,
    super.key,
  });

  @override
  ConsumerState<RideBookingBottomSheet> createState() =>
      _RideBookingBottomSheetState();
}

class _RideBookingBottomSheetState extends ConsumerState<RideBookingBottomSheet> {
  String? _selectedVehicleClass;
  bool _isRequesting = false;
  double _distance = 0;
  int _duration = 0;
  Map<String, dynamic> _estimatedFares = {};
  bool _faresLoaded = false;

  static const _vehicleTypes = [
    _VehicleOption(
      class_: VehicleClass.standard,
      name: 'Standard',
      description: 'Quick and affordable',
      icon: Icons.directions_car,
    ),
    _VehicleOption(
      class_: VehicleClass.bike,
      name: 'Bike',
      description: 'Fast & economical',
      icon: Icons.two_wheeler,
    ),
    _VehicleOption(
      class_: VehicleClass.executive,
      name: 'Premium',
      description: 'Luxury experience',
      icon: Icons.stars,
      badge: 'Top Rated',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.dropoffPlace != null) {
      _loadFares();
    }
  }

  @override
  void didUpdateWidget(RideBookingBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dropoffPlace?.id != oldWidget.dropoffPlace?.id) {
      _selectedVehicleClass = null;
      _faresLoaded = false;
      _estimatedFares = {};
      if (widget.dropoffPlace != null) {
        _loadFares();
      }
    }
  }

  Future<void> _loadFares() async {
    final pickup = widget.pickupPlace;
    final dropoff = widget.dropoffPlace;
    if (pickup == null || dropoff == null) return;

    try {
      final directionsService = ref.read(googleDirectionsServiceProvider);
      final routeInfo = await directionsService.getRouteInfo(
        originLat: pickup.latitude,
        originLng: pickup.longitude,
        destLat: dropoff.latitude,
        destLng: dropoff.longitude,
      );

      if (!mounted) return;
      setState(() {
        _distance = routeInfo.distanceKm;
        _duration = routeInfo.durationMinutes;
      });

      final rideShareService = ref.read(rideShareServiceProvider);
      final results = await Future.wait(
        _vehicleTypes.map(
          (v) => rideShareService
              .estimateFare(
                pickupLatitude: pickup.latitude,
                pickupLongitude: pickup.longitude,
                dropoffLatitude: dropoff.latitude,
                dropoffLongitude: dropoff.longitude,
                vehicleClass: v.class_,
              )
              .then((fare) => MapEntry(v.class_, fare)),
        ),
      );

      if (mounted) {
        setState(() {
          _estimatedFares = Map.fromEntries(results);
          _faresLoaded = true;
          _selectedVehicleClass ??= VehicleClass.standard;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _faresLoaded = true;
          _selectedVehicleClass ??= VehicleClass.standard;
        });
      }
    }
  }

  Future<void> _confirmRide() async {
    final pickup = widget.pickupPlace;
    final dropoff = widget.dropoffPlace;
    final vehicleClass = _selectedVehicleClass;
    if (pickup == null || dropoff == null || vehicleClass == null) return;

    setState(() => _isRequesting = true);

    final lifecycle = ref.read(rideLifecycleProvider.notifier);
    await lifecycle.requestRide(
      pickupLat: pickup.latitude,
      pickupLng: pickup.longitude,
      dropoffLat: dropoff.latitude,
      dropoffLng: dropoff.longitude,
      vehicleClass: vehicleClass,
      pickupAddress: pickup.address,
      dropoffAddress: dropoff.address,
    );

    if (!mounted) return;

    final result = ref.read(rideLifecycleProvider);
    switch (result) {
      case RideActive(:final ride):
        widget.onRideRequested(ride.id);
      case RideCancelled():
        setState(() => _isRequesting = false);
      case RideError():
        setState(() => _isRequesting = false);
      default:
        setState(() => _isRequesting = false);
    }
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DestinationSearchScreen()),
    );
  }

  String _fareLabel(String vehicleClass) {
    final fareData = _estimatedFares[vehicleClass];
    if (fareData == null) return '...';
    final fareValue = fareData['estimatedFare'];
    double? fare;
    if (fareValue is num) {
      fare = fareValue.toDouble();
    } else if (fareValue is String) {
      fare = double.tryParse(fareValue);
    }
    return fare != null ? 'MK ${fare.toStringAsFixed(0)}' : '...';
  }

  @override
  Widget build(BuildContext context) {
    final hasDropoff = widget.dropoffPlace != null;
    final rideState = ref.watch(rideLifecycleProvider);
    final isBusy = _isRequesting || rideState is RideRequesting;

    return RideShareGlassPanel(
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: RideShareColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SearchBar(
                  dropoffPlace: widget.dropoffPlace,
                  onTap: _openSearch,
                  onClear: widget.onClearDropoff,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasDropoff) ...[
                        Row(
                          children: [
                            Text(
                              'Choose a ride',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: RideShareColors.titleText,
                                  ),
                            ),
                            if (_distance > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: RideShareColors.primarySoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${_distance.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: RideShareColors.primaryDeep,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!_faresLoaded)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(
                                  RideShareColors.primary,
                                ),
                              ),
                            ),
                          )
                        else
                          ..._vehicleTypes.map(
                            (v) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _VehicleCard(
                                option: v,
                                price: _fareLabel(v.class_),
                                durationMin: _duration,
                                isSelected: _selectedVehicleClass == v.class_,
                                onTap: () => setState(
                                  () => _selectedVehicleClass = v.class_,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        _PaymentRow(),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: isBusy || _selectedVehicleClass == null
                                ? null
                                : _confirmRide,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: RideShareColors.primary,
                              disabledBackgroundColor: RideShareColors.primary
                                  .withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              elevation: 4,
                              shadowColor:
                                  RideShareColors.primary.withValues(alpha: 0.4),
                            ),
                            child: isBusy
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Confirm ${_vehicleTypes.firstWhere((v) => v.class_ == _selectedVehicleClass, orElse: () => _vehicleTypes.first).name} Ride',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ] else ...[
                        _QuickShortcut(
                          icon: Icons.map,
                          iconBg: RideShareColors.primaryContainer,
                          title: 'Set on map',
                          subtitle: 'Pick a location visually',
                          onTap: () {},
                        ),
                        const SizedBox(height: 12),
                        _QuickShortcut(
                          icon: Icons.bookmark_outline,
                          iconBg: RideShareColors.primarySoft,
                          title: 'Saved places',
                          subtitle: 'Home, work & favourites',
                          onTap: _openSearch,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final Place? dropoffPlace;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _SearchBar({
    required this.dropoffPlace,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideShareColors.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: RideShareColors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: RideShareColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dropoffPlace?.name ?? 'Where to?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: dropoffPlace != null
                        ? RideShareColors.titleText
                        : RideShareColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (dropoffPlace != null && onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: RideShareColors.onSurfaceVariant,
                  ),
                ),
              Container(
                height: 24,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: RideShareColors.outlineVariant,
              ),
              const Icon(Icons.schedule, size: 20, color: RideShareColors.titleText),
              const SizedBox(width: 4),
              const Text(
                'Now',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: RideShareColors.titleText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleOption {
  final String class_;
  final String name;
  final String description;
  final IconData icon;
  final String? badge;

  const _VehicleOption({
    required this.class_,
    required this.name,
    required this.description,
    required this.icon,
    this.badge,
  });
}

class _VehicleCard extends StatelessWidget {
  final _VehicleOption option;
  final String price;
  final int durationMin;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleCard({
    required this.option,
    required this.price,
    required this.durationMin,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? RideShareColors.primaryContainer
              : RideShareColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? RideShareColors.primary
                : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: RideShareColors.primary.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.12)
                    : RideShareColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                option.icon,
                size: 28,
                color: isSelected
                    ? Colors.white
                    : RideShareColors.primaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        option.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : RideShareColors.titleText,
                        ),
                      ),
                      if (option.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: RideShareColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            option.badge!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${option.description} • ${durationMin > 0 ? '$durationMin min' : '...'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.75)
                          : RideShareColors.bodyText,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : RideShareColors.titleText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.payments_outlined,
              size: 20, color: RideShareColors.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Cash • Pay on arrival',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: RideShareColors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Icon(Icons.chevron_right,
              size: 20, color: RideShareColors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _QuickShortcut extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickShortcut({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideShareColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RideShareColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: RideShareColors.titleText,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: RideShareColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: RideShareColors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
