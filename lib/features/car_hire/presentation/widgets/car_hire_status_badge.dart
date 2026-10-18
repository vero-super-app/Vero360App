import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';

/// A status pill that always pairs colour with text and an icon, so status is
/// never communicated by colour alone.
class CarHireStatusBadge extends StatelessWidget {
  const CarHireStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  factory CarHireStatusBadge.booking(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.warning,
          icon: Icons.schedule_rounded,
        );
      case BookingStatus.confirmed:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      case BookingStatus.active:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.brandOrange,
          icon: Icons.directions_car_filled_rounded,
        );
      case BookingStatus.completed:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.greyDark,
          icon: Icons.task_alt_rounded,
        );
      case BookingStatus.cancelled:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.cancel_outlined,
        );
      case BookingStatus.expired:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.timer_off_outlined,
        );
      case BookingStatus.rejected:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.block_rounded,
        );
      case BookingStatus.incidentReported:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.report_problem_outlined,
        );
      case BookingStatus.unknown:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  factory CarHireStatusBadge.payment(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.notRequired:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.remove_circle_outline_rounded,
        );
      case PaymentStatus.notStarted:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.warning,
          icon: Icons.payments_outlined,
        );
      case PaymentStatus.pending:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.brandOrange,
          icon: Icons.hourglass_top_rounded,
        );
      case PaymentStatus.succeeded:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.success,
          icon: Icons.verified_rounded,
        );
      case PaymentStatus.failed:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.error_outline_rounded,
        );
      case PaymentStatus.refunded:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.greyDark,
          icon: Icons.replay_rounded,
        );
      case PaymentStatus.unknown:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  factory CarHireStatusBadge.listing(ListingStatus status) {
    switch (status) {
      case ListingStatus.published:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.success,
          icon: Icons.public_rounded,
        );
      case ListingStatus.draft:
      case ListingStatus.pendingReview:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.warning,
          icon: Icons.edit_note_rounded,
        );
      case ListingStatus.suspended:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.pause_circle_outline_rounded,
        );
      case ListingStatus.retired:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.archive_outlined,
        );
      case ListingStatus.unknown:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  factory CarHireStatusBadge.verification(VerificationState status) {
    switch (status) {
      case VerificationState.notStarted:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.warning,
          icon: Icons.badge_outlined,
        );
      case VerificationState.submitted:
      case VerificationState.underReview:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.brandOrange,
          icon: Icons.hourglass_top_rounded,
        );
      case VerificationState.verified:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.success,
          icon: Icons.verified_user_rounded,
        );
      case VerificationState.rejected:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.error_outline_rounded,
        );
      case VerificationState.expired:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.timer_off_outlined,
        );
      case VerificationState.suspended:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.pause_circle_outline_rounded,
        );
      case VerificationState.unknown:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  factory CarHireStatusBadge.extension(ExtensionStatus status) {
    switch (status) {
      case ExtensionStatus.requested:
      case ExtensionStatus.pending:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.warning,
          icon: Icons.more_time_rounded,
        );
      case ExtensionStatus.approved:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      case ExtensionStatus.declined:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.block_rounded,
        );
      case ExtensionStatus.cancelled:
      case ExtensionStatus.expired:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.timer_off_outlined,
        );
      case ExtensionStatus.unknown:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  factory CarHireStatusBadge.inspection(InspectionStatus status) {
    switch (status) {
      case InspectionStatus.pending:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.warning,
          icon: Icons.schedule_rounded,
        );
      case InspectionStatus.submitted:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.brandOrange,
          icon: Icons.assignment_turned_in_outlined,
        );
      case InspectionStatus.acknowledged:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      case InspectionStatus.declined:
      case InspectionStatus.disputed:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.error,
          icon: Icons.report_problem_outlined,
        );
      case InspectionStatus.unknown:
        return CarHireStatusBadge(
          label: status.label,
          color: CarRentalColors.grey,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = Color.lerp(color, Colors.black, 0.32) ?? color;

    return Semantics(
      label: '$label status',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.34)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
