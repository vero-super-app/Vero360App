import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_section_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_account_pages.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_browse_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_listing_card.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_search_form.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_section_frame.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/widgets/merchant_verified_badge.dart';

/// Vehicle categories shown as the horizontal chip rail.
enum _VehicleCategory { all, suv, luxury, budget, sevenSeater }

extension on _VehicleCategory {
  String get label {
    switch (this) {
      case _VehicleCategory.all:
        return 'All cars';
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
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  _VehicleCategory _category = _VehicleCategory.all;
  _SortOption _sort = _SortOption.recommended;

  static final DateFormat _shortMonthDay = DateFormat('MMM d');
  static final NumberFormat _money = NumberFormat.decimalPattern();

  @override
  void initState() {
    super.initState();
    final query = ref.read(carHireSearchProvider);
    _pickupController = TextEditingController(text: query.pickupArea);
    _searchController = TextEditingController(
      text: ref.read(carHireFiltersProvider).text,
    );
    // Sections load independently after the first frame so the static chrome
    // (location bar, search, filters) paints immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(carHireBrowseProvider.notifier).loadAll();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pickupController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------

  void _onSearchTextChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      ref.read(carHireFiltersProvider.notifier).setText(value);
      ref.read(carHireBrowseProvider.notifier).refreshResults();
    });
  }

  void _clearSearchText() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {});
    ref.read(carHireFiltersProvider.notifier).setText('');
    ref.read(carHireBrowseProvider.notifier).refreshResults();
  }

  void _clearAllFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(carHireFiltersProvider.notifier).clear();
    setState(() => _category = _VehicleCategory.all);
    ref.read(carHireBrowseProvider.notifier).refreshResults();
  }

  void _toggleCompany(CarHireCompanyOption company) {
    final current = ref.read(carHireFiltersProvider).company;
    ref
        .read(carHireFiltersProvider.notifier)
        .setCompany(current?.id == company.id ? null : company);
    ref.read(carHireBrowseProvider.notifier).refreshResults();
  }

  Future<void> _openFilterSheet() async {
    FocusScope.of(context).unfocus();
    final next = await showModalBottomSheet<CarHireFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: CarHirePalette.background,
      barrierColor: CarHirePalette.primary.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _FilterSheet(
        initial: ref.read(carHireFiltersProvider),
        companies:
            ref.read(carHireBrowseProvider).companies.data ??
            const <CarHireCompanyOption>[],
        formatMoney: (value) => 'MWK ${_money.format(value)}',
      ),
    );
    if (next != null && mounted) {
      ref.read(carHireFiltersProvider.notifier).set(next);
      ref.read(carHireBrowseProvider.notifier).refreshResults();
    }
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
    final query = ref.read(carHireSearchProvider);
    final initial =
        query.startAt ?? DateTime.now().add(const Duration(days: 1));
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
      _snack(
        'Choose a pick-up and return time, with the return after pick-up.',
      );
      return;
    }
    ref
        .read(carHireSearchProvider.notifier)
        .setPickupArea(_pickupController.text);
    ref.read(carHireBrowseProvider.notifier).refreshResults();
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
    // Each section swallows its own failure; the strips explain what failed.
    await ref.read(carHireBrowseProvider.notifier).loadAll();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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
    final rates =
        cars
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

    bool isSuv(CarListing car) {
      final body = (car.bodyType ?? '').toUpperCase();
      return body.contains('SUV') ||
          body.contains('4X4') ||
          body.contains('CROSSOVER') ||
          body.contains('PICKUP');
    }

    final filtered = cars
        .where((car) {
          switch (_category) {
            case _VehicleCategory.all:
              return true;
            case _VehicleCategory.suv:
              return isSuv(car);
            case _VehicleCategory.luxury:
              return median > 0 && car.dailyRate >= median * 1.3;
            case _VehicleCategory.budget:
              return median > 0 && car.dailyRate <= median * 0.75;
            case _VehicleCategory.sevenSeater:
              return (car.seats ?? 0) >= 7;
          }
        })
        .toList(growable: false);

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
    return '$startLabel – $endLabel · $days ${days == 1 ? 'day' : 'days'}';
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
    final browse = ref.watch(carHireBrowseProvider);
    final filters = ref.watch(carHireFiltersProvider);
    final hasCompany =
        (ref.watch(carHireAccountProvider).value?.isActive ?? false) ||
        (ref.watch(companyAccessProvider).value?.hasCompany ?? false);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Car hire',
        actions: [
          if (hasCompany) ...[
            CarHireIconButton(
              icon: Icons.business_center_outlined,
              tooltip: 'My company',
              onTap: () => CarHireRoutes.openCompany(context),
            ),
            const SizedBox(width: 8),
          ],
          CarHireIconButton(
            icon: Icons.receipt_long_rounded,
            tooltip: 'My bookings',
            onTap: () => CarHireRoutes.openBookings(context),
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
            const SliverToBoxAdapter(
              child: CarHireAccountBanner(renterInvite: true),
            ),
            SliverToBoxAdapter(child: _locationBar(query)),
            const SliverToBoxAdapter(child: CarHireAccountBanner()),
            SliverToBoxAdapter(child: _searchRow(filters)),
            SliverToBoxAdapter(child: _companyRail(browse.companies, filters)),
            SliverToBoxAdapter(
              child: _categoryRail(
                browse.facets,
                browse.results.data?.data ?? const <CarListing>[],
              ),
            ),
            SliverToBoxAdapter(child: _activeFilterChips(filters)),
            ..._resultSlivers(browse.results, query, filters),
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
        border: Border(bottom: BorderSide(color: CarHirePalette.hairline)),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: CarHirePalette.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: CarHirePalette.hairline),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_calendar_rounded,
                        size: 15,
                        color: CarHirePalette.accent,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Edit',
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

  Widget _searchRow(CarHireFilters filters) {
    final count = filters.activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: CarHirePalette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CarHirePalette.hairline),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: CarHirePalette.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchTextChanged,
                      onSubmitted: (value) {
                        _searchDebounce?.cancel();
                        ref
                            .read(carHireFiltersProvider.notifier)
                            .setText(value);
                        ref
                            .read(carHireBrowseProvider.notifier)
                            .refreshResults();
                      },
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: CarHirePalette.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search make, model or company',
                        hintStyle: TextStyle(
                          color: CarHirePalette.muted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearchText,
                      icon: const Icon(
                        Icons.cancel_rounded,
                        size: 18,
                        color: CarHirePalette.muted,
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: count > 0 ? CarHirePalette.accent : CarHirePalette.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _openFilterSheet,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: count > 0
                        ? CarHirePalette.accent
                        : CarHirePalette.hairline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: count > 0
                          ? CarHirePalette.onAccent
                          : CarHirePalette.onSurface,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      count > 0 ? 'Filters · $count' : 'Filters',
                      style: TextStyle(
                        color: count > 0
                            ? CarHirePalette.onAccent
                            : CarHirePalette.onSurface,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyRail(
    CarHireSectionState<List<CarHireCompanyOption>> companies,
    CarHireFilters filters,
  ) {
    if (companies.isInitialLoading) {
      return const CarHireCompanyRailSkeleton();
    }
    if (companies.isUnavailable) {
      return CarHireSectionFrame(
        title: 'Companies',
        child: CarHireSectionErrorStrip(
          title: 'Company filters unavailable',
          message: 'Every car is still shown below.',
          onRetry: companies.retryable
              ? () => ref
                    .read(carHireBrowseProvider.notifier)
                    .refreshCompanies()
              : null,
        ),
      );
    }

    final list = companies.data ?? const <CarHireCompanyOption>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Companies', style: CarHireType.subtitle),
        ),
        if (companies.showsStaleData)
          CarHireSectionStaleStrip(
            message: 'Showing the companies we loaded earlier.',
            onRefresh: () =>
                ref.read(carHireBrowseProvider.notifier).refreshCompanies(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final company = list[index];
              return _CompanyAvatar(
                company: company,
                selected: filters.company?.id == company.id,
                onTap: () => _toggleCompany(company),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _activeFilterChips(CarHireFilters filters) {
    final chips = <Widget>[
      if (filters.company != null)
        _RemovableChip(
          label: filters.company!.name,
          onRemove: () =>
              ref.read(carHireFiltersProvider.notifier).setCompany(null),
        ),
      if (filters.transmission != null)
        _RemovableChip(
          label: _titleCase(filters.transmission!),
          onRemove: () => ref
              .read(carHireFiltersProvider.notifier)
              .set(filters.copyWith(transmission: () => null)),
        ),
      if (filters.fuelType != null)
        _RemovableChip(
          label: _titleCase(filters.fuelType!),
          onRemove: () => ref
              .read(carHireFiltersProvider.notifier)
              .set(filters.copyWith(fuelType: () => null)),
        ),
      if (filters.minSeats != null)
        _RemovableChip(
          label: '${filters.minSeats}+ seats',
          onRemove: () => ref
              .read(carHireFiltersProvider.notifier)
              .set(filters.copyWith(minSeats: () => null)),
        ),
      if (filters.maxRate != null)
        _RemovableChip(
          label: 'Up to MWK ${_money.format(filters.maxRate)}/day',
          onRemove: () => ref
              .read(carHireFiltersProvider.notifier)
              .set(filters.copyWith(maxRate: () => null)),
        ),
      if (filters.instantOnly)
        _RemovableChip(
          label: 'Instant confirmation',
          onRemove: () => ref
              .read(carHireFiltersProvider.notifier)
              .set(filters.copyWith(instantOnly: false)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          TextButton(
            onPressed: _clearAllFilters,
            style: TextButton.styleFrom(
              foregroundColor: CarHirePalette.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  Widget _categoryRail(
    CarHireSectionState<CarHireFacets> facets,
    List<CarListing> cars,
  ) {
    // Only hide the rail when the first load is still running with nothing to
    // count; the chips themselves are always usable once rendered.
    if (facets.isInitialLoading && cars.isEmpty) {
      return const CarHireFacetChipSkeleton();
    }
    final counts = facets.data?.categories ?? _localCategoryCounts(cars);
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
            label: _categoryLabel(category, counts),
            icon: category.icon,
            selected: selected,
            onTap: () => setState(() => _category = category),
          );
        },
      ),
    );
  }

  String _categoryLabel(
    _VehicleCategory category,
    CarHireCategoryCounts counts,
  ) {
    final count = switch (category) {
      _VehicleCategory.all => counts.all,
      _VehicleCategory.suv => counts.suv,
      _VehicleCategory.luxury => counts.luxury,
      _VehicleCategory.budget => counts.budget,
      _VehicleCategory.sevenSeater => counts.sevenSeater,
    };
    return count > 0 ? '${category.label} · $count' : category.label;
  }

  /// Fallback chip counts when the facets section failed but the cards loaded.
  /// Mirrors the server rules in `car-hire-sections.ts`.
  CarHireCategoryCounts _localCategoryCounts(List<CarListing> cars) {
    if (cars.isEmpty) return CarHireCategoryCounts.empty;
    final median = _medianRate(cars);
    var suv = 0;
    var luxury = 0;
    var budget = 0;
    var sevenSeater = 0;
    for (final car in cars) {
      final body = (car.bodyType ?? '').toUpperCase();
      if (body.contains('SUV') ||
          body.contains('4X4') ||
          body.contains('CROSSOVER') ||
          body.contains('PICKUP')) {
        suv += 1;
      }
      if (median > 0 && car.dailyRate > 0) {
        if (car.dailyRate >= median * 1.3) luxury += 1;
        if (car.dailyRate <= median * 0.75) budget += 1;
      }
      if ((car.seats ?? 0) >= 7) sevenSeater += 1;
    }
    return CarHireCategoryCounts(
      all: cars.length,
      suv: suv,
      luxury: luxury,
      budget: budget,
      sevenSeater: sevenSeater,
    );
  }

  List<Widget> _resultSlivers(
    CarHireSectionState<CarHireSearchResult> results,
    CarHireSearchQuery query,
    CarHireFilters filters,
  ) {
    if (results.isInitialLoading) {
      return const <Widget>[
        SliverToBoxAdapter(child: CarHireResultsHeaderSkeleton()),
        SliverToBoxAdapter(child: CarHireListingListSkeleton()),
      ];
    }

    if (results.isUnavailable) {
      return <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _resultsUnavailableCard(results),
          ),
        ),
      ];
    }

    final result = results.data ?? const CarHireSearchResult();
    final cars = result.data;
    final visible = _visibleCars(cars);
    final days = _rentalDays(query);

    final statusSlivers = <Widget>[
      if (results.showsStaleData)
        SliverToBoxAdapter(
          child: CarHireSectionStaleStrip(
            message: 'Showing earlier results for these dates.',
            onRefresh: () =>
                ref.read(carHireBrowseProvider.notifier).refreshResultCards(),
          ),
        )
      else if (results.isRefreshing)
        const SliverToBoxAdapter(
          child: CarHireSectionUpdatingStrip(
            message: 'Updating cars for your dates…',
          ),
        ),
    ];

    if (cars.isEmpty && !filters.isEmpty) {
      return <Widget>[
        ...statusSlivers,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: CarHireEmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'No cars match your filters',
              message: filters.company != null
                  ? '${filters.company!.name} has no cars matching these '
                        'dates and filters. Try other dates or clear the '
                        'filters.'
                  : 'Nothing matches these dates and filters. Loosen a '
                        'filter or clear them all.',
              actionLabel: 'Clear filters',
              onAction: _clearAllFilters,
            ),
          ),
        ),
      ];
    }

    if (cars.isEmpty) {
      return <Widget>[
        ...statusSlivers,
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
      ...statusSlivers,
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${visible.length} '
                  '${visible.length == 1 ? 'car' : 'cars'} available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.subtitle,
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
                        const Icon(
                          Icons.swap_vert_rounded,
                          size: 16,
                          color: CarHirePalette.onSurface,
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
                    onPressed: () =>
                        setState(() => _category = _VehicleCategory.all),
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
              'Showing ${cars.length} of ${result.total}',
              textAlign: TextAlign.center,
              style: CarHireType.labelSmall,
            ),
          ),
        ),
    ];
  }

  /// Results failed with nothing cached: a compact card that keeps the page
  /// (search, filters, companies) fully usable.
  Widget _resultsUnavailableCard(CarHireSectionState<CarHireSearchResult> state) {
    final message = state.error?.message.trim() ?? '';
    return CarHireSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              shape: BoxShape.circle,
              border: Border.all(color: CarHirePalette.hairline),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 24,
              color: CarHirePalette.muted,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cars could not load',
            textAlign: TextAlign.center,
            style: CarHireType.subtitle,
          ),
          const SizedBox(height: 4),
          Text(
            message.isEmpty
                ? 'Check your connection and try again.'
                : message,
            textAlign: TextAlign.center,
            style: CarHireType.bodySmall,
          ),
          if (state.retryable) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: 200,
              child: FilledButton.icon(
                onPressed: () => ref
                    .read(carHireBrowseProvider.notifier)
                    .refreshResultCards(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: carHirePrimaryButton(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Small pieces
// -------------------------------------------------------------------------

String _titleCase(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) return lower;
  return lower[0].toUpperCase() + lower.substring(1);
}

class _CompanyAvatar extends StatelessWidget {
  const _CompanyAvatar({
    required this.company,
    required this.selected,
    required this.onTap,
  });

  final CarHireCompanyOption company;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logo = company.logoUrl?.trim() ?? '';
    final initials = Text(
      company.initials,
      style: const TextStyle(
        color: CarHirePalette.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${company.name}, ${company.listings} cars',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: CarHireShape.fast,
                    width: 56,
                    height: 56,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? CarHirePalette.accent
                            : CarHirePalette.hairline,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: Container(
                        color: CarHirePalette.surfaceLow,
                        alignment: Alignment.center,
                        child: logo.isEmpty
                            ? initials
                            : Image.network(
                                logo,
                                fit: BoxFit.cover,
                                width: 56,
                                height: 56,
                                errorBuilder: (_, _, _) => initials,
                              ),
                      ),
                    ),
                  ),
                  if (company.verified)
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: MerchantVerifiedBadge(
                        showLabel: false,
                        size: 16,
                        tooltip: 'Verified car hire',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                company.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? CarHirePalette.accent
                      : CarHirePalette.onSurface,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              Text(
                '${company.listings} ${company.listings == 1 ? 'car' : 'cars'}',
                style: CarHireType.labelSmall.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CarHirePalette.accentPale,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: CarHirePalette.onSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.close_rounded,
                size: 15,
                color: CarHirePalette.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that edits a draft of the filters and returns it on apply.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.companies,
    required this.formatMoney,
  });

  final CarHireFilters initial;
  final List<CarHireCompanyOption> companies;
  final String Function(double value) formatMoney;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CarHireFilters _draft = widget.initial;

  static const _transmissions = ['AUTOMATIC', 'MANUAL'];
  static const _fuels = ['PETROL', 'DIESEL', 'HYBRID'];
  static const _seats = [4, 5, 7];
  static const _prices = <double>[50000, 80000, 120000, 200000];

  Widget _section(String title, List<Widget> pills) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CarHireType.subtitle),
          const SizedBox(height: 9),
          Wrap(spacing: 7, runSpacing: 7, children: pills),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return _CategoryChip(
      label: label,
      icon: selected ? Icons.check_rounded : Icons.circle_outlined,
      selected: selected,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: CarHirePalette.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Filters', style: CarHireType.titleLarge),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _draft = CarHireFilters(text: draft.text)),
                  style: TextButton.styleFrom(
                    foregroundColor: CarHirePalette.accent,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.companies.isNotEmpty)
                    _section('Company', [
                      _pill('Any company', draft.company == null, () {
                        setState(
                          () => _draft = draft.copyWith(company: () => null),
                        );
                      }),
                      for (final company in widget.companies)
                        _pill(
                          company.name,
                          draft.company?.id == company.id,
                          () => setState(
                            () =>
                                _draft = draft.copyWith(company: () => company),
                          ),
                        ),
                    ]),
                  _section('Gearbox', [
                    _pill('Any', draft.transmission == null, () {
                      setState(
                        () => _draft = draft.copyWith(transmission: () => null),
                      );
                    }),
                    for (final value in _transmissions)
                      _pill(
                        _titleCase(value),
                        draft.transmission == value,
                        () => setState(
                          () => _draft = draft.copyWith(
                            transmission: () => value,
                          ),
                        ),
                      ),
                  ]),
                  _section('Fuel', [
                    _pill('Any', draft.fuelType == null, () {
                      setState(
                        () => _draft = draft.copyWith(fuelType: () => null),
                      );
                    }),
                    for (final value in _fuels)
                      _pill(
                        _titleCase(value),
                        draft.fuelType == value,
                        () => setState(
                          () => _draft = draft.copyWith(fuelType: () => value),
                        ),
                      ),
                  ]),
                  _section('Seats', [
                    _pill('Any', draft.minSeats == null, () {
                      setState(
                        () => _draft = draft.copyWith(minSeats: () => null),
                      );
                    }),
                    for (final value in _seats)
                      _pill(
                        '$value+',
                        draft.minSeats == value,
                        () => setState(
                          () => _draft = draft.copyWith(minSeats: () => value),
                        ),
                      ),
                  ]),
                  _section('Daily price', [
                    _pill('Any price', draft.maxRate == null, () {
                      setState(
                        () => _draft = draft.copyWith(maxRate: () => null),
                      );
                    }),
                    for (final value in _prices)
                      _pill(
                        'Up to ${widget.formatMoney(value)}',
                        draft.maxRate == value,
                        () => setState(
                          () => _draft = draft.copyWith(maxRate: () => value),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: CarHirePalette.accent,
                    value: draft.instantOnly,
                    onChanged: (value) => setState(
                      () => _draft = draft.copyWith(instantOnly: value),
                    ),
                    title: const Text(
                      'Instant confirmation only',
                      style: CarHireType.subtitle,
                    ),
                    subtitle: const Text(
                      'Hide companies that review each request first.',
                      style: CarHireType.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_draft),
                style: FilledButton.styleFrom(
                  backgroundColor: CarHirePalette.accent,
                  foregroundColor: CarHirePalette.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Show cars'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
              color: selected ? CarHirePalette.accent : CarHirePalette.hairline,
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
