// lib/config/paychangu_config.dart
/// Centralized configuration for PayChangu payment gateway
/// 
/// Usage:
///   final paymentUrl = PayChanguConfig.paymentEndpoint;
///   final verifyUrl = PayChanguConfig.verifyEndpoint(txRef);
///   final transferUrl = PayChanguConfig.transferEndpoint;

class PayChanguConfig {
  /// PayChangu API base URL
  static const String baseUrl = 'https://api.paychangu.com';

  /// Payment processing endpoint
  /// POST to create/process a payment
  static const String paymentEndpoint = '$baseUrl/payment';

  /// Transaction verification endpoint
  /// GET to verify a transaction by reference
  static String verifyEndpoint(String txRef) =>
      '$baseUrl/transaction/verify/$txRef';

  /// Merchant payout/transfer endpoint
  /// POST to request a payout to merchant account
  static const String transferEndpoint = '$baseUrl/transfer';

  /// Default callback URL (should be overridden in actual implementation)
  /// This would be your backend webhook endpoint
  static const String callbackUrl = 'https://webhook.site/your-webhook';

  /// Default return URL (should be overridden in actual implementation)
  /// This is where users are sent after payment
  static const String returnUrl = 'https://your-app.com/payment-success';

  /// Standard headers for PayChangu requests
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Whether to use sandbox/test mode
  /// Set to false for production
  static bool get isSandbox => false;

  /// Public key for PayChangu integration
  /// This should be stored in environment config, not hardcoded
  static const String publicKey = 'pk_prod_xxx'; // Replace with actual key

  /// Check if PayChangu is available and configured
  static bool isConfigured() {
    return baseUrl.isNotEmpty && publicKey.isNotEmpty;
  }

  /// Get full payment request URL with parameters
  static Uri paymentUri() {
    return Uri.parse(paymentEndpoint);
  }

  /// Get full verify request URL with transaction reference
  static Uri verifyUri(String txRef) {
    return Uri.parse(verifyEndpoint(txRef));
  }

  /// Get full transfer request URL
  static Uri transferUri() {
    return Uri.parse(transferEndpoint);
  }
}
