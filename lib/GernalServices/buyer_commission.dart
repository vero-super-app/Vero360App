/// Buyer-paid commission for marketplace, food, and stays.
///
/// The service provider's price is unchanged. Commission is added to the
/// buyer's bill (not deducted from the merchant). The full commission goes
/// to the Vero platform wallet after PawaPay's collection processing fee
/// (Malawi: 3.33% of the collected amount — 2.33% MMO + 1% PawaPay).
///
/// Amount added for the customer, by the price the merchant wants to receive:
///   MWK 100–5,000              10%     (MWK 10–500)
///   MWK 5,001–10,000            9%     (about MWK 450–900)
///   MWK 10,001–20,000           8%     (about MWK 800–1,600)
///   MWK 20,001–50,000           7%     (about MWK 1,400–3,500)
///   MWK 50,001–100,000          6%     (about MWK 3,000–6,000)
///   MWK 100,001–500,000         5%     (about MWK 5,000–25,000)
///   MWK 500,001–2,000,000       4%     (about MWK 20,000–80,000)
///   MWK 2,000,001–10,000,000    3.3%   (about MWK 66,000–330,000)
///   Above MWK 10,000,000        3%     (about MWK 300,000–600,000 up to 20,000,000)
class BuyerCommissionQuote {
  const BuyerCommissionQuote({
    required this.providerPrice,
    required this.rate,
    required this.commission,
    required this.buyerTotal,
    required this.veroShare,
    required this.processingFee,
  });

  final double providerPrice;
  final double rate;
  final double commission;
  final double buyerTotal;
  /// Commission minus PawaPay processing. This is what the platform wallet gets.
  final double veroShare;
  /// PawaPay + MMO collection fee, taken from commission only.
  final double processingFee;

  double get pawapayShare => processingFee;

  String get percentLabel {
    final pct = rate * 100;
    if (pct == pct.roundToDouble()) return '${pct.toInt()}%';
    return '${pct.toStringAsFixed(1)}%';
  }
}

class BuyerCommission {
  BuyerCommission._();

  /// Malawi collections: 2.33% MMO pass-through + 1% PawaPay.
  static const double pawapayCollectionFeeRate = 0.0333;

  static const List<({String price, String added})> merchantRanges = [
    (price: 'MWK 100 – 5,000', added: 'MWK 10 – 500'),
    (price: 'MWK 5,001 – 10,000', added: 'about MWK 450 – 900'),
    (price: 'MWK 10,001 – 20,000', added: 'about MWK 800 – 1,600'),
    (price: 'MWK 20,001 – 50,000', added: 'about MWK 1,400 – 3,500'),
    (price: 'MWK 50,001 – 100,000', added: 'about MWK 3,000 – 6,000'),
    (price: 'MWK 100,001 – 500,000', added: 'about MWK 5,000 – 25,000'),
    (price: 'MWK 500,001 – 2,000,000', added: 'about MWK 20,000 – 80,000'),
    (price: 'MWK 2,000,001 – 10,000,000', added: 'about MWK 66,000 – 330,000'),
    (price: 'MWK 10,000,001 – 20,000,000', added: 'about MWK 300,000 – 600,000'),
  ];

  static double rateFor(double providerPrice) {
    if (providerPrice <= 0) return 0;
    if (providerPrice <= 5000) return 0.10;
    if (providerPrice <= 10000) return 0.09;
    if (providerPrice <= 20000) return 0.08;
    if (providerPrice <= 50000) return 0.07;
    if (providerPrice <= 100000) return 0.06;
    if (providerPrice <= 500000) return 0.05;
    if (providerPrice <= 2000000) return 0.04;
    if (providerPrice <= 10000000) return 0.033;
    return 0.03;
  }

  static double money(double value) => (value * 100).round() / 100;

  static double processingFeeOn({
    required double buyerTotal,
    required double commission,
  }) {
    if (!(buyerTotal > 0) || !(commission > 0)) return 0;
    final fee = money(buyerTotal * pawapayCollectionFeeRate);
    if (fee <= 0) return 0;
    return fee > commission ? commission : fee;
  }

  /// Buyer-facing unit price: the amount the seller entered plus commission.
  /// Show this anywhere a customer sees a price. Do not store it as the
  /// seller's price, or checkout will add commission twice.
  static double buyerFacing(num providerPrice) =>
      quote(providerPrice.toDouble()).buyerTotal;

  static BuyerCommissionQuote quote(double providerPrice) {
    final price = money(providerPrice < 0 ? 0 : providerPrice);
    final rate = rateFor(price);
    final commission = money(price * rate);
    final buyerTotal = money(price + commission);
    final processingFee = processingFeeOn(
      buyerTotal: buyerTotal,
      commission: commission,
    );
    return BuyerCommissionQuote(
      providerPrice: price,
      rate: rate,
      commission: commission,
      buyerTotal: buyerTotal,
      veroShare: money(commission - processingFee),
      processingFee: processingFee,
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
    var allocatedProc = 0.0;
    for (var n = 0; n < positiveIndexes.length; n++) {
      final i = positiveIndexes[n];
      final line = cleaned[i];
      final isLast = n == positiveIndexes.length - 1;
      final fee = isLast
          ? money(order.commission - allocatedFee)
          : money(line * order.rate);
      allocatedFee = money(allocatedFee + fee);
      final safeFee = fee < 0 ? 0.0 : fee;
      final proc = isLast
          ? money(order.processingFee - allocatedProc)
          : order.commission > 0
              ? money(order.processingFee * (safeFee / order.commission))
              : 0.0;
      allocatedProc = money(allocatedProc + proc);
      final safeProc = proc < 0 ? 0.0 : (proc > safeFee ? safeFee : proc);
      out[i] = BuyerCommissionQuote(
        providerPrice: line,
        rate: order.rate,
        commission: safeFee,
        buyerTotal: money(line + safeFee),
        processingFee: safeProc,
        veroShare: money(safeFee - safeProc),
      );
    }
    return out;
  }
}
