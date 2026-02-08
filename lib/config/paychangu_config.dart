import 'package:flutter/foundation.dart' show kDebugMode;

/// PayChangu configuration – using deep links completely
class PayChanguConfig {
  // ───────────────────────────────────────────────
  //  Base & Auth
  // ───────────────────────────────────────────────

  static const String baseUrl = 'https://api.paychangu.com';

  static bool get isTestMode => kDebugMode;

  static String get authorizationToken {
    if (isTestMode) {
      return 'Bearer SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u';
    } else {
      // Replace with your real production secret key
      // Better: load from secure storage / Remote Config in production
      return 'Bearer SEC-LIVE-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
    }
  }

  // ───────────────────────────────────────────────
  //  Endpoints
  // ───────────────────────────────────────────────

  static Uri get paymentUri => Uri.parse('$baseUrl/payment');

  static Uri verifyUri(String txRef) => Uri.parse('$baseUrl/transaction/verify/$txRef');

  // ───────────────────────────────────────────────
  //  Deep Links – completely replace http callbacks
  // ───────────────────────────────────────────────

  static const String scheme = 'vero360';

  /// PayChangu redirects here after successful payment
  static String get callbackUrl => '$scheme://payment-complete';

  /// PayChangu redirects here on cancel/failure
  static String get returnUrl => '$scheme://payment-complete';

  // ───────────────────────────────────────────────
  //  Headers & Helpers
  // ───────────────────────────────────────────────

  static Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': authorizationToken,
      };

  static Map<String, dynamic> buildPaymentBody({
    required String txRef,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String amount,
  }) {
    return {
      'tx_ref': txRef,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone_number': phone,
      'currency': 'MWK',
      'amount': amount,
      'payment_methods': ['card', 'mobile_money', 'bank'],
      'callback_url': callbackUrl,
      'return_url': returnUrl,
      'customization': {
        'title': 'Vero 360 Payment',
        'description': 'Order checkout',
      },
    };
  }

  static bool get isConfigured => authorizationToken.isNotEmpty && !authorizationToken.contains('XXX');
}