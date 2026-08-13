import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vero360_app/features/Auth/AuthPresenter/auth_ui.dart';
import 'package:vero360_app/features/Auth/AuthServices/registration_verification_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class RegisterOtpScreen extends StatefulWidget {
  final String identifier;
  final String channel; // 'email' | 'phone'
  final Future<bool> Function(String code) onVerify;
  final Future<bool> Function() onResend;

  const RegisterOtpScreen({
    super.key,
    required this.identifier,
    required this.channel,
    required this.onVerify,
    required this.onResend,
  });

  @override
  State<RegisterOtpScreen> createState() => _RegisterOtpScreenState();
}

class _RegisterOtpScreenState extends State<RegisterOtpScreen> {
  final _codeCtrl = TextEditingController();
  final _focus = FocusNode();
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _channelLabel =>
      widget.channel == 'email' ? 'email' : 'phone number';

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final ok = await widget.onVerify(code);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = 'Invalid or expired code. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = RegistrationVerificationService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final ok = await widget.onResend();
      if (!mounted) return;
      if (ok) {
        _codeCtrl.clear();
        _focus.requestFocus();
        ToastHelper.showCustomToast(
          context,
          widget.channel == 'email'
              ? 'New code sent to your email'
              : 'New code sent via SMS',
          isSuccess: true,
          errorMessage: '',
        );
      } else {
        setState(() => _error = 'Could not resend code. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = RegistrationVerificationService.friendlyError(e, forSend: true));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _onCodeChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits != value) {
      _codeCtrl.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    if (_error != null) setState(() => _error = null);
    if (digits.length == 6 && !_verifying) {
      _verify();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _codeCtrl.text;
    final busy = _verifying || _resending;

    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: busy ? null : () => Navigator.of(context).pop(false),
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      children: [
                        const AuthLogoMark(size: 76),
                        const SizedBox(height: 20),
                        const Text(
                          'Enter your code',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AuthPalette.ink,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'We sent a 6-digit code to your $_channelLabel',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AuthPalette.muted,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.identifier,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AuthPalette.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AuthCard(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () => _focus.requestFocus(),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Opacity(
                                      opacity: 0,
                                      child: TextField(
                                        controller: _codeCtrl,
                                        focusNode: _focus,
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.done,
                                        maxLength: 6,
                                        enabled: !_verifying,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                        ],
                                        onChanged: _onCodeChanged,
                                        onSubmitted: (_) {
                                          if (!_verifying) _verify();
                                        },
                                        decoration: const InputDecoration(
                                          counterText: '',
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: List.generate(6, (i) {
                                        final filled = i < code.length;
                                        final active = i == code.length;
                                        return Expanded(
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 160),
                                            margin: EdgeInsets.only(right: i == 5 ? 0 : 8),
                                            height: 56,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: AuthPalette.field,
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: _error != null
                                                    ? const Color(0xFFD32F2F)
                                                    : active
                                                        ? AuthPalette.orange
                                                        : filled
                                                            ? AuthPalette.orange.withValues(alpha: 0.45)
                                                            : Colors.transparent,
                                                width: active || _error != null ? 1.6 : 1,
                                              ),
                                            ),
                                            child: Text(
                                              filled ? code[i] : '',
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                color: AuthPalette.ink,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD32F2F),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              AuthPrimaryButton(
                                label: _verifying ? 'Verifying…' : 'Verify code',
                                loading: _verifying,
                                onPressed: busy ? null : _verify,
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: busy ? null : _resend,
                                child: Text(
                                  _resending ? 'Sending a new code…' : 'Resend code',
                                  style: const TextStyle(
                                    color: AuthPalette.orange,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
