/// Buyer-paid commission for marketplace, food, and stays.
///
/// The service provider's price is unchanged. Commission is added to the
/// buyer's bill (not deducted from the merchant). Of that commission,
/// Vero360 keeps 60% and PayChangu's share is 40%.
///
/// Tiers are based on the provider price (the transaction value):
///   MWK 1–50,000            10%
///   MWK 50,001–500,000       8%
///   MWK 500,001–2,000,000    6%
///   MWK 2,000,001–5,000,000  5%
///   MWK 5,000,001–10,000,000 4%
///   MWK 10,000,001–20,000,000 3%
///   Above MWK 20,000,000    2.5%
class BuyerCommissionQuote {
  const BuyerCommissionQuote({
    required this.providerPrice,
    required this.rate,
    required this.commission,
    required this.buyerTotal,
    required this.veroShare,
    required this.paychanguShare,
  });

  final double providerPrice;
  final double rate;
  final double commission;
  final double buyerTotal;
  final double veroShare;
  final double paychanguShare;

  String get percentLabel {
    final pct = rate * 100;
    if (pct == pct.roundToDouble()) return '${pct.toInt()}%';
    return '${pct.toStringAsFixed(1)}%';
  }
}

class BuyerCommission {
  BuyerCommission._();

  static const double veroShareRate = 0.60;
  static const double paychanguShareRate = 0.40;

  static double rateFor(double providerPrice) {
    if (providerPrice <= 0) return 0;
    if (providerPrice <= 50000) return 0.10;
    if (providerPrice <= 500000) return 0.08;
    if (providerPrice <= 2000000) return 0.06;
    if (providerPrice <= 5000000) return 0.05;
    if (providerPrice <= 10000000) return 0.04;
    if (providerPrice <= 20000000) return 0.03;
    return 0.025;
  }

  static double money(double value) => (value * 100).round() / 100;

  static BuyerCommissionQuote quote(double providerPrice) {
    final price = money(providerPrice < 0 ? 0 : providerPrice);
    final rate = rateFor(price);
    final commission = money(price * rate);
    final veroShare = money(commission * veroShareRate);
    final paychanguShare = money(commission - veroShare);
    return BuyerCommissionQuote(
      providerPrice: price,
      rate: rate,
      commission: commission,
      buyerTotal: money(price + commission),
      veroShare: veroShare,
      paychanguShare: paychanguShare,
    );
  }

  /// Split one checkout commission across line grosses so the parts sum
  /// to the tier commission for the whole transaction.
  static List<BuyerCommissionQuote> allocateLines(List<double> lineGrosses) {
    final cleaned = lineGrosses
        .map((g) => g.isFinite && g > 0 ? money(g) : 0.0)
        .toList();
    final total = cleaned.fold<double>(0, (sum, g) => sum + g);
    final order = quote(total);
    if (cleaned.isEmpty) return const [];

    final positiveIndexes = <int>[
      for (var i = 0; i < cleaned.length; i++)
        if (cleaned[i] > 0) i,
    ];
    final out = List<BuyerCommissionQuote>.generate(
      cleaned.length,
      (i) => quote(0),
    );
    if (positiveIndexes.isEmpty || order.commission <= 0) return out;

    var allocatedFee = 0.0;
    for (var n = 0; n < positiveIndexes.length; n++) {
      final i = positiveIndexes[n];
      final line = cleaned[i];
      final isLast = n == positiveIndexes.length - 1;
      final fee = isLast
          ? money(order.commission - allocatedFee)
          : money(line * order.rate);
      allocatedFee = money(allocatedFee + fee);
      final vero = money(fee * veroShareRate);
      out[i] = BuyerCommissionQuote(
        providerPrice: line,
        rate: order.rate,
        commission: fee < 0 ? 0 : fee,
        buyerTotal: money(line + (fee < 0 ? 0 : fee)),
        veroShare: vero < 0 ? 0 : vero,
        paychanguShare: money((fee < 0 ? 0 : fee) - (vero < 0 ? 0 : vero)),
      );
    }
    return out;
  }
}
