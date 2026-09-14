import 'package:flutter/material.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/digital_services_catalog.dart';
import 'package:vero360_app/features/DigitalServices/netflix_plans.dart';
import 'dart:async';

/// Netflix plan chooser — Mobile / Basic / Standard / Premium (Vero360 orange UI).
class NetflixPlanPickerPage extends StatefulWidget {
  final void Function(DigitalProduct plan) onSelectPlan;

  const NetflixPlanPickerPage({
    super.key,
    required this.onSelectPlan,
  });

  @override
  State<NetflixPlanPickerPage> createState() => _NetflixPlanPickerPageState();
}

class _NetflixPlanPickerPageState extends State<NetflixPlanPickerPage> {
  static const _orange = Color(0xFFFF6B00);
  static const _orangeDeep = Color(0xFFD94F00);
  static const _bg = Color(0xFFFFFBF6);
  static const _card = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF6B7280);

  final _catalog = DigitalServicesCatalog.instance;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _catalog.ensureStarted();
    _catalog.addListener(_onCatalog);
    _selectedKey = kNetflixPlanSpecs
        .firstWhere((s) => s.mostPopular, orElse: () => kNetflixPlanSpecs.last)
        .key;
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    super.dispose();
  }

  void _onCatalog() {
    if (mounted) setState(() {});
  }

  DigitalProduct? _productFor(NetflixPlanSpec spec) {
    for (final p in _catalog.allProducts) {
      if (p.key == spec.key && p.active) return p;
    }
    // Shell product without price while catalog warms — never use hardcoded MWK.
    for (final p in kNetflixPlanProducts) {
      if (p.key == spec.key) {
        return p.copyWith(clearFixedMwkPrice: true);
      }
    }
    return null;
  }

  List<({NetflixPlanSpec spec, DigitalProduct product})> get _plans {
    final out = <({NetflixPlanSpec spec, DigitalProduct product})>[];
    for (final s in kNetflixPlanSpecs) {
      final p = _productFor(s);
      if (p != null) out.add((spec: s, product: p));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Choose your plan',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_orange, _orangeDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _orange.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: Colors.white,
                      child: Image.asset(
                        'assets/brands/netflix.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.movie_creation_outlined,
                          color: _orangeDeep,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Netflix — pick the plan that fits you. Change anytime.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: plans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final entry = plans[i];
                final selected = _selectedKey == entry.spec.key;
                final price = entry.product.fixedMwkPrice;
                return _PlanCard(
                  spec: entry.spec,
                  priceMwk: price,
                  selected: selected,
                  onTap: () => setState(() => _selectedKey = entry.spec.key),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    final key = _selectedKey;
                    if (key == null) return;
                    final match = plans.where((e) => e.spec.key == key);
                    if (match.isEmpty) return;
                    final product = match.first.product;
                    final live =
                        _catalog.productByKey(product.key) ?? product;
                    if (live.fixedMwkPrice == null ||
                        live.fixedMwkPrice! <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Price not set yet. Please try again in a moment.',
                          ),
                        ),
                      );
                      unawaited(_catalog.ensureStarted());
                      return;
                    }
                    // Keep this page under checkout so Back returns here.
                    widget.onSelectPlan(live);
                  },
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF6B7280);

  final NetflixPlanSpec spec;
  final double? priceMwk;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.spec,
    required this.priceMwk,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final priceText = (priceMwk != null && priceMwk! > 0)
        ? '${formatMwk(priceMwk!)} / month'
        : 'Price from admin…';
    return Material(
      color: Colors.white,
      elevation: selected ? 3 : 0,
      shadowColor: _orange.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _orange : const Color(0xFFE8E4DE),
              width: selected ? 2 : 1,
            ),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      _orange.withValues(alpha: 0.08),
                      Colors.white,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (spec.mostPopular)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _orange,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Most popular',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected ? _orange : const Color(0xFFC4C0B8),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                priceText,
                style: const TextStyle(
                  color: _orange,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              for (final line in spec.featureLines) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: _orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13.2,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
