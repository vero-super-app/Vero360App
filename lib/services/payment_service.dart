import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/models/payment_model.dart';
import 'package:vero360_app/dto/payment_dto.dart';

class PaymentService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Initiate payment for a booking
  Future<PaymentModel> initiatePayment(InitiatePaymentDto paymentDto) async {
    final token = await _getToken();
    if (token == null) throw PaymentException('Not authenticated');

    try {
      final res = await ApiClient.post(
        '/car-rental/payments/initiate',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode(paymentDto.toJson()),
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final payment = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return PaymentModel.fromJson(payment as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PaymentException(e.message);
    }
  }

  /// Verify payment status
  Future<PaymentModel> verifyPayment(String paymentId) async {
    final token = await _getToken();
    if (token == null) throw PaymentException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/payments/$paymentId/verify',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final payment = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return PaymentModel.fromJson(payment as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PaymentException(e.message);
    }
  }

  /// Get payment methods
  Future<List<PaymentMethodModel>> getPaymentMethods() async {
    final token = await _getToken();
    if (token == null) throw PaymentException('Not authenticated');

    try {
      final res = await ApiClient.get(
        '/car-rental/payments/methods',
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
          .map<PaymentMethodModel>(
              (e) => PaymentMethodModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw PaymentException(e.message);
    }
  }

  /// Add payment method
  Future<PaymentMethodModel> addPaymentMethod(
      PaymentMethodDto methodDto) async {
    final token = await _getToken();
    if (token == null) throw PaymentException('Not authenticated');

    try {
      final res = await ApiClient.post(
        '/car-rental/payments/methods',
        headers: {'Authorization': 'Bearer $token'},
        body: jsonEncode(methodDto.toJson()),
        timeout: _timeout,
      );

      final data = jsonDecode(res.body);
      final method = data is Map
          ? data
          : (data['data'] is Map ? data['data'] : <String, dynamic>{});

      return PaymentMethodModel.fromJson(method as Map<String, dynamic>);
    } on ApiException catch (e) {
      throw PaymentException(e.message);
    }
  }

  /// Remove payment method
  Future<void> removePaymentMethod(String methodId) async {
    final token = await _getToken();
    if (token == null) throw PaymentException('Not authenticated');

    try {
      await ApiClient.delete(
        '/car-rental/payments/methods/$methodId',
        headers: {'Authorization': 'Bearer $token'},
        timeout: _timeout,
      );
    } on ApiException catch (e) {
      throw PaymentException(e.message);
    }
  }

  /// Get transaction history
  Future<List<PaymentModel>> getTransactionHistory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final token = await _getToken();
    if (token == null) throw PaymentException('Not authenticated');

    try {
      String endpoint = '/car-rental/payments/history';
      final params = <String>[];
      if (startDate != null) params.add('startDate=${startDate.toIso8601String()}');
      if (endDate != null) params.add('endDate=${endDate.toIso8601String()}');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      final res = await ApiClient.get(
        endpoint,
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
          .map<PaymentModel>(
              (e) => PaymentModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      throw PaymentException(e.message);
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token') ?? prefs.getString('token');
  }
}

class PaymentException implements Exception {
  final String message;
  PaymentException(this.message);

  @override
  String toString() => message;
}
