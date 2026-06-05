import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GeneralModels/ride_history_model.dart';
import 'package:vero360_app/GeneralModels/ride_model.dart';
import 'package:vero360_app/GernalServices/ride_share_http_service.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_history_detail_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/widgets/ride_share_skeleton_loaders.dart';

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
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  final RideShareHttpService _http = RideShareHttpService();
  final TextEditingController _searchController = TextEditingController();

  Future<RideHistoryPage>? _historyFuture;
  Future<DriverEarningsSummary>? _earningsFuture;
  String _statusFilter = 'ALL';
  String _searchQuery = '';

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

  bool _matchesSearch(Ride ride, DateFormat dateFmt) {
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
      dateFmt.format(ride.endTime ?? ride.createdAt),
    ];
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'en');
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      appBar: AppBar(
        title: Text(_isDriver ? 'Trip History & Earnings' : 'My VeroRide Trips'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<RideHistoryPage>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return RideHistoryScreenSkeleton(showDriverEarnings: _isDriver);
          }

          if (snapshot.hasError) {
            final msg = snapshot.error.toString();
            final needAuth = msg.contains('401') ||
                msg.contains('Unauthorized') ||
                msg.contains('No auth');
            return _errorState(
              needAuth
                  ? 'Sign in to see your trip history'
                  : 'Could not load trip history',
              needAuth
                  ? 'Your completed rides appear here after each trip.'
                  : msg.replaceFirst('Exception: ', ''),
              showSignIn: needAuth,
            );
          }

          final page = snapshot.data!;
          final filtered =
              page.rides.where((r) => _matchesSearch(r, dateFmt)).toList();

          return RefreshIndicator(
            color: _brandOrange,
            onRefresh: () async {
              _reload();
              await _historyFuture;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: filtered.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isDriver)
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
                            return _earningsSummaryCard(earnings, money);
                          },
                        ),
                      if (_isDriver) const SizedBox(height: 12),
                      _summaryCard(page, money),
                      const SizedBox(height: 12),
                      _filterSection(dateFmt),
                      if (filtered.isEmpty && page.rides.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'No trips match this search.',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (page.rides.isEmpty)
                        _emptyInline(),
                    ],
                  );
                }

                final ride = filtered[index - 1];
                return _rideCard(ride, dateFmt, money);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _earningsSummaryCard(
    DriverEarningsSummary earnings,
    NumberFormat money,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _brandNavy,
            _brandNavy.withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Earnings',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MK ${money.format(earnings.thisMonth.earnings)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'This month',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _earningsChip(
                'Today',
                earnings.today,
                money,
              ),
              const SizedBox(width: 8),
              _earningsChip(
                'Week',
                earnings.thisWeek,
                money,
              ),
              const SizedBox(width: 8),
              _earningsChip(
                'All time',
                earnings.allTime,
                money,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _earningsChip(String label, EarningsPeriod period, NumberFormat money) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              'MK ${money.format(period.earnings)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            Text(
              '${period.trips} trips',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(RideHistoryPage page, NumberFormat money) {
    final summary = page.summary;
    final primaryValue = _isDriver
        ? summary.totalEarnings ?? 0
        : summary.totalSpent ?? 0;
    final primaryLabel =
        _isDriver ? 'Total earnings' : 'Total spent';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryStat(
              primaryLabel,
              'MK ${money.format(primaryValue)}',
              Icons.payments_outlined,
            ),
          ),
          Container(width: 1, height: 44, color: const Color(0xFFE2E6EF)),
          Expanded(
            child: _summaryStat(
              'Completed',
              '${summary.completedCount}',
              Icons.check_circle_outline,
            ),
          ),
          Container(width: 1, height: 44, color: const Color(0xFFE2E6EF)),
          Expanded(
            child: _summaryStat(
              'Cancelled',
              '${summary.cancelledCount}',
              Icons.cancel_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Icon(icon, size: 18, color: _brandOrange),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: _brandNavy,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _filterSection(DateFormat dateFmt) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search trips',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: _brandNavy,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Trip #, address, driver or passenger',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF7F8FB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _statusChipFilter('ALL', 'All'),
              _statusChipFilter('COMPLETED', 'Completed'),
              _statusChipFilter('CANCELLED', 'Cancelled'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChipFilter(String value, String label) {
    final selected = _statusFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _statusFilter = value;
          _reload();
        });
      },
      selectedColor: _brandOrange.withValues(alpha: 0.18),
      checkmarkColor: _brandOrange,
      labelStyle: TextStyle(
        color: selected ? _brandOrange : _brandNavy,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: selected ? _brandOrange : const Color(0xFFE2E6EF),
      ),
    );
  }

  Widget _rideCard(Ride ride, DateFormat dateFmt, NumberFormat money) {
    final summary = ride.tripSummary;
    final when = ride.endTime ?? ride.createdAt;
    final amount = _isDriver
        ? (summary?.driverEarnings ?? ride.driverEarnings ?? ride.resolvedFare)
        : (summary?.fare ?? ride.resolvedFare);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RideHistoryDetailScreen(
                ride: ride,
                perspective: _isDriver
                    ? RideHistoryPerspective.driver
                    : RideHistoryPerspective.passenger,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E6EF)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _brandOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_taxi_rounded,
                      color: _brandOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.routeLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _brandNavy,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFmt.format(when),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                        if ((summary?.counterpartyName ??
                                (_isDriver
                                    ? ride.passengerName
                                    : ride.driver?.fullName)) !=
                            null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _isDriver
                                  ? 'Passenger: ${summary?.counterpartyName ?? ride.passengerName}'
                                  : 'Driver: ${summary?.counterpartyName ?? ride.driver?.fullName}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'MK ${money.format(amount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _brandOrange,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _rideStatusBadge(ride.status),
                      if (ride.isCompleted) ...[
                        const SizedBox(height: 4),
                        _paymentStatusBadge(
                          summary?.paymentStatus ?? ride.paymentStatus,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.straighten, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${(summary?.distance ?? ride.resolvedDistance).toStringAsFixed(1)} km',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    (summary?.durationMinutes ?? 0) > 0
                        ? '${summary!.durationMinutes} mins'
                        : '—',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'View details',
                    style: TextStyle(
                      color: _brandOrange,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: _brandOrange,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentStatusBadge(String? status) {
    final normalized = (status ?? 'pending').toLowerCase();
    final isPaid = normalized == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPaid
            ? const Color(0xFFE3F2FD)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isPaid ? 'Paid' : 'Pending',
        style: TextStyle(
          color: isPaid ? const Color(0xFF1565C0) : const Color(0xFFF57F17),
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _rideStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case RideStatus.completed:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        label = 'Done';
        break;
      case RideStatus.cancelled:
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        label = 'Cancelled';
        break;
      default:
        bg = const Color(0xFFFFF3E0);
        fg = _brandOrange;
        label = status.replaceAll('_', ' ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _emptyInline() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.local_taxi_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No trips yet',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: _brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isDriver
                ? 'Completed trips and earnings will appear here.'
                : 'Your VeroRide trips will appear here after each ride.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String title, String body, {bool showSignIn = false}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey.shade500),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: _brandNavy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, height: 1.35),
        ),
        if (showSignIn) ...[
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const LoginScreen(),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Sign in'),
          ),
        ],
      ],
    );
  }
}
