import 'dart:convert';

import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';

/// Result of a successful registration identifier verification (email or phone).
class RegistrationVerificationResult {
  final String channel; // 'email' | 'phone'
  final String verificationTicket;

  const RegistrationVerificationResult({
    required this.channel,
    required this.verificationTicket,
  });

  bool get isVerified => verificationTicket.isNotEmpty;
}

/// Sends and verifies registration OTP via the Vero API (`/vero/auth/otp/*`).
/// Phone SMS is sent by Vero (Africa's Talking), not Firebase, so the text
/// is branded Vero360 and does not include the Firebase project id.
class RegistrationVerificationService {
  /// Malawi mobile → `+265` + 9 digits (08/09xxxxxxxx or +2658/9…).
  static String formatPhoneE164(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return raw.trim();

    // +265 0 88… (country code plus leftover local 0)
    if (digits.startsWith('2650') && digits.length >= 13) {
      digits = '265${digits.substring(4)}';
    }
    if (digits.startsWith('0') && digits.length == 10) {
      digits = '265${digits.substring(1)}';
    }
    if (RegExp(r'^[89]\d{8}$').hasMatch(digits)) {
      digits = '265$digits';
    }
    if (digits.startsWith('265') && digits.length == 12) {
      return '+$digits';
    }
    return '+$digits';
  }

  static bool isThrottled(Object e) {
    if (e is! ApiException) return false;
    if (e.statusCode == 429) return true;
    final hay = '${e.message} ${e.backendMessage ?? ''}'.toLowerCase();
    return hay.contains('throttl') || hay.contains('too many');
  }

  Future<void> requestOtp({
    required String channel,
    String? email,
    String? phone,
    String purpose = 'registration',
  }) async {
    String? e164;
    if (channel == 'phone') {
      e164 = formatPhoneE164(phone ?? '');
      if (!RegExp(r'^\+265[89]\d{8}$').hasMatch(e164)) {
        throw const ApiException(
          message: 'Use a 10-digit Malawi mobile starting with 08 or 09.',
          statusCode: 400,
        );
      }
    }

    await ApiClient.post(
      '/auth/otp/request',
      body: jsonEncode({
        'channel': channel,
        'purpose': purpose,
        if (email != null && email.trim().isNotEmpty)
          'email': email.trim().toLowerCase(),
        if (e164 != null) 'phone': e164,
      }),
    );
  }

  Future<String> verifyOtp({
    required String channel,
    String? email,
    String? phone,
    required String code,
  }) async {
    final res = await ApiClient.post(
      '/auth/otp/verify',
      body: jsonEncode({
        'channel': channel,
        if (channel == 'email' && email != null)
          'email': email.trim().toLowerCase(),
        if (channel == 'phone' && phone != null)
          'phone': formatPhoneE164(phone),
        'code': code.trim(),
      }),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final ticket = data['ticket']?.toString() ??
        data['verificationToken']?.toString() ??
        data['verificationTicket']?.toString();

    if (ticket == null || ticket.isEmpty) {
      throw const ApiException(message: 'Invalid or expired code');
    }
    return ticket;
  }

  static String friendlyError(
    Object e, {
    bool forSend = false,
  }) {
    if (e is ApiException) {
      if (looksLikeAccountExists(e)) {
        return 'Account exists. Please sign in to continue.';
      }
      if (isThrottled(e)) {
        return 'Too many codes for this number. Wait 10 minutes, then try once.';
      }
      final msg = e.message.trim();
      if (msg.toLowerCase().contains('insufficient') ||
          msg.toLowerCase().contains('credit is empty') ||
          msg.toLowerCase().contains('balance')) {
        return 'SMS is unavailable right now. Try email, or try again later.';
      }
      if (msg.toLowerCase().contains('e.164') ||
          msg.toLowerCase().contains('international')) {
        return 'Use a 10-digit Malawi mobile starting with 08 or 09.';
      }
      if (msg.isNotEmpty) return msg;
    }
    return forSend
        ? 'Could not send verification code. Try again.'
        : 'Invalid or expired code. Try again.';
  }

  /// Backend / OTP responses that mean this email or phone is already registered.
  static bool looksLikeAccountExists(Object e) {
    if (e is! ApiException) return false;
    if (e.requiresLogin) return true;
    final hay = '${e.message} ${e.backendMessage ?? ''}'.toLowerCase();
    return hay.contains('already exist') ||
        hay.contains('already registered') ||
        hay.contains('already in use') ||
        hay.contains('email is taken') ||
        hay.contains('phone is taken') ||
        hay.contains('account exists') ||
        hay.contains('user already') ||
        (e.statusCode == 409 &&
            (hay.contains('exist') ||
                hay.contains('registered') ||
                hay.contains('taken') ||
                hay.contains('duplicate')));
  }
}
