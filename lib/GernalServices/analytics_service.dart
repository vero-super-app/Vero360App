import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GeneralModels/analytics_model.dart';

class AnalyticsService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Get merchant analytics for date range
  Future<MerchantAnalytics> getAnalytics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final token = await _getToken();
    if (token == null) throw AnalyticsException('Not authenticated');

    try {
      String endpoint = '/car-rental/merchant/analytics';
      final params = <String>[];
      if (startDate != null) params.add('startDate=${startDate.toIso8601String()}');
      if (endDate != null) params.add('endDate=${endDate.toIso8601String()}');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      final res = await ApiClient.get(
        endpoint,
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final analytics = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return MerchantAnalytics.fromJson(analytics as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw AnalyticsException(e.message);
    }
  }

  /// Get daily metrics for a car
  Future<List<DailyMetric>> getDailyMetrics(int carId, DateTime month) async {
    final token = await _getToken();
    if (token == null) throw AnalyticsException('Not authenticated');

    try {
      final monthStr = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final res = await ApiClient.get(
        '/car-rental/cars/$carId/metrics/daily?month=$monthStr',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list
          .map<DailyMetric>((e) => DailyMetric.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw AnalyticsException(e.message);
    }
  }

  /// Get fleet utilization stats
  Future<Map<String, dynamic>> getFleetUtilization() async {
    final token = await _getToken();
    if (token == null) throw AnalyticsException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/merchant/fleet/utilization',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      return data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});
    } on ApiException catch (e) {
      throw AnalyticsException(e.message);
    }
  }

  /// Get revenue report for date range
  Future<Map<String, dynamic>> getRevenueReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final token = await _getToken();
    if (token == null) throw AnalyticsException('Not authenticated');

    try {
      String endpoint = '/car-rental/merchant/revenue/report';
      final params = <String>[];
      if (startDate != null) params.add('startDate=${startDate.toIso8601String()}');
      if (endDate != null) params.add('endDate=${endDate.toIso8601String()}');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      final res = await ApiClient.get(
        endpoint,
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      return data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});
    } on ApiException catch (e) {
      throw AnalyticsException(e.message);
    }
  }

  /// Get monthly revenue for a year
  Future<List<Map<String, dynamic>>> getMonthlyRevenue(int year) async {
    final token = await _getToken();
    if (token == null) throw AnalyticsException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/merchant/revenue/monthly?year=$year',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final decoded = jsonDecode(res.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['data'] is List
              ? decoded['data']
              : <dynamic>[]);

      return list.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      throw AnalyticsException(e.message);
    }
  }

  /// Get trip statistics for a car
  Future<Map<String, dynamic>> getTripStatistics(int carId) async {
    final token = await _getToken();
    if (token == null) throw AnalyticsException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/cars/$carId/statistics',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      return data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});
    } on ApiException catch (e) {
      throw AnalyticsException(e.message);
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }
}

class AnalyticsException implements Exception {
  final String message;
  AnalyticsException(this.message);

  @override
  String toString() => message;
}
