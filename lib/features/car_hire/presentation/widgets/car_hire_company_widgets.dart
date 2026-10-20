import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';

void showCompanySnack(BuildContext context, String message, {bool error = false}) {
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
                Text(
                  booking.bookingNumberLabel,
                  style: CarHireType.labelSmall,
                ),
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
              Text(
                title,
                style: CarHireType.title.copyWith(color: tone),
              ),
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
