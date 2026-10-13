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
    return explainFailure(raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim());
  }

  static String explainFailure(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('not approve') || text.contains('payment_not_approved')) {
      return 'The prompt was not approved. Open it on your phone, enter your PIN, then try again.';
    }
    if (text.contains('insufficient') || text.contains('enough funds')) {
      return 'This wallet does not have enough money for this payment.';
    }
    if (text.contains('payer_not_found') ||
        text.contains('does not belong') ||
        text.contains('does not have an')) {
      return 'This number is not registered on the network you selected.';
    }
    if (text.contains('in progress') || text.contains('payment_in_progress')) {
      return 'A payment is already waiting on this number. Finish that prompt, then try again.';
    }
    if (text.contains('limit')) {
      return 'This wallet has reached its mobile-money limit.';
    }
    if (raw.trim().isEmpty || text.contains('rejected the payout')) {
      return 'The payment was not completed. Approve the prompt on your phone and try again.';
    }
    return raw;
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
  static const _orange = Color(0xFFFF8A00);
  static const _navy = Color(0xFF16284C);
  static const _page = Color(0xFFFFF8F2);

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
      color: _page,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
        children: [
                if (waiting)
                  _WaitingPanel(phone: phoneController.text.trim())
                else ...[
                  _AmountHero(amountMwk: amountMwk),
                  const SizedBox(height: 26),
                  const Text(
                    'Pay with',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _NetworkCard(
                          title: 'Airtel Money',
                          hint: 'Numbers starting 099',
                          color: const Color(0xFFED1C24),
                          selected:
                              operatorId == PawaPayPayment.airtelOperatorId,
                          onTap: busy
                              ? null
                              : () => onOperatorChanged(
                                    PawaPayPayment.airtelOperatorId,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NetworkCard(
                          title: 'TNM Mpamba',
                          hint: 'Numbers starting 088',
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                      letterSpacing: -0.2,
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
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _navy,
                    ),
                    decoration: InputDecoration(
                      hintText: '099 000 0000',
                      prefixIcon: const Icon(
                        Icons.phone_iphone_rounded,
                        color: _orange,
                      ),
                      hintStyle: const TextStyle(
                        color: Color(0xFFC4B8A8),
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFFFE0C2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: _orange, width: 1.8),
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
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFD0CC)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFF9F2D22),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
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
                    ),
                  ),
                ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9A1F), Color(0xFFFF6A00)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _orange.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: busy ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: busy
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            waiting
                                ? 'Waiting for approval'
                                : 'Sending prompt',
                          ),
                        ],
                      )
                    : Text(
                        'Pay MWK ${PawaPayPayment.formatMwk(amountMwk)}',
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 14, color: Color(0xFFB08968)),
              SizedBox(width: 6),
              Text(
                'Secured by PawaPay',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB08968),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmountHero extends StatelessWidget {
  final int amountMwk;
  const _AmountHero({required this.amountMwk});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A1F), Color(0xFFFF6A00)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Amount due',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MWK ${PawaPayPayment.formatMwk(amountMwk)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'A prompt arrives on your phone. Approve it to finish.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFFF8A00),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Check your phone',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: Color(0xFF16284C),
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
              color: Color(0xFF8A5A32),
              fontWeight: FontWeight.w600,
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
    final fill = selected
        ? const Color(0xFFFF8A00).withValues(alpha: 0.08)
        : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: fill,
        border: Border.all(
          color: selected ? const Color(0xFFFF8A00) : const Color(0xFFFFE0C2),
          width: selected ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withValues(alpha: selected ? 0.16 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFFFF8A00),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF16284C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: Color(0xFF8A847C),
                  ),
                ),
              ],
            ),
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
            PawaPayPayment.explainFailure((status['failure'] ?? '').toString()),
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
      backgroundColor: const Color(0xFFFFF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F2),
        foregroundColor: const Color(0xFF16284C),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Payment',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF16284C),
            letterSpacing: -0.2,
          ),
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
