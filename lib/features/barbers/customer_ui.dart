import 'package:flutter/material.dart';


class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
}
class BarbersCustomerScreen extends StatefulWidget {
  const BarbersCustomerScreen({super.key});
  @override
  State<BarbersCustomerScreen> createState() => _BarbersCustomerScreenState();
}

class _BarbersCustomerScreenState extends State<BarbersCustomerScreen> {
  final _search = TextEditingController();
  String _selectedCat = 'All';

  @override
  Widget build(BuildContext context) {
    final items = _mockBarbers
        .where((b) => _selectedCat == 'All' || b.services.contains(_selectedCat))
        .where((b) => b.name.toLowerCase().contains(_search.text.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            const CircleAvatar(radius: 14, backgroundColor: Colors.white24, child: Icon(Icons.person, size: 16, color: Colors.white)),
            const SizedBox(width: 8),
            const Text('Alabama, USA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.notifications_none_rounded, color: Colors.white), onPressed: () {}),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Search
          _SearchBar(
            controller: _search,
            onChanged: (_) => setState(() {}),
            onFilterTap: () => _openFilters(context),
          ),
          const SizedBox(height: 16),

          // Categories
          _SectionHeader('Categories', onSeeAll: () => setState(() => _selectedCat = 'All')),
          _CategoryRow(
            categories: const ['All','Haircut','Beard','Shaves','Hair Deals','Nail Cut'],
            selected: _selectedCat,
            onChanged: (c) => setState(() => _selectedCat = c),
          ),
          const SizedBox(height: 16),

          // Best Salon (horizontal cards)
          _SectionHeader('Best Salon', onSeeAll: () {}),
          const SizedBox(height: 8),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final b = items[i];
                return _BestSalonCard(
                  barber: b,
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (_, a, __) => FadeTransition(
                        opacity: a,
                        child: BarberDetailScreen(barber: b),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Recommended (vertical list)
          _SectionHeader('Recommended', onSeeAll: () {}),
          const SizedBox(height: 8),
          ...items.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BarberListTile(
                  barber: b,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BarberDetailScreen(barber: b)),
                  ),
                ),
              )),
          if (items.isEmpty)
            Container(
              height: 140,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x11FF8A00)),
              ),
              child: const Text('No barbers found nearby', style: TextStyle(color: AppColors.body, fontWeight: FontWeight.w700)),
            ),
        ],
      ),

    );
  }

  void _openFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE1E1E1), borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            const Text('Sort & Filters', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: const [
              _ChipFilter('Top rated'),
              _ChipFilter('Open now'),
              _ChipFilter('Under \$20'),
              _ChipFilter('Kids friendly'),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandOrange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BarberDetailScreen extends StatelessWidget {
  final Barber barber;
  const BarberDetailScreen({super.key, required this.barber});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top cover
            _CoverImage(barber: barber),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F7F9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _QuickAction(icon: Icons.call_rounded, label: 'Call', onTap: () => _todo(context, 'Call ${barber.phone}')),
                        _QuickAction(icon: Icons.chat_rounded, label: 'Message', onTap: () => _todo(context, 'Message barber')),
                        _QuickAction(icon: Icons.directions_rounded, label: 'Directions', onTap: () => _todo(context, 'Open maps')),
                        _QuickAction(icon: Icons.share_rounded, label: 'Share', onTap: () => _todo(context, 'Share barber info')),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // About / Services / Reviews tabs (fake tabs – about & services shown)
                    Row(
                      children: const [
                        _TabPill('About', active: true),
                        SizedBox(width: 8),
                        _TabPill('Services'),
                        SizedBox(width: 8),
                        _TabPill('Review'),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // About
                    Text(
                      barber.about,
                      style: const TextStyle(color: AppColors.body, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),

                    // Services chips
                    const Text('Services', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.title)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: barber.services.map((s) => _ServiceChip(s)).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Recent work gallery
                    if (barber.photos.isNotEmpty) ...[
                      Row(
                        children: const [
                          Expanded(child: Text('Recent Work', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.title))),
                          Text('See All', style: TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 86,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: barber.photos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(barber.photos[i], height: 86, width: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                              return Container(color: const Color(0xFFEDEFF3), width: 120, height: 86, child: const Icon(Icons.image_not_supported_rounded));
                            }),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Book CTA
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandOrange, foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () async {
                final when = await showModalBottomSheet<DateTime>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _ScheduleSheet(),
                );
                if (when == null) return;
                // TODO: Send appointment to backend/Firebase
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Requested: ${when.toLocal()} (awaiting confirmation)')),
                  );
                }
              },
              child: const Text('Book Appointment', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }

  void _todo(BuildContext c, String m) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$m — TODO')));
}

/// ─────────────────────────────────────────────────────────────────────────────
/// UI PARTS
/// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  const _SearchBar({required this.controller, required this.onChanged, required this.onFilterTap});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: onFilterTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 48, width: 48,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x11FF8A00)),
            ),
            child: const Icon(Icons.tune_rounded, color: AppColors.title),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader(this.title, {this.onSeeAll});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.title)),
        const Spacer(),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See All', style: TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800))),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onChanged;
  const _CategoryRow({required this.categories, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = categories[i];
          final active = c == selected;
          return ChoiceChip(
            label: Text(c),
            selected: active,
            labelStyle: TextStyle(
              color: active ? Colors.white : AppColors.title,
              fontWeight: FontWeight.w800,
            ),
            selectedColor: AppColors.brandOrange,
            onSelected: (_) => onChanged(c),
          );
        },
      ),
    );
  }
}

class _BestSalonCard extends StatelessWidget {
  final Barber barber;
  final VoidCallback onTap;
  const _BestSalonCard({required this.barber, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(16);
    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: r,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 8))],
              border: Border.all(color: const Color(0x11FF8A00)),
            ),
            child: Column(
              children: [
                // image
                ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  child: Container(
                    height: 130,
                    color: const Color(0xFF222222),
                    child: barber.cover == null
                        ? const Center(child: Icon(Icons.image, color: Colors.white54))
                        : Image.network(barber.cover!, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                            return const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54));
                          }),
                  ),
                ),
                // info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(barber.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.title)),
                              const SizedBox(height: 4),
                              Row(children: [
                                _pill(Icons.star_rounded, barber.rating.toStringAsFixed(1)),
                                const SizedBox(width: 6),
                                _pill(Icons.place_rounded, '${barber.distanceKm.toStringAsFixed(1)} km'),
                              ]),
                              const Spacer(),
                              Row(children: [
                                const Icon(Icons.place_rounded, size: 14, color: AppColors.body),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(barber.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.body, fontWeight: FontWeight.w600, fontSize: 12)),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: const BoxDecoration(color: AppColors.brandOrange, shape: BoxShape.circle),
                          child: const Padding(
                            padding: EdgeInsets.all(8), child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
                          ),
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

  static Widget _pill(IconData i, String t) => Container(
    height: 22, padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0x14FF8A00), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0x22FF8A00)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 14, color: AppColors.brandOrange), const SizedBox(width: 4),
      Text(t, style: const TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800, fontSize: 12)),
    ]),
  );
}

class _BarberListTile extends StatelessWidget {
  final Barber barber;
  final VoidCallback onTap;
  const _BarberListTile({required this.barber, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(16);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: r,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 8))],
            border: Border.all(color: const Color(0x11FF8A00)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                child: Container(
                  width: 96, height: 96, color: const Color(0xFF222222),
                  child: barber.cover == null
                      ? const Icon(Icons.image, color: Colors.white54)
                      : Image.network(barber.cover!, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                          return const Icon(Icons.broken_image_rounded, color: Colors.white54);
                        }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(barber.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.title)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _BestSalonCard._pill(Icons.star_rounded, barber.rating.toStringAsFixed(1)),
                        const SizedBox(width: 6),
                        _BestSalonCard._pill(Icons.place_rounded, '${barber.distanceKm.toStringAsFixed(1)} km'),
                      ]),
                      const SizedBox(height: 8),
                      Text(barber.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.body, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final Barber barber;
  const _CoverImage({required this.barber});
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 220, width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            image: barber.cover == null
                ? null
                : DecorationImage(image: NetworkImage(barber.cover!), fit: BoxFit.cover),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, -1), end: Alignment(0, 1),
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
        ),
        Positioned(
          top: 12, left: 12,
          child: _circleBtn(context, Icons.arrow_back_rounded, () => Navigator.pop(context)),
        ),
        Positioned(
          top: 12, right: 12,
          child: _circleBtn(context, Icons.favorite_border_rounded, () {}),
        ),
        Positioned(
          bottom: 12, left: 16, right: 16,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  barber.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
                ),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  const Icon(Icons.star_rounded, color: AppColors.brandOrange, size: 18),
                  Text(barber.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(BuildContext c, IconData i, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(i, color: AppColors.title)),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48, width: 78,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x11FF8A00)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: AppColors.title),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.title)),
        ]),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String text; final bool active;
  const _TabPill(this.text, {this.active = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? AppColors.brandOrange : const Color(0xFFF2F3F7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Text(text, style: TextStyle(
          color: active ? Colors.white : AppColors.title, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final String t;
  const _ServiceChip(this.t);
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FF8A00),
        border: Border.all(color: const Color(0x22FF8A00)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(child: Text(t, style: const TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800))),
    );
  }
}

class _ChipFilter extends StatelessWidget {
  final String t; const _ChipFilter(this.t);
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x11FF8A00)),
      ),
      child: Center(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title))),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon; final String label; final bool active;
  const _NavIcon({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: active ? AppColors.brandOrange : AppColors.title),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(
        fontWeight: FontWeight.w800, fontSize: 11,
        color: active ? AppColors.brandOrange : AppColors.title,
      )),
    ]);
  }
}

/// Booking bottom sheet (UI-only, returns DateTime)
class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet();
  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  DateTime _day = DateTime.now();
  TimeOfDay? _time;
  final _slots = const ['09:00','09:30','10:00','10:30','11:00','11:30','12:00','14:00','14:30','15:00','15:30','16:00'];

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(20);          
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30)],
      ),
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE1E1E1), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 12),
          const Text('Schedule time', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                      initialDate: _day,
                    );
                    if (picked != null) setState(() => _day = picked);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: _Field(icon: Icons.calendar_today_rounded, text: '${_day.year}-${_day.month}-${_day.day}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (t != null) setState(() => _time = t);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: _Field(icon: Icons.schedule_rounded, text: _time == null ? 'Pick time' : _fmt(_time!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: _slots.map((s) {
                final sel = _time != null && _fmt(_time!) == s;
                return ChoiceChip(
                  label: Text(s),
                  selected: sel,
                  selectedColor: AppColors.brandOrange,
                  labelStyle: TextStyle(color: sel ? Colors.white : AppColors.title, fontWeight: FontWeight.w800),
                  onSelected: (_) {
                    final p = s.split(':');
                    setState(() => _time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandOrange, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
              ),
              onPressed: _time == null ? null : () {
                final dt = DateTime(_day.year, _day.month, _day.day, _time!.hour, _time!.minute);
                Navigator.of(context).pop<DateTime>(dt);
              },
              child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
}

class _Field extends StatelessWidget {
  final IconData icon; final String text;
  const _Field({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x11FF8A00)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(icon, color: AppColors.title, size: 18),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title)),
      ]),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// DATA MODELS (mocked for UI-only run)
/// ─────────────────────────────────────────────────────────────────────────────

class Barber {
  final String id;
  final String name;
  final double rating;
  final double distanceKm;
  final String address;
  final String phone;
  final String? cover;
  final String about;
  final List<String> services;
  final List<String> photos;

  Barber({
    required this.id,
    required this.name,
    required this.rating,
    required this.distanceKm,
    required this.address,
    required this.phone,
    this.cover,
    required this.about,
    required this.services,
    required this.photos,
  });
}

final _mockBarbers = <Barber>[
  Barber(
    id: '1',
    name: 'Razor hair ltd.',
    rating: 5.0,
    distanceKm: 0.6,
    address: '5 Albert road, Barnoldswick',
    phone: '+265991234567',
    cover: null, // use a real image URL to showcase
    about: 'A hair specialist with deep knowledge of hair types and modern styles.',
    services: const ['Haircut','Beard','Shaves','Kids'],
    photos: const [],
  ),
  Barber(
    id: '2',
    name: 'Star hair itd.',
    rating: 4.9,
    distanceKm: 1.1,
    address: '3660 W Quail Kansan City',
    phone: '+265888000111',
    cover: null,
    about: 'Premium cuts and fades with attention to detail.',
    services: const ['Haircut','Fade','Line-up'],
    photos: const [],
  ),
  Barber(
    id: '3',
    name: 'Wade Warren Studio',
    rating: 4.0,
    distanceKm: 2.3,
    address: 'Downtown district',
    phone: '+265770000222',
    cover: null,
    about: 'Classic and contemporary grooming services.',
    services: const ['Shaves','Beard'],
    photos: const [],
  ),
];
