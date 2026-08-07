import 'package:flutter/material.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Swipeable promo photos (up to 4) with optional dot indicators.
class PromoImageGallery extends StatefulWidget {
  const PromoImageGallery({
    super.key,
    required this.urls,
    this.height = 260,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.showIndicators = true,
    this.overlay,
  });

  final List<String> urls;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool showIndicators;
  final Widget? overlay;

  @override
  State<PromoImageGallery> createState() => _PromoImageGalleryState();
}

class _PromoImageGalleryState extends State<PromoImageGallery> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      return SizedBox(height: widget.height);
    }

    final radius = widget.borderRadius ?? BorderRadius.zero;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (urls.length == 1)
          ResilientCachedNetworkImage(
            url: urls.first,
            fit: widget.fit,
            width: double.infinity,
            height: widget.height,
          )
        else
          PageView.builder(
            controller: _page,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => ResilientCachedNetworkImage(
              url: urls[i],
              fit: widget.fit,
              width: double.infinity,
              height: widget.height,
            ),
          ),
        if (widget.overlay != null) widget.overlay!,
        if (widget.showIndicators && urls.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ),
        if (urls.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_index + 1}/${urls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(height: widget.height, child: content),
    );
  }
}
