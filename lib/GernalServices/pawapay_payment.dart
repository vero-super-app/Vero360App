import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Customer mobile-money payments. The API token stays in Cloud Functions.
class PawaPayPayment {
  static const airtelOperatorId = '20be6c20-adeb-4b5b-a7ba-0769820df4fb';
  static const tnmOperatorId = '27494cb5-ba9e-437f-a114-4e7a7686bcca';

  static String localPhone(String raw) {
    var mobile = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (mobile.startsWith('+265')) mobile = '0${mobile.substring(4)}';
    else if (mobile.startsWith('265') && mobile.length > 3) {
      mobile = '0${mobile.substring(3)}';
    }
    return mobile;
  }

  static String? operatorForPhone(String raw) {
    final mobile = localPhone(raw);
    if (mobile.startsWith('09')) return airtelOperatorId;
    if (mobile.startsWith('08')) return tnmOperatorId;
    return null;
  }

  static String readableError(Object error) {
    final raw = error is FirebaseFunctionsException
        ? (error.message ?? error.toString())
        : error.toString();
    final text = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (text.toLowerCase().contains('api token')) {
      return 'PawaPay rejected the API token. Create it in the same dashboard you are using, Sandbox or Live, then set it again.';
    }
    return text;
  }

  static String formatMwk(int amount) {
    final digits = amount.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static Future<String> createDeposit({
    required int amountMwk,
    required String phone,
    required String operatorId,
    required String reference,
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('createPawaPayDeposit');
    final result = await callable.call(<String, dynamic>{
      'amount': amountMwk,
      'phone': phone,
      'operatorId': operatorId,
      'reference': reference,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final depositId = (data['depositId'] ?? '').toString().trim();
    if (depositId.isEmpty) {
      throw Exception('PawaPay did not start the payment.');
    }
    return depositId;
  }

  static Future<Map<String, dynamic>> readStatus(String depositId) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('getPawaPayDepositStatus');
    final result = await callable.call(<String, dynamic>{
      'depositId': depositId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}

class PawaPayCheckoutView extends StatelessWidget {
  final int amountMwk;
  final TextEditingController phoneController;
  final String operatorId;
  final ValueChanged<String> onOperatorChanged;
  final VoidCallback onSubmit;
  final bool busy;
  final bool waiting;
  final String message;

  const PawaPayCheckoutView({
    super.key,
    required this.amountMwk,
    required this.phoneController,
    required this.operatorId,
    required this.onOperatorChanged,
    required this.onSubmit,
    required this.busy,
    required this.waiting,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: const Color(0xFFF6F4F0),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (waiting) _WaitingPanel(phone: phoneController.text.trim())
                else ...[
                  const Text(
                    'Amount',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B6760),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MWK ${PawaPayPayment.formatMwk(amountMwk)}',
                    style: const TextStyle(
                      fontSize: 40,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.2,
                      color: Color(0xFF161513),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A prompt will arrive on this number. Approve it to finish payment.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Color(0xFF5C5852),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Network',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF161513),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _NetworkCard(
                          title: 'Airtel Money',
                          hint: '099',
                          color: const Color(0xFFED1C24),
                          selected: operatorId == PawaPayPayment.airtelOperatorId,
                          onTap: busy
                              ? null
                              : () => onOperatorChanged(
                                    PawaPayPayment.airtelOperatorId,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NetworkCard(
                          title: 'TNM Mpamba',
                          hint: '088',
                          color: const Color(0xFFF5B800),
                          selected: operatorId == PawaPayPayment.tnmOperatorId,
                          onTap: busy
                              ? null
                              : () => onOperatorChanged(
                                    PawaPayPayment.tnmOperatorId,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Mobile number',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF161513),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneController,
                    enabled: !busy,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                      LengthLimitingTextInputFormatter(13),
                    ],
                    onChanged: (value) {
                      final guessed = PawaPayPayment.operatorForPhone(value);
                      if (guessed != null && guessed != operatorId) {
                        onOperatorChanged(guessed);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                    decoration: InputDecoration(
                      hintText: '099 000 0000',
                      hintStyle: const TextStyle(
                        color: Color(0xFFB0AAA2),
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE6E1D8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE6E1D8)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF161513),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
                if (message.isNotEmpty && !waiting) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFD0CC)),
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xFF9F2D22),
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: busy ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF161513),
                      disabledBackgroundColor: const Color(0xFF161513),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      waiting
                          ? 'Waiting for approval'
                          : 'Pay MWK ${PawaPayPayment.formatMwk(amountMwk)}',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Airtel Money and TNM Mpamba · confirmed by PawaPay',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF8A847C)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingPanel extends StatelessWidget {
  final String phone;
  const _WaitingPanel({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF161513),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Check your phone',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: Color(0xFF161513),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            phone.isEmpty
                ? 'Approve the mobile-money prompt to complete this payment.'
                : 'Approve the prompt sent to $phone.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Color(0xFF5C5852),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final String title;
  final String hint;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const _NetworkCard({
    required this.title,
    required this.hint,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF161513) : const Color(0xFFE6E1D8),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_rounded, size: 18, color: Color(0xFF161513)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF161513),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A847C)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone prompt used by ride checkout. Pops the deposit id when PawaPay confirms.
class PawaPayCheckoutPage extends StatefulWidget {
  final int amountMwk;
  final String reference;
  final String? initialPhone;

  const PawaPayCheckoutPage({
    super.key,
    required this.amountMwk,
    required this.reference,
    this.initialPhone,
  });

  @override
  State<PawaPayCheckoutPage> createState() => _PawaPayCheckoutPageState();
}

class _PawaPayCheckoutPageState extends State<PawaPayCheckoutPage> {
  late final TextEditingController _phone;
  String _operator = PawaPayPayment.airtelOperatorId;
  bool _busy = false;
  bool _waiting = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    final local = PawaPayPayment.localPhone(widget.initialPhone ?? '');
    _phone = TextEditingController(text: local);
    _operator = PawaPayPayment.operatorForPhone(local) ?? _operator;
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _waiting = false;
      _message = '';
    });
    try {
      final depositId = await PawaPayPayment.createDeposit(
        amountMwk: widget.amountMwk,
        phone: _phone.text.trim(),
        operatorId: _operator,
        reference: widget.reference,
      );
      if (!mounted) return;
      setState(() => _waiting = true);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        final status = await PawaPayPayment.readStatus(depositId);
        final state = (status['status'] ?? '').toString();
        if (state == 'completed') {
          if (mounted) Navigator.of(context).pop(depositId);
          return;
        }
        if (state == 'failed') {
          throw Exception(
            (status['failure'] ?? 'The payment was declined.').toString(),
          );
        }
      }
      throw Exception('Still waiting for the phone prompt. Try again.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waiting = false;
        _message = PawaPayPayment.readableError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F4F0),
        foregroundColor: const Color(0xFF161513),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Pay',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: PawaPayCheckoutView(
        amountMwk: widget.amountMwk,
        phoneController: _phone,
        operatorId: _operator,
        onOperatorChanged: (value) => setState(() => _operator = value),
        onSubmit: _pay,
        busy: _busy,
        waiting: _waiting,
        message: _message,
      ),
    );
  }
}
