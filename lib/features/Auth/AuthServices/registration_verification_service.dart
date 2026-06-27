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
class RegistrationVerificationService {
  static String formatPhoneE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return raw.trim();
    if (digits.startsWith('265') && digits.length == 12) return '+$digits';
    if (digits.startsWith('0') && digits.length == 10) {
      return '+265${digits.substring(1)}';
    }
    if (raw.trim().startsWith('+')) return raw.trim();
    return '+$digits';
  }

  Future<void> requestOtp({
    required String channel,
    String? email,
    String? phone,
    String purpose = 'registration',
  }) async {
    await ApiClient.post(
      '/auth/otp/request',
      body: jsonEncode({
        'channel': channel,
        'purpose': purpose,
        if (email != null && email.trim().isNotEmpty)
          'email': email.trim().toLowerCase(),
        if (phone != null && phone.trim().isNotEmpty)
          'phone': formatPhoneE164(phone),
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
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
    }
    return forSend
        ? 'Could not send verification code. Try again.'
        : 'Invalid or expired code. Try again.';
  }
}
