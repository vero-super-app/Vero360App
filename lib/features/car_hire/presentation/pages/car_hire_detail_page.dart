import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/formatters.dart';
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
    _startAt = widget.initialStartAt ??
        DateTime(now.year, now.month, now.day, 9)
            .add(const Duration(days: 1));
    final fallbackEnd =
        DateTime(_startAt.year, _startAt.month, _startAt.day + 3, 17);
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CarHirePalette.accent,
                ),
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CarHirePalette.accent,
                ),
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
          loading: () => const CarHireLoadingState(
            message: 'Loading vehicle details…',
          ),
          error: (error, _) => CarHireErrorState(
            error: error,
            onRetry: _refresh,
          ),
          data: (_) => CarHireErrorState(
            message: 'This vehicle is no longer available.',
            onRetry: _refresh,
          ),
        ),
      );
    }

    final refreshError = async.hasError ? async.error : null;
    final available = car.isAvailable && car.availableForDates != false;

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
              _CarHireGallery(car: car, available: available),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (refreshError != null) ...[
                      CarHireInfoBanner(
                        icon: Icons.cloud_off_rounded,
                        title: 'Showing saved details',
                        message:
                            'We could not refresh this vehicle. The details '
                            'below were already loaded.',
                        tone: CarHireInfoTone.warning,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _titleBlock(car, available),
                    const SizedBox(height: 16),
                    _datesCard(car),
                    const SizedBox(height: 20),
                    const _SectionLabel('Vehicle details'),
                    const SizedBox(height: 10),
                    _specGrid(car),
                    if (car.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 20),
                      const _SectionLabel('About this car'),
                      const SizedBox(height: 8),
                      CarHireSurface(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          car.description!.trim(),
                          style: CarHireType.body,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const _SectionLabel('What is included'),
                    const SizedBox(height: 10),
                    const _IncludedList(),
                    const SizedBox(height: 16),
                    CarHireInfoBanner(
                      icon: Icons.info_outline_rounded,
                      title: 'Final price is confirmed at checkout',
                      message:
                          'Your final total, fees and deposit are calculated '
                          'by Vero360 for your exact dates and shown before '
                          'you submit a booking.',
                      tone: CarHireInfoTone.accent,
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _continueBar(car),
    );
  }

  PreferredSizeWidget _appBar() {
    return carHireAppBar(
      title: 'Vehicle details',
      actions: [
        CarHireIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onTap: _refresh,
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _titleBlock(CarListing car, bool available) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                car.title,
                style: CarHireType.headline,
              ),
            ),
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
                  car.pickupAreaLabel,
                  if (car.subtitle.isNotEmpty) car.subtitle,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CarHireType.bodySmall.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            CarHirePill(
              label: available ? 'Available for your dates' : 'Unavailable',
              icon: available
                  ? Icons.check_circle_outline_rounded
                  : Icons.do_not_disturb_on_outlined,
              background: available
                  ? CarHirePalette.successSoft
                  : CarHirePalette.errorSoft,
              foreground: available
                  ? CarHirePalette.success
                  : CarHirePalette.error,
              fontSize: 10.5,
            ),
            const CarHirePill(
              label: 'Verified provider',
              icon: Icons.verified_user_outlined,
              fontSize: 10.5,
            ),
            const CarHirePill(
              label: 'Secure payment',
              icon: Icons.lock_outline_rounded,
              fontSize: 10.5,
            ),
          ],
        ),
      ],
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
          ],
          const SizedBox(height: 10),
          Text(
            car.rentalWindowLabel,
            style: CarHireType.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _specGrid(CarListing car) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: width,
              child: _SpecTile(
                icon: Icons.airline_seat_recline_normal_rounded,
                label: 'Seats',
                value: car.seats == null ? 'Not specified' : '${car.seats}',
              ),
            ),
            SizedBox(
              width: width,
              child: _SpecTile(
                icon: Icons.settings_input_component_rounded,
                label: 'Transmission',
                value: car.transmissionLabel,
              ),
            ),
            SizedBox(
              width: width,
              child: _SpecTile(
                icon: Icons.local_gas_station_rounded,
                label: 'Fuel',
                value: car.fuelLabel,
              ),
            ),
            SizedBox(
              width: width,
              child: _SpecTile(
                icon: Icons.directions_car_rounded,
                label: 'Body type',
                value: car.bodyLabel.isEmpty ? 'Not specified' : car.bodyLabel,
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: _SpecTile(
                icon: Icons.place_outlined,
                label: 'Pick-up area',
                value: car.pickupAreaLabel,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _continueBar(CarListing car) {
    final canContinue = _rangeValid && car.isBookable;
    final estimate = car.dailyRate * _rentalDays;

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
                    minimumSize: WidgetStateProperty.all(
                      const Size(148, 48),
                    ),
                  ),
                  child: Text(car.isBookable ? 'Continue' : 'Unavailable'),
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
  const _CarHireGallery({required this.car, required this.available});

  final CarListing car;
  final bool available;

  @override
  State<_CarHireGallery> createState() => _CarHireGalleryState();
}

class _CarHireGalleryState extends State<_CarHireGallery> {
  int _index = 0;

  bool get _isElectric {
    final fuel = (widget.car.fuelType ?? '').toUpperCase();
    return fuel.contains('ELECTRIC') || fuel.contains('EV');
  }

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
          Positioned(
            left: 16,
            top: 14,
            child: CarHirePill(
              label: _isElectric
                  ? 'EV · Instant book'
                  : widget.available
                      ? 'Instant book'
                      : 'Unavailable',
              icon: _isElectric
                  ? Icons.bolt_rounded
                  : widget.available
                      ? Icons.flash_on_rounded
                      : Icons.do_not_disturb_on_rounded,
              background: widget.available
                  ? CarHirePalette.primary
                  : Colors.white.withValues(alpha: 0.95),
              foreground: widget.available
                  ? Colors.white
                  : CarHirePalette.error,
              fontSize: 10.5,
            ),
          ),
          if (images.length > 1) ...[
            Positioned(
              right: 16,
              top: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
  const _SpecTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(13),
      radius: 16,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: CarHirePalette.onSurface),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: CarHireType.labelSmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarHirePalette.onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

class _IncludedList extends StatelessWidget {
  const _IncludedList();

  static const _items = <(IconData, String, String)>[
    (
      Icons.verified_user_outlined,
      'Verified vehicle provider',
      'Every listing is reviewed and linked to a verified Vero360 provider.'
    ),
    (
      Icons.shield_outlined,
      'Damage protection guidance',
      'Record a handover inspection in the app at pick-up and return.'
    ),
    (
      Icons.support_agent_rounded,
      '24/7 support',
      'Report an incident or open a support case from the booking screen.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var index = 0; index < _items.length; index++) ...[
            if (index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: CarHirePalette.hairline),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: CarHirePalette.accentPale,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _items[index].$1,
                    size: 17,
                    color: CarHirePalette.onAccentSoft,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _items[index].$2,
                        style: const TextStyle(
                          color: CarHirePalette.onSurface,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _items[index].$3,
                        style: CarHireType.bodySmall.copyWith(fontSize: 11.5),
                      ),
                    ],
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
