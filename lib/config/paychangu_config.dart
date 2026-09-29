import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/utils/app_logger.dart';

/// PayChangu configuration – secrets from `.env` / dart-define (never hardcode).
class PayChanguConfig {
  // ───────────────────────────────────────────────
  //  Base & Auth
  // ───────────────────────────────────────────────

  static const String baseUrl = 'https://api.paychangu.com';

  static String _secretTest = '';
  static String _secretLive = '';
  static bool _initialized = false;

  /// `test` | `live`. Empty → debug builds use test, release uses live.
  static String _modeOverride = '';

  static Future<void> initialize() async {
    if (_initialized &&
        (_secretTest.isNotEmpty || _secretLive.isNotEmpty)) {
      return;
    }

    const ddTest =
        String.fromEnvironment('PAYCHANGU_SECRET_TEST', defaultValue: '');
    const ddLive =
        String.fromEnvironment('PAYCHANGU_SECRET_LIVE', defaultValue: '');
    const ddMode =
        String.fromEnvironment('PAYCHANGU_MODE', defaultValue: '');

    if (ddTest.isNotEmpty || ddLive.isNotEmpty) {
      _secretTest = ddTest.trim();
      _secretLive = ddLive.trim();
      _modeOverride = ddMode.trim().toLowerCase();
      _initialized = true;
      _warnIfMissing();
      return;
    }

    try {
      if (!dotenv.isInitialized) {
        try {
          await dotenv.load(fileName: '.env');
        } catch (_) {
          await dotenv.load(fileName: '.env.example');
        }
      }
      _secretTest = (dotenv.env['PAYCHANGU_SECRET_TEST'] ?? '').trim();
      _secretLive = (dotenv.env['PAYCHANGU_SECRET_LIVE'] ?? '').trim();
      _modeOverride =
          (dotenv.env['PAYCHANGU_MODE'] ?? '').trim().toLowerCase();
    } catch (e) {
      AppLogger.d('[PayChanguConfig] Error loading env', e);
    }

    _initialized = true;
    _warnIfMissing();
  }

  static void _warnIfMissing() {
    if (kDebugMode && !isConfigured) {
      AppLogger.w(
        '[PayChanguConfig] Missing PayChangu secret. '
        'Add PAYCHANGU_SECRET_TEST / PAYCHANGU_SECRET_LIVE to .env '
        'or use --dart-define.',
      );
    }
  }

  /// Debug → test; release → live. Override with PAYCHANGU_MODE=test|live.
  /// A release build that only has the test secret still checks out in test
  /// mode instead of failing with "payment is not configured".
  static bool get isTestMode {
    if (_modeOverride == 'test') return true;
    if (_modeOverride == 'live') return false;
    if (kDebugMode) return true;
    if (_secretLive.isEmpty && _secretTest.isNotEmpty) return true;
    return false;
  }

  static String get _rawSecret {
    final raw = isTestMode ? _secretTest : _secretLive;
    if (raw.isNotEmpty) return raw;
    // Fallback: if live empty in release, don't silently charge test.
    return isTestMode ? _secretTest : _secretLive;
  }

  static String get authorizationToken {
    final secret = _rawSecret;
    if (secret.isEmpty) return '';
    if (secret.toLowerCase().startsWith('bearer ')) return secret;
    return 'Bearer $secret';
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

  static bool get isConfigured {
    final t = authorizationToken;
    return t.isNotEmpty && !t.contains('XXX') && !t.endsWith('Bearer ');
  }
}
