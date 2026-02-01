import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vero360_app/GeneralModels/car_model.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/error_handler.dart';
import 'package:vero360_app/Gernalproviders/payment_provider.dart';

class PaymentPage extends ConsumerStatefulWidget {
  final CarModel car;
  final DateTime startDate;
  final DateTime endDate;
  final bool includeInsurance;

  const PaymentPage({
    Key? key,
    required this.car,
    required this.startDate,
    required this.endDate,
    required this.includeInsurance,
  }) : super(key: key);

  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  String _selectedPaymentMethod = 'card'; // card, mobile, bank
  String? _selectedPromoCode;
  final TextEditingController _promoController = TextEditingController();
  bool _agreeToTerms = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the terms and conditions'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // TODO: Implement payment processing
      // final paymentDto = PaymentDto(
      //   bookingId: bookingId,
      //   amount: totalAmount,
      //   method: _selectedPaymentMethod,
      //   promoCode: _selectedPromoCode,
      // );
      // final service = ref.read(paymentServiceProvider);
      // await service.initiatePayment(paymentDto);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment processing...'),
            backgroundColor: Colors.blue,
          ),
        );

        // TODO: Navigate to confirmation page
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(
              '/rental/confirmation',
              arguments: {'car': widget.car},
            );
          }
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        CarHireErrorHandler.showErrorSnackbar(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _applyPromoCode() {
    final code = _promoController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a promo code')),
      );
      return;
    }

    // TODO: Validate promo code
    setState(() => _selectedPromoCode = code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Promo code "$code" applied'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rentalDays = widget.endDate.difference(widget.startDate).inDays + 1;
    final baseCost = widget.car.dailyRate * rentalDays;
    final insuranceCost = widget.includeInsurance ? 5000.0 * rentalDays : 0.0;
    final promoDiscount = _selectedPromoCode != null ? baseCost * 0.1 : 0.0; // 10% discount
    final totalCost = baseCost + insuranceCost - promoDiscount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Booking Summary
            Text(
              'Booking Summary',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Car Info
                    Row(
                      children: [
                        Container(
                          width: 80,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: widget.car.imageUrl != null
                              ? Image.network(
                                  widget.car.imageUrl!,
                                  fit: BoxFit.cover,
                                )
                              : Icon(
                                  Icons.directions_car,
                                  color: Colors.grey[600],
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.car.brand} ${widget.car.model}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.car.licensePlate,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$rentalDays days rental',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Dates
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-in',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                            Text(
                              CarHireFormatters.formatDate(widget.startDate),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_forward, color: Colors.grey[400]),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Check-out',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                            Text(
                              CarHireFormatters.formatDate(widget.endDate),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Cost Breakdown
            Text(
              'Cost Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildCostRow(
                      context,
                      'Daily Rate × $rentalDays',
                      CarHireFormatters.formatCurrency(baseCost),
                    ),
                    if (widget.includeInsurance) ...[
                      const SizedBox(height: 12),
                      _buildCostRow(
                        context,
                        'Insurance × $rentalDays',
                        CarHireFormatters.formatCurrency(insuranceCost),
                      ),
                    ],
                    if (_selectedPromoCode != null) ...[
                      const SizedBox(height: 12),
                      _buildCostRow(
                        context,
                        'Promo Discount ($_selectedPromoCode)',
                        '- ${CarHireFormatters.formatCurrency(promoDiscount)}',
                        isDiscount: true,
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          CarHireFormatters.formatCurrency(totalCost),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Promo Code
            Text(
              'Promo Code',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            if (_selectedPromoCode == null)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promoController,
                      decoration: InputDecoration(
                        hintText: 'Enter promo code',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _applyPromoCode,
                    child: const Text('Apply'),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Promo: $_selectedPromoCode',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPromoCode = null;
                          _promoController.clear();
                        });
                      },
                      child: Icon(Icons.close, color: Colors.green[700]),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Payment Method Selection
            Text(
              'Payment Method',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            _buildPaymentMethodCard(
              context,
              'card',
              'Credit/Debit Card',
              'Visa, Mastercard, etc.',
              Icons.credit_card,
            ),
            const SizedBox(height: 12),

            _buildPaymentMethodCard(
              context,
              'mobile',
              'Mobile Money',
              'Merchant Money, Airtel Money',
              Icons.phone_android,
            ),
            const SizedBox(height: 12),

            _buildPaymentMethodCard(
              context,
              'bank',
              'Bank Transfer',
              'Direct bank deposit',
              Icons.account_balance,
            ),
            const SizedBox(height: 24),

            // Terms & Conditions
            CheckboxListTile(
              value: _agreeToTerms,
              onChanged: (value) {
                setState(() => _agreeToTerms = value ?? false);
              },
              title: Text(
                'I agree to the rental terms',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      // TODO: Show terms
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Terms & Conditions'),
                  ),
                  const Text(' • '),
                  TextButton(
                    onPressed: () {
                      // TODO: Show cancellation policy
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Cancellation Policy'),
                  ),
                ],
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),

            // Confirm Payment Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Pay ${CarHireFormatters.formatCurrency(totalCost)}',
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Cancel Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isProcessing ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Security Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, size: 20, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your payment information is secure and encrypted',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blue[700],
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCostRow(
    BuildContext context,
    String label,
    String amount, {
    bool isDiscount = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          amount,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDiscount ? Colors.red : null,
              ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(
    BuildContext context,
    String value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _selectedPaymentMethod == value;

    return InkWell(
      onTap: () {
        setState(() => _selectedPaymentMethod = value);
      },
      child: Container(
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(color: Colors.blue[700]!, width: 2)
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Card(
          color: isSelected ? Colors.blue[50] : null,
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
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                  ),
                  ),
                  if (isSelected)
                  Icon(Icons.check_circle, color: Colors.blue[700], size: 24),
                  ],
                  ),
                  ),
                  ),
                  ),
                  );
                  }
                  }
