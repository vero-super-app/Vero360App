import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/digital_services_catalog.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Generic ChatGPT-style plan chooser for any subscription hub (Claude, Canva, …).
class SubscriptionPlanPickerPage extends StatefulWidget {
  final DigitalProduct hub;
  final void Function(DigitalProduct plan) onSelectPlan;

  const SubscriptionPlanPickerPage({
    super.key,
    required this.hub,
    required this.onSelectPlan,
  });

  @override
  State<SubscriptionPlanPickerPage> createState() =>
      _SubscriptionPlanPickerPageState();
}

class _SubscriptionPlanPickerPageState
    extends State<SubscriptionPlanPickerPage> {
  static const _orange = Color(0xFFFF6B00);
  static const _orangeDeep = Color(0xFFD94F00);
  static const _bg = Color(0xFFFFFBF6);
  static const _ink = Color(0xFF1A1A1A);

  final _catalog = DigitalServicesCatalog.instance;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _catalog.ensureStarted();
    _catalog.addListener(_onCatalog);
    final plans = _plans;
    if (plans.isNotEmpty) {
      final rec = plans.where((p) => p.recommended);
      _selectedKey = rec.isNotEmpty ? rec.first.key : plans.first.key;
    }
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalog);
    super.dispose();
  }

  void _onCatalog() {
    if (!mounted) return;
    setState(() {
      final plans = _plans;
      if (_selectedKey == null && plans.isNotEmpty) {
        final rec = plans.where((p) => p.recommended);
        _selectedKey = rec.isNotEmpty ? rec.first.key : plans.first.key;
      }
    });
  }

  List<DigitalProduct> get _plans {
    final hubKey = widget.hub.key;
    final out = <DigitalProduct>[];
    for (final p in _catalog.allProducts) {
      if (!p.active) continue;
      if (p.hubKey != hubKey) continue;
      if (p.fixedMwkPrice == null || p.fixedMwkPrice! <= 0) continue;
      out.add(p);
    }
    out.sort((a, b) {
      if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
      return (a.fixedMwkPrice ?? 0).compareTo(b.fixedMwkPrice ?? 0);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    final hub = widget.hub;
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
                      child: _HubArt(hub: hub),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${hub.name} — pick the plan that fits you.',
                      style: const TextStyle(
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
            child: plans.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Plans are not set yet. Check back in a moment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: plans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final plan = plans[i];
                      return _PlanCard(
                        plan: plan,
                        selected: _selectedKey == plan.key,
                        onTap: () => setState(() => _selectedKey = plan.key),
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
                  onPressed: plans.isEmpty
                      ? null
                      : () {
                          final key = _selectedKey;
                          if (key == null) return;
                          final match = plans.where((e) => e.key == key);
                          if (match.isEmpty) return;
                          final product = match.first;
                          final live = _catalog.productByKey(product.key);
                          final chosen = (live != null &&
                                  live.fixedMwkPrice != null &&
                                  live.fixedMwkPrice! > 0)
                              ? live
                              : product;
                          if (chosen.fixedMwkPrice == null ||
                              chosen.fixedMwkPrice! <= 0) {
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
                          widget.onSelectPlan(chosen);
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

class _HubArt extends StatelessWidget {
  const _HubArt({required this.hub});
  final DigitalProduct hub;

  @override
  Widget build(BuildContext context) {
    final url = (hub.imageUrl ?? '').trim();
    if (url.isNotEmpty) {
      return ResilientCachedNetworkImage(
        url: url,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
      );
    }
    final asset = hub.logoAsset;
    if (asset != null && asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          hub.icon ?? Icons.workspace_premium_outlined,
          color: const Color(0xFFD94F00),
        ),
      );
    }
    return Icon(
      hub.icon ?? Icons.workspace_premium_outlined,
      color: const Color(0xFFD94F00),
    );
  }
}

class _PlanCard extends StatelessWidget {
  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF6B7280);

  final DigitalProduct plan;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.fixedMwkPrice;
    final priceText =
        (price != null && price > 0) ? '${formatMwk(price)} / month' : 'Price loading…';
    final badge = plan.planBadge.trim().isNotEmpty
        ? plan.planBadge
        : (plan.brandTag.trim().isNotEmpty ? plan.brandTag : 'Plan');
    final lines = plan.featureLines.isNotEmpty
        ? plan.featureLines
        : (plan.subtitle.trim().isEmpty
            ? const <String>[]
            : plan.subtitle.split('·').map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
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
                      plan.name,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _orange,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
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
              for (final line in lines) ...[
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
