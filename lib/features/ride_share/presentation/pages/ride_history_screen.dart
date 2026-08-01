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

class RideHistoryScreen extends StatefulWidget {
  final RideHistoryMode mode;

  const RideHistoryScreen({
    super.key,
    this.mode = RideHistoryMode.passenger,
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

  void _openDetail(Ride ride) {
    Navigator.push(
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
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        if (_isDriver) ...[
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
                        ],
                        Row(
                          children: [
                            Text(
                              _isDriver ? 'Recent Activity' : 'Past Trips',
                              style: const TextStyle(
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
                          SingleChildScrollView(
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
                                        : status[0] +
                                            status.substring(1).toLowerCase(),
                                    selected: _statusFilter == status,
                                    onTap: () {
                                      setState(() => _statusFilter = status);
                                      _reload();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: RideShareColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            color: RideShareColors.titleText,
            style: IconButton.styleFrom(
              backgroundColor: RideShareColors.surfaceContainerLow,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isDriver ? 'Earnings & History' : 'Activity',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: RideShareColors.titleText,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RideShareColors.primarySoft,
              border: Border.all(color: RideShareColors.outlineVariant),
            ),
            child: Icon(
              _isDriver ? Icons.local_taxi : Icons.person,
              color: RideShareColors.primary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniSummary(RideHistoryPage page, NumberFormat money) {
    final summary = page.summary;
    final primary = _isDriver
        ? summary.totalEarnings ?? 0
        : summary.totalSpent ?? 0;
    return Row(
      children: [
        Expanded(
          child: _statTile(
            _isDriver ? 'Total earned' : 'Total spent',
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

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: RideShareColors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.history,
              color: RideShareColors.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No trips yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: RideShareColors.titleText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isDriver
                ? 'Completed trips and earnings will show up here.'
                : 'Your past Vero Rides will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: RideShareColors.onSurfaceVariant),
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
