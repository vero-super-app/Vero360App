import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_history_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_history_detail_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_history_ui.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_skeleton_loaders.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_ui_constants.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

enum RideHistoryMode { passenger, driver }

/// Driver shortcuts open different surfaces so Earnings ≠ History.
enum RideHistoryFocus {
  /// Passenger default / legacy combined driver view.
  combined,
  /// Money-first: periods, totals, cash-out.
  earnings,
  /// Trips-first: searchable chronological history.
  history,
}

class RideHistoryScreen extends StatefulWidget {
  final RideHistoryMode mode;
  final RideHistoryFocus focus;

  const RideHistoryScreen({
    super.key,
    this.mode = RideHistoryMode.passenger,
    this.focus = RideHistoryFocus.combined,
  });

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final RideShareHttpService _http = RideShareHttpService();
  final TextEditingController _searchController = TextEditingController();

  Future<RideHistoryPage>? _historyFuture;
  Future<DriverEarningsSummary>? _earningsFuture;
  String _statusFilter = 'ALL';
  String _searchQuery = '';
  bool _showSearch = false;

  bool get _isDriver => widget.mode == RideHistoryMode.driver;
  bool get _earningsFocus =>
      _isDriver && widget.focus == RideHistoryFocus.earnings;
  bool get _historyFocus =>
      _isDriver && widget.focus == RideHistoryFocus.history;

  @override
  void initState() {
    super.initState();
    _reload();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _http.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _historyFuture = _loadHistory();
      if (_isDriver) {
        _earningsFuture = _http.getDriverEarningsSummary();
      }
    });
  }

  Future<RideHistoryPage> _loadHistory() {
    if (_isDriver) {
      return _http.getDriverRideHistory(status: _statusFilter);
    }
    return _http.getPassengerRideHistory(status: _statusFilter);
  }

  bool _matchesSearch(Ride ride) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery;
    final fields = <String>[
      '${ride.id}',
      ride.pickupAddress ?? '',
      ride.dropoffAddress ?? '',
      ride.routeLabel,
      ride.driver?.fullName ?? '',
      ride.passengerName ?? '',
      ride.tripSummary?.counterpartyName ?? '',
      ride.status,
    ];
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  Future<void> _openDetail(Ride ride) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideHistoryDetailScreen(
          ride: ride,
          perspective: _isDriver
              ? RideHistoryPerspective.driver
              : RideHistoryPerspective.passenger,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'en');

    return Scaffold(
      backgroundColor: RideShareColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: FutureBuilder<RideHistoryPage>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return RideHistoryScreenSkeleton(
                      showDriverEarnings: _isDriver,
                    );
                  }

                  if (snapshot.hasError) {
                    final safe = UserFacingError.from(
                      snapshot.error,
                      fallback: 'Could not load trip history',
                    );
                    final needAuth = safe == UserFacingError.unauthorized;
                    return _errorState(
                      needAuth
                          ? 'Sign in to see your trip history'
                          : 'Could not load trip history',
                      needAuth
                          ? 'Your completed rides appear here after each trip.'
                          : safe,
                      showSignIn: needAuth,
                    );
                  }

                  final page = snapshot.data!;
                  final filtered =
                      page.rides.where(_matchesSearch).toList();
                  final completedTrips = filtered
                      .where((r) =>
                          r.status.toUpperCase().contains('COMPLETE'))
                      .toList();

                  // Unpaid completed first for passengers
                  if (!_isDriver) {
                    filtered.sort((a, b) {
                      final ap = ridePaymentPending(a) ? 0 : 1;
                      final bp = ridePaymentPending(b) ? 0 : 1;
                      if (ap != bp) return ap.compareTo(bp);
                      final at = a.endTime ?? a.createdAt;
                      final bt = b.endTime ?? b.createdAt;
                      return bt.compareTo(at);
                    });
                  }

                  return RefreshIndicator(
                    color: RideShareColors.primary,
                    onRefresh: () async {
                      _reload();
                      await _historyFuture;
                      if (_isDriver) await _earningsFuture;
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        if (_earningsFocus) ...[
                          _buildDriverEarningsFocus(money),
                          const SizedBox(height: 22),
                          _sectionHeader(
                            title: 'Recent paid trips',
                            subtitle:
                                'Money earned from your latest completed rides',
                            trailing: completedTrips.isEmpty
                                ? null
                                : '${completedTrips.length > 8 ? 8 : completedTrips.length}',
                          ),
                          const SizedBox(height: 12),
                          if (page.rides.isEmpty)
                            _emptyState(
                              title: 'No earnings yet',
                              body:
                                  'Complete a trip while online and your payouts will land here.',
                              icon: Icons.payments_outlined,
                            )
                          else if (completedTrips.isEmpty)
                            _emptyState(
                              title: 'Waiting on first payout',
                              body:
                                  'Finished rides show up here once they are marked completed.',
                              icon: Icons.hourglass_empty_rounded,
                              compact: true,
                            )
                          else
                            ...completedTrips.take(8).map(
                                  (ride) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: RideHistoryTripCard(
                                      ride: ride,
                                      isDriver: true,
                                      money: money,
                                      onTap: () => _openDetail(ride),
                                      onPrimaryAction: () =>
                                          _openDetail(ride),
                                    ),
                                  ),
                                ),
                        ] else if (_historyFocus) ...[
                          _historyIntroCard(page),
                          const SizedBox(height: 14),
                          _modernSearchField(),
                          const SizedBox(height: 12),
                          _statusFilters(),
                          const SizedBox(height: 14),
                          _historyMiniSummary(page),
                          const SizedBox(height: 16),
                          _sectionHeader(
                            title: 'Your trips',
                            subtitle: filtered.isEmpty
                                ? 'Nothing matches these filters'
                                : 'Newest first · tap a trip for details',
                          ),
                          const SizedBox(height: 12),
                          if (page.rides.isEmpty)
                            _emptyState(
                              title: 'No trip history',
                              body:
                                  'When you finish rides, they appear here with route, time, and status.',
                              icon: Icons.route_outlined,
                            )
                          else if (filtered.isEmpty)
                            _emptyState(
                              title: 'No matches',
                              body: 'Try another search or clear the filters.',
                              icon: Icons.search_off_rounded,
                              compact: true,
                            )
                          else
                            ...filtered.map(
                              (ride) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: RideHistoryTripCard(
                                  ride: ride,
                                  isDriver: true,
                                  money: money,
                                  onTap: () => _openDetail(ride),
                                  onPrimaryAction: () => _openDetail(ride),
                                ),
                              ),
                            ),
                        ] else if (_isDriver) ...[
                          FutureBuilder<DriverEarningsSummary>(
                            future: _earningsFuture,
                            builder: (context, earningsSnap) {
                              if (earningsSnap.connectionState ==
                                  ConnectionState.waiting) {
                                return const DriverEarningsCardSkeleton();
                              }
                              final earnings = earningsSnap.data;
                              if (earnings == null) {
                                return const SizedBox.shrink();
                              }
                              final today = earnings.today;
                              final yesterdayHint = earnings.thisWeek.trips > 0
                                  ? '${earnings.thisWeek.trips} trips this week'
                                  : 'Keep driving to grow earnings';
                              return RideHistoryEarningsHero(
                                title: 'Performance Insight',
                                amountLabel: formatRideMoney(
                                  today.earnings,
                                  money,
                                ),
                                tripsLabel: '${today.trips}',
                                trendLabel: yesterdayHint,
                                onCashOut: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Cash out will be available soon.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Text(
                                'Recent Activity',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: RideShareColors.titleText,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _showSearch = !_showSearch),
                                icon: Icon(
                                  _showSearch
                                      ? Icons.close
                                      : Icons.filter_list,
                                  size: 18,
                                  color: RideShareColors.primary,
                                ),
                                label: Text(
                                  _showSearch ? 'Close' : 'Filter',
                                  style: const TextStyle(
                                    color: RideShareColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_showSearch) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search trips, places, people…',
                                filled: true,
                                fillColor: Colors.white,
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: RideShareColors.outlineVariant,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: RideShareColors.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _statusFilters(),
                          ],
                          const SizedBox(height: 12),
                          _miniSummary(page, money),
                          const SizedBox(height: 14),
                          if (page.rides.isEmpty)
                            _emptyState()
                          else if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'No trips match this search.',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...filtered.map(
                              (ride) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: RideHistoryTripCard(
                                  ride: ride,
                                  isDriver: _isDriver,
                                  money: money,
                                  onTap: () => _openDetail(ride),
                                  onPrimaryAction: () => _openDetail(ride),
                                ),
                              ),
                            ),
                        ] else ...[
                          const Text(
                            'Your trips',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: RideShareColors.titleText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap a trip to see the full receipt.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by place or driver…',
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.search),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: RideShareColors.outlineVariant,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: RideShareColors.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _statusFilters(),
                          const SizedBox(height: 12),
                          _miniSummary(page, money),
                          const SizedBox(height: 14),
                          if (page.rides.isEmpty)
                            _emptyState()
                          else if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'No trips match this search.',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...filtered.map(
                              (ride) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: RideHistoryTripCard(
                                  ride: ride,
                                  isDriver: _isDriver,
                                  money: money,
                                  onTap: () => _openDetail(ride),
                                  onPrimaryAction: () => _openDetail(ride),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = _earningsFocus
        ? 'Trip Earnings'
        : _historyFocus
            ? 'Trip History'
            : _isDriver
                ? 'Earnings & History'
                : 'My rides';
    final subtitle = _earningsFocus
        ? 'See what you made today, this week, and all time'
        : _historyFocus
            ? 'Browse every trip — search, filter, open details'
            : !_isDriver
                ? 'From → To · when · price · status'
                : 'Money and trips in one place';

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: RideShareColors.titleText,
            style: IconButton.styleFrom(
              backgroundColor: RideShareColors.surfaceContainerLow,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: RideShareColors.titleText,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: RideShareColors.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  RideShareColors.primary.withValues(alpha: 0.18),
                  RideShareColors.primarySoft,
                ],
              ),
            ),
            child: Icon(
              _earningsFocus
                  ? Icons.account_balance_wallet_rounded
                  : _historyFocus
                      ? Icons.map_rounded
                      : _isDriver
                          ? Icons.local_taxi
                          : Icons.directions_car_filled_rounded,
              color: RideShareColors.primaryDeep,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    String? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: RideShareColors.titleText,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trailing,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: RideShareColors.primaryDeep,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _historyIntroCard(RideHistoryPage page) {
    final total =
        page.summary.completedCount + page.summary.cancelledCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            RideShareColors.primarySoft.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: RideShareColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: RideShareColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: RideShareColors.primaryDeep,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0 ? 'Your trip log' : '$total trips on record',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: RideShareColors.titleText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Routes, times, and status — not a payout screen.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernSearchField() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: RideShareColors.titleText,
      ),
      decoration: InputDecoration(
        hintText: 'Search place, passenger, trip…',
        hintStyle: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: RideShareColors.onSurfaceVariant,
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RideShareColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RideShareColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: RideShareColors.primary,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildDriverEarningsFocus(NumberFormat money) {
    return FutureBuilder<DriverEarningsSummary>(
      future: _earningsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const DriverEarningsCardSkeleton();
        }
        final earnings = snap.data;
        if (earnings == null) {
          return _emptyState(
            title: 'Earnings start here',
            body:
                'After your first completed trip, daily and weekly totals appear in this view.',
            icon: Icons.savings_outlined,
            compact: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RideHistoryEarningsHero(
              title: 'Today’s earnings',
              amountLabel: formatRideMoney(earnings.today.earnings, money),
              tripsLabel: '${earnings.today.trips}',
              trendLabel: earnings.today.trips == 0
                  ? 'Go online to start earning'
                  : '${earnings.today.trips} trip${earnings.today.trips == 1 ? '' : 's'} today',
              onCashOut: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cash out will be available soon.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const Text(
              'Breakdown',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: RideShareColors.titleText,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _periodCard(
                    icon: Icons.date_range_rounded,
                    label: 'This week',
                    amount: formatRideMoney(earnings.thisWeek.earnings, money),
                    meta: '${earnings.thisWeek.trips} trips',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _periodCard(
                    icon: Icons.calendar_month_rounded,
                    label: 'This month',
                    amount:
                        formatRideMoney(earnings.thisMonth.earnings, money),
                    meta: '${earnings.thisMonth.trips} trips',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _periodCard(
              icon: Icons.insights_rounded,
              label: 'All time',
              amount: formatRideMoney(earnings.allTime.earnings, money),
              meta: '${earnings.allTime.trips} trips completed',
              wide: true,
            ),
          ],
        );
      },
    );
  }

  Widget _periodCard({
    required IconData icon,
    required String label,
    required String amount,
    required String meta,
    bool wide = false,
  }) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RideShareColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: RideShareColors.primaryDeep),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: RideShareColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: RideShareColors.titleText,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meta,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: RideShareColors.primaryDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyMiniSummary(RideHistoryPage page) {
    final summary = page.summary;
    return Row(
      children: [
        Expanded(
          child: _statTile('Completed', '${summary.completedCount}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile('Cancelled', '${summary.cancelledCount}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            'Total trips',
            '${summary.completedCount + summary.cancelledCount}',
          ),
        ),
      ],
    );
  }

  Widget _miniSummary(RideHistoryPage page, NumberFormat money) {
    final summary = page.summary;
    if (!_isDriver) {
      final spent = summary.totalSpent ?? 0;
      final trips = summary.completedCount + summary.cancelledCount;
      final label = trips == 0
          ? 'No trips yet'
          : '${summary.completedCount} completed'
              '${summary.cancelledCount > 0 ? ' · ${summary.cancelledCount} cancelled' : ''}'
              '${spent > 0 ? ' · ${formatRideMoney(spent, money)} spent' : ''}';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: RideShareColors.primarySoft.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: RideShareColors.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: RideShareColors.titleText,
          ),
        ),
      );
    }

    final primary = summary.totalEarnings ?? 0;
    return Row(
      children: [
        Expanded(
          child: _statTile(
            'Total earned',
            formatRideMoney(primary, money),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile('Completed', '${summary.completedCount}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile('Cancelled', '${summary.cancelledCount}'),
        ),
      ],
    );
  }

  Widget _statusFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final status in const [
            'ALL',
            'COMPLETED',
            'CANCELLED',
          ])
            RideHistoryFilterChip(
              label: status == 'ALL'
                  ? 'All'
                  : status == 'COMPLETED'
                      ? 'Completed'
                      : 'Cancelled',
              selected: _statusFilter == status,
              onTap: () {
                setState(() => _statusFilter = status);
                _reload();
              },
            ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RideShareColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: RideShareColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: RideShareColors.titleText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    String title = 'No rides yet',
    String? body,
    IconData icon = Icons.history,
    bool compact = false,
  }) {
    final message = body ??
        (_isDriver
            ? 'Completed trips and earnings will show up here.'
            : 'When you take a Vero Ride, it shows up here\nas From → To with the price and status.');

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 28 : 48),
      child: Column(
        children: [
          Container(
            width: compact ? 56 : 72,
            height: compact ? 56 : 72,
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: RideShareColors.primary,
              size: compact ? 28 : 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.w800,
              color: RideShareColors.titleText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: RideShareColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(
    String title,
    String subtitle, {
    bool showSignIn = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            if (showSignIn)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RideShareColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text('Sign in'),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RideShareColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _reload,
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
