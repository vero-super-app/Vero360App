import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_section_frame.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// One vehicle: its live state, the rental on it, and the four things a
/// company actually changes from a phone (rate, documents, service, listing).
class CarHireCompanyUnitPage extends ConsumerStatefulWidget {
  const CarHireCompanyUnitPage({
    super.key,
    required this.unit,
    required this.access,
  });

  final FleetUnit unit;
  final CompanyAccess access;

  @override
  ConsumerState<CarHireCompanyUnitPage> createState() =>
      _CarHireCompanyUnitPageState();
}

class _CarHireCompanyUnitPageState
    extends ConsumerState<CarHireCompanyUnitPage> {
  bool _busy = false;

  FleetUnit get _fallback => widget.unit;

  FleetUnit _current(List<FleetUnit>? units) {
    if (units == null) return _fallback;
    for (final unit in units) {
      if (unit.id == _fallback.id) return unit;
    }
    return _fallback;
  }

  Future<void> _patch(
    FleetUnit unit,
    Map<String, dynamic> changes, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(carHireApiProvider).updateCompanyCar(unit.id, changes);
      ref.invalidate(companyFleetProvider);
      ref.invalidate(companyAnalyticsProvider);
      if (!mounted) return;
      showCompanySnack(context, success);
    } catch (error) {
      if (!mounted) return;
      showCompanySnack(
        context,
        error is CarHireApiException
            ? error.message
            : 'That change could not be saved.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAvailability(FleetUnit unit, bool available) async {
    await _patch(
      unit,
      <String, dynamic>{'isAvailable': available},
      success: available
          ? '${unit.plate} is available for bookings.'
          : '${unit.plate} is out of service.',
    );
  }

  Future<void> _confirmDelete(FleetUnit unit, CarHireBooking? booking) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CarHirePalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DeleteSheet(unit: unit, booking: booking),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(carHireApiProvider).deleteCompanyCar(unit.id);
      ref.invalidate(companyFleetProvider);
      ref.invalidate(companyAnalyticsProvider);
      ref.invalidate(companyBookingsProvider);
      if (!mounted) return;
      showCompanySnack(context, '${unit.plate} was removed from the fleet.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showCompanySnack(
        context,
        error is CarHireApiException
            ? error.message
            : 'The vehicle could not be removed.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(companyFleetProvider);
    final unit = _current(fleet.value);
    final bookingAsync = ref.watch(unitActiveBookingProvider(unit.id));
    final booking = bookingAsync.value;
    final analytics = ref.watch(companyAnalyticsProvider).value;

    final canManage = widget.access.canManageFleet;

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Vehicle',
        actions: [
          if (canManage)
            CarHireIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit details',
              onTap: _busy
                  ? () {}
                  : () => _openSheet(
                      _DetailsSheet(unit: unit, access: widget.access),
                    ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        color: CarHirePalette.accent,
        onRefresh: () async {
          ref.invalidate(companyFleetProvider);
          ref.invalidate(unitActiveBookingProvider(unit.id));
          ref.invalidate(companyComplianceProvider(unit.id));
          ref.invalidate(companyMaintenanceBlocksProvider(unit.id));
          try {
            await ref.read(companyFleetProvider.future);
          } catch (_) {
            // The page keeps its last good snapshot.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (fleet.hasError)
              CarHireSectionStaleStrip(
                message:
                    'Showing the details you opened. Live fleet data could '
                    'not refresh.',
                padding: const EdgeInsets.only(bottom: 10),
                onRefresh: () => ref.invalidate(companyFleetProvider),
              ),
            _StatusBar(
              unit: unit,
              booking: booking,
              busy: _busy || !canManage,
              onAvailable: () => _setAvailability(unit, true),
              onOutOfService: () => _setAvailability(unit, false),
              onBooking: booking == null
                  ? null
                  : () => CarHireRoutes.openCompanyBooking(
                      context,
                      bookingId: booking.id,
                    ),
            ),
            const SizedBox(height: 12),
            _HeroCard(unit: unit),
            const SizedBox(height: 12),
            _SnapshotCard(unit: unit),
            const SizedBox(height: 12),
            _LocationCard(unit: unit),
            const SizedBox(height: 12),
            _ReservationCard(
              booking: booking,
              loading: bookingAsync.isLoading && !bookingAsync.hasValue,
              error: bookingAsync.hasError && !bookingAsync.hasValue,
              onRetry: () => ref.invalidate(unitActiveBookingProvider(unit.id)),
              unit: unit,
              onOpen: booking == null
                  ? null
                  : () => CarHireRoutes.openCompanyBooking(
                      context,
                      bookingId: booking.id,
                    ),
              onBlock: canManage
                  ? () => showCompanyBlockSheet(context, unit: unit)
                  : null,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Management',
                    style: CarHireType.title.copyWith(fontSize: 14),
                  ),
                ),
                if (analytics != null)
                  Text(
                    '${analytics.utilizationRate}% fleet use',
                    style: CarHireType.labelSmall.copyWith(fontSize: 10),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _ManagementGrid(
              unit: unit,
              enabled: canManage,
              onRates: () =>
                  _openSheet(_DetailsSheet(unit: unit, access: widget.access)),
              onDocuments: () => _openSheet(_DocumentsSheet(unit: unit)),
              onService: () => _openSheet(_ServiceSheet(unit: unit)),
              onListing: () => _openSheet(_ListingSheet(unit: unit)),
            ),
            if (canManage) ...[
              const SizedBox(height: 20),
              _DangerZone(
                unit: unit,
                busy: _busy,
                onRemove: () => _confirmDelete(unit, booking),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(Widget sheet) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CarHirePalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => sheet,
    );
  }
}

// ---------------------------------------------------------------------------
// Status and identity
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.unit,
    required this.booking,
    required this.busy,
    required this.onAvailable,
    required this.onOutOfService,
    required this.onBooking,
  });

  final FleetUnit unit;
  final CarHireBooking? booking;
  final bool busy;
  final VoidCallback onAvailable;
  final VoidCallback onOutOfService;
  final VoidCallback? onBooking;

  @override
  Widget build(BuildContext context) {
    final onRent = booking != null;
    final available = !onRent && unit.car.isAvailable;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          if (onRent)
            Expanded(
              child: _StatusTab(
                label: 'On rent',
                dot: CarHirePalette.accent,
                selected: true,
                onTap: onBooking,
              ),
            ),
          if (!onRent) ...[
            Expanded(
              child: _StatusTab(
                label: 'Available',
                dot: CarHirePalette.success,
                selected: available,
                onTap: busy ? null : onAvailable,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _StatusTab(
                label: 'Out of service',
                dot: CarHirePalette.muted,
                selected: !available,
                onTap: busy ? null : onOutOfService,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.dot,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color dot;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: CarHireShape.fast,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? CarHirePalette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: CarHirePalette.primary.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? CarHirePalette.onSurface
                      : CarHirePalette.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.unit});

  final FleetUnit unit;

  @override
  Widget build(BuildContext context) {
    final images = unit.car.galleryImages;
    final listing = unit.car.listingStatus;
    final tracker = unit.tracker;

    return CarHireSurface(
      padding: const EdgeInsets.all(10),
      radius: 18,
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              height: 176,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (images.isEmpty)
                    _ImagePlaceholder()
                  else
                    ResilientCachedNetworkImage(
                      url: images.first,
                      fit: BoxFit.cover,
                      height: 176,
                      memCacheWidth: 900,
                    ),
                  Positioned(
                    left: 9,
                    top: 9,
                    child: CarHirePill(
                      label: listing.label,
                      background: listing == ListingStatus.published
                          ? CarHirePalette.primary.withValues(alpha: 0.82)
                          : Colors.white.withValues(alpha: 0.94),
                      foreground: listing == ListingStatus.published
                          ? Colors.white
                          : CarHirePalette.onSurface,
                      fontSize: 9.5,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 9,
                    top: 9,
                    child: CarHirePill(
                      label: tracker == null ? 'No tracker' : 'GPS paired',
                      icon: tracker == null
                          ? Icons.sensors_off_rounded
                          : Icons.sensors_rounded,
                      background: Colors.white.withValues(alpha: 0.94),
                      foreground: tracker == null
                          ? CarHirePalette.muted
                          : CarHirePalette.onSurface,
                      fontSize: 9.5,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (images.length > 1) ...[
            const SizedBox(height: 7),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length - 1,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 58,
                    height: 42,
                    child: ResilientCachedNetworkImage(
                      url: images[index + 1],
                      fit: BoxFit.cover,
                      height: 42,
                      memCacheWidth: 260,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        unit.car.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CarHireType.titleLarge.copyWith(fontSize: 19),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CarHirePalette.surfaceContainer,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        unit.plate,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: CarHirePalette.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (unit.car.subtitle.trim().isNotEmpty) unit.car.subtitle,
                    'Fleet #${unit.id}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: CarHirePalette.surfaceLow,
      alignment: Alignment.center,
      child: const Icon(
        Icons.directions_car_filled_rounded,
        size: 42,
        color: CarHirePalette.outlineVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snapshot
// ---------------------------------------------------------------------------

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.unit});

  final FleetUnit unit;

  @override
  Widget build(BuildContext context) {
    final car = unit.car;
    final rate = car.dailyRate > 0
        ? companyMoney(car.dailyRate, currency: car.currency)
        : 'Not set';

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.payments_outlined,
                  value: rate,
                  label: 'Daily rate',
                  accent: true,
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: Icons.airline_seat_recline_extra_rounded,
                  value: car.seats == null ? '—' : '${car.seats}',
                  label: 'Seats',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.settings_suggest_outlined,
                  value: _humanize(car.transmission),
                  label: 'Transmission',
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: _fuelIcon(car.fuelType),
                  value: _humanize(car.fuelType),
                  label: 'Fuel',
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (car.year != null) _MiniTag(label: '${car.year}'),
              if (car.bodyType != null && car.bodyType!.trim().isNotEmpty)
                _MiniTag(label: _humanize(car.bodyType)),
              if (car.color != null && car.color!.trim().isNotEmpty)
                _MiniTag(label: _humanize(car.color)),
              if (car.minRentalDays > 1)
                _MiniTag(label: 'Min ${car.minRentalDays} days'),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _fuelIcon(String? fuel) {
    final value = (fuel ?? '').toUpperCase();
    if (value.contains('ELECTRIC')) return Icons.bolt_rounded;
    if (value.contains('HYBRID')) return Icons.eco_rounded;
    return Icons.local_gas_station_outlined;
  }

  static String _humanize(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || text == 'UNKNOWN') return '—';
    final lower = text.toLowerCase().replaceAll('_', ' ');
    return lower[0].toUpperCase() + lower.substring(1);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: CarHirePalette.surface,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 15,
            color: accent ? CarHirePalette.accent : CarHirePalette.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: accent
                      ? CarHirePalette.accent
                      : CarHirePalette.onSurface,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CarHireType.labelSmall.copyWith(fontSize: 9.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CarHirePalette.surface,
        borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: CarHirePalette.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

class _LocationCard extends ConsumerWidget {
  const _LocationCard({required this.unit});

  final FleetUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = unit.tracker;
    final latitude = tracker?.latitude ?? unit.car.latitude;
    final longitude = tracker?.longitude ?? unit.car.longitude;
    final hasFix = latitude != null && longitude != null;

    final branchesAsync = unit.operatorId == null
        ? null
        : ref.watch(companyBranchesProvider(unit.operatorId!));
    final branches = branchesAsync?.value;
    String? branchName;
    if (branches != null && unit.locationId != null) {
      for (final branch in branches) {
        if (branch.id == unit.locationId) branchName = branch.name;
      }
    }
    final branchFailed =
        branchesAsync != null &&
        branchesAsync.hasError &&
        !branchesAsync.hasValue &&
        unit.locationId != null;

    final place = [
      ?branchName,
      if (unit.car.pickupArea != null && unit.car.pickupArea!.trim().isNotEmpty)
        unit.car.pickupArea!,
    ].join(' · ');

    return CarHireSurface(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.near_me_outlined,
                size: 16,
                color: CarHirePalette.accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Location',
                  style: CarHireType.title.copyWith(fontSize: 13.5),
                ),
              ),
              if (hasFix)
                CarHirePill(
                  label: tracker?.lastUpdate == null
                      ? 'GPS fix'
                      : 'Fix ${CarHireFormatters.formatTime(tracker!.lastUpdate!.toLocal())}',
                  background: CarHirePalette.accentPale,
                  foreground: CarHirePalette.onAccentSoft,
                  fontSize: 9.5,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (branchFailed) ...[
            CarHireSectionErrorStrip(
              message: 'Branch details could not load.',
              padding: EdgeInsets.zero,
              onRetry: () =>
                  ref.invalidate(companyBranchesProvider(unit.operatorId!)),
            ),
            const SizedBox(height: 7),
          ],
          if (place.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: CarHirePalette.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CarHireType.bodySmall.copyWith(
                      color: CarHirePalette.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          if (hasFix)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${latitude.toStringAsFixed(5)}, '
                    '${longitude.toStringAsFixed(5)}'
                    '${tracker?.speed == null ? '' : ' · ${tracker!.speed!.toStringAsFixed(0)} km/h'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CarHireType.bodySmall.copyWith(fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text:
                            '${latitude.toStringAsFixed(5)}, '
                            '${longitude.toStringAsFixed(5)}',
                      ),
                    );
                    if (!context.mounted) return;
                    showCompanySnack(context, 'Coordinates copied.');
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: CarHirePalette.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Copy',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          else
            Text(
              tracker == null
                  ? 'No tracker paired yet. Save the car again from the '
                        'vehicle form or pair hardware on the web workspace.'
                  : 'Tracker ${tracker.deviceLabel} is paired but has not '
                        'reported a position yet.',
              style: CarHireType.bodySmall.copyWith(fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active reservation
// ---------------------------------------------------------------------------

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.booking,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.unit,
    required this.onOpen,
    required this.onBlock,
  });

  final CarHireBooking? booking;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;
  final FleetUnit unit;
  final VoidCallback? onOpen;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    if (loading && booking == null) {
      return const CarHireSurface(
        padding: EdgeInsets.fromLTRB(13, 12, 13, 12),
        radius: 16,
        child: CarHireCompanyRowSkeleton(count: 2),
      );
    }

    if (booking == null && error) {
      return CarHireSurface(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CarHireSectionErrorStrip(
              title: 'Live rental not checked',
              message:
                  'We could not read active rentals. This car may be on '
                  'rent — open the booking inbox before handing it out.',
              padding: EdgeInsets.zero,
              onRetry: onRetry,
            ),
            if (onBlock != null && unit.car.isAvailable) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onBlock,
                  style: TextButton.styleFrom(
                    foregroundColor: CarHirePalette.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Block dates',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (booking == null) {
      return CarHireSurface(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        radius: 16,
        child: Row(
          children: [
            const Icon(
              Icons.event_available_outlined,
              size: 17,
              color: CarHirePalette.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                unit.car.isAvailable
                    ? 'No rental right now · open for bookings.'
                    : 'Out of service · not accepting bookings.',
                style: CarHireType.bodySmall.copyWith(fontSize: 11.5),
              ),
            ),
            if (onBlock != null && unit.car.isAvailable)
              TextButton(
                onPressed: onBlock,
                style: TextButton.styleFrom(
                  foregroundColor: CarHirePalette.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Block dates',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      );
    }

    final active = booking!;
    final name = active.renterName?.trim();
    final initials = _initials(name);
    final daysLeft = active.endAt?.difference(DateTime.now()).inDays;

    return CarHireSurface(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_ind_outlined,
                size: 16,
                color: CarHirePalette.accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Active rental',
                  style: CarHireType.title.copyWith(fontSize: 13.5),
                ),
              ),
              if (daysLeft != null && daysLeft >= 0)
                CarHirePill(
                  label: daysLeft == 0
                      ? 'Returns today'
                      : '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
                  background: CarHirePalette.accentPale,
                  foreground: CarHirePalette.onAccentSoft,
                  fontSize: 9.5,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: CarHirePalette.surfaceHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: CarHirePalette.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == null || name.isEmpty ? 'Renter' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CarHireType.title.copyWith(fontSize: 12),
                      ),
                      Text(
                        active.bookingNumberLabel,
                        style: CarHireType.labelSmall.copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      companyMoney(active.total, currency: active.currency),
                      style: CarHireType.title.copyWith(
                        fontSize: 12,
                        color: CarHirePalette.accent,
                      ),
                    ),
                    Text(
                      'Booking total',
                      style: CarHireType.labelSmall.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _TimePoint(
                  label: 'Pickup',
                  value: active.startAt == null
                      ? '—'
                      : CarHireFormatters.formatDateTime(
                          active.startAt!.toLocal(),
                        ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: CarHirePalette.muted,
                ),
              ),
              Expanded(
                child: _TimePoint(
                  label: 'Return due',
                  value: active.endAt == null
                      ? '—'
                      : CarHireFormatters.formatDateTime(
                          active.endAt!.toLocal(),
                        ),
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (onOpen != null)
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: CarHirePalette.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CarHireShape.pillRadius,
                          ),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Open booking'),
                    ),
                  ),
                ),
              if (onOpen != null && onBlock != null) const SizedBox(width: 8),
              if (onBlock != null)
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: onBlock,
                      style: carHireGhostButton(),
                      child: const Text(
                        'Block dates',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class _TimePoint extends StatelessWidget {
  const _TimePoint({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: CarHireType.labelSmall.copyWith(fontSize: 9.5)),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: CarHirePalette.onSurface,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Management
// ---------------------------------------------------------------------------

class _ManagementGrid extends ConsumerWidget {
  const _ManagementGrid({
    required this.unit,
    required this.enabled,
    required this.onRates,
    required this.onDocuments,
    required this.onService,
    required this.onListing,
  });

  final FleetUnit unit;
  final bool enabled;
  final VoidCallback onRates;
  final VoidCallback onDocuments;
  final VoidCallback onService;
  final VoidCallback onListing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complianceState = ref.watch(companyComplianceProvider(unit.id));
    final compliance = complianceState.value;
    final blocksState = ref.watch(companyMaintenanceBlocksProvider(unit.id));
    final blocks = blocksState.value ?? const [];
    final activeBlocks = blocks.where((block) => block.isActive).length;
    final service = unit.nextServiceDueAt;
    final complianceFailed = complianceState.hasError && compliance == null;
    final blocksFailed = blocksState.hasError && !blocksState.hasValue;

    final documentNote = compliance == null
        ? complianceFailed
              ? 'Could not check · retry'
              : 'Checking…'
        : compliance.compliant
        ? 'Approved'
        : compliance.issueCount == 1
        ? '1 document to fix'
        : '${compliance.issueCount} documents to fix';

    final serviceNote = [
      if (service == null)
        'No service date'
      else if (unit.serviceDueSoon)
        'Due ${CarHireFormatters.formatDate(service)}'
      else
        'Next ${CarHireFormatters.formatDate(service)}',
      if (blocksFailed)
        'Blocks unavailable'
      else if (activeBlocks > 0)
        activeBlocks == 1 ? '1 active block' : '$activeBlocks active blocks',
    ].join(' · ');

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 1.36,
      children: [
        _ModuleTile(
          icon: Icons.payments_outlined,
          iconBackground: CarHirePalette.accentPale,
          iconColor: CarHirePalette.onAccentSoft,
          title: 'Pricing & rates',
          subtitle: unit.car.dailyRate > 0
              ? '${companyMoney(unit.car.dailyRate, currency: unit.car.currency)} / day'
              : 'Set a daily rate',
          footer:
              'Min ${unit.car.minRentalDays} '
              '${unit.car.minRentalDays == 1 ? 'day' : 'days'}',
          footerTone: CarHirePalette.accent,
          onTap: enabled ? onRates : null,
        ),
        _ModuleTile(
          icon: Icons.verified_user_outlined,
          iconBackground: CarHirePalette.surfaceContainer,
          iconColor: CarHirePalette.primary,
          title: 'Documents',
          subtitle: documentNote,
          footer: complianceFailed
              ? 'Retry'
              : compliance != null && !compliance.compliant
              ? 'Review'
              : 'Private',
          footerTone: complianceFailed
              ? CarHirePalette.warning
              : compliance != null && !compliance.compliant
              ? CarHirePalette.warning
              : CarHirePalette.muted,
          onTap: enabled
              ? complianceFailed
                    ? () => ref.invalidate(companyComplianceProvider(unit.id))
                    : onDocuments
              : null,
        ),
        _ModuleTile(
          icon: Icons.build_circle_outlined,
          iconBackground: CarHirePalette.surfaceContainer,
          iconColor: CarHirePalette.primary,
          title: 'Service & blocks',
          subtitle: serviceNote,
          footer: 'Open',
          footerTone: CarHirePalette.muted,
          onTap: enabled ? onService : null,
        ),
        _ModuleTile(
          icon: Icons.key_outlined,
          iconBackground: CarHirePalette.surfaceContainer,
          iconColor: CarHirePalette.primary,
          title: 'Listing',
          subtitle: unit.car.listingStatus.label,
          footer: unit.tracker == null ? 'No GPS' : 'GPS paired',
          footerTone: unit.tracker == null
              ? CarHirePalette.muted
              : CarHirePalette.success,
          onTap: enabled ? onListing : null,
        ),
      ],
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.footer,
    required this.footerTone,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String footer;
  final Color footerTone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CarHirePalette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CarHirePalette.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: CarHirePalette.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CarHireType.labelSmall.copyWith(fontSize: 9.5),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      footer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: footerTone,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: CarHirePalette.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.unit,
    required this.busy,
    required this.onRemove,
  });

  final FleetUnit unit;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: CarHirePalette.errorSoft.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: CarHirePalette.error,
              ),
              const SizedBox(width: 7),
              Text(
                'Remove from fleet',
                style: CarHireType.title.copyWith(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Removing ${unit.plate} stops tracking, unlinks its GPS device and '
            'archives its booking history.',
            style: CarHireType.bodySmall.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: busy ? null : onRemove,
              style: FilledButton.styleFrom(
                backgroundColor: CarHirePalette.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.delete_forever_outlined, size: 17),
              label: const Text('Remove vehicle from fleet'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.unit, required this.booking});

  final FleetUnit unit;
  final CarHireBooking? booking;

  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: CarHirePalette.errorSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 22,
              color: CarHirePalette.error,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Remove ${widget.unit.car.title}?',
            style: CarHireType.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            widget.booking == null
                ? '${widget.unit.plate} will leave the fleet. This cannot be '
                      'undone from the app.'
                : '${widget.unit.plate} has an active rental. Removing the '
                      'unit does not cancel that booking — open the booking '
                      'first if the renter still needs the car.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: CarHirePalette.error,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Confirm removal'),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: CarHirePalette.onSurface,
                minimumSize: const Size.fromHeight(42),
              ),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Details, documents, service and listing sheets
// ---------------------------------------------------------------------------

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = (MediaQuery.sizeOf(context).height - insets) * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: CarHireType.titleLarge),
                      const SizedBox(height: 3),
                      Text(subtitle, style: CarHireType.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: CarHirePalette.hairline),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.paddingOf(context).bottom + 22,
              ),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsSheet extends ConsumerStatefulWidget {
  const _DetailsSheet({required this.unit, required this.access});

  final FleetUnit unit;
  final CompanyAccess access;

  @override
  ConsumerState<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends ConsumerState<_DetailsSheet> {
  static const _transmissions = <(String, String)>[
    ('AUTOMATIC', 'Automatic'),
    ('MANUAL', 'Manual'),
  ];
  static const _fuels = <(String, String)>[
    ('PETROL', 'Petrol'),
    ('DIESEL', 'Diesel'),
    ('HYBRID', 'Hybrid'),
    ('ELECTRIC', 'Electric'),
  ];
  static const _bodyTypes = <(String, String)>[
    ('SEDAN', 'Sedan'),
    ('SUV', 'SUV'),
    ('HATCHBACK', 'Hatchback'),
    ('EXECUTIVE', 'Executive'),
    ('PICKUP', 'Pickup'),
    ('VAN', 'Van'),
  ];

  late final TextEditingController _plate;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _color;
  late final TextEditingController _seats;
  late final TextEditingController _rate;
  late final TextEditingController _deposit;
  late final TextEditingController _minDays;
  late final TextEditingController _maxDays;

  late String _transmission;
  late String _fuel;
  late String _body;
  String? _branchId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final car = widget.unit.car;
    _plate = TextEditingController(text: widget.unit.licensePlate ?? '');
    _make = TextEditingController(text: car.make);
    _model = TextEditingController(text: car.model);
    _year = TextEditingController(text: car.year?.toString() ?? '');
    _color = TextEditingController(text: car.color ?? '');
    _seats = TextEditingController(text: car.seats?.toString() ?? '');
    _rate = TextEditingController(
      text: car.dailyRate > 0
          ? car.dailyRate.roundToDouble() == car.dailyRate
                ? car.dailyRate.round().toString()
                : car.dailyRate.toString()
          : '',
    );
    _deposit = TextEditingController(
      text: car.depositAmount > 0 ? car.depositAmount.round().toString() : '',
    );
    _minDays = TextEditingController(text: '${car.minRentalDays}');
    _maxDays = TextEditingController(
      text: car.maxRentalDays == null ? '' : '${car.maxRentalDays}',
    );
    _transmission = (car.transmission ?? 'AUTOMATIC').toUpperCase();
    _fuel = (car.fuelType ?? 'PETROL').toUpperCase();
    _body = (car.bodyType ?? 'SEDAN').toUpperCase();
    _branchId = widget.unit.locationId;
  }

  @override
  void dispose() {
    _plate.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _color.dispose();
    _seats.dispose();
    _rate.dispose();
    _deposit.dispose();
    _minDays.dispose();
    _maxDays.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final rate = parseMwkInput(_rate.text);
    if (_make.text.trim().isEmpty || _model.text.trim().isEmpty) {
      setState(() => _error = 'Make and model are required.');
      return;
    }
    if (rate == null || rate <= 0) {
      setState(() => _error = 'Enter a daily rate.');
      return;
    }
    final minDays = int.tryParse(_minDays.text.trim()) ?? 1;
    final maxDays = int.tryParse(_maxDays.text.trim());
    if (maxDays != null && maxDays < minDays) {
      setState(
        () => _error = 'Maximum days cannot be shorter than the minimum.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final changes = <String, dynamic>{
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      if (_year.text.trim().isNotEmpty) 'year': int.tryParse(_year.text.trim()),
      'color': _color.text.trim().isEmpty ? 'Unspecified' : _color.text.trim(),
      if (_plate.text.trim().isNotEmpty)
        'licensePlate': _plate.text.trim().toUpperCase(),
      'dailyRate': rate,
      'seats': int.tryParse(_seats.text.trim()) ?? widget.unit.car.seats ?? 5,
      'transmission': _transmission,
      'fuelType': _fuel,
      'bodyType': _body,
      'minRentalDays': minDays,
      'maxRentalDays': maxDays,
      'depositAmount': parseMwkInput(_deposit.text) ?? 0,
      'locationId': _branchId,
    };

    try {
      await ref
          .read(carHireApiProvider)
          .updateCompanyCar(widget.unit.id, changes);
      ref.invalidate(companyFleetProvider);
      ref.invalidate(companyAnalyticsProvider);
      if (!mounted) return;
      showCompanySnack(context, 'Vehicle details saved.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is CarHireApiException
            ? error.message
            : 'The details could not be saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Details & rates',
      subtitle: widget.unit.plateLabel,
      children: [
        Row(
          children: [
            Expanded(
              child: _SheetField(
                label: 'Registration',
                child: TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: carHireInputDecoration(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetField(
                label: 'Year',
                child: TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _SheetField(
                label: 'Make',
                child: TextFormField(
                  controller: _make,
                  textCapitalization: TextCapitalization.words,
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetField(
                label: 'Model',
                child: TextFormField(
                  controller: _model,
                  textCapitalization: TextCapitalization.words,
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _SheetField(
                label: 'Colour',
                child: TextFormField(
                  controller: _color,
                  textCapitalization: TextCapitalization.words,
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetField(
                label: 'Seats',
                child: TextFormField(
                  controller: _seats,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
          ],
        ),
        _ChipRow(
          label: 'Body',
          options: _bodyTypes,
          value: _body,
          onChanged: (value) => setState(() => _body = value),
        ),
        _ChipRow(
          label: 'Transmission',
          options: _transmissions,
          value: _transmission,
          onChanged: (value) => setState(() => _transmission = value),
        ),
        _ChipRow(
          label: 'Fuel',
          options: _fuels,
          value: _fuel,
          onChanged: (value) => setState(() => _fuel = value),
        ),
        Row(
          children: [
            Expanded(
              child: _SheetField(
                label: 'Daily rate (MWK)',
                child: TextFormField(
                  controller: _rate,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetField(
                label: 'Deposit (MWK)',
                child: TextFormField(
                  controller: _deposit,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: carHireInputDecoration(hint: 'Optional'),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _SheetField(
                label: 'Min days',
                child: TextFormField(
                  controller: _minDays,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: carHireInputDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SheetField(
                label: 'Max days',
                child: TextFormField(
                  controller: _maxDays,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: carHireInputDecoration(hint: 'No limit'),
                ),
              ),
            ),
          ],
        ),
        if (widget.unit.operatorId != null)
          _BranchChips(
            operatorId: widget.unit.operatorId!,
            value: _branchId,
            onChanged: (value) => setState(() => _branchId = value),
          ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: CarHireType.bodySmall.copyWith(
              color: CarHirePalette.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: carHirePrimaryButton(),
            child: Text(_saving ? 'Saving…' : 'Save changes'),
          ),
        ),
      ],
    );
  }
}

class _BranchChips extends ConsumerWidget {
  const _BranchChips({
    required this.operatorId,
    required this.value,
    required this.onChanged,
  });

  final String operatorId;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches =
        ref
            .watch(companyBranchesProvider(operatorId))
            .value
            ?.where((branch) => branch.isActive)
            .toList(growable: false) ??
        const <CompanyBranch>[];
    if (branches.isEmpty) return const SizedBox.shrink();
    return _ChipRow(
      label: 'Branch',
      options: <(String, String)>[
        for (final branch in branches) (branch.id, branch.name),
      ],
      value: value ?? '',
      onChanged: (next) => onChanged(next.isEmpty ? null : next),
      allowEmpty: true,
      emptyLabel: 'None',
    );
  }
}

class _DocumentsSheet extends ConsumerStatefulWidget {
  const _DocumentsSheet({required this.unit});

  final FleetUnit unit;

  @override
  ConsumerState<_DocumentsSheet> createState() => _DocumentsSheetState();
}

class _DocumentsSheetState extends ConsumerState<_DocumentsSheet> {
  static const _types = <(String, String)>[
    ('INSURANCE', 'Insurance'),
    ('REGISTRATION', 'Registration'),
    ('ROADWORTHINESS', 'Roadworthiness'),
    ('PERMIT', 'Permit'),
  ];

  final _reference = TextEditingController();
  final _picker = ImagePicker();
  String _type = 'INSURANCE';
  DateTime? _expiry;
  String? _photoUrl;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _attachPhoto() async {
    if (_uploading) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final url = await ref
          .read(carHireApiProvider)
          .uploadPhoto(
            await file.readAsBytes(),
            filename: file.name.trim().isEmpty ? 'document.jpg' : file.name,
          );
      if (!mounted) return;
      setState(() => _photoUrl = url);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is CarHireApiException
            ? error.message
            : 'The document photo could not be attached.';
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 12),
      initialDate: _expiry ?? now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    final reference = _reference.text.trim();
    if (reference.isEmpty && _photoUrl == null) {
      setState(() => _error = 'Add a reference number or attach a photo.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(carHireApiProvider)
          .addCarDocument(
            widget.unit.id,
            type: _type,
            fileReference: _photoUrl ?? reference,
            referenceNumber: reference.isEmpty ? null : reference,
            expiresAt: _expiry,
          );
      ref.invalidate(companyComplianceProvider(widget.unit.id));
      if (!mounted) return;
      showCompanySnack(
        context,
        '${vehicleDocumentLabel(_type)} submitted for review.',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is CarHireApiException
            ? error.message
            : 'The document could not be submitted.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compliance = ref.watch(companyComplianceProvider(widget.unit.id));

    return _SheetShell(
      title: 'Documents & insurance',
      subtitle: widget.unit.plateLabel,
      children: [
        if (compliance.hasError && compliance.hasValue)
          CarHireSectionStaleStrip(
            message: 'Compliance may be out of date.',
            padding: EdgeInsets.zero,
            onRefresh: () =>
                ref.invalidate(companyComplianceProvider(widget.unit.id)),
          ),
        if (compliance.hasValue)
          _ComplianceSummary(state: compliance.value!)
        else if (compliance.hasError)
          CarHireSectionErrorStrip(
            message: 'Compliance could not be loaded.',
            padding: EdgeInsets.zero,
            onRetry: () =>
                ref.invalidate(companyComplianceProvider(widget.unit.id)),
          )
        else
          const CarHireCompanyRowSkeleton(count: 2),
        const SizedBox(height: 16),
        Text(
          'Add a document',
          style: CarHireType.title.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 8),
        _ChipRow(
          label: 'Type',
          options: _types,
          value: _type,
          onChanged: (value) => setState(() => _type = value),
        ),
        _SheetField(
          label: 'Reference number',
          child: TextFormField(
            controller: _reference,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(120),
              FilteringTextInputFormatter.deny(RegExp(r'\n')),
            ],
            decoration: carHireInputDecoration(hint: 'Policy or document no.'),
          ),
        ),
        _SheetField(
          label: 'Expires',
          child: Material(
            color: CarHirePalette.surfaceLow,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _pickExpiry,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CarHirePalette.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 16,
                      color: CarHirePalette.muted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _expiry == null
                            ? 'No expiry set'
                            : CarHireFormatters.formatDate(_expiry!),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _expiry == null
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: _expiry == null
                              ? CarHirePalette.muted
                              : CarHirePalette.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _attachPhoto,
            style: carHireGhostButton(),
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _photoUrl == null
                        ? Icons.attach_file_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 17,
                    color: _photoUrl == null
                        ? CarHirePalette.onSurface
                        : CarHirePalette.success,
                  ),
            label: Text(
              _uploading
                  ? 'Uploading…'
                  : _photoUrl == null
                  ? 'Attach a photo (optional)'
                  : 'Photo attached',
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: CarHireType.bodySmall.copyWith(
              color: CarHirePalette.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving || _uploading ? null : _save,
            style: carHirePrimaryButton(),
            child: Text(_saving ? 'Submitting…' : 'Submit document'),
          ),
        ),
      ],
    );
  }
}

class _ComplianceSummary extends StatelessWidget {
  const _ComplianceSummary({required this.state});

  final CarCompliance state;

  @override
  Widget build(BuildContext context) {
    if (state.compliant) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: CarHirePalette.successSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 17,
              color: CarHirePalette.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'All required documents are approved.',
                style: CarHireType.bodySmall.copyWith(
                  color: CarHirePalette.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rows = <(String, Color, String)>[
      for (final type in state.missing)
        (vehicleDocumentLabel(type), CarHirePalette.warning, 'Missing'),
      for (final type in state.expired)
        (vehicleDocumentLabel(type), CarHirePalette.error, 'Expired'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: rows[i].$2,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: CarHirePalette.onSurface,
                    ),
                  ),
                ),
                Text(
                  rows[i].$3,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: rows[i].$2,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceSheet extends ConsumerStatefulWidget {
  const _ServiceSheet({required this.unit});

  final FleetUnit unit;

  @override
  ConsumerState<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends ConsumerState<_ServiceSheet> {
  bool _savingDate = false;

  Future<void> _pickServiceDate() async {
    final now = DateTime.now();
    final current = widget.unit.nextServiceDueAt;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: current ?? now.add(const Duration(days: 90)),
    );
    if (picked == null || _savingDate) return;
    setState(() => _savingDate = true);
    try {
      await ref
          .read(carHireApiProvider)
          .updateCompanyCar(widget.unit.id, <String, dynamic>{
            'nextServiceDueAt':
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}',
          });
      ref.invalidate(companyFleetProvider);
      if (!mounted) return;
      showCompanySnack(context, 'Service date updated.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showCompanySnack(
        context,
        error is CarHireApiException
            ? error.message
            : 'The service date could not be saved.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _savingDate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(companyMaintenanceBlocksProvider(widget.unit.id));

    return _SheetShell(
      title: 'Service & blocks',
      subtitle: widget.unit.plateLabel,
      children: [
        CarHireSurface(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          radius: 14,
          color: CarHirePalette.surfaceLow,
          borderColor: CarHirePalette.surfaceLow,
          onTap: _savingDate ? null : _pickServiceDate,
          child: Row(
            children: [
              const Icon(
                Icons.build_circle_outlined,
                size: 18,
                color: CarHirePalette.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next service',
                      style: CarHireType.labelSmall.copyWith(fontSize: 10),
                    ),
                    Text(
                      widget.unit.nextServiceDueAt == null
                          ? 'Not scheduled'
                          : CarHireFormatters.formatDate(
                              widget.unit.nextServiceDueAt!,
                            ),
                      style: CarHireType.subtitle.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                _savingDate ? 'Saving…' : 'Change',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: CarHirePalette.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Blocks',
                style: CarHireType.title.copyWith(fontSize: 13.5),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  showCompanyBlockSheet(context, unit: widget.unit),
              style: TextButton.styleFrom(
                foregroundColor: CarHirePalette.accent,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text(
                'Add',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (blocks.hasError && !blocks.hasValue)
          CarHireSectionErrorStrip(
            message: 'Blocks could not be loaded.',
            padding: EdgeInsets.zero,
            onRetry: () => ref.invalidate(
              companyMaintenanceBlocksProvider(widget.unit.id),
            ),
          )
        else if (blocks.isLoading && !blocks.hasValue)
          const CarHireCompanyRowSkeleton(count: 2)
        else if ((blocks.value ?? const <MaintenanceBlock>[]).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No cleaning, safety or maintenance blocks.',
              style: CarHireType.bodySmall,
            ),
          )
        else
          Column(
            children: [
              if (blocks.hasError)
                CarHireSectionStaleStrip(
                  message: 'Blocks may be out of date.',
                  padding: const EdgeInsets.only(bottom: 8),
                  onRefresh: () => ref.invalidate(
                    companyMaintenanceBlocksProvider(widget.unit.id),
                  ),
                ),
              for (final block in blocks.value!)
                _BlockRow(
                  block: block,
                  onCancel: block.isActive ? () => _cancel(block) : null,
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _cancel(MaintenanceBlock block) async {
    try {
      await ref
          .read(carHireApiProvider)
          .cancelMaintenanceBlock(widget.unit.id, block.id);
      ref.invalidate(companyMaintenanceBlocksProvider(widget.unit.id));
      if (!mounted) return;
      showCompanySnack(context, 'Block cancelled.');
    } catch (error) {
      if (!mounted) return;
      showCompanySnack(
        context,
        error is CarHireApiException
            ? error.message
            : 'The block could not be cancelled.',
        error: true,
      );
    }
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({required this.block, required this.onCancel});

  final MaintenanceBlock block;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final start = CarHireFormatters.formatDate(block.startAt.toLocal());
    final end = CarHireFormatters.formatDate(block.endAt.toLocal());
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            block.categoryLabel == 'Cleaning'
                ? Icons.cleaning_services_outlined
                : block.categoryLabel == 'Safety'
                ? Icons.health_and_safety_outlined
                : Icons.build_outlined,
            size: 15,
            color: CarHirePalette.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${block.categoryLabel} · $start – $end',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: CarHirePalette.onSurface,
                  ),
                ),
                if (block.reason != null && block.reason!.trim().isNotEmpty)
                  Text(
                    block.reason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CarHireType.labelSmall.copyWith(fontSize: 10),
                  ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: 'Cancel block',
              onPressed: onCancel,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: CarHirePalette.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _ListingSheet extends ConsumerStatefulWidget {
  const _ListingSheet({required this.unit});

  final FleetUnit unit;

  @override
  ConsumerState<_ListingSheet> createState() => _ListingSheetState();
}

class _ListingSheetState extends ConsumerState<_ListingSheet> {
  bool _saving = false;

  Future<void> _setListing(String status) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(carHireApiProvider).updateCompanyCar(
        widget.unit.id,
        <String, dynamic>{
          'listingStatus': status,
          'isAvailable': status == 'PUBLISHED',
        },
      );
      ref.invalidate(companyFleetProvider);
      ref.invalidate(companyAnalyticsProvider);
      if (!mounted) return;
      showCompanySnack(
        context,
        status == 'PUBLISHED'
            ? '${widget.unit.plate} is listed for renters.'
            : '${widget.unit.plate} is hidden from renters.',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showCompanySnack(
        context,
        error is CarHireApiException
            ? error.message
            : 'The listing could not be updated.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final current = unit.car.listingStatus;
    final tracker = unit.tracker;

    return _SheetShell(
      title: 'Listing & pairing',
      subtitle: unit.plateLabel,
      children: [
        _ListingChoice(
          title: 'Published',
          subtitle: 'Renters can find and book this car.',
          icon: Icons.public_rounded,
          selected: current == ListingStatus.published,
          onTap: _saving ? null : () => _setListing('PUBLISHED'),
        ),
        const SizedBox(height: 8),
        _ListingChoice(
          title: 'Draft / in prep',
          subtitle: 'Hidden from renters while you finish preparing it.',
          icon: Icons.visibility_off_outlined,
          selected: current == ListingStatus.draft,
          onTap: _saving ? null : () => _setListing('DRAFT'),
        ),
        if (current == ListingStatus.pendingReview ||
            current == ListingStatus.suspended ||
            current == ListingStatus.retired) ...[
          const SizedBox(height: 10),
          Text(
            'This listing is ${current.label.toLowerCase()}. Only Vero360 '
            'operations can change that state.',
            style: CarHireType.bodySmall.copyWith(
              color: CarHirePalette.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: CarHirePalette.surfaceLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                tracker == null
                    ? Icons.sensors_off_rounded
                    : Icons.sensors_rounded,
                size: 18,
                color: tracker == null
                    ? CarHirePalette.muted
                    : CarHirePalette.success,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tracker == null ? 'No tracker paired' : 'Tracker paired',
                      style: CarHireType.subtitle.copyWith(fontSize: 12.5),
                    ),
                    Text(
                      tracker == null
                          ? 'Removing and re-adding the car creates a device.'
                          : tracker.deviceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CarHireType.labelSmall.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Digital keys and remote unlock are not enabled for this fleet yet. '
          'Handovers use the inspection and key steps in the booking.',
          style: CarHireType.bodySmall.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _ListingChoice extends StatelessWidget {
  const _ListingChoice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CarHirePalette.accentPale : CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? CarHirePalette.accent : CarHirePalette.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? CarHirePalette.accent : CarHirePalette.muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CarHireType.subtitle.copyWith(fontSize: 12.5),
                    ),
                    Text(
                      subtitle,
                      style: CarHireType.labelSmall.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: CarHirePalette.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet form pieces
// ---------------------------------------------------------------------------

class _SheetField extends StatelessWidget {
  const _SheetField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 5),
            child: Text(label, style: CarHireType.label),
          ),
          child,
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allowEmpty = false,
    this.emptyLabel = 'None',
  });

  final String label;
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label, style: CarHireType.label),
          ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (allowEmpty)
                _PillChoice(
                  label: emptyLabel,
                  selected: value.isEmpty,
                  onTap: () => onChanged(''),
                ),
              for (final (wire, text) in options)
                _PillChoice(
                  label: text,
                  selected: value == wire,
                  onTap: () => onChanged(wire),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillChoice extends StatelessWidget {
  const _PillChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: CarHireShape.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? CarHirePalette.primary : CarHirePalette.surfaceLow,
          borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
          border: Border.all(
            color: selected ? CarHirePalette.primary : CarHirePalette.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : CarHirePalette.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
