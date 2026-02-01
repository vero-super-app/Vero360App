import 'package:flutter/material.dart';
import 'package:vero360_app/utils/formatters.dart';

class CostBreakdownWidget extends StatelessWidget {
  final double baseCost;
  final double distanceCost;
  final double surcharges;
  final double discounts;
  final double insurance;
  final double total;
  final String? breakdown;

  const CostBreakdownWidget({
    Key? key,
    required this.baseCost,
    this.distanceCost = 0,
    this.surcharges = 0,
    this.discounts = 0,
    this.insurance = 0,
    required this.total,
    this.breakdown,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost Breakdown',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _buildCostRow(context, 'Base Rental', baseCost),
          if (distanceCost > 0) ...[
            const SizedBox(height: 12),
            _buildCostRow(context, 'Distance Charges', distanceCost),
          ],
          if (insurance > 0) ...[
            const SizedBox(height: 12),
            _buildCostRow(context, 'Insurance', insurance),
          ],
          if (surcharges > 0) ...[
            const SizedBox(height: 12),
            _buildCostRow(context, 'Surcharges', surcharges, color: Colors.orange),
          ],
          if (discounts > 0) ...[
            const SizedBox(height: 12),
            _buildCostRow(context, 'Discount', -discounts, color: Colors.green),
          ],
          const Divider(height: 24),
          _buildCostRow(
            context,
            'Total Amount',
            total,
            isBold: true,
            fontSize: 16,
          ),
          if (breakdown != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                breakdown!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue[900],
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCostRow(
    BuildContext context,
    String label,
    double amount, {
    Color? color,
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: fontSize,
              ),
        ),
        Text(
          CarHireFormatters.formatCurrency(amount),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: fontSize,
              ),
        ),
      ],
    );
  }
}
