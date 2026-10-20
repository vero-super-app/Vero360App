import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';

/// Renders the server's quote / booking amounts. It never recalculates totals.
class CarHirePriceBreakdown extends StatelessWidget {
  const CarHirePriceBreakdown({
    super.key,
    required this.currency,
    this.lineItems = const <QuoteLineItem>[],
    this.subtotal = 0,
    this.surcharges = 0,
    this.discounts = 0,
    this.insurance = 0,
    this.deposit,
    this.totalDueNow = 0,
    this.totalDueLater = 0,
    this.total = 0,
    this.showSubtotal = true,
    this.showDueNow = true,
  });

  final String currency;
  final List<QuoteLineItem> lineItems;
  final double subtotal;
  final double surcharges;
  final double discounts;
  final double insurance;
  final QuoteDeposit? deposit;
  final double totalDueNow;
  final double totalDueLater;
  final double total;
  final bool showSubtotal;
  final bool showDueNow;

  factory CarHirePriceBreakdown.quote(RentalQuote quote) {
    return CarHirePriceBreakdown(
      currency: quote.currency,
      lineItems: quote.lineItems,
      subtotal: quote.subtotal,
      surcharges: quote.surcharges,
      discounts: quote.discounts,
      insurance: quote.insurance,
      deposit: quote.deposit,
      totalDueNow: quote.totalDueNow,
      totalDueLater: quote.totalDueLater,
      total: quote.total,
      showSubtotal: true,
      showDueNow: true,
    );
  }

  factory CarHirePriceBreakdown.booking(CarHireBooking booking) {
    final hasSnapshot = booking.priceBreakdown.isNotEmpty;
    final items = hasSnapshot
        ? booking.priceBreakdown
        : <QuoteLineItem>[
            if (booking.baseCost > 0)
              QuoteLineItem(
                code: 'rental_base',
                label: 'Vehicle hire',
                amount: booking.baseCost,
              ),
            if (booking.distanceCost > 0)
              QuoteLineItem(
                code: 'distance',
                label: 'Distance',
                amount: booking.distanceCost,
              ),
          ];

    return CarHirePriceBreakdown(
      currency: booking.currency,
      lineItems: items,
      surcharges: hasSnapshot ? 0 : booking.surcharges,
      discounts: hasSnapshot ? 0 : booking.discounts,
      insurance: hasSnapshot ? 0 : booking.insurance,
      total: booking.total,
      showSubtotal: false,
      showDueNow: false,
    );
  }

  String _money(double amount) => carHireMoney(currency, amount);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    // v2 quotes itemise company pricing adjustments, so the summary rows
    // would repeat them.
    final itemised = lineItems.any(
      (item) =>
          item.code == 'seasonal_adjustment' ||
          item.code == 'weekend_adjustment' ||
          item.code == 'duration_discount',
    );

    for (final item in lineItems) {
      if (item.label.trim().isEmpty && item.amount == 0) continue;
      rows.add(
        _row(
          item.label.trim().isEmpty ? 'Charge' : item.label,
          item.amount < 0 ? '- ${_money(-item.amount)}' : _money(item.amount),
          color: item.amount < 0 ? CarHirePalette.success : null,
        ),
      );
    }

    if (showSubtotal && subtotal > 0 && !itemised) {
      rows.add(const _Hairline());
      rows.add(_row('Subtotal', _money(subtotal), muted: true));
    }

    if (surcharges > 0 && !itemised) {
      rows.add(_row('Surcharges', _money(surcharges)));
    }
    if (insurance > 0) {
      rows.add(_row('Insurance', _money(insurance)));
    }
    if (discounts > 0 && !itemised) {
      rows.add(
        _row(
          'Discounts',
          '- ${_money(discounts)}',
          color: CarHirePalette.success,
        ),
      );
    }

    final depositInfo = deposit;
    if (depositInfo != null && depositInfo.amount > 0) {
      rows.add(
        _row(
          'Deposit (${depositInfo.collectionModeLabel.toLowerCase()})',
          _money(depositInfo.amount),
        ),
      );
    }

    if (showDueNow && totalDueNow > 0) {
      rows.add(const _Hairline());
      rows.add(_row('Due now', _money(totalDueNow), muted: true));
    }
    if (totalDueLater > 0) {
      rows.add(_row('Due later', _money(totalDueLater), muted: true));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: CarHirePalette.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _money(total),
                style: const TextStyle(
                  color: CarHirePalette.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    String label,
    String value, {
    bool muted = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted
                    ? CarHirePalette.onSurfaceVariant
                    : CarHirePalette.onSurface,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: color ??
                  (muted
                      ? CarHirePalette.onSurfaceVariant
                      : CarHirePalette.onSurface),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: CarHirePalette.hairline,
    );
  }
}
