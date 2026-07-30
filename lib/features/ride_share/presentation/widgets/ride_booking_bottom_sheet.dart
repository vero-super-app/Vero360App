import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/destination_search_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_notifier.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_lifecycle_state.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/ride_share_provider.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_completion_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Bottom sheet on the taxi home screen — search bar, ride options, confirm.
class RideBookingBottomSheet extends ConsumerStatefulWidget {
  final Place? dropoffPlace;
  final Place? pickupPlace;
  final void Function(int rideId) onRideRequested;
  final VoidCallback? onClearDropoff;
  final VoidCallback? onOpenSavedPlaces;
  final VoidCallback? onSetOnMap;

  const RideBookingBottomSheet({
    required this.dropoffPlace,
    required this.pickupPlace,
    required this.onRideRequested,
    this.onClearDropoff,
    this.onOpenSavedPlaces,
    this.onSetOnMap,
    super.key,
  });

  @override
  ConsumerState<RideBookingBottomSheet> createState() =>
      _RideBookingBottomSheetState();
}

class _RideBookingBottomSheetState extends ConsumerState<RideBookingBottomSheet> {
  String? _selectedVehicleClass;
  bool _isRequesting = false;
  String? _errorTitle;
  String? _errorMessage;
  Ride? _unpaidRide;
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
    if (dropoff == null || vehicleClass == null) return;

    if (pickup == null) {
      _showRequestFailure(
        title: 'Location needed',
        detail: 'Waiting for your pickup location. Try again in a moment.',
      );
      return;
    }

    setState(() {
      _isRequesting = true;
      _errorTitle = null;
      _errorMessage = null;
      _unpaidRide = null;
    });

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
        setState(() => _isRequesting = false);
        widget.onRideRequested(ride.id);

      case RideCancelled(:final ride):
        final detail = ride.cancellationReason?.trim().isNotEmpty == true
            ? ride.cancellationReason!
            : 'No drivers found in your area right now.';
        _showRequestFailure(
          title: 'No ride available',
          detail: detail,
        );
        ref.read(rideLifecycleProvider.notifier).reset();

      case RideError(:final message):
        if (kDebugMode) {
          debugPrint('[RideBookingBottomSheet] request error: $message');
        }
        final friendly = _friendlyError(message);
        final unpaid = _isUnpaidPaymentError(friendly)
            ? await ref.read(rideShareHttpServiceProvider).findUnpaidCompletedRide()
            : null;
        if (!mounted) return;
        _showRequestFailure(
          title: unpaid != null ? 'Payment required' : 'Could not request ride',
          detail: friendly,
          unpaidRide: unpaid,
        );
        ref.read(rideLifecycleProvider.notifier).reset();

      default:
        _showRequestFailure(
          title: 'No ride available',
          detail: 'No drivers found in your area right now.',
        );
        ref.read(rideLifecycleProvider.notifier).reset();
    }
  }

  void _showRequestFailure({
    required String title,
    required String detail,
    Ride? unpaidRide,
  }) {
    if (!mounted) return;
    setState(() {
      _isRequesting = false;
      _errorTitle = title;
      _errorMessage = detail;
      _unpaidRide = unpaidRide;
    });
    ToastHelper.showCustomToast(
      context,
      title,
      isSuccess: false,
      errorMessage: detail,
    );
  }

  bool _isUnpaidPaymentError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('complete payment') ||
        lower.contains('previous trip') ||
        lower.contains('unpaid');
  }

  Future<void> _openUnpaidPayment() async {
    final unpaid = _unpaidRide ??
        await ref.read(rideShareHttpServiceProvider).findUnpaidCompletedRide();
    if (!mounted || unpaid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RideCompletionScreen(
          ride: unpaid,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _errorTitle = null;
      _errorMessage = null;
      _unpaidRide = null;
    });
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('complete payment') ||
        lower.contains('previous trip')) {
      return 'Please complete payment for your previous trip before booking a new ride.';
    }
    if (lower.contains('no driver') ||
        lower.contains('no ride') ||
        lower.contains('unavailable')) {
      return 'No drivers found in your area right now.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('connection')) {
      return 'Check your internet connection and try again.';
    }
    if (lower.contains('auth') || lower.contains('unauthorized')) {
      return 'Please sign in again to request a ride.';
    }
    // Avoid dumping long stack traces into the UI.
    final cleaned = raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^ApiException:\s*'), '')
        .trim();
    if (cleaned.length > 120) {
      return 'Something went wrong while requesting your ride. Please try again.';
    }
    return cleaned.isEmpty
        ? 'Something went wrong while requesting your ride. Please try again.'
        : cleaned;
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Choose a ride',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: RideShareColors.primaryContainer,
                              ),
                            ),
                            if (_distance > 0)
                              Text(
                                '${_distance.toStringAsFixed(1)} km trip',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: RideShareColors.onSurfaceVariant,
                                ),
                              ),
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
                          SizedBox(
                            height: 132,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _vehicleTypes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final v = _vehicleTypes[index];
                                return _VehicleCard(
                                  option: v,
                                  price: _fareLabel(v.class_),
                                  durationMin: _duration,
                                  isSelected:
                                      _selectedVehicleClass == v.class_,
                                  onTap: () => setState(() {
                                    _selectedVehicleClass = v.class_;
                                    _errorTitle = null;
                                    _errorMessage = null;
                                    _unpaidRide = null;
                                  }),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        _PaymentRow(),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _RequestErrorBanner(
                            title: _errorTitle ?? 'No ride available',
                            message: _errorMessage!,
                            actionLabel:
                                _unpaidRide != null ? 'Pay Now' : null,
                            onAction:
                                _unpaidRide != null ? _openUnpaidPayment : null,
                            onDismiss: () => setState(() {
                              _errorTitle = null;
                              _errorMessage = null;
                              _unpaidRide = null;
                            }),
                          ),
                        ],
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
                                borderRadius: BorderRadius.circular(16),
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
                          onTap: widget.onSetOnMap ?? () {},
                        ),
                        const SizedBox(height: 12),
                        _QuickShortcut(
                          icon: Icons.bookmark_outline,
                          iconBg: RideShareColors.primarySoft,
                          iconColor: RideShareColors.primary,
                          title: 'Saved places',
                          subtitle: 'Home, work & favourites',
                          onTap: widget.onOpenSavedPlaces ?? _openSearch,
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

class _RequestErrorBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _RequestErrorBanner({
    required this.title,
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: Color(0xFFC62828),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFFC62828),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB71C1C),
                    height: 1.35,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: onAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RideShareColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            color: const Color(0xFFC62828),
            visualDensity: VisualDensity.compact,
          ),
        ],
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
    final eta = durationMin > 0 ? '$durationMin min' : '…';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? RideShareColors.primary
                : RideShareColors.outlineVariant.withValues(alpha: 0.25),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.1 : 0.04),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? RideShareColors.primary.withValues(alpha: 0.1)
                    : RideShareColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                option.icon,
                size: 22,
                color: isSelected
                    ? RideShareColors.primaryDeep
                    : RideShareColors.primaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              option.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: RideShareColors.primaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              '$eta • $price',
              style: const TextStyle(
                fontSize: 10,
                color: RideShareColors.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            size: 20,
            color: RideShareColors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Cash • Pay on arrival',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: RideShareColors.primaryContainer,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: RideShareColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _QuickShortcut extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickShortcut({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
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
                child: Icon(
                  icon,
                  color: iconColor ?? Colors.white,
                  size: 22,
                ),
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
