class RentalCostModel {
  final double baseCost;
  final double dailyRate;
  final int days;
  final double lateFee;
  final double otherCharges;
  final double totalCost;
  final String breakdown; // Human-readable cost summary

  RentalCostModel({
    required this.baseCost,
    required this.dailyRate,
    required this.days,
    required this.lateFee,
    required this.otherCharges,
    required this.totalCost,
    required this.breakdown,
  });

  String get totalFormatted => 'MWK${totalCost.toStringAsFixed(2)}';
  String get baseFormatted => 'MWK${baseCost.toStringAsFixed(2)}';
  String get lateFeeFormatted => 'MWK${lateFee.toStringAsFixed(2)}';
  String get dailyRateFormatted => 'MWK${dailyRate.toStringAsFixed(0)}';

  factory RentalCostModel.fromJson(Map<String, dynamic> json) {
    return RentalCostModel(
      baseCost: (json['baseCost'] ?? 0).toDouble(),
      dailyRate: (json['dailyRate'] ?? 0).toDouble(),
      days: json['days'] ?? 1,
      lateFee: (json['lateFee'] ?? 0).toDouble(),
      otherCharges: (json['otherCharges'] ?? 0).toDouble(),
      totalCost: (json['totalCost'] ?? 0).toDouble(),
      breakdown: json['breakdown'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'baseCost': baseCost,
        'dailyRate': dailyRate,
        'days': days,
        'lateFee': lateFee,
        'otherCharges': otherCharges,
        'totalCost': totalCost,
        'breakdown': breakdown,
      };

  RentalCostModel copyWith({
    double? baseCost,
    double? dailyRate,
    int? days,
    double? lateFee,
    double? otherCharges,
    double? totalCost,
    String? breakdown,
  }) {
    return RentalCostModel(
      baseCost: baseCost ?? this.baseCost,
      dailyRate: dailyRate ?? this.dailyRate,
      days: days ?? this.days,
      lateFee: lateFee ?? this.lateFee,
      otherCharges: otherCharges ?? this.otherCharges,
      totalCost: totalCost ?? this.totalCost,
      breakdown: breakdown ?? this.breakdown,
    );
  }
}
