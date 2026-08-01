import 'package:cloud_functions/cloud_functions.dart';
import 'package:didit_sdk/sdk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends State<KycVerificationScreen> {
  static const _brandOrange = Color(0xFFFF8A00);

  bool _busy = false;
  String? _error;

  Future<void> _startVerification() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createDiditSession')
          .call();

      final data = result.data;
      final sessionToken = data is Map
          ? (data['session_token'] ?? data['sessionToken'])?.toString()
          : null;

      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception('Could not start verification. Try again.');
      }

      if (!mounted) return;

      final verificationResult =
          await DiditSdk.startVerification(sessionToken);

      if (!mounted) return;

      switch (verificationResult) {
        case VerificationCompleted():
          ToastHelper.showCustomToast(
            context,
            'Verification submitted — under review',
            isSuccess: true,
            errorMessage: '',
          );
          Navigator.of(context).pop(true);
        case VerificationCancelled():
          setState(() {
            _error = 'Verification was cancelled. You can try again.';
          });
        case VerificationFailed(:final error):
          setState(() {
            _error = error.message.trim().isNotEmpty
                ? error.message
                : 'Verification failed. You can try again.';
          });
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = (e.message?.trim().isNotEmpty == true)
            ? e.message!
            : 'Could not start verification. Try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Identity verification'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101010),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verify your identity',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: Color(0xFF101010),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We will guide you through a quick ID scan and face check. '
                'This usually takes about a minute.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet('Have a valid Malawian ID ready'),
                    const SizedBox(height: 8),
                    _bullet('Allow camera access when prompted'),
                    const SizedBox(height: 8),
                    _bullet('Complete the liveness / face match step'),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _startVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _busy
                            ? 'Starting…'
                            : (_error != null ? 'Retry' : 'Start verification'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, color: _brandOrange, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
