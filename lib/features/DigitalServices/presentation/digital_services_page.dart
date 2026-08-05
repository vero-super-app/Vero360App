import 'package:flutter/material.dart';
import 'package:vero360_app/features/DigitalServices/digital_product.dart';
import 'package:vero360_app/features/DigitalServices/presentation/digital_product_amount_page.dart';

class DigitalServicesPage extends StatefulWidget {
  final void Function({
    required DigitalProduct product,
    required double selectedUsd,
    required DigitalPayMethod payMethod,
  }) onContinueCheckout;

  const DigitalServicesPage({super.key, required this.onContinueCheckout});

  @override
  State<DigitalServicesPage> createState() => _DigitalServicesPageState();
}

class _DigitalServicesPageState extends State<DigitalServicesPage>
    with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFFF6B00);
  static const _orangeDeep = Color(0xFFD94F00);
  static const _bg = Color(0xFFFFFBF6);

  final _searchCtrl = TextEditingController();
  String _category = 'all';
  String _query = '';
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q == _query) return;
      setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _enter.dispose();
    super.dispose();
  }

  List<DigitalProduct> get _filtered {
    return kAllDigitalProducts.where((p) {
      final catOk = _category == 'all' || p.category == _category;
      if (!catOk) return false;
      if (_query.isEmpty) return true;
      return p.name.toLowerCase().contains(_query) ||
          p.subtitle.toLowerCase().contains(_query) ||
          p.brandTag.toLowerCase().contains(_query);
    }).toList();
  }

  void _openProduct(DigitalProduct p) {
    // Fixed-price streaming codes skip the USD amount picker.
    if (!p.usesAmountPicker) {
      widget.onContinueCheckout(
        product: p,
        selectedUsd: 0,
        payMethod: DigitalPayMethod.paychangu,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DigitalProductAmountPage(
          product: p,
          onContinue: ({
            required product,
            required selectedUsd,
            required payMethod,
          }) {
            Navigator.of(context).pop(); // close amount page
            widget.onContinueCheckout(
              product: product,
              selectedUsd: selectedUsd,
              payMethod: payMethod,
            );
          },
        ),
      ),
    );
  }

  List<DigitalProduct> get _featured => kAllDigitalProducts
      .where((p) => p.category == 'gift_cards' || p.category == 'gaming')
      .take(6)
      .toList();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final width = media.size.width;
    final textScale = media.textScaler.scale(1.0).clamp(1.0, 1.2);
    final items = _filtered;
    final narrow = width < 360;
    final gridRatio = narrow ? 0.72 : 0.78;
    final featuredH = narrow ? 128.0 : 140.0;
    final featuredW = narrow ? 200.0 : 228.0;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(top, narrow, textScale)),
          SliverToBoxAdapter(child: _buildSearch()),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverToBoxAdapter(child: _buildCategories()),
          if (_category == 'all' && _query.isEmpty)
            SliverToBoxAdapter(
              child: _buildFeaturedStrip(featuredH, featuredW),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _category == 'all'
                          ? 'All services'
                          : kDigitalCategories
                              .firstWhere((c) => c.id == _category)
                              .label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: narrow ? 15 : 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111111),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptySearch(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: gridRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = items[i];
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _enter,
                        curve: Interval(
                          (0.15 + i * 0.04).clamp(0.0, 1.0),
                          1.0,
                          curve: Curves.easeOut,
                        ),
                      ),
                      child: _GiftCardTile(
                        product: p,
                        compact: narrow,
                        onTap: () => _openProduct(p),
                      ),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(double topInset, bool narrow, double textScale) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_orangeDeep, _orange, Color(0xFFFF9A3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, topInset + 2, 12, narrow ? 18 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'DIGITAL · INSTANT DELIVERY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Gift Cards & Digital Services',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (narrow ? 22 : 26) / textScale,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Visa, PayPal, gaming, streaming & more',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: narrow ? 12 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeaderStat(
                        icon: Icons.bolt_rounded,
                        label: '${kAllDigitalProducts.length}+ codes',
                      ),
                      const _HeaderStat(
                        icon: Icons.lock_rounded,
                        label: 'Secure pay',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFE8CC)),
          boxShadow: [
            BoxShadow(
              color: _orange.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search Visa, PayPal, Steam…',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 22),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: kDigitalCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = kDigitalCategories[i];
          final selected = _category == c.id;
          return GestureDetector(
            onTap: () => setState(() => _category = c.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? _orange : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: selected ? _orange : const Color(0xFFFFE8CC),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    c.icon,
                    size: 15,
                    color: selected ? Colors.white : _orange,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xFF111111),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedStrip(double height, double cardWidth) {
    final featured = _featured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Popular gift cards',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111111),
              letterSpacing: -0.3,
            ),
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = featured[i];
              return GestureDetector(
                onTap: () => _openProduct(p),
                child: _FeaturedGiftCard(product: p, width: cardWidth),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeaderStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedGiftCard extends StatelessWidget {
  final DigitalProduct product;
  final double width;

  const _FeaturedGiftCard({required this.product, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            product.accent,
            Color.lerp(product.accent, Colors.black, 0.25)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: product.accent.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.brandTag.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            product.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftCardTile extends StatefulWidget {
  final DigitalProduct product;
  final bool compact;
  final VoidCallback onTap;

  const _GiftCardTile({
    required this.product,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_GiftCardTile> createState() => _GiftCardTileState();
}

class _GiftCardTileState extends State<_GiftCardTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final compact = widget.compact;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFE8CC)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        p.accent,
                        Color.lerp(p.accent, Colors.black, 0.22)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 72),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            p.brandTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: p.logoAsset != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.asset(
                                  p.logoAsset!,
                                  width: compact ? 36 : 42,
                                  height: compact ? 36 : 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    p.icon ?? Icons.card_giftcard_rounded,
                                    color: Colors.white,
                                    size: compact ? 28 : 32,
                                  ),
                                ),
                              )
                            : Icon(
                                p.icon ?? Icons.card_giftcard_rounded,
                                color: Colors.white,
                                size: compact ? 28 : 32,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 10,
                    compact ? 6 : 8,
                    compact ? 8 : 10,
                    compact ? 6 : 8,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF111111),
                                ),
                              ),
                              if (p.fixedMwkPrice != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  p.priceLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: compact ? 11 : 12,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFF6B00),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF4E6),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 12,
                                    color: Color(0xFFFF6B00),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text(
              'No digital services found',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111111),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try another brand or category',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
