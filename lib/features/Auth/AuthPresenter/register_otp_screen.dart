import 'dart:async';

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
  Timer? _focusRetry;

  @override
  void initState() {
    super.initState();
    // Route push + keyboard often miss a single post-frame focus. Retry briefly
    // so the first digit is typeable immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureKeyboard());
    _focusRetry = Timer(const Duration(milliseconds: 350), _ensureKeyboard);
  }

  void _ensureKeyboard() {
    if (!mounted || _verifying) return;
    if (!_focus.hasFocus) {
      _focus.requestFocus();
    }
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  @override
  void dispose() {
    _focusRetry?.cancel();
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
        _codeCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _codeCtrl.text.length,
        );
        _ensureKeyboard();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = RegistrationVerificationService.friendlyError(e));
      _ensureKeyboard();
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
        ToastHelper.showCustomToast(
          context,
          widget.channel == 'email'
              ? 'New code sent to your email'
              : 'New code sent via SMS',
          isSuccess: true,
          errorMessage: '',
        );
        _ensureKeyboard();
      } else {
        setState(() => _error = 'Could not resend code. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            RegistrationVerificationService.friendlyError(e, forSend: true),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _onCodeChanged(String value) {
    if (_error != null) setState(() => _error = null);
    if (value.length == 6 && !_verifying) {
      _verify();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _verifying || _resending;

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
                      onPressed:
                          busy ? null : () => Navigator.of(context).pop(false),
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
                      ScrollViewKeyboardDismissBehavior.manual,
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
                              _OtpDigitBoxes(
                                controller: _codeCtrl,
                                focusNode: _focus,
                                error: _error != null,
                                enabled: !_verifying,
                                onChanged: _onCodeChanged,
                                onSubmitted: () {
                                  if (!_verifying) _verify();
                                },
                                onBoxTap: _ensureKeyboard,
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
                                label:
                                    _verifying ? 'Verifying…' : 'Verify code',
                                loading: _verifying,
                                onPressed: busy ? null : _verify,
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: busy ? null : _resend,
                                child: Text(
                                  _resending
                                      ? 'Sending a new code…'
                                      : 'Resend code',
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

/// Digit UI under an always-on-top transparent [TextField] so the first tap
/// and first keystrokes always reach the input (boxes never steal hits).
class _OtpDigitBoxes extends StatelessWidget {
  const _OtpDigitBoxes({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
    required this.onBoxTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool error;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onBoxTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Visual only — never intercepts taps/keys.
          IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, focusNode]),
              builder: (context, _) {
                final code = controller.text;
                return Row(
                  children: List.generate(6, (i) {
                    final filled = i < code.length;
                    final active = focusNode.hasFocus && i == code.length;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 5 ? 0 : 8),
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AuthPalette.field,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: error
                                ? const Color(0xFFD32F2F)
                                : active
                                    ? AuthPalette.orange
                                    : filled
                                        ? AuthPalette.orange
                                            .withValues(alpha: 0.45)
                                        : Colors.transparent,
                            width: active || error ? 1.6 : 1,
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
                );
              },
            ),
          ),
          // Real input on top — full-size hit target, invisible text.
          Positioned.fill(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                signed: false,
                decimal: false,
              ),
              textInputAction: TextInputAction.done,
              maxLength: 6,
              showCursor: false,
              style: const TextStyle(
                color: Colors.transparent,
                fontSize: 16,
                height: 1.2,
              ),
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              enableInteractiveSelection: false,
              keyboardAppearance: Brightness.light,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
              onTap: onBoxTap,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
