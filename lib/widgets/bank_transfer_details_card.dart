import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/GernalServices/bank_transfer_config.dart';

/// Shows Vero360 National Bank details for a customer to copy and transfer.
class BankTransferDetailsCard extends StatelessWidget {
  static const _navy = Color(0xFF16284C);
  static const _orange = Color(0xFFFF8A00);

  final BankTransferDetails details;
  final String? amountLabel;
  final String? reference;
  final bool compact;

  const BankTransferDetailsCard({
    super.key,
    required this.details,
    this.amountLabel,
    this.reference,
    this.compact = false,
  });

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded, color: _orange, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Bank transfer',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            compact
                ? 'Pay to this account at checkout.'
                : 'Transfer the exact amount to this account. Use the payment reference as the deposit description.',
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          if (amountLabel != null && amountLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              amountLabel!,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: _orange,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _row(context, 'Bank', details.bankName),
          _row(context, 'Account name', details.accountName),
          _row(context, 'Account number', details.accountNumber, copyValue: details.accountNumber),
          _row(context, 'Branch', details.branch),
          if (reference != null && reference!.trim().isNotEmpty)
            _row(context, 'Payment reference', reference!.trim(), copyValue: reference!.trim()),
          const SizedBox(height: 4),
          const Row(
            children: [
              Icon(Icons.lock_rounded, size: 14, color: Color(0xFFB08968)),
              SizedBox(width: 6),
              Text(
                'Secured by Vero escrow',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB08968),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    String? copyValue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ),
          if (copyValue != null && copyValue.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Copy $label',
              onPressed: () => _copy(context, label, copyValue),
              icon: const Icon(Icons.copy_rounded, size: 16, color: _orange),
            ),
        ],
      ),
    );
  }
}
