import 'package:vero360_app/GeneralModels/ride_model.dart';

class RideHistorySummary {
  final int completedCount;
  final int cancelledCount;
  final double? totalSpent;
  final double? totalEarnings;
  final String currency;

  RideHistorySummary({
    required this.completedCount,
    required this.cancelledCount,
    this.totalSpent,
    this.totalEarnings,
    this.currency = 'MWK',
  });

  factory RideHistorySummary.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return RideHistorySummary(
      completedCount: parseInt(json['completedCount']),
      cancelledCount: parseInt(json['cancelledCount']),
      totalSpent: parseDouble(json['totalSpent']),
      totalEarnings: parseDouble(json['totalEarnings']),
      currency: json['currency'] as String? ?? 'MWK',
    );
  }
}

class RideHistoryPage {
  final List<Ride> rides;
  final int total;
  final int page;
  final int limit;
  final RideHistorySummary summary;

  RideHistoryPage({
    required this.rides,
    required this.total,
    required this.page,
    required this.limit,
    required this.summary,
  });

  factory RideHistoryPage.fromJson(Map<String, dynamic> json) {
    final ridesJson = json['rides'];
    final rides = ridesJson is List
        ? ridesJson
            .map((r) => Ride.fromJson(r as Map<String, dynamic>))
            .toList()
        : <Ride>[];

    return RideHistoryPage(
      rides: rides,
      total: (json['total'] as num?)?.toInt() ?? rides.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? rides.length,
      summary: RideHistorySummary.fromJson(
        (json['summary'] as Map<String, dynamic>?) ?? {},
      ),
    );
  }
}

class EarningsPeriod {
  final int trips;
  final double earnings;

  EarningsPeriod({required this.trips, required this.earnings});

  factory EarningsPeriod.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return EarningsPeriod(
      trips: (json['trips'] as num?)?.toInt() ?? 0,
      earnings: parseDouble(json['earnings']),
    );
  }
}

class DriverEarningsSummary {
  final EarningsPeriod today;
  final EarningsPeriod thisWeek;
  final EarningsPeriod thisMonth;
  final EarningsPeriod allTime;
  final String currency;

  DriverEarningsSummary({
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.allTime,
    this.currency = 'MWK',
  });

  factory DriverEarningsSummary.fromJson(Map<String, dynamic> json) {
    EarningsPeriod period(String key) => EarningsPeriod.fromJson(
          (json[key] as Map<String, dynamic>?) ?? {},
        );

    return DriverEarningsSummary(
      today: period('today'),
      thisWeek: period('thisWeek'),
      thisMonth: period('thisMonth'),
      allTime: period('allTime'),
      currency: json['currency'] as String? ?? 'MWK',
    );
  }
}
