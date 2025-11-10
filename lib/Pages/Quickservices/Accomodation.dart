import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/models/hostel_model.dart';
import 'package:vero360_app/services/hostel_service.dart';

class AccomodationPage extends StatefulWidget {
  const AccomodationPage({Key? key}) : super(key: key);

  @override
  State<AccomodationPage> createState() => _AccomodationPageState();
}

class _AccomodationPageState extends State<AccomodationPage> {
  final _service = AccommodationService();
  late Future<List<Accommodation>> _future;

  final _filters = const ['All', 'Apartments', 'Houses','Hostels', 'BnB', 'Hotels','Lodge'];
  String _active = 'All';
  bool _animateIn = false;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchAll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateIn = true);
    });
  }

  Future<void> _reload() async => setState(() => _future = _service.fetchAll());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Brand.bg,
      body: RefreshIndicator(
        color: _Brand.orange,
        onRefresh: _reload,
        child: FutureBuilder<List<Accommodation>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }
            if (snap.hasError) {
              return _Error(msg: 'Failed to load.\n${snap.error}', onRetry: _reload);
            }

            final data = (snap.data ?? <Accommodation>[]);
            final filtered = data.where((a) {
              final type = (a.accommodationType ?? '').toLowerCase();
              if (_active == 'All') return true;
              if (_active == 'Apartments') return type.contains('apartment');
              if (_active == 'Houses') return type.contains('house');
              return true;
            }).toList();

            final topDeals = filtered.isNotEmpty ? filtered : _placeholders(tag: 'Deal');
            final recommended = filtered.isNotEmpty ? filtered.reversed.toList() : _placeholders(tag: 'Reco');
            final newOffers = filtered.length >= 4 ? filtered.sublist(0, 4) : _placeholders(tag: 'New');

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _DiscoverAppBar(animateIn: _animateIn),
                SliverToBoxAdapter(
                  child: AnimatedOpacity(
                    opacity: _animateIn ? 1 : 0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: _FilterRow(
                      filters: _filters,
                      active: _active,
                      onPick: (v) => setState(() => _active = v),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // Top deals
                SliverToBoxAdapter(child: _SectionHeader(title: 'Top deals', emoji: '🔥', onSeeAll: () {})),
                _GridTwo(items: topDeals),

                // Recommended
                SliverToBoxAdapter(child: _SectionHeader(title: 'Recommended for you', emoji: '✨', onSeeAll: () {})),
                _GridTwo(items: recommended),

                // New offers
                SliverToBoxAdapter(child: _SectionHeader(title: 'New offers', emoji: '🆕', onSeeAll: () {})),
                _GridTwo(items: newOffers),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
     // bottomNavigationBar: const Bottomnavbar(email: '',),
    );
  }

  List<Accommodation> _placeholders({required String tag}) {
    return List.generate(
      6,
      (i) => Accommodation(
        id: -1000 - i,
        name: '${tag == "Deal" ? "Indigo" : tag == "Reco" ? "Emerald" : "Sapphire"} House',
        location: 'Abuja, Nigeria',
        price: 38000,
        description: 'This place is located in the middle of Abuja. There is nightlife and a poolside.',
        accommodationType: 'Apartment',
        owner: null,
      ),
    );
  }
}

/*────────────────────────  APP BAR  ────────────────────────*/

class _DiscoverAppBar extends StatelessWidget {
  final bool animateIn;
  const _DiscoverAppBar({required this.animateIn});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 132,
      elevation: 0,
      backgroundColor: Colors.white,
      titleSpacing: 0,
      centerTitle: false,
      title: Row(
        children: const [
          SizedBox(width: 12),
          Text('Discover', style: TextStyle(color: _Brand.title, fontWeight: FontWeight.w900)),
        ],
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: AnimatedOpacity(
          opacity: animateIn ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 72, 16, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.2, -1),
                end: Alignment(1, 1),
                colors: [Color(0xFFFFF3E3), Colors.white],
              ),
            ),
            child: _HeroCard(),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22FF8A00)),
        boxShadow: [
          BoxShadow(color: _Brand.orange.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: const [
          Text('🏠', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Find your next stay — curated deals near you',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _Brand.title, fontWeight: FontWeight.w800),
            ),
          ),
          Icon(Icons.tune_rounded, color: _Brand.orange),
        ],
      ),
    );
  }
}

/*────────────────────────  SECTIONS  ────────────────────────*/

class _FilterRow extends StatelessWidget {
  final List<String> filters;
  final String active;
  final ValueChanged<String> onPick;
  const _FilterRow({required this.filters, required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = filters[i];
          final sel = f == active;
          return AnimatedScale(
            scale: sel ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: ChoiceChip(
              selected: sel,
              onSelected: (_) => onPick(f),
              label: Text(
                f,
                style: TextStyle(fontWeight: FontWeight.w800, color: sel ? Colors.white : _Brand.title),
              ),
              selectedColor: _Brand.orange,
              backgroundColor: const Color(0xFFF2F3F7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: sel ? _Brand.orange : const Color(0xFFE9E9EC)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String emoji;
  final VoidCallback onSeeAll;
  const _SectionHeader({required this.title, required this.onSeeAll, this.emoji = ''});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Text(
            '${emoji.isNotEmpty ? '$emoji  ' : ''}$title',
            style: const TextStyle(color: _Brand.title, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const Spacer(),
          TextButton(
            onPressed: onSeeAll,
            child: const Text('See all', style: TextStyle(color: _Brand.orange, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Two-column grid (taller tiles to avoid overflow)
class _GridTwo extends StatelessWidget {
  final List<Accommodation> items;
  const _GridTwo({required this.items});

  @override
  Widget build(BuildContext context) {
    final count = math.min(items.length, 8);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _StayCard(a: items[index]),
          childCount: count,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          // ↓ more height per tile fixes RenderFlex overflow on small screens
          childAspectRatio: 0.72,
        ),
      ),
    );
  }
}

/*────────────────────────  CARD  ────────────────────────*/

class _StayCard extends StatefulWidget {
  final Accommodation a;
  const _StayCard({required this.a});

  @override
  State<_StayCard> createState() => _StayCardState();
}

class _StayCardState extends State<_StayCard> {
  bool _pressed = false;

  String _price(dynamic v) {
    if (v == null) return '#0.00/night';
    num n;
    if (v is num) {
      n = v;
    } else if (v is String) {
      n = num.tryParse(v) ?? 0;
    } else {
      n = 0;
    }
    final s = n.toStringAsFixed(n % 1 == 0 ? 0 : 2);
    final parts = s.split('.');
    final whole = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '#$whole${parts.length == 1 ? '.00' : '.${parts.last}'}/night';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final desc = (a.description ?? '').isEmpty
        ? 'Cozy stay close to attractions and nightlife.'
        : a.description!;
    return Semantics(
      label: '${a.name}. ${a.location}. ${a.accommodationType}. ${_price(a.price)}.',
      button: true,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onTap: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              isScrollControlled: true,
              builder: (_) => _DetailSheet(a: a, priceText: _price(a.price)),
            );
          },
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image area (fixed)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFFEFEFF3), Color(0xFFF9F9FB)]),
                    ),
                    child: const Center(
                      child: Icon(Icons.photo_size_select_actual_outlined, color: Color(0xFFB8BBC7), size: 36),
                    ),
                  ),
                ),

                // Texts area (flexible to avoid overflow)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name ?? 'Untitled',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _Brand.title, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        // rating row (tight)
                        const Row(
                          children: [
                            Icon(Icons.star, color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star, color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star, color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star, color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star_half, color: Color(0xFFFFC107), size: 14),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // description uses Flexible to compress first
                        Flexible(
                          child: Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _Brand.body, height: 1.3, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_price(a.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _Brand.title, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        // location badge (tiny)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFEDEDF2)),
                              ),
                              child: Text(
                                (a.location ?? 'Nearby'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _Brand.title,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.favorite_border_rounded, color: _Brand.title, size: 18),
                          ],
                        ),
                      ],
                    ),
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

/*────────────────────  DETAIL SHEET  ───────────────────*/

class _DetailSheet extends StatelessWidget {
  final Accommodation a;
  final String priceText;
  const _DetailSheet({required this.a, required this.priceText});

  @override
  Widget build(BuildContext context) {
    final desc = (a.description ?? '').isEmpty ? 'No description provided.' : a.description!;
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      maxChildSize: 0.96,
      minChildSize: 0.60,
      expand: false,
      builder: (_, controller) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Center(
                  child: Container(
                    height: 4, width: 48,
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Text(
                      a.name ?? 'Untitled stay',
                      style: const TextStyle(color: _Brand.title, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x14FF8A00),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x22FF8A00)),
                    ),
                    child: Text(priceText,
                        style: const TextStyle(color: _Brand.orange, fontWeight: FontWeight.w900)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('${a.location ?? '—'} • ${a.accommodationType ?? '—'}',
                    style: const TextStyle(color: _Brand.body, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(desc,
                    style: const TextStyle(color: _Brand.body, fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 16),
                if (a.owner != null) ...[
                  const Text('Owner', style: TextStyle(color: _Brand.title, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  _OwnerLine(icon: Icons.person_outline_rounded, text: a.owner!.name),
                  const SizedBox(height: 6),
                  _OwnerLine(icon: Icons.mail_outline_rounded, text: a.owner!.email),
                  const SizedBox(height: 6),
                  _OwnerLine(icon: Icons.phone_outlined, text: a.owner!.phone),
                  const SizedBox(height: 16),
                ],
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Brand.orange, foregroundColor: Colors.white,
                        elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: const Text('Book now', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _Brand.orange, side: const BorderSide(color: _Brand.orange),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Contact', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OwnerLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OwnerLine({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        height: 28, width: 28,
        decoration: BoxDecoration(color: const Color(0x14FF8A00), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: _Brand.orange, size: 16),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _Brand.body, fontWeight: FontWeight.w700),
        ),
      ),
    ]);
  }
}

/*──────────────  STATES & BOTTOM BAR  ──────────────*/

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(padding: EdgeInsets.only(top: 120), child: CircularProgressIndicator()),
      );
}

class _Error extends StatelessWidget {
  final String msg;
  final Future<void> Function() onRetry;
  const _Error({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      const SizedBox(height: 120),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
            const SizedBox(height: 8),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: _Brand.body)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _Brand.orange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Try again', style: TextStyle(color: _Brand.orange, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ),
    ]);
  }
}


class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  const _NavIcon({required this.icon, required this.active});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44, width: 44,
      decoration: BoxDecoration(
        color: active ? const Color(0x14FF8A00) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: active ? _Brand.orange : _Brand.title),
    );
  }
}

/*────────────────────────  BRAND  ────────────────────────*/
class _Brand {
  static const orange = Color(0xFFFF8A00); // brand accent
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const bg = Color(0xFFF7F8FA);
}
