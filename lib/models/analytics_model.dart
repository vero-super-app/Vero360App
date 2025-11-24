class MerchantAnalytics {
  final int totalCars;
  final int totalBookings;
  final int activeRentals;
  final double totalEarnings;
  final double monthlyEarnings;
  final double weeklyEarnings;
  final double dailyEarnings;
  final double averageRating;
  final double utilizationRate;
  final List<DailyMetric> dailyMetrics;
  final List<CarAnalytics> carAnalytics;
  final RevenueBreakdown revenueBreakdown;
  final DateTime generatedAt;

  MerchantAnalytics({
    required this.totalCars,
    required this.totalBookings,
    required this.activeRentals,
    required this.totalEarnings,
    required this.monthlyEarnings,
    required this.weeklyEarnings,
    required this.dailyEarnings,
    required this.averageRating,
    required this.utilizationRate,
    required this.dailyMetrics,
    required this.carAnalytics,
    required this.revenueBreakdown,
    required this.generatedAt,
  });

  factory MerchantAnalytics.fromJson(Map<String, dynamic> json) {
    return MerchantAnalytics(
      totalCars: json['totalCars'] ?? json['total_cars'] ?? 0,
      totalBookings: json['totalBookings'] ?? json['total_bookings'] ?? 0,
      activeRentals: json['activeRentals'] ?? json['active_rentals'] ?? 0,
      totalEarnings: (json['totalEarnings'] ?? json['total_earnings'] ?? 0).toDouble(),
      monthlyEarnings: (json['monthlyEarnings'] ?? json['monthly_earnings'] ?? 0).toDouble(),
      weeklyEarnings: (json['weeklyEarnings'] ?? json['weekly_earnings'] ?? 0).toDouble(),
      dailyEarnings: (json['dailyEarnings'] ?? json['daily_earnings'] ?? 0).toDouble(),
      averageRating: (json['averageRating'] ?? json['average_rating'] ?? 0).toDouble(),
      utilizationRate: (json['utilizationRate'] ?? json['utilization_rate'] ?? 0).toDouble(),
      dailyMetrics: json['dailyMetrics'] != null
          ? (json['dailyMetrics'] as List).map((e) => DailyMetric.fromJson(e)).toList()
          : [],
      carAnalytics: json['carAnalytics'] != null
          ? (json['carAnalytics'] as List).map((e) => CarAnalytics.fromJson(e)).toList()
          : [],
      revenueBreakdown: json['revenueBreakdown'] != null
          ? RevenueBreakdown.fromJson(json['revenueBreakdown'])
          : RevenueBreakdown.empty(),
      generatedAt: DateTime.parse(
        json['generatedAt'] ?? json['generated_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalCars': totalCars,
        'totalBookings': totalBookings,
        'activeRentals': activeRentals,
        'totalEarnings': totalEarnings,
        'monthlyEarnings': monthlyEarnings,
        'weeklyEarnings': weeklyEarnings,
        'dailyEarnings': dailyEarnings,
        'averageRating': averageRating,
        'utilizationRate': utilizationRate,
        'dailyMetrics': dailyMetrics.map((m) => m.toJson()).toList(),
        'carAnalytics': carAnalytics.map((c) => c.toJson()).toList(),
        'revenueBreakdown': revenueBreakdown.toJson(),
        'generatedAt': generatedAt.toIso8601String(),
      };
}

class DailyMetric {
  final DateTime date;
  final int bookings;
  final double earnings;
  final double totalKm;
  final double utilizationPercentage;
  final int completedTrips;
  final int cancelledTrips;

  DailyMetric({
    required this.date,
    required this.bookings,
    required this.earnings,
    required this.totalKm,
    required this.utilizationPercentage,
    this.completedTrips = 0,
    this.cancelledTrips = 0,
  });

  factory DailyMetric.fromJson(Map<String, dynamic> json) {
    return DailyMetric(
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      bookings: json['bookings'] ?? 0,
      earnings: (json['earnings'] ?? 0).toDouble(),
      totalKm: (json['totalKm'] ?? json['total_km'] ?? 0).toDouble(),
      utilizationPercentage:
          (json['utilizationPercentage'] ?? json['utilization_percentage'] ?? 0).toDouble(),
      completedTrips: json['completedTrips'] ?? json['completed_trips'] ?? 0,
      cancelledTrips: json['cancelledTrips'] ?? json['cancelled_trips'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'bookings': bookings,
        'earnings': earnings,
        'totalKm': totalKm,
        'utilizationPercentage': utilizationPercentage,
        'completedTrips': completedTrips,
        'cancelledTrips': cancelledTrips,
      };
}

class CarAnalytics {
  final int carId;
  final String carName;
  final int bookings;
  final double earnings;
  final double totalKm;
  final double utilizationRate;
  final double averageRating;
  final int reviews;
  final double averageDailyRate;

  CarAnalytics({
    required this.carId,
    required this.carName,
    required this.bookings,
    required this.earnings,
    required this.totalKm,
    required this.utilizationRate,
    required this.averageRating,
    this.reviews = 0,
    this.averageDailyRate = 0,
  });

  factory CarAnalytics.fromJson(Map<String, dynamic> json) {
    return CarAnalytics(
      carId: json['carId'] ?? json['car_id'] ?? 0,
      carName: json['carName'] ?? json['car_name'] ?? '',
      bookings: json['bookings'] ?? 0,
      earnings: (json['earnings'] ?? 0).toDouble(),
      totalKm: (json['totalKm'] ?? json['total_km'] ?? 0).toDouble(),
      utilizationRate: (json['utilizationRate'] ?? json['utilization_rate'] ?? 0).toDouble(),
      averageRating: (json['averageRating'] ?? json['average_rating'] ?? 0).toDouble(),
      reviews: json['reviews'] ?? 0,
      averageDailyRate:
          (json['averageDailyRate'] ?? json['average_daily_rate'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'carId': carId,
        'carName': carName,
        'bookings': bookings,
        'earnings': earnings,
        'totalKm': totalKm,
        'utilizationRate': utilizationRate,
        'averageRating': averageRating,
        'reviews': reviews,
        'averageDailyRate': averageDailyRate,
      };
}

class RevenueBreakdown {
  final double rentalRevenue;
  final double distanceCharges;
  final double surcharges;
  final double discounts;
  final double platformCommission;
  final double netRevenue;
  final double insuranceRevenue;

  RevenueBreakdown({
    required this.rentalRevenue,
    required this.distanceCharges,
    required this.surcharges,
    required this.discounts,
    required this.platformCommission,
    required this.netRevenue,
    this.insuranceRevenue = 0,
  });

  factory RevenueBreakdown.fromJson(Map<String, dynamic> json) {
    return RevenueBreakdown(
      rentalRevenue: (json['rentalRevenue'] ?? json['rental_revenue'] ?? 0).toDouble(),
      distanceCharges:
          (json['distanceCharges'] ?? json['distance_charges'] ?? 0).toDouble(),
      surcharges: (json['surcharges'] ?? 0).toDouble(),
      discounts: (json['discounts'] ?? 0).toDouble(),
      platformCommission:
          (json['platformCommission'] ?? json['platform_commission'] ?? 0).toDouble(),
      netRevenue: (json['netRevenue'] ?? json['net_revenue'] ?? 0).toDouble(),
      insuranceRevenue:
          (json['insuranceRevenue'] ?? json['insurance_revenue'] ?? 0).toDouble(),
    );
  }

  factory RevenueBreakdown.empty() {
    return RevenueBreakdown(
      rentalRevenue: 0,
      distanceCharges: 0,
      surcharges: 0,
      discounts: 0,
      platformCommission: 0,
      netRevenue: 0,
      insuranceRevenue: 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'rentalRevenue': rentalRevenue,
        'distanceCharges': distanceCharges,
        'surcharges': surcharges,
        'discounts': discounts,
        'platformCommission': platformCommission,
        'netRevenue': netRevenue,
        'insuranceRevenue': insuranceRevenue,
      };

  double get totalRevenue =>
      rentalRevenue + distanceCharges + surcharges + insuranceRevenue;
  double get totalDeductions => discounts + platformCommission;
}
