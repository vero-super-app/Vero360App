import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_listing_card.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_search_form.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/formatters.dart';

/// Vehicle categories shown as the horizontal chip rail.
enum _VehicleCategory { all, electric, suv, luxury, budget, sevenSeater }

extension on _VehicleCategory {
  String get label {
    switch (this) {
      case _VehicleCategory.all:
        return 'All cars';
      case _VehicleCategory.electric:
        return 'Electric (EV)';
      case _VehicleCategory.suv:
        return 'SUVs';
      case _VehicleCategory.luxury:
        return 'Luxury & exec';
      case _VehicleCategory.budget:
        return 'Budget';
      case _VehicleCategory.sevenSeater:
        return '7-seaters';
    }
  }

  IconData get icon {
    switch (this) {
      case _VehicleCategory.all:
        return Icons.directions_car_rounded;
      case _VehicleCategory.electric:
        return Icons.bolt_rounded;
      case _VehicleCategory.suv:
        return Icons.airport_shuttle_rounded;
      case _VehicleCategory.luxury:
        return Icons.workspace_premium_rounded;
      case _VehicleCategory.budget:
        return Icons.savings_rounded;
      case _VehicleCategory.sevenSeater:
        return Icons.groups_rounded;
    }
  }
}

enum _SortOption { recommended, priceLow, priceHigh, topRated }

extension on _SortOption {
  String get label {
    switch (this) {
      case _SortOption.recommended:
        return 'Recommended';
      case _SortOption.priceLow:
        return 'Price: low to high';
      case _SortOption.priceHigh:
        return 'Price: high to low';
      case _SortOption.topRated:
        return 'Top rated';
    }
  }

  String get shortLabel {
    switch (this) {
      case _SortOption.recommended:
        return 'Recommended';
      case _SortOption.priceLow:
        return 'Lowest price';
      case _SortOption.priceHigh:
        return 'Highest price';
      case _SortOption.topRated:
        return 'Top rated';
    }
  }
}

class CarHireBrowsePage extends ConsumerStatefulWidget {
  const CarHireBrowsePage({super.key});

  @override
  ConsumerState<CarHireBrowsePage> createState() => _CarHireBrowsePageState();
}

class _CarHireBrowsePageState extends ConsumerState<CarHireBrowsePage> {
  late final TextEditingController _pickupController;
  _VehicleCategory _category = _VehicleCategory.all;
  _SortOption _sort = _SortOption.recommended;

  static final DateFormat _shortMonthDay = DateFormat('MMM d');

  @override
  void initState() {
    super.initState();
    final query = ref.read(carHireSearchProvider);
    _pickupController = TextEditingController(text: query.pickupArea);
  }

  @override
  void dispose() {
    _pickupController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Date + search
  // ---------------------------------------------------------------------

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
    final query = ref.read(carHireSearchProvider);
    final initial = query.startAt ?? DateTime.now().add(const Duration(days: 1));
    final picked = await _pickDateTime(initial);
    if (picked == null || !mounted) return;

    final notifier = ref.read(carHireSearchProvider.notifier);
    final currentEnd = query.endAt;
    if (currentEnd == null || !currentEnd.isAfter(picked)) {
      final nextEnd = DateTime(picked.year, picked.month, picked.day + 1, 17);
      notifier.setDates(startAt: picked, endAt: nextEnd);
    } else {
      notifier.setStartAt(picked);
    }
  }

  Future<void> _pickEnd() async {
    final query = ref.read(carHireSearchProvider);
    final start = query.startAt ?? DateTime.now();
    final initial = query.endAt ?? start.add(const Duration(days: 3));
    final picked = await _pickDateTime(initial);
    if (picked == null || !mounted) return;

    if (!picked.isAfter(start)) {
      _snack('The return date and time must be after pick-up.');
      return;
    }
    ref.read(carHireSearchProvider.notifier).setEndAt(picked);
  }

  void _onSearch({bool closeSheet = false}) {
    final query = ref.read(carHireSearchProvider);
    if (!query.isDateRangeValid) {
      _snack('Choose a pick-up and return time, with the return after pick-up.');
      return;
    }
    ref
        .read(carHireSearchProvider.notifier)
        .setPickupArea(_pickupController.text);
    ref.invalidate(carHireResultsProvider);
    FocusScope.of(context).unfocus();
    if (closeSheet && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _openTripSheet() async {
    final query = ref.read(carHireSearchProvider);
    _pickupController.text = query.pickupArea;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CarHirePalette.background,
      barrierColor: CarHirePalette.primary.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 2),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CarHirePalette.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final live = ref.watch(carHireSearchProvider);
                    return CarHireSearchForm(
                      pickupController: _pickupController,
                      startAt: live.startAt ?? DateTime.now(),
                      endAt: live.endAt ?? DateTime.now(),
                      onPickStart: _pickStart,
                      onPickEnd: _pickEnd,
                      onSearch: () => _onSearch(closeSheet: true),
                      searching: false,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    ref
        .read(carHireSearchProvider.notifier)
        .setPickupArea(_pickupController.text);
    ref.invalidate(carHireResultsProvider);
    try {
      await ref.read(carHireResultsProvider.future);
    } catch (_) {
      // The error state rendered by the provider is sufficient.
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ---------------------------------------------------------------------
  // Derived data
  // ---------------------------------------------------------------------

  int _rentalDays(CarHireSearchQuery query) {
    final start = query.startAt;
    final end = query.endAt;
    if (start == null || end == null) return 0;
    final hours = end.difference(start).inHours;
    if (hours <= 0) return 0;
    final days = (hours / 24).ceil();
    return days < 1 ? 1 : days;
  }

  double _medianRate(List<CarListing> cars) {
    final rates = cars
        .map((car) => car.dailyRate)
        .where((rate) => rate > 0)
        .toList(growable: false)
      ..sort();
    if (rates.isEmpty) return 0;
    final middle = rates.length ~/ 2;
    if (rates.length.isOdd) return rates[middle];
    return (rates[middle - 1] + rates[middle]) / 2;
  }

  List<CarListing> _visibleCars(List<CarListing> cars) {
    final median = _medianRate(cars);

    bool isElectric(CarListing car) {
      final fuel = (car.fuelType ?? '').toUpperCase();
      return fuel.contains('ELECTRIC') || fuel == 'EV' || fuel.contains('BEV');
    }

    bool isSuv(CarListing car) {
      final body = (car.bodyType ?? '').toUpperCase();
      return body.contains('SUV') ||
          body.contains('4X4') ||
          body.contains('CROSSOVER') ||
          body.contains('PICKUP');
    }

    final filtered = cars.where((car) {
      switch (_category) {
        case _VehicleCategory.all:
          return true;
        case _VehicleCategory.electric:
          return isElectric(car);
        case _VehicleCategory.suv:
          return isSuv(car);
        case _VehicleCategory.luxury:
          return median > 0 && car.dailyRate >= median * 1.3;
        case _VehicleCategory.budget:
          return median > 0 && car.dailyRate <= median * 0.75;
        case _VehicleCategory.sevenSeater:
          return (car.seats ?? 0) >= 7;
      }
    }).toList(growable: false);

    final sorted = List<CarListing>.of(filtered);
    switch (_sort) {
      case _SortOption.recommended:
        // Keep the server's relevance order.
        break;
      case _SortOption.priceLow:
        sorted.sort((a, b) => a.dailyRate.compareTo(b.dailyRate));
      case _SortOption.priceHigh:
        sorted.sort((a, b) => b.dailyRate.compareTo(a.dailyRate));
      case _SortOption.topRated:
        sorted.sort((a, b) {
          final byRating = b.rating.compareTo(a.rating);
          if (byRating != 0) return byRating;
          return b.reviews.compareTo(a.reviews);
        });
    }
    return sorted;
  }

  CarPriceBand _bandFor(CarListing car, double median) {
    if (median <= 0) return CarPriceBand.standard;
    if (car.dailyRate >= median * 1.3) return CarPriceBand.premium;
    if (car.dailyRate <= median * 0.75) return CarPriceBand.value;
    return CarPriceBand.standard;
  }

  String _tripSummary(CarHireSearchQuery query) {
    final start = query.startAt;
    final end = query.endAt;
    if (start == null || end == null) return 'Choose your pick-up and return';
    final days = _rentalDays(query);
    final sameMonth = start.year == end.year && start.month == end.month;
    final startLabel = _shortMonthDay.format(start);
    final endLabel = sameMonth
        ? DateFormat('d').format(end)
        : _shortMonthDay.format(end);
    return '$startLabel – $endLabel · $days ${days == 1 ? 'day' : 'days'} '
        '(self-drive)';
  }

  Future<void> _openAreaOnMap(CarHireSearchQuery query) async {
    final area = query.pickupArea.trim();
    final search = area.isEmpty ? 'car rental near me' : 'car rental $area';
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': search,
    });
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _snack('We could not open the map on this device.');
    }
  }

  Future<void> _openSortSheet() async {
    final selected = await showModalBottomSheet<_SortOption>(
      context: context,
      backgroundColor: CarHirePalette.background,
      barrierColor: CarHirePalette.primary.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: CarHirePalette.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const Text('Sort cars', style: CarHireType.titleLarge),
                const SizedBox(height: 10),
                for (final option in _SortOption.values)
                  _SortTile(
                    label: option.label,
                    selected: option == _sort,
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _sort = selected);
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(carHireSearchProvider);
    final results = ref.watch(carHireResultsProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Car hire',
        actions: [
          CarHireIconButton(
            icon: Icons.receipt_long_rounded,
            tooltip: 'My bookings',
            onTap: () => CarHireRoutes.openBookings(context),
          ),
          const SizedBox(width: 8),
          CarHireIconButton(
            icon: Icons.verified_user_outlined,
            tooltip: 'Driver verification',
            onTap: () => CarHireRoutes.openVerification(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        color: CarHirePalette.accent,
        backgroundColor: CarHirePalette.surface,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _locationBar(query)),
            SliverToBoxAdapter(child: _categoryRail()),
            SliverToBoxAdapter(child: _perkRail()),
            ..._resultSlivers(results, query),
            SliverToBoxAdapter(child: _guaranteeBanner()),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationBar(CarHireSearchQuery query) {
    final area = query.pickupArea.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      decoration: const BoxDecoration(
        color: CarHirePalette.surfaceLow,
        border: Border(
          bottom: BorderSide(color: CarHirePalette.hairline),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTripSheet,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: CarHirePalette.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: CarHirePalette.hairline),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 19,
                    color: CarHirePalette.onSurface,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              area.isEmpty ? 'All pick-up areas' : area,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CarHirePalette.onSurface,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.expand_more_rounded,
                            size: 17,
                            color: CarHirePalette.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tripSummary(query),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CarHireType.labelSmall.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: CarHirePalette.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: CarHirePalette.hairline),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 15,
                        color: CarHirePalette.accent,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Filter',
                        style: TextStyle(
                          color: CarHirePalette.onSurface,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryRail() {
    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        itemCount: _VehicleCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _VehicleCategory.values[index];
          final selected = category == _category;
          return _CategoryChip(
            label: category.label,
            icon: category.icon,
            selected: selected,
            onTap: () => setState(() => _category = category),
          );
        },
      ),
    );
  }

  Widget _perkRail() {
    const perks = <(IconData, String)>[
      (Icons.verified_user_outlined, 'Zero deposit'),
      (Icons.bolt_rounded, 'Instant unlock'),
      (Icons.event_available_rounded, 'Free cancel (24h)'),
      (Icons.clean_hands_rounded, 'Sanitised & inspected'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        itemCount: perks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final perk = perks[index];
          return CarHirePill(
            label: perk.$2,
            icon: perk.$1,
            background: CarHirePalette.surfaceLow,
            foreground: CarHirePalette.onSurfaceVariant,
            fontSize: 10.5,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          );
        },
      ),
    );
  }

  List<Widget> _resultSlivers(
    AsyncValue<CarHireSearchResult> results,
    CarHireSearchQuery query,
  ) {
    return results.when(
      loading: () => <Widget>[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 24),
            child: CarHireLoadingState(
              message: 'Checking availability for your dates…',
              padding: EdgeInsets.all(20),
            ),
          ),
        ),
      ],
      error: (error, _) => <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: CarHireErrorState(
              error: error,
              onRetry: _refresh,
            ),
          ),
        ),
      ],
      data: (result) {
        final cars = result.data;
        final visible = _visibleCars(cars);
        final median = _medianRate(cars);
        final days = _rentalDays(query);

        if (cars.isEmpty) {
          return <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: CarHireEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No cars available',
                  message: query.pickupArea.trim().isEmpty
                      ? 'No vehicles match these dates. Try a different '
                          'pick-up or return time.'
                      : 'No vehicles match these dates in '
                          '"${query.pickupArea}". Try different dates or clear '
                          'the pick-up area.',
                  actionLabel: query.pickupArea.trim().isEmpty
                      ? null
                      : 'Clear area & retry',
                  onAction: query.pickupArea.trim().isEmpty
                      ? null
                      : () {
                          _pickupController.clear();
                          _onSearch();
                        },
                ),
              ),
            ),
          ];
        }

        return <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: _PriceMapCard(
                cars: visible.isEmpty ? cars : visible,
                query: query,
                onViewMap: () => _openAreaOnMap(query),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Available near you',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CarHireType.titleLarge.copyWith(fontSize: 19),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CarHirePill(
                          label: '${visible.length} cars',
                          background: CarHirePalette.accentPale,
                          foreground: CarHirePalette.onAccentSoft,
                          fontSize: 10.5,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openSortSheet,
                      borderRadius: BorderRadius.circular(99),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Sort:',
                              style: CarHireType.labelSmall.copyWith(
                                fontSize: 10.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sort.shortLabel,
                              style: const TextStyle(
                                color: CarHirePalette.onSurface,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: CarHirePalette.onSurface,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: CarHireSurface(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 26,
                        color: CarHirePalette.muted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No cars match "${_category.label}"',
                        textAlign: TextAlign.center,
                        style: CarHireType.subtitle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try another category or clear the filter to see all '
                        '${cars.length} available vehicles.',
                        textAlign: TextAlign.center,
                        style: CarHireType.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => setState(
                          () => _category = _VehicleCategory.all,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: CarHirePalette.accent,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        child: const Text('Show all cars'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final car = visible[index];
                  return CarHireListingCard(
                    car: car,
                    rentalDays: days,
                    priceBand: _bandFor(car, median),
                    onTap: () => CarHireRoutes.openDetail(
                      context,
                      car: car,
                      startAt: query.startAt,
                      endAt: query.endAt,
                    ),
                  );
                },
              ),
            ),
          if (result.hasMore || result.total > cars.length)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  'Showing ${cars.length} of ${result.total}. Add a pick-up '
                  'area to narrow the results.',
                  textAlign: TextAlign.center,
                  style: CarHireType.labelSmall,
                ),
              ),
            ),
        ];
      },
    );
  }

  Widget _guaranteeBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CarHireSurface(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: CarHirePalette.accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 21,
                color: CarHirePalette.onAccentSoft,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vero360 Hire Guarantee',
                    style: TextStyle(
                      color: CarHirePalette.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Verified providers, secure in-app payment and 24/7 '
                    'roadside support on every trip.',
                    style: TextStyle(
                      color: CarHirePalette.onSurfaceVariant,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Small pieces
// -------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: CarHireShape.fast,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? CarHirePalette.accent : CarHirePalette.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? CarHirePalette.accent
                  : CarHirePalette.hairline,
            ),
            boxShadow: selected ? CarHireShape.cardShadow : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? CarHirePalette.onAccent
                    : CarHirePalette.accent,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? CarHirePalette.onAccent
                      : CarHirePalette.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  const _SortTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? CarHirePalette.accentPale
                : CarHirePalette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? CarHirePalette.accent.withValues(alpha: 0.4)
                  : CarHirePalette.hairline,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: CarHirePalette.onSurface,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: CarHirePalette.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "radar" preview showing where the closest prices sit.
class _PriceMapCard extends StatelessWidget {
  const _PriceMapCard({
    required this.cars,
    required this.query,
    required this.onViewMap,
  });

  final List<CarListing> cars;
  final CarHireSearchQuery query;
  final VoidCallback onViewMap;

  static const List<Alignment> _slots = <Alignment>[
    Alignment(-0.62, -0.5),
    Alignment(0.12, 0.02),
    Alignment(0.6, -0.62),
    Alignment(-0.16, 0.6),
  ];

  @override
  Widget build(BuildContext context) {
    final pins = cars
        .where((car) => car.dailyRate > 0)
        .take(_slots.length)
        .toList(growable: false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 162,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _MapPainter()),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        CarHirePalette.primary.withValues(alpha: 0.02),
                        CarHirePalette.primary.withValues(alpha: 0.12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            for (var index = 0; index < pins.length; index++)
              Align(
                alignment: _slots[index],
                child: _PricePin(
                  label: _compactMoney(pins[index].dailyRate),
                  highlighted: index == 0,
                  onTap: onViewMap,
                ),
              ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.explore_outlined,
                      size: 13,
                      color: CarHirePalette.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      query.pickupArea.trim().isEmpty
                          ? 'All pick-up areas'
                          : query.pickupArea.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CarHirePalette.onSurface,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  onTap: onViewMap,
                  borderRadius: BorderRadius.circular(99),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.map_outlined,
                          size: 14,
                          color: CarHirePalette.accent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'View on map (${cars.length})',
                          style: const TextStyle(
                            color: CarHirePalette.onSurface,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compactMoney(double amount) {
    final formatted = CarHireFormatters.formatCurrency(amount);
    final whole = formatted.split('.').first;
    return whole;
  }
}

class _PricePin extends StatelessWidget {
  const _PricePin({
    required this.label,
    required this.highlighted,
    required this.onTap,
  });

  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: highlighted
                ? CarHirePalette.primary
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: CarHirePalette.primary.withValues(alpha: 0.16),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (highlighted) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: CarHirePalette.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                '$label/d',
                style: TextStyle(
                  color: highlighted
                      ? Colors.white
                      : CarHirePalette.onSurface,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight stylised street grid. Keeps the preview honest (it is a
/// coverage illustration, not a live map) while matching the reference.
class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFEDEAE8);
    canvas.drawRect(Offset.zero & size, background);

    final blockPaint = Paint()..color = const Color(0xFFE2DFDD);
    final blocks = <Rect>[
      Rect.fromLTWH(size.width * 0.04, size.height * 0.08,
          size.width * 0.22, size.height * 0.24),
      Rect.fromLTWH(size.width * 0.31, size.height * 0.05,
          size.width * 0.18, size.height * 0.18),
      Rect.fromLTWH(size.width * 0.55, size.height * 0.12,
          size.width * 0.16, size.height * 0.26),
      Rect.fromLTWH(size.width * 0.76, size.height * 0.06,
          size.width * 0.2, size.height * 0.2),
      Rect.fromLTWH(size.width * 0.08, size.height * 0.5,
          size.width * 0.2, size.height * 0.24),
      Rect.fromLTWH(size.width * 0.34, size.height * 0.46,
          size.width * 0.16, size.height * 0.18),
      Rect.fromLTWH(size.width * 0.58, size.height * 0.52,
          size.width * 0.2, size.height * 0.2),
      Rect.fromLTWH(size.width * 0.84, size.height * 0.44,
          size.width * 0.14, size.height * 0.3),
      Rect.fromLTWH(size.width * 0.1, size.height * 0.82,
          size.width * 0.24, size.height * 0.14),
      Rect.fromLTWH(size.width * 0.48, size.height * 0.8,
          size.width * 0.22, size.height * 0.14),
    ];
    for (final block in blocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(block, const Radius.circular(4)),
        blockPaint,
      );
    }

    final roadCasement = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final roadCentre = Paint()
      ..color = const Color(0xFFD8D4D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    final roads = <Path>[
      Path()
        ..moveTo(-10, size.height * 0.36)
        ..cubicTo(
          size.width * 0.25,
          size.height * 0.24,
          size.width * 0.55,
          size.height * 0.56,
          size.width + 10,
          size.height * 0.38,
        ),
      Path()
        ..moveTo(size.width * 0.28, -10)
        ..cubicTo(
          size.width * 0.36,
          size.height * 0.3,
          size.width * 0.2,
          size.height * 0.62,
          size.width * 0.34,
          size.height + 10,
        ),
      Path()
        ..moveTo(size.width * 0.72, -10)
        ..cubicTo(
          size.width * 0.66,
          size.height * 0.35,
          size.width * 0.8,
          size.height * 0.6,
          size.width * 0.7,
          size.height + 10,
        ),
    ];

    for (final road in roads) {
      canvas.drawPath(road, roadCasement);
      canvas.drawPath(road, roadCentre);
    }

    // A small park block for visual texture.
    final park = Paint()..color = const Color(0xFFD9E4D6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.46, size.height * 0.66,
            size.width * 0.1, size.height * 0.12),
        const Radius.circular(6),
      ),
      park,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}
