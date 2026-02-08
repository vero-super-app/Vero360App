import 'package:flutter/foundation.dart' show kDebugMode;

/// PayChangu configuration class
/// Central place for all PayChangu-related constants and helpers
class PayChanguConfig {
  // ───────────────────────────────────────────────
  //  Base Configuration
  // ───────────────────────────────────────────────

  /// API base URL (same for test & production)
  static const String baseUrl = 'https://api.paychangu.com';

  /// Whether the app is running in debug mode or using test credentials
  static bool get isTestMode => kDebugMode;

  /// Authorization token (use test key in debug, live key in release)
  /// In production: store in .env / Firebase Remote Config / secure storage
  static String get authorizationToken {
    if (isTestMode) {
      return 'Bearer SEC-TEST-MwiucQ5HO8rCVIWzykcMK13UkXTdsO7u';
    } else {
      // TODO: Replace with your production secret key
      // Best: load from Firebase Remote Config or flutter_secure_storage
      return 'Bearer SEC-LIVE-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
    }
  }

  // ───────────────────────────────────────────────
  //  Endpoints
  // ───────────────────────────────────────────────

  /// Payment initiation endpoint (POST)
  static Uri get paymentUri => Uri.parse('$baseUrl/payment');

  /// Transaction verification endpoint (GET)
  static Uri verifyUri(String txRef) =>
      Uri.parse('$baseUrl/transaction/verify/$txRef');

  /// Transfer/payout endpoint (POST) - if you need merchant withdrawals later
  static Uri get transferUri => Uri.parse('$baseUrl/transfer');

  // ───────────────────────────────────────────────
  //  Redirect / Notification URLs
  // ───────────────────────────────────────────────

  /// Deep link scheme for your app
  /// Must match what you declared in AndroidManifest.xml & Info.plist
  static const String appScheme = 'vero360';

  /// Callback URL – PayChangu redirects here after successful payment
  /// Using deep link so it opens your app directly
  static String get callbackUrl => '$appScheme://payment-complete';

  /// Return URL – PayChangu redirects here on cancel / failure / manual close
  static String get returnUrl => '$appScheme://payment-complete';

  // Optional: if you ever add a real backend webhook later (Blaze plan)
  static String get backendWebhookUrl =>
      isTestMode ? 'https://webhook.site/your-test-id' : 'https://your-domain.com/webhooks/paychangu';

  // ───────────────────────────────────────────────
  //  Common Headers & Defaults
  // ───────────────────────────────────────────────

  static Map<String, String> get defaultHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': authorizationToken,
      };

  // ───────────────────────────────────────────────
  //  Utility Methods
  // ───────────────────────────────────────────────

  /// Check if configuration looks valid
  static bool get isConfigured {
    if (authorizationToken.isEmpty || authorizationToken.contains('XXX')) {
      return false;
    }
    return true;
  }

  /// Helper to get full authorization header map (convenience)
  static Map<String, String> get authHeaders => {
        'Authorization': authorizationToken,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Build a payment request body with common defaults
  /// You can extend this in your checkout page
  static Map<String, dynamic> buildPaymentBody({
    required String txRef,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String amount,
    List<String> paymentMethods = const ['card', 'mobile_money', 'bank'],
    Map<String, dynamic>? customization,
  }) {
    return {
      'tx_ref': txRef,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone_number': phone,
      'currency': 'MWK',
      'amount': amount,
      'payment_methods': paymentMethods,
      'callback_url': callbackUrl,
      'return_url': returnUrl,
      'customization': customization ?? {
        'title': 'Vero 360 Payment',
        'description': 'Order checkout from cart',
      },
    };
  }
}