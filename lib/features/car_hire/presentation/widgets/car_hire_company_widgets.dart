import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/utils/formatters.dart';

/// Compact money label for dense company cards: "MWK 85,000" not "MWK
/// 85,000.00". Currency comes from the listing so it stays truthful.
String companyMoney(double amount, {String currency = 'MWK'}) {
  final code = currency.trim().isEmpty ? 'MWK' : currency.trim().toUpperCase();
  return '$code ${NumberFormat.decimalPattern().format(amount)}';
}

void showCompanySnack(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CarHirePalette.error : CarHirePalette.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// One booking row in company mode: car, unit, renter and when.
class CompanyBookingTile extends StatelessWidget {
  const CompanyBookingTile({
    super.key,
    required this.booking,
    required this.onTap,
    this.timeLabel,
  });

  final CarHireBooking booking;
  final VoidCallback onTap;

  /// Overrides the date range, e.g. "Pickup 09:00" on the Today board.
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final car = booking.car;
    final title = [
      car?.title ?? 'Car #${booking.carId ?? '—'}',
      if (booking.assignedPlate != null) booking.assignedPlate!,
    ].join(' · ');
    final meta = [
      timeLabel ?? booking.dateRangeLabel,
      if (booking.renterName != null) booking.renterName!,
      if (booking.branchName != null) booking.branchName!,
    ].join(' · ');

    return CarHireSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      radius: CarHireShape.tileRadius,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.bookingNumberLabel, style: CarHireType.labelSmall),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.subtitle,
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CarHireType.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CarHireStatusBadge.booking(booking.bookingStatus),
              if (booking.isRequest &&
                  booking.bookingStatus == BookingStatus.pending) ...[
                const SizedBox(height: 5),
                const CarHirePill(
                  label: 'Request',
                  icon: Icons.schedule_rounded,
                  background: CarHirePalette.warningSoft,
                  foreground: CarHirePalette.warning,
                  fontSize: 10,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the "block these dates" sheet for one unit, from any company screen.
Future<void> showCompanyBlockSheet(
  BuildContext context, {
  required FleetUnit unit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: CarHirePalette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BlockDatesSheet(unit: unit),
  );
}

class _BlockDatesSheet extends ConsumerStatefulWidget {
  const _BlockDatesSheet({required this.unit});

  final FleetUnit unit;

  @override
  ConsumerState<_BlockDatesSheet> createState() => _BlockDatesSheetState();
}

class _BlockDatesSheetState extends ConsumerState<_BlockDatesSheet> {
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
    _range = DateTimeRange(
      start: start,
      end: start.add(const Duration(days: 1)),
    );
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
    final ok = await ref
        .read(companyActionProvider.notifier)
        .run(
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
          Text(
            'Block ${widget.unit.plateLabel}',
            style: CarHireType.titleLarge,
          ),
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
                  onSelected: busy
                      ? null
                      : (_) => setState(() => _category = value),
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

/// Small heading with a count above a group of rows.
class CompanyGroupHeader extends StatelessWidget {
  const CompanyGroupHeader({
    super.key,
    required this.title,
    required this.count,
    this.hint,
    this.tone,
  });

  final String title;
  final int count;
  final String? hint;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: CarHireType.title.copyWith(color: tone)),
              const SizedBox(width: 8),
              Text('$count', style: CarHireType.labelSmall),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: CarHireType.bodySmall),
          ],
        ],
      ),
    );
  }
}
