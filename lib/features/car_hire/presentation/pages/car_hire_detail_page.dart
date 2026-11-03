import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_section_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_browse_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_section_frame.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_policy_block.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/widgets/merchant_verified_badge.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class CarHireDetailPage extends ConsumerStatefulWidget {
  const CarHireDetailPage({
    super.key,
    required this.carId,
    this.initialCar,
    this.initialStartAt,
    this.initialEndAt,
  });

  final int carId;
  final CarListing? initialCar;
  final DateTime? initialStartAt;
  final DateTime? initialEndAt;

  @override
  ConsumerState<CarHireDetailPage> createState() => _CarHireDetailPageState();
}

class _CarHireDetailPageState extends ConsumerState<CarHireDetailPage> {
  late DateTime _startAt;
  late DateTime _endAt;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startAt =
        widget.initialStartAt ??
        DateTime(now.year, now.month, now.day, 9).add(const Duration(days: 1));
    final fallbackEnd = DateTime(
      _startAt.year,
      _startAt.month,
      _startAt.day + 3,
      17,
    );
    _endAt = widget.initialEndAt ?? fallbackEnd;
    if (!_endAt.isAfter(_startAt)) {
      _endAt = DateTime(_startAt.year, _startAt.month, _startAt.day + 1, 17);
    }
  }

  bool get _rangeValid => _endAt.isAfter(_startAt);

  int get _rentalDays {
    final hours = _endAt.difference(_startAt).inHours;
    if (hours <= 0) return 0;
    final days = (hours / 24).ceil();
    return days < 1 ? 1 : days;
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final safeInitial = initial.isBefore(firstDate) ? firstDate : initial;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2, now.month, now.day),
      helpText: 'Select date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: CarHirePalette.accent),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (pickedDate == null || !mounted) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(safeInitial),
      helpText: 'Select time',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: CarHirePalette.accent),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_startAt);
    if (picked == null || !mounted) return;
    setState(() {
      _startAt = picked;
      if (!_endAt.isAfter(_startAt)) {
        _endAt = DateTime(picked.year, picked.month, picked.day + 1, 17);
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_endAt);
    if (picked == null || !mounted) return;
    if (!picked.isAfter(_startAt)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('The return date and time must be after pick-up.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() => _endAt = picked);
  }

  Future<void> _refresh() async {
    ref.invalidate(carHireDetailProvider(widget.carId));
    ref.invalidate(
      carHireAvailabilityProvider(
        CarHireAvailabilityRequest(
          carId: widget.carId,
          startAt: _startAt,
          endAt: _endAt,
        ),
      ),
    );
    try {
      await ref.read(carHireDetailProvider(widget.carId).future);
    } catch (_) {
      // Surfaced through the AsyncValue.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(carHireDetailProvider(widget.carId));
    final car = async.asData?.value ?? widget.initialCar;

    if (car == null) {
      return Scaffold(
        backgroundColor: CarHirePalette.background,
        appBar: _appBar(),
        body: async.when(
          loading: () => const CarHireDetailSkeleton(),
          error: (error, _) =>
              CarHireErrorState(error: error, onRetry: _refresh),
          data: (_) => CarHireErrorState(
            message: 'This vehicle is no longer available.',
            onRetry: _refresh,
          ),
        ),
      );
    }

    final refreshError = async.hasError ? async.error : null;

    // The calendar check is its own section: it can load, fail and retry
    // without touching the vehicle details above it.
    final availabilityRequest = CarHireAvailabilityRequest(
      carId: widget.carId,
      startAt: _startAt,
      endAt: _endAt,
    );
    final availabilityAsync = ref.watch(
      carHireAvailabilityProvider(availabilityRequest),
    );
    final availability = availabilityAsync.asData?.value;
    final checkingAvailability =
        availabilityAsync.isLoading && availability == null;
    final availabilityFailed = availabilityAsync.hasError;
    final availableForDates =
        availability?.availableForDates ?? car.availableForDates;
    final available = car.isAvailable && availableForDates != false;

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: _appBar(),
      body: RefreshIndicator(
        color: CarHirePalette.accent,
        backgroundColor: CarHirePalette.surface,
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (async.isLoading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: CarHirePalette.accent,
                  backgroundColor: CarHirePalette.accentPale,
                ),
              _CarHireGallery(car: car),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (refreshError != null) ...[
                      CarHireInfoBanner(
                        icon: Icons.cloud_off_rounded,
                        title: 'Showing saved details',
                        message: 'Pull down to try again.',
                        tone: CarHireInfoTone.warning,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _titleBlock(car),
                    const SizedBox(height: 12),
                    _availabilityStatus(
                      car: car,
                      availability: availability,
                      checking: checkingAvailability,
                      failed: availabilityFailed,
                      available: available,
                      onRetry: () => ref.invalidate(
                        carHireAvailabilityProvider(availabilityRequest),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _specRow(car),
                    const SizedBox(height: 16),
                    _datesCard(car),
                    if (car.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 20),
                      const _SectionLabel('About this car'),
                      const SizedBox(height: 6),
                      Text(car.description!.trim(), style: CarHireType.body),
                    ],
                    if (car.listingPolicies != null) ...[
                      const SizedBox(height: 20),
                      CarHirePolicyBlock(policies: car.listingPolicies!),
                    ],
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () => CarHireRoutes.openTerms(context),
                        style: TextButton.styleFrom(
                          foregroundColor: CarHirePalette.muted,
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        child: const Text('Rental terms & protections'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _continueBar(
        car,
        available: available,
        checkingAvailability: checkingAvailability,
        availabilityFailed: availabilityFailed,
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return carHireAppBar(
      title: 'Vehicle details',
      subtitle: 'Verified car hire',
      actions: [
        CarHireIconButton(
          icon: Icons.receipt_long_rounded,
          tooltip: 'My bookings',
          size: 36,
          iconSize: 18,
          onTap: () => CarHireRoutes.openBookings(context),
        ),
      ],
    );
  }

  Widget _titleBlock(CarListing car) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(car.title, style: CarHireType.headline)),
            if (car.rating > 0 || car.reviews > 0) ...[
              const SizedBox(width: 10),
              CarHireRatingPill(rating: car.rating, reviews: car.reviews),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.place_outlined,
              size: 14,
              color: CarHirePalette.muted,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                [
                  car.branchLabel ?? car.pickupAreaLabel,
                  if (car.subtitle.isNotEmpty) car.subtitle,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CarHireType.bodySmall.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
        if (car.provider != null) ...[
          const SizedBox(height: 10),
          _ProviderRow(provider: car.provider!),
        ],
      ],
    );
  }

  /// Availability is its own section: skeleton, error strip or status pill,
  /// independent of the vehicle details above it.
  Widget _availabilityStatus({
    required CarListing car,
    required CarHireAvailability? availability,
    required bool checking,
    required bool failed,
    required bool available,
    required VoidCallback onRetry,
  }) {
    if (checking) {
      return const SizedBox(
        height: 28,
        child: Align(
          alignment: Alignment.centerLeft,
          child: CarHireAvailabilityPillSkeleton(),
        ),
      );
    }
    if (failed) {
      return CarHireSectionErrorStrip(
        message: 'We could not check these dates. Continue and we will '
            'confirm availability at checkout.',
        title: 'Availability not checked',
        retryLabel: 'Retry',
        onRetry: onRetry,
        padding: EdgeInsets.zero,
      );
    }

    final units = availability?.availableUnits ?? 0;
    final label = available
        ? units > 1
              ? 'Available for your dates · $units units left'
              : 'Available for your dates'
        : 'Unavailable for these dates';
    return CarHirePill(
      label: label,
      icon: available
          ? Icons.check_circle_outline_rounded
          : Icons.do_not_disturb_on_outlined,
      background: available
          ? CarHirePalette.successSoft
          : CarHirePalette.errorSoft,
      foreground: available ? CarHirePalette.success : CarHirePalette.error,
      fontSize: 10.5,
    );
  }

  Widget _datesCard(CarListing car) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Your trip', style: CarHireType.subtitle),
              ),
              Text(
                _rentalDays == 1 ? '1 day' : '$_rentalDays days',
                style: CarHireType.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateTile(
                  label: 'Pick-up',
                  date: _startAt,
                  icon: Icons.flight_takeoff_rounded,
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateTile(
                  label: 'Return',
                  date: _endAt,
                  icon: Icons.flight_land_rounded,
                  onTap: _pickEnd,
                ),
              ),
            ],
          ),
          if (!_rangeValid) ...[
            const SizedBox(height: 9),
            Text(
              'The return date and time must be after pick-up.',
              style: CarHireType.bodySmall.copyWith(
                color: CarHirePalette.error,
                fontSize: 11.5,
              ),
            ),
          ] else if (car.minRentalDays > 1 || car.maxRentalDays != null) ...[
            const SizedBox(height: 10),
            Text(car.rentalWindowLabel, style: CarHireType.labelSmall),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                car.instantBook ? Icons.bolt_rounded : Icons.schedule_rounded,
                size: 14,
                color: CarHirePalette.muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  car.bookingModeLabel,
                  style: CarHireType.labelSmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _specRow(CarListing car) {
    return CarHireSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: _SpecTile(
              icon: Icons.airline_seat_recline_normal_rounded,
              value: car.seats == null ? '—' : '${car.seats} seats',
            ),
          ),
          Expanded(
            child: _SpecTile(
              icon: Icons.settings_input_component_rounded,
              value: car.transmission == null ? '—' : car.transmissionLabel,
            ),
          ),
          Expanded(
            child: _SpecTile(
              icon: Icons.local_gas_station_rounded,
              value: car.fuelType == null ? '—' : car.fuelLabel,
            ),
          ),
          Expanded(
            child: _SpecTile(
              icon: Icons.directions_car_rounded,
              value: car.bodyLabel.isEmpty ? '—' : car.bodyLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueBar(
    CarListing car, {
    required bool available,
    required bool checkingAvailability,
    required bool availabilityFailed,
  }) {
    // Availability is allowed to be unknown: checkout re-validates with a
    // quote, so a calendar failure must not trap the renter on this page.
    final canContinue =
        _rangeValid &&
        car.isBookable &&
        !checkingAvailability &&
        (availabilityFailed || available);
    final estimate = car.dailyRate * _rentalDays;
    final label = checkingAvailability
        ? 'Checking…'
        : !car.isBookable || (!available && !availabilityFailed)
        ? 'Unavailable'
        : 'Continue';

    return Container(
      decoration: const BoxDecoration(
        color: CarHirePalette.surface,
        border: Border(top: BorderSide(color: CarHirePalette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            CarHireFormatters.formatCurrency(car.dailyRate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CarHireType.priceSmall,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '/ day',
                          style: TextStyle(
                            color: CarHirePalette.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _rentalDays > 0
                          ? 'Est. ${CarHireFormatters.formatCurrency(estimate)} · $_rentalDays ${_rentalDays == 1 ? 'day' : 'days'}'
                          : 'Choose your dates',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CarHireType.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: canContinue
                      ? () => CarHireRoutes.openCheckout(
                          context,
                          car: car,
                          startAt: _startAt,
                          endAt: _endAt,
                        )
                      : null,
                  style: carHirePrimaryButton().copyWith(
                    minimumSize: WidgetStateProperty.all(const Size(148, 48)),
                  ),
                  child: Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarHireGallery extends StatefulWidget {
  const _CarHireGallery({required this.car});

  final CarListing car;

  @override
  State<_CarHireGallery> createState() => _CarHireGalleryState();
}

class _CarHireGalleryState extends State<_CarHireGallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.car.galleryImages;

    return SizedBox(
      height: 264,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isEmpty)
            Container(
              color: CarHirePalette.surfaceLow,
              alignment: Alignment.center,
              child: const Icon(
                Icons.directions_car_filled_rounded,
                size: 64,
                color: CarHirePalette.outlineVariant,
              ),
            )
          else
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                return ResilientCachedNetworkImage(
                  url: images[index],
                  fit: BoxFit.cover,
                  height: 264,
                  memCacheWidth: 1400,
                );
              },
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 96,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.24),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (images.length > 1) ...[
            Positioned(
              right: 16,
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${_index + 1} / ${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(images.length, (index) {
                  final active = index == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.date,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label ${CarHireFormatters.formatDateTime(date)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CarHirePalette.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: CarHirePalette.accent),
                    const SizedBox(width: 5),
                    Text(label.toUpperCase(), style: CarHireType.overline),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  CarHireFormatters.formatDate(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarHirePalette.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  CarHireFormatters.formatTime(date),
                  style: CarHireType.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: CarHirePalette.onSurfaceVariant),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: CarHirePalette.onSurface,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider});

  final CarHireProvider provider;

  @override
  Widget build(BuildContext context) {
    final logo = provider.logoUrl?.trim();
    final initial = provider.name.isEmpty
        ? '?'
        : provider.name[0].toUpperCase();
    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 28,
            height: 28,
            child: logo != null && logo.isNotEmpty
                ? ResilientCachedNetworkImage(
                    url: logo,
                    fit: BoxFit.cover,
                    height: 28,
                    memCacheWidth: 96,
                  )
                : Container(
                    color: CarHirePalette.surfaceLow,
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: CarHirePalette.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Provided by '),
                      TextSpan(
                        text: provider.name,
                        style: const TextStyle(
                          color: CarHirePalette.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.bodySmall.copyWith(fontSize: 12.5),
                ),
              ),
              if (provider.verified) ...[
                const SizedBox(width: 6),
                const MerchantVerifiedBadge(
                  showLabel: false,
                  size: 15,
                  tooltip: 'Verified car hire',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: CarHireType.title);
  }
}
