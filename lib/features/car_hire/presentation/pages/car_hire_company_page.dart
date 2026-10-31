import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/utils/app_wallet_pin.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_section_frame.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/widgets/merchant_verified_badge.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Company home: one glanceable dashboard instead of a wall of tables.
///
/// Fleet pulse first, then only the operations that need an answer today,
/// then the cars themselves. Everything else (pricing, photos, adding cars)
/// stays on the web workspace.
class CarHireCompanyPage extends ConsumerWidget {
  const CarHireCompanyPage({super.key, this.asHome = false});

  /// True when this is the car hire landing page for a company account, so
  /// the renter marketplace is offered as a secondary destination.
  final bool asHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(companyAccessProvider);
    final access = accessAsync.value;

    // Keep the resolved membership on screen while it refreshes so the
    // dashboard never falls back to a skeleton once it has painted.
    if (access != null && access.hasCompany) {
      return _CompanyDashboard(access: access, asHome: asHome);
    }

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(title: 'Company'),
      body: access != null
          ? const CarHireEmptyState(
              icon: Icons.business_outlined,
              title: 'No active company',
              message:
                  'Company mode is for staff of an approved car hire '
                  'company. Ask the company owner to invite your Vero360 email.',
            )
          : accessAsync.hasError
          ? CarHireErrorState(
              error: accessAsync.error,
              onRetry: () => ref.invalidate(companyAccessProvider),
            )
          : Semantics(
              label: 'Opening your company',
              container: true,
              child: const ExcludeSemantics(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 32),
                  child: CarHireCompanyDashboardSkeleton(),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class _CompanyDashboard extends ConsumerStatefulWidget {
  const _CompanyDashboard({required this.access, required this.asHome});

  final CompanyAccess access;
  final bool asHome;

  @override
  ConsumerState<_CompanyDashboard> createState() => _CompanyDashboardState();
}

class _CompanyDashboardState extends ConsumerState<_CompanyDashboard> {
  final _search = TextEditingController();
  String _query = '';
  _UnitFilter _filter = _UnitFilter.all;

  static const _maxCards = 6;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final today = companyDateKey(DateTime.now());
    ref.invalidate(companyFleetProvider);
    ref.invalidate(companyBookingsProvider('ACTIVE'));
    ref.invalidate(companyBookingsProvider('CONFIRMED'));
    ref.invalidate(companyDispatchProvider(today));
    ref.invalidate(companyAnalyticsProvider);
    try {
      await ref.read(companyFleetProvider.future);
    } catch (_) {
      // The inline card states explain the failure; pull-to-refresh must end.
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(companyFleetProvider);
    final activeAsync = widget.access.canViewBookings
        ? ref.watch(companyBookingsProvider('ACTIVE'))
        : const AsyncValue<List<CarHireBooking>>.data(<CarHireBooking>[]);
    final upcomingAsync = widget.access.canViewBookings
        ? ref.watch(companyBookingsProvider('CONFIRMED'))
        : const AsyncValue<List<CarHireBooking>>.data(<CarHireBooking>[]);
    final boardAsync = widget.access.canViewBookings
        ? ref.watch(companyDispatchProvider(companyDateKey(DateTime.now())))
        : const AsyncValue<DispatchBoard>.loading();
    final analytics = ref.watch(companyAnalyticsProvider).value;

    final units = fleetAsync.value ?? const <FleetUnit>[];
    final bookings = <CarHireBooking>[
      ...?activeAsync.value,
      ...?upcomingAsync.value,
    ];
    final snapshot = _FleetSnapshot(
      units: units,
      activeByUnit: _activeByUnit(bookings),
      bookingsKnown: activeAsync.hasValue && upcomingAsync.hasValue,
    );

    final visible = _visibleUnits(snapshot);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: widget.asHome ? 'Car hire' : 'Company',
        actions: widget.asHome
            ? [
                CarHireIconButton(
                  icon: Icons.storefront_outlined,
                  tooltip: 'Browse marketplace',
                  onTap: () => CarHireRoutes.openBrowse(context),
                ),
                const SizedBox(width: 16),
              ]
            : null,
      ),
      body: RefreshIndicator(
        color: CarHirePalette.accent,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _CompanyStrip(
              access: widget.access,
              snapshot: snapshot,
              loading: fleetAsync.isLoading && !fleetAsync.hasValue,
            ),
            if (widget.access.canManageWallet) ...[
              const SizedBox(height: 12),
              _WalletTile(companyName: widget.access.title),
            ],
            const SizedBox(height: 14),
            ..._pulseSection(fleetAsync, activeAsync, analytics, snapshot),
            const SizedBox(height: 18),
            if (widget.access.canViewBookings) ...[
              _NextOpsSection(
                board: boardAsync,
                onSeeAll: () => CarHireRoutes.openCompanyBookings(context),
                onRetry: () => ref.invalidate(
                  companyDispatchProvider(companyDateKey(DateTime.now())),
                ),
                onOpen: (booking) => CarHireRoutes.openCompanyBooking(
                  context,
                  bookingId: booking.id,
                ),
              ),
              const SizedBox(height: 18),
            ],
            TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search plate, model or renter',
                hintStyle: CarHireType.bodySmall.copyWith(
                  color: CarHirePalette.muted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: CarHirePalette.muted,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: 17),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: CarHirePalette.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
                  borderSide: const BorderSide(color: CarHirePalette.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
                  borderSide: const BorderSide(color: CarHirePalette.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
                  borderSide: const BorderSide(color: CarHirePalette.accent),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final filter in _UnitFilter.values) ...[
                    _FilterPill(
                      label: filter.labelFor(snapshot),
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._carSection(snapshot, visible, fleetAsync, activeAsync),
          ],
        ),
      ),
    );
  }

  List<FleetUnit> _visibleUnits(_FleetSnapshot snapshot) {
    final query = _query.trim().toLowerCase();
    return snapshot.units
        .where((unit) {
          final booking = snapshot.activeByUnit[unit.id];
          final matchesFilter = switch (_filter) {
            _UnitFilter.all => true,
            _UnitFilter.onRoad => booking != null,
            _UnitFilter.ready => booking == null && unit.car.isAvailable,
            _UnitFilter.prep => !unit.car.isAvailable,
          };
          if (!matchesFilter) return false;
          if (query.isEmpty) return true;
          final haystack = [
            unit.car.title,
            unit.plateLabel,
            unit.car.branchName ?? '',
            booking?.renterName ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<Widget> _pulseSection(
    AsyncValue<List<FleetUnit>> fleet,
    AsyncValue<List<CarHireBooking>> activeBookings,
    CompanyAnalytics? analytics,
    _FleetSnapshot snapshot,
  ) {
    if (fleet.isLoading && !fleet.hasValue) {
      return const [CarHireCompanyPulseSkeleton()];
    }
    if (fleet.hasError && !fleet.hasValue) {
      return [
        CarHireSectionErrorStrip(
          title: 'Fleet numbers unavailable',
          message:
              'Live counts could not load. Today’s work and your cars '
              'below still load on their own.',
          padding: EdgeInsets.zero,
          onRetry: () => ref.invalidate(companyFleetProvider),
        ),
      ];
    }
    return [
      if (fleet.hasError) ...[
        CarHireSectionStaleStrip(
          message: 'Fleet numbers may be out of date.',
          padding: const EdgeInsets.only(bottom: 8),
          onRefresh: () => ref.invalidate(companyFleetProvider),
        ),
      ],
      _PulseCard(
        snapshot: snapshot,
        analytics: analytics,
        bookingsFailed: activeBookings.hasError,
        loading: fleet.isLoading && !fleet.hasValue,
      ),
    ];
  }

  List<Widget> _carSection(
    _FleetSnapshot snapshot,
    List<FleetUnit> visible,
    AsyncValue<List<FleetUnit>> fleet,
    AsyncValue<List<CarHireBooking>> activeBookings,
  ) {
    if (fleet.hasError && !fleet.hasValue) {
      return [
        CarHireSectionErrorStrip(
          title: 'Fleet unavailable',
          message:
              'We could not load your cars. The rest of the page is still '
              'usable — retry when the connection is back.',
          padding: EdgeInsets.zero,
          onRetry: () => ref.invalidate(companyFleetProvider),
        ),
      ];
    }
    if (fleet.isLoading && !fleet.hasValue) {
      return const [
        CarHireCompanyCarCardSkeleton(),
        CarHireCompanyCarCardSkeleton(),
      ];
    }
    if (snapshot.units.isEmpty) {
      return [
        _QuietCard(
          icon: Icons.directions_car_outlined,
          message: widget.access.canManageFleet
              ? 'No cars yet · add your first vehicle.'
              : 'No cars in this fleet yet.',
          actionLabel: widget.access.canManageFleet ? 'Add car' : null,
          onAction: widget.access.canManageFleet
              ? () => CarHireRoutes.openCompanyAddVehicle(
                  context,
                  access: widget.access,
                )
              : null,
        ),
      ];
    }
    if (visible.isEmpty) {
      return const [
        _QuietCard(icon: Icons.search_off_rounded, message: 'No cars match.'),
      ];
    }

    final cards = visible.take(_maxCards).toList(growable: false);
    final remaining = visible.length - cards.length;
    return [
      if (fleet.hasError)
        CarHireSectionStaleStrip(
          message: 'Showing the last fleet we loaded.',
          padding: const EdgeInsets.only(bottom: 10),
          onRefresh: () => ref.invalidate(companyFleetProvider),
        ),
      if (!snapshot.bookingsKnown && activeBookings.hasError)
        CarHireSectionErrorStrip(
          title: 'Live rentals not checked',
          message:
              'Car statuses may be out of date until active rentals load. '
              'You can still open a car or manage its dates.',
          padding: const EdgeInsets.only(bottom: 10),
          onRetry: () => ref.invalidate(companyBookingsProvider('ACTIVE')),
        )
      else if (!snapshot.bookingsKnown && activeBookings.isLoading)
        const CarHireSectionUpdatingStrip(
          message: 'Checking live rentals…',
          padding: EdgeInsets.only(bottom: 10),
        )
      else if (activeBookings.hasError)
        CarHireSectionStaleStrip(
          message: 'Rental statuses may be out of date.',
          padding: const EdgeInsets.only(bottom: 10),
          onRefresh: () => ref.invalidate(companyBookingsProvider('ACTIVE')),
        ),
      for (final unit in cards)
        _CarCard(
          unit: unit,
          booking: snapshot.activeByUnit[unit.id],
          statusUnknown: !snapshot.bookingsKnown,
          canManage: widget.access.canManageFleet,
          onOpenBooking: (booking) =>
              CarHireRoutes.openCompanyBooking(context, bookingId: booking.id),
          onBlock: () => showCompanyBlockSheet(context, unit: unit),
          onOpenFleet: () => CarHireRoutes.openCompanyFleet(context),
          onOpenUnit: () => CarHireRoutes.openCompanyUnit(
            context,
            unit: unit,
            access: widget.access,
          ),
        ),
      if (remaining > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TextButton(
            onPressed: () => CarHireRoutes.openCompanyFleet(context),
            style: TextButton.styleFrom(
              foregroundColor: CarHirePalette.accent,
              minimumSize: const Size.fromHeight(40),
            ),
            child: Text(
              'Show all ${visible.length} cars',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ];
  }
}

Map<int, CarHireBooking> _activeByUnit(List<CarHireBooking> bookings) {
  final map = <int, CarHireBooking>{};
  for (final booking in bookings) {
    final busy =
        booking.bookingStatus == BookingStatus.active ||
        booking.bookingStatus == BookingStatus.incidentReported ||
        booking.bookingStatus == BookingStatus.confirmed;
    if (!busy) continue;
    final unitId = booking.assignedCarId ?? booking.carId;
    if (unitId == null) continue;
    map.putIfAbsent(unitId, () => booking);
  }
  return map;
}

class _FleetSnapshot {
  const _FleetSnapshot({
    required this.units,
    required this.activeByUnit,
    this.bookingsKnown = true,
  });

  final List<FleetUnit> units;
  final Map<int, CarHireBooking> activeByUnit;

  /// False when live rentals could not be read, so on-road/ready counts are
  /// unknown rather than wrongly showing every car as ready.
  final bool bookingsKnown;

  int get total => units.length;

  int get onRoad => activeByUnit.length;

  int get prep => units
      .where((u) => !u.car.isAvailable && !activeByUnit.containsKey(u.id))
      .length;

  int get ready {
    final value = total - onRoad - prep;
    return value < 0 ? 0 : value;
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _WalletTile extends StatelessWidget {
  const _WalletTile({required this.companyName});

  final String companyName;

  Future<void> _open(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    final ok = await AppWalletPin.verifyWalletUnlock(context);
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantWalletPage(
          merchantId: uid,
          merchantName: companyName,
          serviceType: 'car_hire',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CarHirePalette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: CarHirePalette.accentPale,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: CarHirePalette.accent,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet', style: CarHireType.title),
                    SizedBox(height: 2),
                    Text(
                      'Balance, held rentals, and withdraw',
                      style: CarHireType.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: CarHirePalette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyStrip extends StatelessWidget {
  const _CompanyStrip({
    required this.access,
    required this.snapshot,
    this.loading = false,
  });

  final CompanyAccess access;
  final _FleetSnapshot snapshot;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final subline = loading
        ? 'Loading live fleet…'
        : snapshot.units.isEmpty
        ? 'Live operations'
        : '${snapshot.total} cars · ${snapshot.ready} ready';

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: CarHirePalette.accentPale,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hub_rounded,
            size: 20,
            color: CarHirePalette.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MerchantNameWithBadge(
                name: access.title,
                verified: access.hasCompany,
                showLabel: false,
                badgeSize: 16,
                tooltip: 'Verified car hire',
                style: CarHireType.title.copyWith(fontSize: 16.5),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: CarHirePalette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      subline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CarHireType.bodySmall.copyWith(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (access.canManageFleet) ...[
          CarHireIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Add car',
            size: 38,
            iconSize: 20,
            background: CarHirePalette.accent,
            foreground: Colors.white,
            onTap: () async {
              final created = await CarHireRoutes.openCompanyAddVehicle(
                context,
                access: access,
              );
              if (created != null && context.mounted) {
                CarHireRoutes.openCompanyUnit(
                  context,
                  unit: created,
                  access: access,
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
        CarHireIconButton(
          icon: Icons.directions_car_filled_outlined,
          tooltip: 'Fleet',
          size: 38,
          iconSize: 18,
          onTap: () => CarHireRoutes.openCompanyFleet(context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fleet pulse
// ---------------------------------------------------------------------------

class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.snapshot,
    required this.analytics,
    required this.loading,
    this.bookingsFailed = false,
  });

  final _FleetSnapshot snapshot;
  final CompanyAnalytics? analytics;
  final bool loading;

  /// Live rentals errored (rather than still loading).
  final bool bookingsFailed;

  @override
  Widget build(BuildContext context) {
    String count(int value) => loading && snapshot.total == 0 ? '—' : '$value';
    String rentalCount(int value) =>
        !snapshot.bookingsKnown ? '—' : count(value);

    return CarHireSurface(
      shadow: true,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.insights_rounded,
                size: 16,
                color: CarHirePalette.accent,
              ),
              const SizedBox(width: 6),
              Text(
                'Fleet pulse',
                style: CarHireType.title.copyWith(fontSize: 13.5),
              ),
              const Spacer(),
              CarHirePill(
                label: 'Live',
                icon: Icons.bolt_rounded,
                background: CarHirePalette.accentPale,
                foreground: CarHirePalette.onAccentSoft,
                fontSize: 10,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PulseMetric(
                  value: count(snapshot.total),
                  label: 'Total',
                  background: CarHirePalette.surfaceLow,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _PulseMetric(
                  value: rentalCount(snapshot.onRoad),
                  label: 'On road',
                  background: CarHirePalette.accentPale,
                  valueColor: CarHirePalette.accent,
                  dot: true,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _PulseMetric(
                  value: rentalCount(snapshot.ready),
                  label: 'Ready',
                  background: CarHirePalette.surfaceLow,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _PulseMetric(
                  value: rentalCount(snapshot.prep),
                  label: 'In prep',
                  background: CarHirePalette.surfaceLow,
                  valueColor: CarHirePalette.muted,
                ),
              ),
            ],
          ),
          if (bookingsFailed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 13,
                  color: CarHirePalette.muted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Rental statuses unavailable · counts may be incomplete.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CarHireType.bodySmall.copyWith(fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ],
          if (analytics != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
              decoration: BoxDecoration(
                color: CarHirePalette.surfaceLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: CarHirePalette.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.speed_rounded,
                      size: 16,
                      color: CarHirePalette.accentSoft,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${analytics!.utilizationRate}% utilisation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CarHireType.title.copyWith(fontSize: 12.5),
                        ),
                        Text(
                          'Last ${analytics!.periodDays} days',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CarHireType.bodySmall.copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CarHireFormatters.formatCurrency(analytics!.revenue),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: CarHireType.title.copyWith(
                            fontSize: 13.5,
                            color: CarHirePalette.accent,
                          ),
                        ),
                        Text(
                          analytics!.completed == 1
                              ? '1 completed rental'
                              : '${analytics!.completed} completed rentals',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: CarHireType.bodySmall.copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseMetric extends StatelessWidget {
  const _PulseMetric({
    required this.value,
    required this.label,
    required this.background,
    this.valueColor,
    this.dot = false,
  });

  final String value;
  final String label;
  final Color background;
  final Color? valueColor;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (dot) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: CarHirePalette.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: TextStyle(
                  fontSize: 16.5,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? CarHirePalette.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: CarHireType.labelSmall.copyWith(
              fontSize: 10,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's operations
// ---------------------------------------------------------------------------

class _NextOpsSection extends StatelessWidget {
  const _NextOpsSection({
    required this.board,
    required this.onSeeAll,
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<DispatchBoard> board;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;
  final ValueChanged<CarHireBooking> onOpen;

  @override
  Widget build(BuildContext context) {
    final data = board.value;
    final ops = data == null ? const <_Operation>[] : _operations(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.bolt_rounded,
              size: 17,
              color: CarHirePalette.accent,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Needs you today',
                style: CarHireType.title.copyWith(fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: CarHirePalette.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See all',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (board.hasError && data != null)
          CarHireSectionStaleStrip(
            message: 'Today’s work may be out of date.',
            padding: const EdgeInsets.only(bottom: 6),
            onRefresh: onRetry,
          ),
        CarHireSurface(
          radius: 16,
          padding: const EdgeInsets.all(7),
          child: Column(
            children: [
              if (board.hasError && data == null)
                CarHireSectionErrorStrip(
                  message: 'Could not load today’s work.',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  onRetry: onRetry,
                )
              else if (board.isLoading && data == null)
                const CarHireCompanyOpsRowSkeleton()
              else if (data == null)
                const _QuietRow(
                  icon: Icons.schedule_rounded,
                  message: 'Loading today…',
                )
              else if (ops.isEmpty)
                const _QuietRow(
                  icon: Icons.check_circle_outline_rounded,
                  message: 'All clear · nothing due today.',
                )
              else
                for (final op in ops)
                  _NextOpRow(op: op, onTap: () => onOpen(op.booking)),
            ],
          ),
        ),
      ],
    );
  }

  static List<_Operation> _operations(DispatchBoard board) {
    final ops = <_Operation>[
      for (final booking in board.awaitingResponse)
        _Operation(
          booking: booking,
          title: booking.holdExpiresAt == null
              ? 'Answer request'
              : 'Request · by ${CarHireFormatters.formatTime(booking.holdExpiresAt!)}',
          action: 'Review',
          icon: Icons.hourglass_top_rounded,
          background: CarHirePalette.warningSoft,
          foreground: CarHirePalette.warning,
        ),
      for (final booking in board.upcomingPickups)
        _Operation(
          booking: booking,
          title: booking.startAt == null
              ? 'Paid booking'
              : 'Paid · pickup ${CarHireFormatters.formatDate(booking.startAt!)}',
          action: 'Prepare',
          icon: Icons.event_available_rounded,
          background: CarHirePalette.accentSoft,
          foreground: CarHirePalette.onAccentSoft,
        ),
      for (final booking in board.overdueReturns)
        _Operation(
          booking: booking,
          title: 'Overdue return',
          action: 'Resolve',
          icon: Icons.assignment_return_rounded,
          background: CarHirePalette.errorSoft,
          foreground: CarHirePalette.error,
        ),
      for (final booking in board.latePickups)
        _Operation(
          booking: booking,
          title: 'Late pickup',
          action: 'Resolve',
          icon: Icons.running_with_errors_rounded,
          background: CarHirePalette.errorSoft,
          foreground: CarHirePalette.error,
        ),
      for (final booking in board.returns)
        _Operation(
          booking: booking,
          title: booking.endAt == null
              ? 'Return'
              : 'Return ${CarHireFormatters.formatTime(booking.endAt!)}',
          action: 'Check-in',
          icon: Icons.south_west_rounded,
          background: CarHirePalette.accentSoft,
          foreground: CarHirePalette.onAccentSoft,
        ),
      for (final booking in board.pickups)
        _Operation(
          booking: booking,
          title: booking.startAt == null
              ? 'Pickup'
              : 'Pickup ${CarHireFormatters.formatTime(booking.startAt!)}',
          action: 'Hand over',
          icon: Icons.north_east_rounded,
          background: CarHirePalette.primary,
          foreground: CarHirePalette.accentSoft,
        ),
    ];
    return ops.take(3).toList(growable: false);
  }
}

class _Operation {
  const _Operation({
    required this.booking,
    required this.title,
    required this.action,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final CarHireBooking booking;
  final String title;
  final String action;
  final IconData icon;
  final Color background;
  final Color foreground;

  String get subtitle {
    final car =
        booking.car?.title ??
        booking.assignedPlate ??
        'Car #${booking.assignedCarId ?? booking.carId ?? '—'}';
    return [
      car,
      if (booking.renterName != null && booking.renterName!.trim().isNotEmpty)
        booking.renterName!,
    ].join(' · ');
  }
}

class _NextOpRow extends StatelessWidget {
  const _NextOpRow({required this.op, required this.onTap});

  final _Operation op;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: op.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(op.icon, size: 15, color: op.foreground),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      op.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CarHireType.title.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      op.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CarHireType.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: CarHirePalette.surfaceLow,
                  borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
                ),
                child: Text(
                  op.action,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: CarHirePalette.onSurface,
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

class _QuietRow extends StatelessWidget {
  const _QuietRow({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: CarHirePalette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: CarHireType.bodySmall.copyWith(fontSize: 11.5),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: CarHirePalette.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuietCard extends StatelessWidget {
  const _QuietCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(6),
      child: _QuietRow(
        icon: icon,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters and car cards
// ---------------------------------------------------------------------------

enum _UnitFilter {
  all,
  onRoad,
  ready,
  prep;

  String labelFor(_FleetSnapshot snapshot) => switch (this) {
    _UnitFilter.all => 'All (${snapshot.total})',
    _UnitFilter.onRoad => 'On road (${snapshot.onRoad})',
    _UnitFilter.ready => 'Ready (${snapshot.ready})',
    _UnitFilter.prep => 'In prep (${snapshot.prep})',
  };
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
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
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? CarHirePalette.primary : CarHirePalette.surface,
          borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
          border: Border.all(
            color: selected ? CarHirePalette.primary : CarHirePalette.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : CarHirePalette.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({
    required this.unit,
    required this.booking,
    required this.canManage,
    required this.onOpenBooking,
    required this.onBlock,
    required this.onOpenFleet,
    required this.onOpenUnit,
    this.statusUnknown = false,
  });

  final FleetUnit unit;
  final CarHireBooking? booking;
  final bool canManage;
  final ValueChanged<CarHireBooking> onOpenBooking;
  final VoidCallback onBlock;
  final VoidCallback onOpenFleet;
  final VoidCallback onOpenUnit;

  /// Live rentals failed to load; avoid claiming the car is ready.
  final bool statusUnknown;

  bool get _onRoad =>
      booking != null &&
      (booking!.bookingStatus == BookingStatus.active ||
          booking!.bookingStatus == BookingStatus.incidentReported);
  bool get _booked =>
      booking != null && booking!.bookingStatus == BookingStatus.confirmed;
  bool get _busy => _onRoad || _booked;
  bool get _inPrep => !unit.car.isAvailable && !_busy;

  Color get _tone {
    if (statusUnknown && !_busy && !_inPrep) return CarHirePalette.muted;
    if (_onRoad) return CarHirePalette.accent;
    if (_booked) return CarHirePalette.onAccentSoft;
    if (_inPrep) return CarHirePalette.warning;
    return CarHirePalette.success;
  }

  Color get _toneSoft {
    if (statusUnknown && !_busy && !_inPrep) return CarHirePalette.surfaceLow;
    if (_onRoad) return CarHirePalette.accentPale;
    if (_booked) return CarHirePalette.accentSoft;
    if (_inPrep) return CarHirePalette.warningSoft;
    return CarHirePalette.successSoft;
  }

  String get _statusLabel {
    if (_onRoad) return 'On road · ${_returnsLabel(booking!.endAt)}';
    if (_booked) {
      return booking!.startAt == null
          ? 'Booked · paid'
          : 'Booked · pickup ${CarHireFormatters.formatDate(booking!.startAt!)}';
    }
    if (_inPrep) return 'In prep · unavailable';
    if (statusUnknown) return 'Status not checked';
    if (unit.car.dailyRate > 0) {
      return 'Ready · ${CarHireFormatters.formatCurrency(unit.car.dailyRate)}/day';
    }
    return 'Ready · listed';
  }

  String get _meta {
    final parts = <String>[
      if ((unit.car.fuelType ?? '').trim().isNotEmpty) unit.car.fuelType!,
      if ((unit.car.transmission ?? '').trim().isNotEmpty)
        unit.car.transmission!,
      if (unit.car.seats != null) '${unit.car.seats} seats',
    ];
    return parts.join(' · ');
  }

  String get _plate {
    final plate = unit.licensePlate?.trim();
    if (plate != null && plate.isNotEmpty) return plate.toUpperCase();
    final label = unit.unitLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return 'No plate';
  }

  @override
  Widget build(BuildContext context) {
    final primaryLabel = _busy
        ? 'Open booking'
        : canManage
        ? 'Block dates'
        : 'View unit';
    final primaryIcon = _busy
        ? Icons.receipt_long_outlined
        : canManage
        ? Icons.event_busy_outlined
        : Icons.tune_rounded;

    VoidCallback primaryAction = _busy
        ? () => onOpenBooking(booking!)
        : canManage
        ? onBlock
        : onOpenFleet;

    return CarHireSurface(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onOpenUnit,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 76, height: 60, child: _thumbnail()),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                              style: CarHireType.title.copyWith(fontSize: 13.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: CarHirePalette.surfaceContainer,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              _plate,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: CarHirePalette.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CarHireType.bodySmall.copyWith(fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _toneSoft,
                          borderRadius: BorderRadius.circular(
                            CarHireShape.pillRadius,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _tone,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _tone,
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
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 8),
            _RenterStrip(booking: booking!),
          ],
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _Capsule(
                  label: primaryLabel,
                  icon: primaryIcon,
                  primary: true,
                  onTap: primaryAction,
                ),
              ),
              if (_busy || (canManage && !_inPrep)) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _Capsule(
                    label: _busy ? 'Fleet' : 'Manage',
                    icon: Icons.tune_rounded,
                    onTap: onOpenFleet,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbnail() {
    final url = unit.car.primaryImage;
    if (url == null || url.isEmpty) {
      return Container(
        color: CarHirePalette.surfaceLow,
        alignment: Alignment.center,
        child: const Icon(
          Icons.directions_car_filled_rounded,
          size: 26,
          color: CarHirePalette.outlineVariant,
        ),
      );
    }
    return ResilientCachedNetworkImage(
      url: url,
      fit: BoxFit.cover,
      height: 60,
      memCacheWidth: 300,
    );
  }

  static String _returnsLabel(DateTime? end) {
    if (end == null) return 'soon';
    final now = DateTime.now();
    final local = end.toLocal();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time = CarHireFormatters.formatTime(local);
    if (sameDay) return time;
    final tomorrow = now.add(const Duration(days: 1));
    if (local.year == tomorrow.year &&
        local.month == tomorrow.month &&
        local.day == tomorrow.day) {
      return 'tomorrow $time';
    }
    return CarHireFormatters.formatDate(local);
  }
}

class _RenterStrip extends StatelessWidget {
  const _RenterStrip({required this.booking});

  final CarHireBooking booking;

  String get _initials {
    final name = (booking.renterName ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final name = booking.renterName?.trim();
    final ends = booking.endAt == null
        ? 'Active'
        : 'Ends ${CarHireFormatters.formatDate(booking.endAt!)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: CarHirePalette.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: CarHirePalette.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name == null || name.isEmpty ? 'Renter' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CarHireType.title.copyWith(fontSize: 11.5),
            ),
          ),
          Text(
            ends,
            style: CarHireType.labelSmall.copyWith(
              fontSize: 10,
              color: CarHirePalette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? CarHirePalette.accent : CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CarHireShape.pillRadius),
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: primary ? Colors.white : CarHirePalette.onSurface,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primary ? Colors.white : CarHirePalette.onSurface,
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
