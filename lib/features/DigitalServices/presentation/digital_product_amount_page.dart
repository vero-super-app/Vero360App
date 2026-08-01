import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';

/// Giftsy-style amount picker: USD values + MWK at [kUsdToMwkRate].
class DigitalProductAmountPage extends StatefulWidget {
  final DigitalProduct product;
  final void Function({
    required DigitalProduct product,
    required double selectedUsd,
    required DigitalPayMethod payMethod,
  }) onContinue;

  const DigitalProductAmountPage({
    super.key,
    required this.product,
    required this.onContinue,
  });

  @override
  State<DigitalProductAmountPage> createState() =>
      _DigitalProductAmountPageState();
}

class _DigitalProductAmountPageState extends State<DigitalProductAmountPage> {
  static const _orange = Color(0xFFFF6B00);
  static const _bg = Color(0xFFFFFBF6);
  static const _minUsd = 1.0;
  static const _maxUsd = 500.0;

  late double _selectedUsd;
  DigitalPayMethod _payMethod = DigitalPayMethod.paychangu;

  final _customAmountCtrl = TextEditingController();
  final _customFocus = FocusNode();
  bool _usingCustom = false;

  // Dummy Visa fields (UI only until card charging is wired).
  final _cardNameCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardExpiryCtrl = TextEditingController();
  final _cardCvvCtrl = TextEditingController();
  final _visaFormKey = GlobalKey<FormState>();

  DigitalProduct get p => widget.product;

  @override
  void initState() {
    super.initState();
    _selectedUsd = p.usdAmounts.isNotEmpty ? p.usdAmounts.first : 10;
    _customAmountCtrl.addListener(_onCustomAmountChanged);
  }

  @override
  void dispose() {
    _customAmountCtrl.removeListener(_onCustomAmountChanged);
    _customAmountCtrl.dispose();
    _customFocus.dispose();
    _cardNameCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvvCtrl.dispose();
    super.dispose();
  }

  void _onCustomAmountChanged() {
    final raw = _customAmountCtrl.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return;
    setState(() {
      _usingCustom = true;
      _selectedUsd = parsed.clamp(_minUsd, _maxUsd);
    });
  }

  void _selectPreset(double usd) {
    _customFocus.unfocus();
    setState(() {
      _usingCustom = false;
      _selectedUsd = usd;
      _customAmountCtrl.clear();
    });
  }

  double get _mwk => usdToMwk(_selectedUsd);

  bool get _amountValid =>
      _selectedUsd >= _minUsd && _selectedUsd <= _maxUsd;

  void _onContinue() {
    if (!_amountValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter an amount between ${formatUsd(_minUsd)} and ${formatUsd(_maxUsd)}',
          ),
        ),
      );
      return;
    }

    if (_payMethod == DigitalPayMethod.visa) {
      if (!(_visaFormKey.currentState?.validate() ?? false)) return;
      // Card details collected for later Visa integration — continue as demo.
    }

    widget.onContinue(
      product: p,
      selectedUsd: _selectedUsd,
      payMethod: _payMethod,
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(child: _header(top)),
                SliverToBoxAdapter(child: _brandCard()),
                SliverToBoxAdapter(child: _amountsSection()),
                SliverToBoxAdapter(child: _customAmountField()),
                SliverToBoxAdapter(child: _payMethodsSection()),
                if (_payMethod == DigitalPayMethod.visa)
                  SliverToBoxAdapter(child: _visaFields()),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _header(double topInset) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topInset + 4, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.accent, Color.lerp(p.accent, Colors.black, 0.25)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
            child: Row(
              children: [
                _logoBadge(size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.brandTag.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBadge({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: p.logoAsset != null
          ? Image.asset(
              p.logoAsset!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                p.icon ?? Icons.card_giftcard_rounded,
                color: p.accent,
                size: size * 0.45,
              ),
            )
          : Icon(
              p.icon ?? Icons.card_giftcard_rounded,
              color: p.accent,
              size: size * 0.45,
            ),
    );
  }

  Widget _brandCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE8CC)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: _orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Instant digital delivery · Choose or type your amount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Other values',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: p.usdAmounts.map((usd) {
              final selected = !_usingCustom && usd == _selectedUsd;
              final mwk = usdToMwk(usd);
              return GestureDetector(
                onTap: () => _selectPreset(usd),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: (MediaQuery.of(context).size.width - 42) / 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _orange : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? _orange : const Color(0xFFFFE8CC),
                      width: selected ? 1.6 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: _orange.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatUsd(usd),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color:
                              selected ? Colors.white : const Color(0xFF111111),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMwk(mwk),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _customAmountField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Or type your amount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _usingCustom ? _orange : const Color(0xFFFFE8CC),
                width: _usingCustom ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'USD',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: _orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _customAmountCtrl,
                    focusNode: _customFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onTap: () => setState(() => _usingCustom = true),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111),
                    ),
                    decoration: InputDecoration(
                      hintText: '35',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_usingCustom && _customAmountCtrl.text.trim().isNotEmpty)
                  Text(
                    formatMwk(_mwk),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Text(
          //   'Converted at 1 USD = ${kUsdToMwkRate.toStringAsFixed(0)} MWK',
          //   style: TextStyle(
          //     fontSize: 11,
          //     fontWeight: FontWeight.w600,
          //     color: Colors.grey.shade600,
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _payMethodsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 10),
          _payTile(
            method: DigitalPayMethod.paychangu,
            title: 'Mobile money & bank',
            subtitle: 'Pay in MWK via Airtel, Mpamba, or bank',
            icon: Icons.phone_android_rounded,
          ),
          const SizedBox(height: 10),
          _payTile(
            method: DigitalPayMethod.visa,
            title: 'Visa / card',
            subtitle: 'Enter card details ',
            icon: Icons.credit_card_rounded,
          ),
        ],
      ),
    );
  }

  Widget _payTile({
    required DigitalPayMethod method,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _payMethod == method;
    return GestureDetector(
      onTap: () => setState(() => _payMethod = method),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _orange : const Color(0xFFE8E8E8),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _orange, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? _orange : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _visaFields() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Form(
        key: _visaFormKey,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.credit_card_rounded, color: _orange, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Card details',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Color(0xFF111111),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'coming soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'coming soon',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              _field(
                controller: _cardNameCtrl,
                label: 'Name on card',
                hint: 'vero360',
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  if ((v ?? '').trim().length < 2) return 'Enter name on card';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              _field(
                controller: _cardNumberCtrl,
                label: 'Card number',
                hint: '4242 4242 4242 4242',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16),
                  _CardNumberFormatter(),
                ],
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 13) return 'Enter a valid card number';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _cardExpiryCtrl,
                      label: 'Expiry',
                      hint: 'MM/YY',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                        _ExpiryFormatter(),
                      ],
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(t)) {
                          return 'MM/YY';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _cardCvvCtrl,
                      label: 'CVV',
                      hint: '123',
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.length < 3) return 'CVV';
                        return null;
                      },
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool obscureText = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: Color(0xFF111111),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade700,
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: const Color(0xFFFFFBF6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _orange, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatUsd(_selectedUsd),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111111),
                    ),
                  ),
                  Text(
                    formatMwk(_mwk),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _orange,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    var text = digits;
    if (digits.length >= 3) {
      text = '${digits.substring(0, 2)}/${digits.substring(2)}';
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
