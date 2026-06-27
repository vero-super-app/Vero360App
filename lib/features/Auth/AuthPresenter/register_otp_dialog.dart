import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef OtpVerifyCallback = Future<bool> Function(String code);
typedef OtpResendCallback = Future<bool> Function();

class RegisterOtpDialog extends StatefulWidget {
  final String identifier;
  final String channel; // 'email' | 'phone'
  final OtpVerifyCallback onVerify;
  final OtpResendCallback onResend;

  const RegisterOtpDialog({
    super.key,
    required this.identifier,
    required this.channel,
    required this.onVerify,
    required this.onResend,
  });

  @override
  State<RegisterOtpDialog> createState() => _RegisterOtpDialogState();
}

class _RegisterOtpDialogState extends State<RegisterOtpDialog> {
  static const _brandOrange = Color(0xFFFF8A00);

  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _channelHint =>
      widget.channel == 'email' ? 'email' : 'phone number';

  Future<void> _verify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final ok = await widget.onVerify(_codeCtrl.text.trim());
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = 'Invalid or expired code. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
      if (!ok) {
        setState(() => _error = 'Could not resend code. Try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify your account'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 6-digit code we sent to your $_channelHint:',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              widget.identifier,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofocus: true,
              enabled: !_verifying,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 12,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                filled: true,
                fillColor: const Color(0xFFF7F7F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: _brandOrange, width: 1.2),
                ),
              ),
              validator: (v) {
                final code = v?.trim() ?? '';
                if (code.length != 6) return 'Enter the 6-digit code';
                return null;
              },
              onFieldSubmitted: (_) {
                if (!_verifying) _verify();
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            if (_verifying) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_verifying || _resending) ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_verifying || _resending) ? null : _resend,
          child: Text(_resending ? 'Sending…' : 'Resend code'),
        ),
        ElevatedButton(
          onPressed: _verifying ? null : _verify,
          style: ElevatedButton.styleFrom(backgroundColor: _brandOrange),
          child: Text(_verifying ? 'Verifying…' : 'Verify'),
        ),
      ],
    );
  }
}
