import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_service.dart';
import 'package:vero360_app/features/Auth/AuthServices/password_reset_verification_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialIdentifier;

  const ForgotPasswordScreen({
    super.key,
    this.initialIdentifier = '',
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _brandOrange = Color(0xFFFF8A00);

  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _verificationService = PasswordResetVerificationService();

  final _identifier = TextEditingController();
  final _otpCode = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _otpSent = false;
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _otpError;

  @override
  void initState() {
    super.initState();
    if (widget.initialIdentifier.trim().isNotEmpty) {
      _identifier.text = widget.initialIdentifier.trim();
    }
  }

  @override
  void dispose() {
    _identifier.dispose();
    _otpCode.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String v) =>
      RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(v.trim());

  bool _looksLikePhone(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^(08|09)\d{8}$').hasMatch(digits) ||
        RegExp(r'^\+265[89]\d{8}$').hasMatch(t);
  }

  String? _validateIdentifier(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email or phone number is required';
    if (_looksLikeEmail(s) || _looksLikePhone(s)) return null;
    return 'Enter a valid email or phone number';
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Must be at least 6 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Confirm your password';
    if (v != _password.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _sendOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _otpError = null;
    });

    try {
      final result = await _authService.requestPasswordReset(
        identifier: _identifier.text.trim(),
      );
      if (!mounted) return;

      if (!result.success) {
        ToastHelper.showCustomToast(
          context,
          result.message,
          isSuccess: false,
          errorMessage: result.message,
        );
        return;
      }

      setState(() {
        _otpSent = true;
        _otpCode.clear();
      });

      ToastHelper.showCustomToast(
        context,
        result.message,
        isSuccess: true,
        errorMessage: '',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _loading = true;
      _otpError = null;
    });
    try {
      final identifier = _identifier.text.trim();
      final channel = _looksLikeEmail(identifier) ? 'email' : 'phone';
      if (channel == 'email') {
        await _verificationService.requestOtp(channel: 'email', email: identifier);
      } else {
        await _verificationService.requestOtp(channel: 'phone', phone: identifier);
      }
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        channel == 'email'
            ? 'New code sent to your email'
            : 'New code sent via SMS',
        isSuccess: true,
        errorMessage: '',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _otpError = PasswordResetVerificationService.friendlyError(e, forSend: true);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _otpError = 'Could not resend code. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_otpSent) {
      await _sendOtp();
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = _otpCode.text.trim();
    if (code.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit code');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _otpError = null;
    });

    try {
      final identifier = _identifier.text.trim();
      final channel = _looksLikeEmail(identifier) ? 'email' : 'phone';

      PasswordResetVerificationResult verification;
      try {
        verification = await _verificationService.verifyOtp(
          channel: channel,
          email: channel == 'email' ? identifier : null,
          phone: channel == 'phone' ? identifier : null,
          code: code,
        );
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _otpError = PasswordResetVerificationService.friendlyError(e);
        });
        return;
      }

      final result = await _authService.completePasswordResetWithOtp(
        identifier: identifier,
        otpCode: code,
        newPassword: _password.text,
        verification: verification,
      );

      if (!mounted) return;

      ToastHelper.showCustomToast(
        context,
        result.message,
        isSuccess: result.success,
        errorMessage: result.success ? '' : result.message,
      );

      if (result.success) {
        Navigator.of(context).pop(identifier);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? trailing,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: trailing,
      filled: true,
      fillColor: const Color(0xFFF7F7F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brandOrange, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot password'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101010),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _otpSent
                      ? 'Enter the 6-digit code we sent and choose a new password.'
                      : 'We will send a 6-digit verification code to your email or phone (same as sign-up).',
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _identifier,
                  enabled: !_otpSent && !_loading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _fieldDecoration(
                    label: 'Email or phone number',
                    icon: Icons.alternate_email_outlined,
                  ),
                  validator: _validateIdentifier,
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _brandOrange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _looksLikeEmail(_identifier.text.trim())
                              ? 'Code sent to:'
                              : 'Code sent via SMS to:',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _identifier.text.trim(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _otpCode,
                          enabled: !_loading,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: _fieldDecoration(
                            label: '6-digit code',
                            icon: Icons.pin_outlined,
                          ).copyWith(counterText: ''),
                          onChanged: (_) {
                            if (_otpError != null) {
                              setState(() => _otpError = null);
                            }
                          },
                        ),
                        if (_otpError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _otpError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _resendOtp,
                            child: const Text('Resend code'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _password,
                    enabled: !_loading,
                    obscureText: _obscure1,
                    decoration: _fieldDecoration(
                      label: 'New password',
                      icon: Icons.lock_outline,
                      trailing: IconButton(
                        icon: Icon(
                          _obscure1 ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure1 = !_obscure1),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirm,
                    enabled: !_loading,
                    obscureText: _obscure2,
                    decoration: _fieldDecoration(
                      label: 'Confirm new password',
                      icon: Icons.lock_outline,
                      trailing: IconButton(
                        icon: Icon(
                          _obscure2 ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                      ),
                    ),
                    validator: _validateConfirm,
                    onFieldSubmitted: (_) {
                      if (!_loading) _submitNewPassword();
                    },
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submitNewPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _otpSent ? 'Update password' : 'Send verification code',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _otpSent = false;
                              _otpCode.clear();
                              _password.clear();
                              _confirm.clear();
                              _otpError = null;
                            }),
                    child: const Text('Use a different email or phone'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
