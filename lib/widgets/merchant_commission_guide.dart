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

  /// Always-visible breakdown under a merchant price field.
  static Widget priceNote(
    BuildContext context, {
    required String priceText,
  }) {
    final price = _parse(priceText);
    final hasPrice = price != null && price > 0;
    final quote = hasPrice ? BuyerCommission.quote(price) : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: const Color(0xFFFFF4EB),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => show(context, price: price),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFFF6B00),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPrice
                            ? 'Customer pays ${money(quote!.buyerTotal)}. You receive ${money(quote.providerPrice)}.'
                            : 'Vero360 adds commission for the customer. It is not taken from your price.',
                        style: const TextStyle(
                          color: Color(0xFF7A3E00),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'How commission works',
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFFFF6B00),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double? _parse(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(digits);
  }

  static int _rangeIndexFor(double price) {
    const caps = <double>[
      5000,
      10000,
      20000,
      50000,
      100000,
      500000,
      2000000,
      10000000,
    ];
    for (var i = 0; i < caps.length; i++) {
      if (price <= caps[i]) return i;
    }
    return caps.length;
  }

  static Future<void> show(
    BuildContext context, {
    double? price,
  }) {
    final entered = (price != null && price > 0) ? price : 5000.0;
    final quote = BuyerCommission.quote(entered);
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'How Vero360 Commission Works',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      'Enter the price you want to receive. Commission is added for the customer. It is not taken from you.',
                      style: TextStyle(
                        color: Color(0xFFE8E8E8),
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _exampleCard(quote),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _showRanges(ctx, highlightPrice: entered),
                        icon: const Icon(Icons.table_chart_rounded, size: 20),
                        label: const Text('View the full commission ranges'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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

  static Widget _exampleCard(BuyerCommissionQuote quote) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B00), width: 1.4),
      ),
      child: Column(
        children: [
          _exampleLine('You enter', money(quote.providerPrice)),
          _exampleLine('Amount added', money(quote.commission)),
          _exampleLine('Customer pays', money(quote.buyerTotal), emphasize: true),
          _exampleLine('You receive', money(quote.providerPrice), emphasize: true),
        ],
      ),
    );
  }

  static Widget _exampleLine(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? Colors.white : const Color(0xFFD0D0D0),
                fontSize: 15,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? const Color(0xFFFFB067) : Colors.white,
              fontSize: emphasize ? 16 : 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showRanges(
    BuildContext context, {
    required double highlightPrice,
  }) {
    final active = _rangeIndexFor(highlightPrice);
    final height = MediaQuery.sizeOf(context).height * 0.86;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF102A43),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Commission ranges',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF102A43),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You set the price you receive. This is what is added for the customer.',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: Color(0xFF243B53),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _rangeHeader(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: BuyerCommission.merchantRanges.length,
                      itemBuilder: (_, i) {
                        final row = BuyerCommission.merchantRanges[i];
                        return _rangeRow(
                          row.price,
                          row.added,
                          i.isEven,
                          highlighted: i == active,
                        );
                      },
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
                fontSize: 13,
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
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _rangeRow(
    String price,
    String added,
    bool shaded, {
    bool highlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFFFF1E6)
            : (shaded ? const Color(0xFFF4F7FB) : Colors.white),
        border: Border(
          left: BorderSide(
            color: highlighted ? const Color(0xFFFF6B00) : Colors.transparent,
            width: 5,
          ),
          bottom: const BorderSide(color: Color(0xFFE4E7EB)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              price,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: highlighted
                    ? const Color(0xFF9A3412)
                    : const Color(0xFF102A43),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              added,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: highlighted
                    ? const Color(0xFFC2410C)
                    : const Color(0xFF243B53),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
