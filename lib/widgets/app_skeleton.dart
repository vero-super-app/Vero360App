import 'package:flutter/material.dart';

/// App-wide shimmer skeletons. Prefer one [AppSkeletonShimmer] per screen section
/// wrapping many “core” placeholders (not one shimmer per cell).

class AppSkeletonShimmer extends StatefulWidget {
  const AppSkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<AppSkeletonShimmer> createState() => _AppSkeletonShimmerState();
}

class _AppSkeletonShimmerState extends State<AppSkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Color(0xFFEBEBF5),
            Color(0xFFF8F8FF),
            Color(0xFFEBEBF5),
          ],
          stops: [
            (_anim.value - 0.5).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 0.5).clamp(0.0, 1.0),
          ],
        ).createShader(bounds),
        child: child!,
      ),
      child: widget.child,
    );
  }
}

class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.color = const Color(0xFFE2E5EA),
  });

  final double? width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Grey product tile (wrap with [AppSkeletonShimmer] at grid level).
class AppSkeletonProductCardCore extends StatelessWidget {
  const AppSkeletonProductCardCore({super.key, this.borderRadius = 14});

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(color: const Color(0xFFE2E5EA)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(
                  height: 12,
                  width: double.infinity,
                  radius: 6,
                ),
                const SizedBox(height: 8),
                AppSkeletonBox(height: 10, width: 72, radius: 5),
                const SizedBox(height: 6),
                AppSkeletonBox(height: 9, width: 48, radius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-shimmer product placeholder (use sparingly).
class AppSkeletonProductCard extends StatelessWidget {
  const AppSkeletonProductCard({super.key, this.borderRadius = 14});

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: AppSkeletonProductCardCore(borderRadius: borderRadius),
    );
  }
}

class AppSkeletonAccommodationCardCore extends StatelessWidget {
  const AppSkeletonAccommodationCardCore({super.key, this.isDark = false});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final bone = isDark ? const Color(0xFF334155) : const Color(0xFFE2E5EA);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E6EF),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: bone),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(
                    height: 16, width: double.infinity, radius: 6, color: bone),
                const SizedBox(height: 10),
                AppSkeletonBox(height: 12, width: 180, radius: 5, color: bone),
                const SizedBox(height: 8),
                AppSkeletonBox(height: 12, width: 120, radius: 5, color: bone),
                const SizedBox(height: 12),
                AppSkeletonBox(height: 14, width: 90, radius: 6, color: bone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppSkeletonAccommodationCard extends StatelessWidget {
  const AppSkeletonAccommodationCard({super.key, this.isDark = false});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: AppSkeletonAccommodationCardCore(isDark: isDark),
    );
  }
}

class AppSkeletonCartRowCore extends StatelessWidget {
  const AppSkeletonCartRowCore({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeletonBox(width: 76, height: 76, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(height: 14, width: double.infinity, radius: 6),
                const SizedBox(height: 10),
                AppSkeletonBox(height: 12, width: 140, radius: 5),
                const SizedBox(height: 8),
                AppSkeletonBox(height: 12, width: 88, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppSkeletonCartList extends StatelessWidget {
  const AppSkeletonCartList({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        children: [
          for (var i = 0; i < rows; i++) ...[
            const AppSkeletonCartRowCore(),
            if (i < rows - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class AppSkeletonListPlaceholder extends StatelessWidget {
  const AppSkeletonListPlaceholder({super.key, this.items = 8});

  final int items;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          for (var i = 0; i < items; i++) ...[
            Row(
              children: [
                const AppSkeletonBox(width: 44, height: 44, radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonBox(
                        height: 13,
                        width: i.isEven ? 200.0 : 160.0,
                        radius: 6,
                      ),
                      const SizedBox(height: 8),
                      AppSkeletonBox(
                        height: 11,
                        width: double.infinity,
                        radius: 5,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class AppSkeletonLatestArrivalsGrid extends StatelessWidget {
  const AppSkeletonLatestArrivalsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1200
        ? 4
        : width >= 800
            ? 3
            : 2;
    final ratio = width >= 1200
        ? 0.95
        : width >= 800
            ? 0.85
            : 0.72;
    return AppSkeletonShimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: ratio,
        ),
        itemCount: cols * 2,
        itemBuilder: (_, __) =>
            const AppSkeletonProductCardCore(borderRadius: 12),
      ),
    );
  }
}

class AppSkeletonBootLines extends StatelessWidget {
  const AppSkeletonBootLines({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Column(
        children: [
          AppSkeletonBox(
            height: 6,
            width: 180,
            radius: 4,
          ),
          const SizedBox(height: 10),
          AppSkeletonBox(
            height: 6,
            width: 220,
            radius: 4,
          ),
        ],
      ),
    );
  }
}
