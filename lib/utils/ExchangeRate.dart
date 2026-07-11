import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Matches homepage brand tokens (avoid importing homepage — circular).
class _FxColors {
  static const brandOrange = Color(0xFFFF6B00);
  static const brandOrangeDeep = Color(0xFFD94F00);
  static const brandOrangeLight = Color(0xFFFF9A3C);
  static const brandOrangeSoft = Color(0xFFFFE8CC);
  static const brandOrangePale = Color(0xFFFFF4E6);
  static const title = Color(0xFF111111);
  static const body = Color(0xFF666666);
  static const pageBg = Color(0xFFFFFBF6);
  static const card = Color(0xFFFFFFFF);
}

const _kFxGradient = LinearGradient(
  colors: [_FxColors.brandOrangeDeep, _FxColors.brandOrangeLight],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

final _amountFmt = NumberFormat('#,##0.00', 'en_US');
final _rateFmt = NumberFormat('#,##0.####', 'en_US');
final _intCommaFmt = NumberFormat('#,##0', 'en_US');

/// Formats digits with thousand separators while typing (e.g. 15000 → 15,000).
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    final cleaned = text.replaceAll(',', '');
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(cleaned)) {
      return oldValue;
    }

    final endsWithDot = cleaned.endsWith('.');
    final parts = cleaned.split('.');
    final intPart = parts[0];
    final fracPart = parts.length > 1 ? parts[1] : null;

    String formattedInt;
    if (intPart.isEmpty) {
      formattedInt = endsWithDot || fracPart != null ? '0' : '';
    } else {
      formattedInt = _intCommaFmt.format(int.parse(intPart));
    }

    var formatted = formattedInt;
    if (endsWithDot) {
      formatted = '$formattedInt.';
    } else if (fracPart != null) {
      formatted = '$formattedInt.$fracPart';
    }

    final selectionIndexFromEnd =
        newValue.text.length - newValue.selection.end;
    final newSelection = (formatted.length - selectionIndexFromEnd)
        .clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newSelection),
    );
  }
}

class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({super.key});

  @override
  State<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  Map<String, dynamic>? exchangeRates;
  bool isLoading = true;
  final TextEditingController inputController = TextEditingController();
  String baseCurrency = 'USD';
  double inputAmount = 0.0;

  final List<String> currencies = ['MWK', 'GBP', 'USD', 'CNY', 'ZAR', 'TZS'];

  static const _currencyNames = {
    'MWK': 'Malawian Kwacha',
    'GBP': 'British Pound',
    'USD': 'US Dollar',
    'CNY': 'Chinese Yuan',
    'ZAR': 'South African Rand',
    'TZS': 'Tanzanian Shilling',
  };

  @override
  void initState() {
    super.initState();
    fetchExchangeRates();
  }

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }

  Future<void> fetchExchangeRates() async {
    final apiUrl =
        'https://api.exchangerate-api.com/v4/latest/$baseCurrency';

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          exchangeRates = jsonDecode(response.body)['rates'];
          isLoading = false;
        });
      } else {
        showError(
          'Failed to load exchange rates. Error code: ${response.statusCode}',
        );
      }
    } catch (error) {
      showError('An error occurred while fetching exchange rates: $error');
    }
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _FxColors.brandOrangeDeep,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    setState(() {
      isLoading = false;
    });
  }

  void updateConversion() {
    final raw = inputController.text.replaceAll(',', '');
    setState(() {
      inputAmount = double.tryParse(raw) ?? 0.0;
    });
  }

  String _formatAmount(double value) {
    if (value == 0) return '0.00';
    return _amountFmt.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FxColors.pageBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 148,
            pinned: true,
            backgroundColor: _FxColors.brandOrange,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: _kFxGradient),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'Forex Rates',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Live rates · for reference only',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: _FxColors.brandOrange,
                ),
              ),
            )
          else if (exchangeRates == null)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'Failed to load exchange rates',
                  style: TextStyle(color: _FxColors.body, fontSize: 16),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AmountCard(
                      controller: inputController,
                      baseCurrency: baseCurrency,
                      currencies: currencies,
                      onAmountChanged: (_) => updateConversion(),
                      onCurrencyChanged: (newValue) async {
                        setState(() {
                          baseCurrency = newValue;
                          isLoading = true;
                        });
                        await fetchExchangeRates();
                        updateConversion();
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Converts to',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _FxColors.title,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...currencies.where((c) => c != baseCurrency).map((currency) {
                      final rate = exchangeRates![currency];
                      final converted =
                          rate != null ? (inputAmount * (rate as num)) : 0.0;
                      final rateNum = rate is num ? rate.toDouble() : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RateRow(
                          flag: _getFlag(currency),
                          code: currency,
                          name: _currencyNames[currency] ?? currency,
                          amount: _formatAmount(converted.toDouble()),
                          rateLabel: inputAmount > 0
                              ? '1 $baseCurrency = ${_rateFmt.format(rateNum)} $currency'
                              : 'Rate: ${_rateFmt.format(rateNum)}',
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getFlag(String currency) {
    const flagMap = {
      'MWK': '🇲🇼',
      'GBP': '🇬🇧',
      'USD': '🇺🇸',
      'CNY': '🇨🇳',
      'ZAR': '🇿🇦',
      'TZS': '🇹🇿',
    };
    return flagMap[currency] ?? '🏳️';
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.controller,
    required this.baseCurrency,
    required this.currencies,
    required this.onAmountChanged,
    required this.onCurrencyChanged,
  });

  final TextEditingController controller;
  final String baseCurrency;
  final List<String> currencies;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _FxColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _FxColors.brandOrangeSoft),
        boxShadow: [
          BoxShadow(
            color: _FxColors.brandOrange.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You convert',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _FxColors.body,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    _ThousandsSeparatorInputFormatter(),
                  ],
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _FxColors.title,
                    letterSpacing: -0.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: Color(0xFFCCCCCC),
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: onAmountChanged,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _FxColors.brandOrangePale,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _FxColors.brandOrangeSoft),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: baseCurrency,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _FxColors.brandOrange,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _FxColors.brandOrange,
                    ),
                    dropdownColor: _FxColors.card,
                    borderRadius: BorderRadius.circular(12),
                    items: currencies.map((currency) {
                      return DropdownMenuItem<String>(
                        value: currency,
                        child: Text(currency),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) onCurrencyChanged(value);
                    },
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

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.flag,
    required this.code,
    required this.name,
    required this.amount,
    required this.rateLabel,
  });

  final String flag;
  final String code;
  final String name;
  final String amount;
  final String rateLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _FxColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _FxColors.brandOrangeSoft.withOpacity(0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _FxColors.brandOrangePale,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(flag, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _FxColors.title,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _FxColors.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _FxColors.brandOrangeDeep,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rateLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: _FxColors.body,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
