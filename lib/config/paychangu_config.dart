import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:vero360_app/config/api_config.dart';

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

  static Uri verifyUri(String txRef) =>
      Uri.parse('$baseUrl/transaction/verify/$txRef');

  /// Bank payout initialize (POST).
  /// Docs: https://developer.paychangu.com/docs/bank-account
  static Uri bankPayoutInitializeUri() =>
      Uri.parse('$baseUrl/direct-charge/payouts/initialize');

  /// Mobile money payout initialize (POST).
  /// Docs: https://developer.paychangu.com/docs/mobile-money
  static Uri mobileMoneyPayoutInitializeUri() =>
      Uri.parse('$baseUrl/mobile-money/payouts/initialize');

  /// List MoMo operators for payouts (GET).
  static Uri mobileMoneyOperatorsUri() => Uri.parse('$baseUrl/mobile-money/');

  /// Supported banks for payouts (GET).
  static Uri supportedBanksUri({String currency = 'MWK'}) => Uri.parse(
        '$baseUrl/direct-charge/payouts/supported-banks?currency=$currency',
      );

  /// Malawi MoMo operator ref_ids (from GET /mobile-money/).
  static const String airtelMoneyOperatorRefId =
      '20be6c20-adeb-4b5b-a7ba-0769820df4fb';
  static const String tnmMpambaOperatorRefId =
      '27494cb5-ba9e-437f-a114-4e7a7686bcca';

  // ───────────────────────────────────────────────
  //  Callback / return URLs (must be HTTP/HTTPS)
  // ───────────────────────────────────────────────

  /// Backend/web endpoints registered in your PayChangu dashboard.
  /// They must be valid HTTP/HTTPS URLs – custom schemes like
  /// `vero360://...` are rejected by the API.
  static String get callbackUrl =>
      ApiConfig.endpoint('/payments/callback').toString();

  static String get returnUrl =>
      ApiConfig.endpoint('/payments/return').toString();

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

  static bool get isConfigured =>
      authorizationToken.isNotEmpty && !authorizationToken.contains('XXX');
}
