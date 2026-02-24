import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/Gernalproviders/payment_provider.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/utils/formatters.dart';

class PaymentSettingsPage extends ConsumerStatefulWidget {
  const PaymentSettingsPage({super.key});

  @override
  ConsumerState<PaymentSettingsPage> createState() =>
      _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends ConsumerState<PaymentSettingsPage> {
  bool _expandedPaymentMethods = true;
  bool _expandedBankDetails = false;
  bool _expandedGatewaySettings = false;

  Future<void> _deletePaymentMethod(String methodId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Payment Method'),
        content: const Text(
          'Are you sure you want to remove this payment method? '
          'You will not be able to receive payments through it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // TODO: Implement payment method deletion
        // await ref.read(paymentServiceProvider).removePaymentMethod(methodId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment method removed'),
            backgroundColor: Colors.green,
          ),
        );
      } on Exception catch (e) {
        if (mounted) {
          CarHireErrorHandler.showErrorSnackbar(context, e);
        }
      }
    }
  }

  Future<void> _addPaymentMethod() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _buildAddPaymentMethodSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Settings'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Balance',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      CarHireFormatters.formatCurrency(250000), // TODO: Get from API
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pending Payouts',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CarHireFormatters.formatCurrency(75000), // TODO: Get from API
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Payment Methods Section
            _buildSectionHeader(
              context,
              'Payment Methods',
              _expandedPaymentMethods,
              () {
                setState(() => _expandedPaymentMethods = !_expandedPaymentMethods);
              },
            ),
            if (_expandedPaymentMethods) ...[
              const SizedBox(height: 12),
              _buildPaymentMethodCard(
                context,
                'Mobile Money - Merchant Money',
                'merchant.money@example.com',
                true,
              ),
              const SizedBox(height: 12),
              _buildPaymentMethodCard(
                context,
                'Bank Account - Standard Chartered',
                '•••• •••• •••• 1234',
                false,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addPaymentMethod,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Payment Method'),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Bank Details Section
            _buildSectionHeader(
              context,
              'Settlement Information',
              _expandedBankDetails,
              () {
                setState(() => _expandedBankDetails = !_expandedBankDetails);
              },
            ),
            if (_expandedBankDetails) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(
                        context,
                        'Bank Name',
                        'Standard Chartered Bank',
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        context,
                        'Account Holder',
                        'Mwale Car Rentals Ltd',
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        context,
                        'Account Number',
                        '1234567890',
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        context,
                        'SWIFT Code',
                        'SCBLMWMX',
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            // TODO: Implement edit settlement info
                          },
                          child: const Text('Edit Details'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Gateway Settings Section
            _buildSectionHeader(
              context,
              'Payment Gateway Settings',
              _expandedGatewaySettings,
              () {
                setState(
                  () =>
                      _expandedGatewaySettings = !_expandedGatewaySettings,
                );
              },
            ),
            if (_expandedGatewaySettings) ...[
              const SizedBox(height: 12),
              _buildGatewayToggle(
                context,
                'Merchant Money',
                'Receive payments via mobile money',
                true,
              ),
              const SizedBox(height: 12),
              _buildGatewayToggle(
                context,
                'PayPal',
                'Accept international payments',
                false,
              ),
              const SizedBox(height: 12),
              _buildGatewayToggle(
                context,
                'Stripe',
                'Credit card payments',
                false,
              ),
              const SizedBox(height: 12),
              _buildGatewayToggle(
                context,
                'Bank Transfer',
                'Direct bank deposits',
                true,
              ),
            ],
            const SizedBox(height: 24),

            // Transaction History Link
            Card(
              child: InkWell(
                onTap: () {
                  // TODO: Navigate to transaction history
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Transaction History',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'View all payment transactions',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: Colors.grey[600]),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Withdrawal Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic Withdrawals',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Set up automatic transfers of earnings to your bank account',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Switch(
                          value: true,
                          onChanged: (value) {
                            // TODO: Implement toggle
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Frequency',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: 'Weekly',
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: ['Daily', 'Weekly', 'Monthly']
                          .map((freq) => DropdownMenuItem(
                                value: freq,
                                child: Text(freq),
                              ))
                          .toList(),
                      onChanged: (value) {
                        // TODO: Update frequency
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    bool isExpanded,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard(
    BuildContext context,
    String title,
    String subtitle,
    bool isDefault,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.payment, color: Colors.blue[700]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Default',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: const Text('Edit'),
                  onTap: () {
                    // TODO: Implement edit
                  },
                ),
                if (!isDefault)
                  PopupMenuItem(
                    child: const Text('Set as Default'),
                    onTap: () {
                      // TODO: Implement set default
                    },
                  ),
                PopupMenuItem(
                  child: const Text(
                    'Remove',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => _deletePaymentMethod('method_id'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildGatewayToggle(
    BuildContext context,
    String title,
    String description,
    bool isEnabled,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isEnabled,
              onChanged: (value) {
                // TODO: Implement toggle
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddPaymentMethodSheet() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add Payment Method',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            _buildPaymentMethodOption(
              'Mobile Money',
              'Merchant Money, Airtel Money, etc.',
              Icons.phone_android,
            ),
            const SizedBox(height: 12),
            _buildPaymentMethodOption(
              'Bank Account',
              'Direct bank transfers',
              Icons.account_balance,
            ),
            const SizedBox(height: 12),
            _buildPaymentMethodOption(
              'PayPal',
              'International payments',
              Icons.payment,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodOption(
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          // TODO: Open payment method form
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: Colors.blue[700]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }
}
