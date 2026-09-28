import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/GernalServices/buyer_commission.dart';

/// Merchant-only explanation of buyer-paid commission.
class MerchantCommissionGuide {
  MerchantCommissionGuide._();

  static final NumberFormat _mwk = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'MWK ',
    decimalDigits: 0,
  );

  static String money(num value) => _mwk.format(value.round());

  static Widget infoButton(
    BuildContext context, {
    required String priceText,
  }) {
    return IconButton(
      tooltip: 'How commission works',
      icon: const Icon(Icons.info_outline_rounded),
      color: const Color(0xFFFF6B00),
      onPressed: () => show(
        context,
        price: _parse(priceText),
      ),
    );
  }

  static double? _parse(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(digits);
  }

  static Future<void> show(
    BuildContext context, {
    double? price,
  }) {
    final entered = (price != null && price > 0) ? price : 5000.0;
    final quote = BuyerCommission.quote(entered);
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF2A2A2A),
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'How Vero360 Commission Works',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Enter the price you want to receive. Vero360 adds its commission to the customer’s total; it is not deducted from your price.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        const TextSpan(text: 'For example, if you enter '),
                        TextSpan(
                          text: money(quote.providerPrice),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: ', Vero360 adds '),
                        TextSpan(
                          text: money(quote.commission),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: '. The customer pays '),
                        TextSpan(
                          text: money(quote.buyerTotal),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: ', and you receive '),
                        TextSpan(
                          text: money(quote.providerPrice),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  InkWell(
                    onTap: () => _showRanges(ctx),
                    child: const Text(
                      'View the full commission ranges',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showRanges(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Commission ranges',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF102A43),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'You set the price you receive. This amount is added for the customer.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF486581),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _rangeHeader(),
                      for (var i = 0; i < BuyerCommission.merchantRanges.length; i++)
                        _rangeRow(
                          BuyerCommission.merchantRanges[i].price,
                          BuyerCommission.merchantRanges[i].added,
                          i.isEven,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _rangeHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF102A43),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'MERCHANT PRICE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'AMOUNT ADDED',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _rangeRow(String price, String added, bool shaded) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      color: shaded ? const Color(0xFFF4F7FB) : Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Text(
              price,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF243B53),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              added,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF334E68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
