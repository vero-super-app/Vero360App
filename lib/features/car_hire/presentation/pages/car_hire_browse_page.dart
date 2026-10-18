import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_listing_card.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_search_form.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';

class CarHireBrowsePage extends ConsumerStatefulWidget {
  const CarHireBrowsePage({super.key});

  @override
  ConsumerState<CarHireBrowsePage> createState() => _CarHireBrowsePageState();
}

class _CarHireBrowsePageState extends ConsumerState<CarHireBrowsePage> {
  late final TextEditingController _pickupController;

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

  void _onSearch() {
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

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(carHireSearchProvider);
    final results = ref.watch(carHireResultsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: CarRentalColors.title,
        elevation: 0.4,
        scrolledUnderElevation: 0.4,
        title: const Text(
          'Car Hire',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'My bookings',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => CarHireRoutes.openBookings(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: CarRentalColors.brandOrange,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: CarRentalColors.brandOrangePale,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_car_filled_rounded,
                        size: 20,
                        color: CarRentalColors.brandOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Self-drive rentals',
                            style: TextStyle(
                              color: CarRentalColors.title,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Book a car for your exact dates',
                            style: TextStyle(
                              color: CarRentalColors.body,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CarHireSearchForm(
                pickupController: _pickupController,
                startAt: query.startAt ?? DateTime.now(),
                endAt: query.endAt ?? DateTime.now(),
                onPickStart: _pickStart,
                onPickEnd: _pickEnd,
                onSearch: _onSearch,
                searching: results.isLoading,
              ),
            ),
            ..._resultSlivers(results, query),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 20,
              ),
            ),
          ],
        ),
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
            padding: EdgeInsets.only(top: 26),
            child: CarHireLoadingState(
              message: 'Checking availability for your dates…',
              padding: EdgeInsets.all(20),
            ),
          ),
        ),
      ],
      error: (error, _) => <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: CarHireErrorState(
            error: error,
            onRetry: _refresh,
          ),
        ),
      ],
      data: (result) {
        if (result.data.isEmpty) {
          return <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: CarHireEmptyState(
                icon: Icons.directions_car_outlined,
                title: 'No cars available',
                message: query.pickupArea.trim().isEmpty
                    ? 'No vehicles match these dates. Try a different pick-up '
                        'or return time.'
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
          ];
        }

        return <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Text(
                result.total == 1
                    ? '1 vehicle available'
                    : '${result.total} vehicles available',
                style: const TextStyle(
                  color: CarRentalColors.body,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: result.data.length,
              itemBuilder: (context, index) {
                final car = result.data[index];
                return CarHireListingCard(
                  car: car,
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
          if (result.hasMore || result.total > result.data.length)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: Text(
                  'Showing ${result.data.length} of ${result.total}. '
                  'Add a pick-up area to narrow the results.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CarRentalColors.grey,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
        ];
      },
    );
  }
}
