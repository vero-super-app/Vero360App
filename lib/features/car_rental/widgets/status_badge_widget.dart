import 'package:flutter/material.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_design_system.dart';

/// Status badge widget - displays status with consistent styling
class StatusBadgeWidget extends StatelessWidget {
  final String status;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;
  final bool showLabel;

  const StatusBadgeWidget({
    Key? key,
    required this.status,
    this.fontSize,
    this.padding,
    this.showLabel = true,
  }) : super(key: key);

  Color _getStatusColor() {
    return CarRentalDesignSystem.getStatusColor(status);
  }

  String _getStatusLabel() {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Awaiting Confirmation';
      case 'CONFIRMED':
        return 'Confirmed';
      case 'ACTIVE':
      case 'IN PROGRESS':
        return 'In Progress';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      case 'REJECTED':
        return 'Rejected';
      case 'AVAILABLE':
        return 'Available';
      case 'UNAVAILABLE':
      case 'BOOKED':
        return 'Booked';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: CarRentalSpacing.md,
            vertical: CarRentalSpacing.xs,
          ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CarRentalBorderRadius.full),
        border: Border.all(
          color: statusColor,
          width: 1.5,
        ),
      ),
      child: Text(
        showLabel ? _getStatusLabel() : status,
        style: TextStyle(
          color: statusColor,
          fontSize: fontSize ?? CarRentalSizes.iconSm / 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
