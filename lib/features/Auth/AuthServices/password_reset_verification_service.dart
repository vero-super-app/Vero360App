import 'dart:convert';

import 'package:vero360_app/GernalServices/api_client.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/features/Auth/AuthServices/registration_verification_service.dart';

/// Result of a successful password-reset identifier verification.
class PasswordResetVerificationResult {
  final String channel; // 'email' | 'phone'
  final String verificationTicket;
  final String? firebaseCustomToken;

  const PasswordResetVerificationResult({
    required this.channel,
    required this.verificationTicket,
    this.firebaseCustomToken,
  });

  bool get isVerified => verificationTicket.isNotEmpty;
}

/// Sends and verifies password-reset OTP via the Vero API (`/vero/auth/otp/*`).
class PasswordResetVerificationService {
  static String formatPhoneE164(String raw) =>
      RegistrationVerificationService.formatPhoneE164(raw);

  Future<void> requestOtp({
    required String channel,
    String? email,
    String? phone,
  }) {
    return RegistrationVerificationService().requestOtp(
      channel: channel,
      email: email,
      phone: phone,
      purpose: 'password_reset',
    );
  }

  Future<PasswordResetVerificationResult> verifyOtp({
    required String channel,
    String? email,
    String? phone,
    required String code,
  }) async {
    final res = await ApiClient.post(
      '/auth/otp/verify',
      body: jsonEncode({
        'channel': channel,
        'purpose': 'password_reset',
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

    final customToken = data['customToken']?.toString() ??
        data['firebaseCustomToken']?.toString() ??
        data['firebaseToken']?.toString();

    return PasswordResetVerificationResult(
      channel: channel,
      verificationTicket: ticket,
      firebaseCustomToken:
          customToken != null && customToken.isNotEmpty ? customToken : null,
    );
  }

  static String friendlyError(
    Object e, {
    bool forSend = false,
  }) {
    if (e is ApiException) {
      if (RegistrationVerificationService.isThrottled(e)) {
        return 'Too many codes for this number. Wait 10 minutes, then try once.';
      }
      final msg = e.message.trim();
      if (msg.isNotEmpty) return msg;
    }
    return forSend
        ? 'Could not send verification code. Try again.'
        : 'Invalid or expired code. Try again.';
  }
}
