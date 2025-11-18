// lib/services/payments_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/services/api_config.dart';

class PaymentCreateResponse {
  final String? checkoutUrl;
  final String? transactionId;
  final String? txRef;
  final String? status;
  final String? message;

  PaymentCreateResponse({
    this.checkoutUrl,
    this.transactionId,
    this.txRef,
    this.status,
    this.message,
  });

  factory PaymentCreateResponse.fromJson(Map<String, dynamic> json) {
    return PaymentCreateResponse(
      checkoutUrl:
          (json['payment_url'] ?? json['checkout_url'])?.toString(),
      transactionId: json['transaction_id']?.toString(),
      txRef: json['tx_ref']?.toString(),
      status: json['status']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

class PaymentsService {
  PaymentsService._();

  static bool validateAirtel(String phone) =>
      RegExp(r'^09\d{8}$').hasMatch(phone);
  static bool validateMpamba(String phone) =>
      RegExp(r'^08\d{8}$').hasMatch(phone);

  static Future<String?> _readToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('jwt') ?? sp.getString('token');
  }

  static String _friendlyError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map) {
        final m = parsed['message'] ?? parsed['error'];
        if (m is List && m.isNotEmpty) return m.first.toString();
        if (m is String) return m;
      }
      if (parsed is List && parsed.isNotEmpty) {
        return parsed.first.toString();
      }
    } catch (_) {}
    return 'Payment failed. Please try again.';
  }

  static Future<PaymentCreateResponse> pay({
    required double amount,
    required String currency, // "MWK"
    String? phoneNumber,
    required String relatedType,
    String? relatedId,
    String? description,
    String? txRef,
    String? provider,
    Map<String, dynamic>? meta,
  }) async {
    final uri = ApiConfig.endpoint('/payments/pay');

    final token = await _readToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    final uuid = relatedId ?? const Uuid().v4();
    final ref = txRef ?? 'vero_${DateTime.now().millisecondsSinceEpoch}';

    final body = <String, dynamic>{
      'amount': amount.toStringAsFixed(0),
      'currency': currency,
      'tx_ref': ref,
      'relatedType': relatedType,
      'relatedId': uuid,
      'description': description ?? 'Marketplace payment',
      if (phoneNumber != null && phoneNumber.isNotEmpty)
        'phone_number': phoneNumber,
      if (provider != null && provider.isNotEmpty) 'provider': provider,
      if (meta != null) 'meta': meta,
    };

    try {
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          return PaymentCreateResponse.fromJson(decoded);
        } else if (decoded is Map &&
            decoded['data'] is Map<String, dynamic>) {
          return PaymentCreateResponse.fromJson(
              decoded['data'] as Map<String, dynamic>);
        }
        return PaymentCreateResponse(
          message: 'Payment created, but response format was unexpected.',
        );
      }

      throw Exception(_friendlyError(res.body));
    } on TimeoutException {
      throw Exception('Payment request timed out. Please try again.');
    } on SocketException {
      throw Exception(
          'Network error. Please check your connection and try again.');
    } on http.ClientException {
      throw Exception('Network error. Please try again.');
    }
  }
}
