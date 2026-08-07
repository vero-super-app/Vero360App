// lib/services/payments_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:vero360_app/config/api_config.dart';

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
      checkoutUrl: (json['payment_url'] ?? json['checkout_url'])?.toString(),
      transactionId: json['transaction_id']?.toString(),
      txRef: json['tx_ref']?.toString(),
      status: json['status']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

/// Result of [PaymentsService.requestRefund].
class PaymentRefundResponse {
  final String? status;
  final String? message;
  final String? refundId;
  final String? txRef;
  final int processingDays;

  const PaymentRefundResponse({
    this.status,
    this.message,
    this.refundId,
    this.txRef,
    this.processingDays = 3,
  });

  factory PaymentRefundResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final daysRaw = data['processingDays'] ?? data['processing_days'] ?? 3;
    return PaymentRefundResponse(
      status: (data['status'] ?? json['status'])?.toString(),
      message: (data['message'] ?? json['message'])?.toString(),
      refundId: (data['refundId'] ?? data['refund_id'] ?? data['id'])
          ?.toString(),
      txRef: (data['tx_ref'] ?? data['txRef'] ?? data['reference'])?.toString(),
      processingDays: int.tryParse(daysRaw.toString()) ?? 3,
    );
  }
}

/// Refund type for marketplace / order refunds.
enum PaymentRefundType {
  /// Cancel before delivery and refund payment.
  cancelOrder,

  /// Return goods after delivery and refund payment.
  returnGoods,
}

extension PaymentRefundTypeApi on PaymentRefundType {
  String get apiValue => switch (this) {
        PaymentRefundType.cancelOrder => 'cancel_order',
        PaymentRefundType.returnGoods => 'return_goods',
      };

  String get label => switch (this) {
        PaymentRefundType.cancelOrder => 'Cancel order and refund',
        PaymentRefundType.returnGoods => 'Return goods and refund',
      };
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
        } else if (decoded is Map && decoded['data'] is Map<String, dynamic>) {
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

  /// Request a payment refund via the backend payments API.
  ///
  /// Tries `POST /payments/refund`, then `POST /orders/{orderId}/refund`.
  /// Refunds are typically settled within [PaymentRefundResponse.processingDays]
  /// (default 3).
  static Future<PaymentRefundResponse> requestRefund({
    required String orderId,
    required String orderNumber,
    required double amount,
    required PaymentRefundType refundType,
    required String reason,
    String currency = 'MWK',
    String? txRef,
    String? itemName,
  }) async {
    final token = await _readToken();
    if (token == null || token.isEmpty) {
      throw Exception('Please sign in to request a refund.');
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw Exception('Please enter a reason for the refund.');
    }
    if (amount <= 0) {
      throw Exception('Invalid refund amount.');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final body = <String, dynamic>{
      'orderId': orderId,
      'orderNumber': orderNumber,
      'amount': amount.round(),
      'currency': currency,
      'refundType': refundType.apiValue,
      'reason': trimmedReason,
      'processingDays': 3,
      if (txRef != null && txRef.trim().isNotEmpty) 'tx_ref': txRef.trim(),
      if (itemName != null && itemName.trim().isNotEmpty)
        'itemName': itemName.trim(),
    };

    Future<PaymentRefundResponse> post(Uri uri) async {
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          return PaymentRefundResponse.fromJson(decoded);
        }
        if (decoded is Map) {
          return PaymentRefundResponse.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
        return PaymentRefundResponse(
          status: 'pending',
          message: 'Refund request submitted. Processing takes up to 3 days.',
          txRef: txRef,
          processingDays: 3,
        );
      }

      if (res.statusCode == 404) {
        throw _RefundEndpointMissing();
      }
      throw Exception(_friendlyError(res.body));
    }

    try {
      try {
        return await post(ApiConfig.endpoint('/payments/refund'));
      } on _RefundEndpointMissing {
        return await post(ApiConfig.endpoint('/orders/$orderId/refund'));
      }
    } on TimeoutException {
      throw Exception('Refund request timed out. Please try again.');
    } on SocketException {
      throw Exception(
        'Network error. Please check your connection and try again.',
      );
    } on http.ClientException {
      throw Exception('Network error. Please try again.');
    } on _RefundEndpointMissing {
      throw Exception(
        'Refund service is not available yet. Please contact support.',
      );
    }
  }
}

class _RefundEndpointMissing implements Exception {}
