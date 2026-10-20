import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/formatters.dart';

/// Day-to-day operations for car hire company staff. Fleet setup, pricing and
/// branches stay on the web workspace.
class CarHireCompanyPage extends ConsumerWidget {
  const CarHireCompanyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(companyAccessProvider);

    return access.when(
      loading: () => Scaffold(
        backgroundColor: CarHirePalette.background,
        appBar: carHireAppBar(title: 'Company'),
        body: const CarHireLoadingState(message: 'Loading your company…'),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: CarHirePalette.background,
        appBar: carHireAppBar(title: 'Company'),
        body: CarHireErrorState(
          error: error,
          onRetry: () => ref.invalidate(companyAccessProvider),
        ),
      ),
      data: (access) {
        if (!access.hasCompany) {
          return Scaffold(
            backgroundColor: CarHirePalette.background,
            appBar: carHireAppBar(title: 'Company'),
            body: const CarHireEmptyState(
              icon: Icons.business_outlined,
              title: 'No active company',
              message: 'Company mode is for staff of an approved car hire '
                  'company. Ask the company owner to invite your Vero360 email.',
            ),
          );
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: CarHirePalette.background,
            appBar: carHireAppBar(
              title: access.title,
              bottom: const TabBar(
                labelColor: CarHirePalette.onSurface,
                unselectedLabelColor: CarHirePalette.muted,
                indicatorColor: CarHirePalette.accent,
                labelStyle: TextStyle(fontWeight: FontWeight.w800),
                tabs: [
                  Tab(text: 'Today'),
                  Tab(text: 'Bookings'),
                  Tab(text: 'Fleet'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _TodayTab(access: access),
                _BookingsTab(access: access),
                _FleetTab(access: access),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _noBookingAccess = CarHireEmptyState(
  icon: Icons.lock_outline_rounded,
  title: 'No booking access',
  message: 'Your membership does not include bookings. '
      'Ask the company owner for the bookings permission.',
);

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

class _TodayTab extends ConsumerStatefulWidget {
  const _TodayTab({required this.access});

  final CompanyAccess access;

  @override
  ConsumerState<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends ConsumerState<_TodayTab> {
  DateTime _day = DateTime.now();

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.access.canViewBookings) return _noBookingAccess;
    final key = companyDateKey(_day);
    final board = ref.watch(companyDispatchProvider(key));

    return RefreshIndicator(
      color: CarHirePalette.accent,
      onRefresh: () => ref.refresh(companyDispatchProvider(key).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  _isToday
                      ? 'Today · ${CarHireFormatters.formatDate(_day)}'
                      : CarHireFormatters.formatDate(_day),
                  textAlign: TextAlign.center,
                  style: CarHireType.subtitle,
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          ...board.when(
            loading: () => const [
              CarHireLoadingState(message: 'Loading the day…'),
            ],
            error: (error, _) => [
              CarHireErrorState(
                error: error,
                onRetry: () => ref.invalidate(companyDispatchProvider(key)),
              ),
            ],
            data: _boardChildren,
          ),
        ],
      ),
    );
  }

  List<Widget> _boardChildren(DispatchBoard board) {
    if (board.isEmpty) {
      return const [
        CarHireEmptyState(
          icon: Icons.event_available_outlined,
          title: 'Nothing scheduled',
          message: 'No pickups, returns or open requests on this day.',
        ),
      ];
    }

    void open(CarHireBooking booking) =>
        CarHireRoutes.openCompanyBooking(context, bookingId: booking.id);

    List<Widget> group(
      String title,
      List<CarHireBooking> rows,
      String Function(CarHireBooking) time, {
      String? hint,
      Color? tone,
      bool hideEmpty = false,
    }) {
      if (hideEmpty && rows.isEmpty) return const [];
      return [
        CompanyGroupHeader(
          title: title,
          count: rows.length,
          hint: hint,
          tone: tone,
        ),
        if (rows.isEmpty)
          const Text('None', style: CarHireType.bodySmall)
        else
          for (final booking in rows)
            CompanyBookingTile(
              booking: booking,
              timeLabel: time(booking),
              onTap: () => open(booking),
            ),
      ];
    }

    String at(DateTime? value) =>
        value == null ? '—' : CarHireFormatters.formatDateTime(value);

    return [
      ...group(
        'Awaiting your response',
        board.awaitingResponse,
        (b) => 'Respond by ${at(b.holdExpiresAt)}',
        hint: 'Request-to-book. Accept or decline before it expires.',
        tone: CarHirePalette.warning,
        hideEmpty: true,
      ),
      ...group(
        'Late pickups',
        board.latePickups,
        (b) => 'Pickup was ${at(b.startAt)}',
        tone: CarHirePalette.error,
        hideEmpty: true,
      ),
      ...group(
        'Overdue returns',
        board.overdueReturns,
        (b) => 'Return was ${at(b.endAt)}',
        tone: CarHirePalette.error,
        hideEmpty: true,
      ),
      ...group('Pickups', board.pickups, (b) => 'Pickup ${at(b.startAt)}'),
      ...group('Returns', board.returns, (b) => 'Return ${at(b.endAt)}'),
      if (board.serviceDue.isNotEmpty) ...[
        CompanyGroupHeader(
          title: 'Service due',
          count: board.serviceDue.length,
        ),
        for (final item in board.serviceDue)
          CarHireSurface(
            margin: const EdgeInsets.only(bottom: 8),
            radius: CarHireShape.tileRadius,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [item.title, if (item.licensePlate != null) item.licensePlate!]
                        .join(' · '),
                    style: CarHireType.subtitle,
                  ),
                ),
                CarHirePill(
                  label: item.overdue ? 'Overdue ${item.dueDate}' : 'Due ${item.dueDate}',
                  background: item.overdue
                      ? CarHirePalette.errorSoft
                      : CarHirePalette.warningSoft,
                  foreground: item.overdue
                      ? CarHirePalette.error
                      : CarHirePalette.warning,
                ),
              ],
            ),
          ),
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Bookings inbox
// ---------------------------------------------------------------------------

class _BookingsTab extends ConsumerStatefulWidget {
  const _BookingsTab({required this.access});

  final CompanyAccess access;

  @override
  ConsumerState<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<_BookingsTab> {
  static const _filters = <(String, String)>[
    ('PENDING', 'Needs action'),
    ('CONFIRMED', 'Upcoming'),
    ('ACTIVE', 'On rent'),
    ('', 'All'),
  ];

  String _status = 'PENDING';

  @override
  Widget build(BuildContext context) {
    if (!widget.access.canViewBookings) return _noBookingAccess;
    final bookings = ref.watch(companyBookingsProvider(_status));

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            children: [
              for (final (status, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                    selectedColor: CarHirePalette.accentSoft,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: CarHirePalette.accent,
            onRefresh: () =>
                ref.refresh(companyBookingsProvider(_status).future),
            child: bookings.when(
              loading: () => const CarHireLoadingState(
                message: 'Loading bookings…',
              ),
              error: (error, _) => ListView(
                children: [
                  CarHireErrorState(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(companyBookingsProvider(_status)),
                  ),
                ],
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return ListView(
                    children: const [
                      CarHireEmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'Nothing here',
                        message: 'No bookings match this filter.',
                      ),
                    ],
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final booking in rows)
                      CompanyBookingTile(
                        booking: booking,
                        onTap: () => CarHireRoutes.openCompanyBooking(
                          context,
                          bookingId: booking.id,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fleet
// ---------------------------------------------------------------------------

class _FleetTab extends ConsumerWidget {
  const _FleetTab({required this.access});

  final CompanyAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(companyFleetProvider);
    final busy = ref.watch(companyActionProvider).submitting;

    Future<void> toggle(FleetUnit unit, bool inService) async {
      final ok = await ref.read(companyActionProvider.notifier).run(
            (api) => api.setUnitInService(unit.id, inService),
          );
      if (!context.mounted) return;
      if (ok) {
        showCompanySnack(
          context,
          inService
              ? '${unit.plateLabel} is back in service.'
              : '${unit.plateLabel} is out of service.',
        );
      } else {
        showCompanySnack(
          context,
          ref.read(companyActionProvider).error?.message ??
              'Could not update the car.',
          error: true,
        );
      }
    }

    return RefreshIndicator(
      color: CarHirePalette.accent,
      onRefresh: () => ref.refresh(companyFleetProvider.future),
      child: fleet.when(
        loading: () => const CarHireLoadingState(message: 'Loading fleet…'),
        error: (error, _) => ListView(
          children: [
            CarHireErrorState(
              error: error,
              onRetry: () => ref.invalidate(companyFleetProvider),
            ),
          ],
        ),
        data: (units) {
          if (units.isEmpty) {
            return ListView(
              children: const [
                CarHireEmptyState(
                  title: 'No cars yet',
                  message: 'Add cars and plates from the web workspace.',
                ),
              ],
            );
          }
          final listings = <String, List<FleetUnit>>{};
          for (final unit in units) {
            listings.putIfAbsent(unit.listingKey, () => <FleetUnit>[]).add(unit);
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (!access.canManageFleet)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: CarHireInfoBanner(
                    icon: Icons.visibility_outlined,
                    title: 'View only',
                    message: 'Ask the company owner for the fleet permission '
                        'to take cars out of service or block dates.',
                  ),
                ),
              for (final group in listings.values)
                CarHireSurface(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.first.car.title, style: CarHireType.subtitle),
                      Text(
                        group.length == 1 ? '1 unit' : '${group.length} units',
                        style: CarHireType.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      for (final unit in group)
                        _FleetUnitRow(
                          unit: unit,
                          canManage: access.canManageFleet,
                          busy: busy,
                          onToggle: (value) => toggle(unit, value),
                          onBlock: () => _openBlockSheet(context, unit),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openBlockSheet(BuildContext context, FleetUnit unit) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CarHirePalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MaintenanceSheet(unit: unit),
    );
  }
}

class _FleetUnitRow extends StatelessWidget {
  const _FleetUnitRow({
    required this.unit,
    required this.canManage,
    required this.busy,
    required this.onToggle,
    required this.onBlock,
  });

  final FleetUnit unit;
  final bool canManage;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final inService = unit.car.isAvailable;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.plateLabel,
                  style: CarHireType.label.copyWith(
                    color: CarHirePalette.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  children: [
                    Text(
                      inService ? 'In service' : 'Out of service',
                      style: CarHireType.labelSmall.copyWith(
                        color: inService
                            ? CarHirePalette.success
                            : CarHirePalette.error,
                      ),
                    ),
                    if (unit.serviceDueSoon)
                      Text(
                        'Service due '
                        '${CarHireFormatters.formatDate(unit.nextServiceDueAt!)}',
                        style: CarHireType.labelSmall.copyWith(
                          color: CarHirePalette.warning,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (canManage) ...[
            IconButton(
              tooltip: 'Block dates',
              onPressed: busy ? null : onBlock,
              icon: const Icon(Icons.event_busy_outlined, size: 20),
            ),
            Switch(
              value: inService,
              activeThumbColor: CarHirePalette.accent,
              onChanged: busy ? null : onToggle,
            ),
          ],
        ],
      ),
    );
  }
}

class _MaintenanceSheet extends ConsumerStatefulWidget {
  const _MaintenanceSheet({required this.unit});

  final FleetUnit unit;

  @override
  ConsumerState<_MaintenanceSheet> createState() => _MaintenanceSheetState();
}

class _MaintenanceSheetState extends ConsumerState<_MaintenanceSheet> {
  static const _categories = <(String, String)>[
    ('MAINTENANCE', 'Maintenance'),
    ('CLEANING', 'Cleaning'),
    ('SAFETY', 'Safety'),
  ];

  final _reason = TextEditingController();
  late DateTimeRange _range;
  String _category = 'MAINTENANCE';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    _range = DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _save() async {
    final endExclusive = _range.end.add(const Duration(days: 1));
    final ok = await ref.read(companyActionProvider.notifier).run(
          (api) => api.addMaintenanceBlock(
            widget.unit.id,
            startAt: _range.start,
            endAt: endExclusive,
            category: _category,
            reason: _reason.text,
          ),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showCompanySnack(context, '${widget.unit.plateLabel} is blocked.');
    } else {
      showCompanySnack(
        context,
        ref.read(companyActionProvider).error?.message ??
            'Could not block these dates.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(companyActionProvider).submitting;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Block ${widget.unit.plateLabel}', style: CarHireType.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'The car cannot be booked on these days.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy ? null : _pickRange,
            style: carHireGhostButton(),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              '${CarHireFormatters.formatDate(_range.start)} – '
              '${CarHireFormatters.formatDate(_range.end)}',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in _categories)
                ChoiceChip(
                  label: Text(label),
                  selected: _category == value,
                  onSelected: busy ? null : (_) => setState(() => _category = value),
                  selectedColor: CarHirePalette.accentSoft,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 500,
            decoration: carHireInputDecoration(label: 'Reason (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : _save,
            style: carHirePrimaryButton(),
            child: Text(busy ? 'Saving…' : 'Block dates'),
          ),
        ],
      ),
    );
  }
}
