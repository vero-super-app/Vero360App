// lib/Pages/Accomodation.dart
import 'package:flutter/material.dart';
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

  // Filters + search
  final _filters = const ['All', 'Hotel', 'Hostel', 'BnB', 'Lodge'];
  String _activeFilter = 'All';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchAll();
    _searchCtrl.addListener(() {
      setState(() {
        _searchTerm = _searchCtrl.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _service.fetchAll();
    });
    await _future;
  }

  List<Accommodation> _applyFilters(List<Accommodation> all) {
    final q = _searchTerm.toLowerCase();

    return all.where((a) {
      final type = (a.accommodationType ?? '').toLowerCase();
      final name = (a.name ?? '').toLowerCase();
      final loc = (a.location ?? '').toLowerCase();

      // filter by type
      bool matchesFilter = true;
      switch (_activeFilter) {
        case 'Hotel':
          matchesFilter = type.contains('hotel');
          break;
        case 'Hostel':
          matchesFilter = type.contains('hostel');
          break;
        case 'BnB':
          matchesFilter =
              type.contains('bnb') || type.contains('bed and breakfast');
          break;
        case 'Lodge':
          matchesFilter = type.contains('lodge');
          break;
        default:
          matchesFilter = true;
      }

      // filter by search text
      if (q.isEmpty) return matchesFilter;

      final combined = '$name $loc $type';
      final matchesSearch = combined.contains(q);

      return matchesFilter && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Brand.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _Brand.title,
        centerTitle: false,
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 4.0),
          child: Text(
            'Discover stays',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _Brand.title,
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Accommodation>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const _Loading();
          }

          if (snap.hasError) {
            return _Error(
              msg: 'Failed to load accommodations.\n${snap.error}',
              onRetry: _reload,
            );
          }

          final all = snap.data ?? <Accommodation>[];
          final filtered = _applyFilters(all);
          final resultCount = filtered.length;

          return RefreshIndicator(
            color: _Brand.orange,
            onRefresh: _reload,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // Header: search + filters + result count
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 6.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SearchCard(controller: _searchCtrl),
                        const SizedBox(height: 12),
                        _FilterRow(
                          filters: _filters,
                          active: _activeFilter,
                          onPick: (v) =>
                              setState(() => _activeFilter = v),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$resultCount result${resultCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: _Brand.body,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.search_off_rounded,
                              size: 42,
                              color: Colors.black38,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No results found',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _Brand.title,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Try another type (hotel, hostel, bnb, lodge), '
                              'change the filter, or clear your search.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _Brand.body,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _StayCard(a: filtered[index]),
                        childCount: filtered.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/*────────────────── SEARCH CARD + FILTER ROW ──────────────────*/

class _SearchCard extends StatelessWidget {
  final TextEditingController controller;
  const _SearchCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0x11FF8A00)),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, color: _Brand.orange),
          hintText: 'Search by type (hotel, hostel, bnb, lodge)…',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final List<String> filters;
  final String active;
  final ValueChanged<String> onPick;
  const _FilterRow({
    required this.filters,
    required this.active,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = filters[i];
          final sel = f == active;
          return ChoiceChip(
            label: Text(
              f,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: sel ? Colors.white : _Brand.title,
              ),
            ),
            selected: sel,
            onSelected: (_) => onPick(f),
            selectedColor: _Brand.orange,
            backgroundColor: const Color(0xFFF3F4F8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: sel ? _Brand.orange : const Color(0xFFE3E4EA),
              ),
            ),
          );
        },
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
    if (v == null) return 'MWK 0/night';
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
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    return 'MWK $whole${parts.length == 1 ? '' : '.${parts.last}'}/night';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final desc = (a.description ?? '').isEmpty
        ? 'Cozy stay close to attractions and nightlife.'
        : a.description!;

    return Semantics(
      label:
          '${a.name}. ${a.location}. ${a.accommodationType}. ${_price(a.price)}.',
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
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => _DetailSheet(
                a: a,
                priceText: _price(a.price),
              ),
            );
          },
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image area (placeholder gradient for now)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFF3E3), Color(0xFFFDFCFB)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.photo_size_select_actual_outlined,
                        color: Color(0xFFB8BBC7),
                        size: 36,
                      ),
                    ),
                  ),
                ),

                // Texts
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name ?? 'Untitled stay',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _Brand.title,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Row(
                          children: [
                            Icon(Icons.star,
                                color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star,
                                color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star,
                                color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star,
                                color: Color(0xFFFFC107), size: 14),
                            Icon(Icons.star_half,
                                color: Color(0xFFFFC107), size: 14),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _Brand.body,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _price(a.price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _Brand.title,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFEDEDF2),
                                ),
                              ),
                              child: Text(
                                a.location ?? 'Nearby',
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
                            const Icon(
                              Icons.favorite_border_rounded,
                              color: _Brand.title,
                              size: 18,
                            ),
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
    final desc =
        (a.description ?? '').isEmpty ? 'No description provided.' : a.description!;
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
                    height: 4,
                    width: 48,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.name ?? 'Untitled stay',
                        style: const TextStyle(
                          color: _Brand.title,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x14FF8A00),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x22FF8A00)),
                      ),
                      child: Text(
                        priceText,
                        style: const TextStyle(
                          color: _Brand.orange,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${a.location ?? '—'} • ${a.accommodationType ?? '—'}',
                  style: const TextStyle(
                    color: _Brand.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  desc,
                  style: const TextStyle(
                    color: _Brand.body,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                if (a.owner != null) ...[
                  const Text(
                    'Owner',
                    style: TextStyle(
                      color: _Brand.title,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _OwnerLine(icon: Icons.person_outline_rounded, text: a.owner!.name),
                  const SizedBox(height: 6),
                  _OwnerLine(icon: Icons.mail_outline_rounded, text: a.owner!.email),
                  const SizedBox(height: 6),
                  _OwnerLine(icon: Icons.phone_outlined, text: a.owner!.phone),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _Brand.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.calendar_today_rounded),
                        label: const Text(
                          'Book now',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _Brand.orange,
                          side: const BorderSide(color: _Brand.orange),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text(
                          'Contact',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
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
    return Row(
      children: [
        Container(
          height: 28,
          width: 28,
          decoration: BoxDecoration(
            color: const Color(0x14FF8A00),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _Brand.orange, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _Brand.body,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/*────────────── STATES + BRAND ──────────────*/

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 120),
          child: CircularProgressIndicator(),
        ),
      );
}

class _Error extends StatelessWidget {
  final String msg;
  final Future<void> Function() onRetry;
  const _Error({required this.msg, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 8),
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _Brand.body),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _Brand.orange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Try again',
                    style: TextStyle(
                      color: _Brand.orange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Brand {
  static const orange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const bg = Color(0xFFF7F8FA);
}
