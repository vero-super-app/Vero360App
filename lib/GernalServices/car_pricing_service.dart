import 'package:vero360_app/GeneralModels/rental_cost_model.dart';

class CarPricingService {
  /// Calculate rental cost upfront (when booking is created)
  RentalCostModel calculateRentalCost({
    required double dailyRate,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final diff = endDate.difference(startDate);
    final days = (diff.inHours / 24).ceil();
    final baseCost = dailyRate * (days > 0 ? days : 1);

    return RentalCostModel(
      baseCost: baseCost,
      dailyRate: dailyRate,
      days: days > 0 ? days : 1,
      lateFee: 0,
      otherCharges: 0,
      totalCost: baseCost,
      breakdown: 'Base: MWK${dailyRate.toStringAsFixed(0)} × ${days > 0 ? days : 1} days',
    );
  }

  /// Calculate late fee when car is returned after scheduled date
  double calculateLateFee({
    required DateTime actualReturn,
    required DateTime scheduledReturn,
    required double lateFeePerDay,
  }) {
    if (actualReturn.isBefore(scheduledReturn) ||
        actualReturn.isAtSameMomentAs(scheduledReturn)) {
      return 0; // On time
    }

    final diff = actualReturn.difference(scheduledReturn);
    final daysLate = (diff.inHours / 24).ceil();

    return lateFeePerDay * daysLate;
  }

  /// Final bill with all charges
  RentalCostModel calculateFinalBill({
    required double baseCost,
    required double dailyRate,
    required int days,
    required DateTime actualReturn,
    required DateTime scheduledReturn,
    required double lateFeePerDay,
    double otherCharges = 0,
  }) {
    final lateFee = calculateLateFee(
      actualReturn: actualReturn,
      scheduledReturn: scheduledReturn,
      lateFeePerDay: lateFeePerDay,
    );

    final total = baseCost + lateFee + otherCharges;

    return RentalCostModel(
      baseCost: baseCost,
      dailyRate: dailyRate,
      days: days,
      lateFee: lateFee,
      otherCharges: otherCharges,
      totalCost: total,
      breakdown:
          'Base: MWK${baseCost.toStringAsFixed(2)} + Late: MWK${lateFee.toStringAsFixed(2)} + Other: MWK${otherCharges.toStringAsFixed(2)}',
    );
  }
}
