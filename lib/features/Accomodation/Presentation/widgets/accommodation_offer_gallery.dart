import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accommodation_offers.dart';
import 'package:vero360_app/features/Accomodation/Presentation/widgets/accommodation_listing_image.dart';

/// Horizontal room / conference cards. Photos inside each card slide.
class AccommodationOfferGallery extends StatelessWidget {
  static const Color _navy = Color(0xFF16284C);
  static const Color _orange = Color(0xFFFF8A00);

  final String title;
  final String? hint;
  final List<_OfferCardData> items;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;

  const AccommodationOfferGallery({
    super.key,
    required this.title,
    required this.items,
    this.hint,
    this.selectedIndex,
    this.onSelect,
  });

  factory AccommodationOfferGallery.rooms({
    Key? key,
    required List<AccommodationRoomOffer> rooms,
    String priceSuffix = '',
    int? selectedIndex,
    ValueChanged<int>? onSelect,
  }) {
    return AccommodationOfferGallery(
      key: key,
      title: 'Rooms',
      hint: 'Tap the room you want to pay for.',
      selectedIndex: selectedIndex,
      onSelect: onSelect,
      items: [
        for (final room in rooms)
          _OfferCardData(
            name: room.name,
            priceLabel:
                'MWK ${formatAccommodationMwk(room.price)}$priceSuffix',
            imageUrls: room.imageUrls,
            localImages: room.localImages,
          ),
      ],
    );
  }

  factory AccommodationOfferGallery.conferences({
    Key? key,
    required List<AccommodationConferenceOffer> conferences,
    String priceSuffix = '',
    int? selectedIndex,
    ValueChanged<int>? onSelect,
  }) {
    return AccommodationOfferGallery(
      key: key,
      title: 'Conferences',
      hint: 'Tap the hall you want to pay for.',
      selectedIndex: selectedIndex,
      onSelect: onSelect,
      items: [
        for (final hall in conferences)
          _OfferCardData(
            name: hall.name,
            priceLabel:
                'MWK ${formatAccommodationMwk(hall.price)}$priceSuffix',
            imageUrls: hall.imageUrls,
            localImages: hall.localImages,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _navy,
            letterSpacing: -0.2,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _SlidingOfferCard(
              item: items[index],
              selected: selectedIndex == index,
              onTap: onSelect == null ? null : () => onSelect!(index),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfferCardData {
  final String name;
  final String priceLabel;
  final List<String> imageUrls;
  final List<Uint8List> localImages;

  const _OfferCardData({
    required this.name,
    required this.priceLabel,
    this.imageUrls = const [],
    this.localImages = const [],
  });

  int get photoCount =>
      localImages.isNotEmpty ? localImages.length : imageUrls.length;
}

class _SlidingOfferCard extends StatefulWidget {
  final _OfferCardData item;
  final bool selected;
  final VoidCallback? onTap;

  const _SlidingOfferCard({
    required this.item,
    required this.selected,
    this.onTap,
  });

  @override
  State<_SlidingOfferCard> createState() => _SlidingOfferCardState();
}

class _SlidingOfferCardState extends State<_SlidingOfferCard> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant _SlidingOfferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.photoCount != widget.item.photoCount) {
      _index = 0;
      _armTimer();
    }
  }

  void _armTimer() {
    _timer?.cancel();
    if (widget.item.photoCount < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_page.hasClients) return;
      final next = (_index + 1) % widget.item.photoCount;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.item.photoCount;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: widget.selected
                        ? AccommodationOfferGallery._orange
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (count == 0)
                        const ColoredBox(
                          color: Color(0xFFF1F3F7),
                          child: Icon(Icons.image_outlined),
                        )
                      else
                        PageView.builder(
                          controller: _page,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: count,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (_, i) => _photoAt(i),
                        ),
                      if (widget.selected)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: AccommodationOfferGallery._orange,
                            child: Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                      if (count > 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < count; i++)
                                Container(
                                  width: i == _index ? 12 : 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: i == _index
                                        ? Colors.white
                                        : Colors.white60,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AccommodationOfferGallery._navy,
              ),
            ),
            Text(
              widget.item.priceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: widget.selected
                    ? AccommodationOfferGallery._orange
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoAt(int index) {
    if (widget.item.localImages.isNotEmpty) {
      return Image.memory(
        widget.item.localImages[index],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return accImageFromAnySource(
      widget.item.imageUrls[index],
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 336,
    );
  }
}
