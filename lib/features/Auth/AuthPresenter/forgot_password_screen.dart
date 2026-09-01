import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/auth_ui.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_otp_screen.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _verificationService = PasswordResetVerificationService();

  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  PasswordResetVerificationResult? _verification;
  bool _otpVerified = false;
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

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
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _identifierValue => _identifier.text.trim();

  String get _channel =>
      _looksLikeEmail(_identifierValue) ? 'email' : 'phone';

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

  Future<bool> _sendPasswordResetOtp() async {
    _verification = null;
    try {
      if (_channel == 'email') {
        await _verificationService.requestOtp(
          channel: 'email',
          email: _identifierValue,
        );
      } else {
        await _verificationService.requestOtp(
          channel: 'phone',
          phone: _identifierValue,
        );
      }
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      ToastHelper.showCustomToast(
        context,
        PasswordResetVerificationService.friendlyError(e, forSend: true),
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ToastHelper.showCustomToast(
        context,
        'Could not send verification code. Try again.',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    }
  }

  Future<bool> _verifyPasswordResetOtp(String code) async {
    try {
      _verification = await _verificationService.verifyOtp(
        channel: _channel,
        email: _channel == 'email' ? _identifierValue : null,
        phone: _channel == 'phone' ? _identifierValue : null,
        code: code,
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> _startOtpFlow() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);
    try {
      final sent = await _sendPasswordResetOtp();
      if (!sent || !mounted) return;

      ToastHelper.showCustomToast(
        context,
        _channel == 'email'
            ? '6-digit code sent to your email'
            : '6-digit code sent via SMS',
        isSuccess: true,
        errorMessage: '',
      );

      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RegisterOtpScreen(
            identifier: _identifierValue,
            channel: _channel,
            onVerify: _verifyPasswordResetOtp,
            onResend: _sendPasswordResetOtp,
          ),
        ),
      );

      if (verified == true && mounted) {
        setState(() => _otpVerified = true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_otpVerified || _verification == null) {
      await _startOtpFlow();
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final result = await _authService.completePasswordResetWithOtp(
        identifier: _identifierValue,
        otpCode: '',
        newPassword: _password.text,
        verification: _verification!,
      );

      if (!mounted) return;

      ToastHelper.showCustomToast(
        context,
        result.message,
        isSuccess: result.success,
        errorMessage: result.success ? '' : result.message,
      );

      if (result.success) {
        Navigator.of(context).pop(_identifierValue);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetFlow() {
    setState(() {
      _otpVerified = false;
      _verification = null;
      _password.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading;
    final title = _otpVerified ? 'New password' : 'Forgot password';
    final subtitle = _otpVerified
        ? 'Choose a strong password for your Vero360 account.'
        : 'We will send a 6-digit code to your email or phone';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AuthBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AuthPalette.ink,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          AuthHeroHeader(title: title, subtitle: subtitle),
                          const SizedBox(height: 22),
                          AuthCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_otpVerified) ...[
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AuthPalette.cream,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AuthPalette.orange
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.verified_rounded,
                                          color: AuthPalette.orange,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Verified: $_identifierValue',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AuthPalette.ink,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _password,
                                    enabled: !busy,
                                    obscureText: _obscure1,
                                    onChanged: (_) => setState(() {}),
                                    decoration: authFieldDecoration(
                                      label: 'New password',
                                      hint: 'At least 6 characters',
                                      icon: Icons.lock_outline_rounded,
                                      trailing: IconButton(
                                        icon: Icon(
                                          _obscure1
                                              ? Icons.visibility_rounded
                                              : Icons.visibility_off_rounded,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscure1 = !_obscure1,
                                        ),
                                      ),
                                    ),
                                    validator: _validatePassword,
                                  ),
                                  AuthPasswordStrengthMeter(
                                    password: _password.text,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _confirm,
                                    enabled: !busy,
                                    obscureText: _obscure2,
                                    decoration: authFieldDecoration(
                                      label: 'Confirm password',
                                      hint: 'Re-enter your password',
                                      icon: Icons.lock_outline_rounded,
                                      trailing: IconButton(
                                        icon: Icon(
                                          _obscure2
                                              ? Icons.visibility_rounded
                                              : Icons.visibility_off_rounded,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscure2 = !_obscure2,
                                        ),
                                      ),
                                    ),
                                    validator: _validateConfirm,
                                    onFieldSubmitted: (_) {
                                      if (!busy) _submitNewPassword();
                                    },
                                  ),
                                  const SizedBox(height: 22),
                                  AuthPrimaryButton(
                                    label: busy
                                        ? 'Updating…'
                                        : 'Update password',
                                    loading: busy,
                                    onPressed: busy ? null : _submitNewPassword,
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: busy ? null : _resetFlow,
                                    child: const Text(
                                      'Start over',
                                      style: TextStyle(
                                        color: AuthPalette.orange,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  TextFormField(
                                    controller: _identifier,
                                    enabled: !busy,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.done,
                                    decoration: authFieldDecoration(
                                      label: 'Email or phone',
                                      hint: 'you@email.com or 08xxxxxxxx',
                                      icon: Icons.alternate_email_rounded,
                                    ),
                                    validator: _validateIdentifier,
                                    onFieldSubmitted: (_) {
                                      if (!busy) _startOtpFlow();
                                    },
                                  ),
                                  const SizedBox(height: 22),
                                  AuthPrimaryButton(
                                    label: busy
                                        ? 'Sending code…'
                                        : 'Send verification code',
                                    loading: busy,
                                    onPressed: busy ? null : _startOtpFlow,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
