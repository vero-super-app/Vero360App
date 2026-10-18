import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
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
    final fallbackEnd = DateTime(_startAt.year, _startAt.month, _startAt.day + 3, 17);
    _endAt = widget.initialEndAt ?? fallbackEnd;
    if (!_endAt.isAfter(_startAt)) {
      _endAt = DateTime(_startAt.year, _startAt.month, _startAt.day + 1, 17);
    }
  }

  bool get _rangeValid => _endAt.isAfter(_startAt);

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
                  primary: CarRentalColors.brandOrange,
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
                  primary: CarRentalColors.brandOrange,
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

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: _appBar(),
      body: RefreshIndicator(
        color: CarRentalColors.brandOrange,
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (async.isLoading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: CarRentalColors.brandOrange,
                  backgroundColor: CarRentalColors.brandOrangePale,
                ),
              if (refreshError != null)
                _StaleBanner(
                  message:
                      'Could not refresh this vehicle. Showing the details we '
                      'already loaded.',
                  onRetry: _refresh,
                ),
              _CarHireGallery(car: car),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                car.title,
                                style: const TextStyle(
                                  color: CarRentalColors.title,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                              ),
                              if (car.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  car.subtitle,
                                  style: const TextStyle(
                                    color: CarRentalColors.body,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              car.pricePerDayLabel,
                              style: const TextStyle(
                                color: CarRentalColors.brandOrange,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Text(
                              'daily rate',
                              style: TextStyle(
                                color: CarRentalColors.grey,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _AvailabilityPill(car: car),
                        if (car.rating > 0 && car.reviews > 0)
                          _Pill(
                            icon: Icons.star_rounded,
                            label:
                                '${car.rating.toStringAsFixed(1)} (${car.reviews})',
                            color: CarRentalColors.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DatesCard(
                      startAt: _startAt,
                      endAt: _endAt,
                      valid: _rangeValid,
                      onPickStart: _pickStart,
                      onPickEnd: _pickEnd,
                      rentalWindow: car.rentalWindowLabel,
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle('Vehicle details'),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = (constraints.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: width,
                              child: _SpecTile(
                                icon: Icons.event_seat_rounded,
                                label: 'Seats',
                                value: car.seats == null
                                    ? 'Not specified'
                                    : '${car.seats}',
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _SpecTile(
                                icon: Icons.settings_rounded,
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
                                value:
                                    car.bodyLabel.isEmpty ? 'Not specified' : car.bodyLabel,
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
                    ),
                    if (car.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 20),
                      const _SectionTitle('About this car'),
                      const SizedBox(height: 8),
                      Text(
                        car.description!.trim(),
                        style: const TextStyle(
                          color: CarRentalColors.body,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CarRentalColors.brandOrangePale,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 17,
                            color: CarRentalColors.brandOrange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The daily rate is a guide. Your final total, '
                              'fees and deposit are calculated by Vero360 on the '
                              'next step for your exact dates.',
                              style: TextStyle(
                                color: CarRentalColors.body,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
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
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      foregroundColor: CarRentalColors.title,
      elevation: 0.4,
      scrolledUnderElevation: 0.4,
      title: const Text(
        'Vehicle details',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refresh,
        ),
      ],
    );
  }

  Widget _continueBar(CarListing car) {
    final canContinue = _rangeValid && car.isBookable;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Color(0xFFEDE7DF)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Price from',
                    style: TextStyle(
                      color: CarRentalColors.grey,
                      fontSize: 10.5,
                    ),
                  ),
                  Text(
                    car.pricePerDayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CarRentalColors.title,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
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
                style: FilledButton.styleFrom(
                  backgroundColor: CarRentalColors.brandOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      CarRentalColors.brandOrange.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(car.isBookable ? 'Continue' : 'Unavailable'),
              ),
            ),
          ],
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
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isEmpty)
            Container(
              color: CarRentalColors.chip,
              alignment: Alignment.center,
              child: const Icon(
                Icons.directions_car_filled_rounded,
                size: 62,
                color: CarRentalColors.grey,
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
                  height: 250,
                  memCacheWidth: 1400,
                );
              },
            ),
          if (images.length > 1)
            Positioned(
              right: 14,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_index + 1} / ${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(images.length, (index) {
                  final active = index == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _DatesCard extends StatelessWidget {
  const _DatesCard({
    required this.startAt,
    required this.endAt,
    required this.valid,
    required this.onPickStart,
    required this.onPickEnd,
    required this.rentalWindow,
  });

  final DateTime startAt;
  final DateTime endAt;
  final bool valid;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final String rentalWindow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CarRentalColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE7DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your rental dates',
            style: TextStyle(
              color: CarRentalColors.title,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateTile(
                  label: 'Pick-up',
                  date: startAt,
                  icon: Icons.flight_takeoff_rounded,
                  onTap: onPickStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateTile(
                  label: 'Return',
                  date: endAt,
                  icon: Icons.flight_land_rounded,
                  onTap: onPickEnd,
                ),
              ),
            ],
          ),
          if (!valid) ...[
            const SizedBox(height: 8),
            const Text(
              'The return date and time must be after pick-up.',
              style: TextStyle(color: CarRentalColors.error, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            rentalWindow,
            style: const TextStyle(
              color: CarRentalColors.grey,
              fontSize: 11,
            ),
          ),
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
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: CarRentalColors.greyLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4DED6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: CarRentalColors.brandOrange),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        color: CarRentalColors.body,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  CarHireFormatters.formatDate(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  CarHireFormatters.formatTime(date),
                  style: const TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 11.5,
                  ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CarRentalColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE7DF)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: CarRentalColors.brandOrangePale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: CarRentalColors.brandOrange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: CarRentalColors.grey,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CarRentalColors.title,
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

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.car});

  final CarListing car;

  @override
  Widget build(BuildContext context) {
    final available = car.isAvailable && car.availableForDates != false;
    final color =
        available ? CarRentalColors.success : CarRentalColors.error;
    return _Pill(
      icon: available
          ? Icons.check_circle_outline_rounded
          : Icons.do_not_disturb_on_outlined,
      label: car.availabilityLabel,
      color: color,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final foreground = Color.lerp(color, Colors.black, 0.3) ?? color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: CarRentalColors.title,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      color: CarRentalColors.warningLight,
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 17,
            color: CarRentalColors.greyDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: CarRentalColors.greyDark,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
