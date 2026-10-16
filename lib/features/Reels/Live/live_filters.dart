import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colour looks applied on the host preview and, from the live doc, on viewers.
class LiveFilter {
  final String id;
  final String name;
  final List<double>? matrix;

  const LiveFilter(this.id, this.name, this.matrix);
}

const liveFilters = <LiveFilter>[
  LiveFilter('normal', 'Normal', null),
  LiveFilter('warm', 'Warm', [
    1.10, 0, 0, 0, 12, //
    0, 1.02, 0, 0, 4,
    0, 0, 0.88, 0, -12,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('cool', 'Cool', [
    0.90, 0, 0, 0, -6, //
    0, 1.0, 0, 0, 2,
    0, 0, 1.15, 0, 16,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('vivid', 'Vivid', [
    1.3937, -0.3576, -0.0361, 0, 0, //
    -0.1063, 1.1424, -0.0361, 0, 0,
    -0.1063, -0.3576, 1.4639, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('rosy', 'Rosy', [
    1.06, 0, 0, 0, 20, //
    0, 1.0, 0, 0, 8,
    0, 0, 1.03, 0, 14,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('golden', 'Golden', [
    1.15, 0.05, 0, 0, 10, //
    0.05, 1.05, 0, 0, 4,
    0, 0, 0.80, 0, -16,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('vintage', 'Vintage', [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('matte', 'Matte', [
    0.85, 0, 0, 0, 30, //
    0, 0.85, 0, 0, 30,
    0, 0, 0.85, 0, 30,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('bw', 'B&W', [
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  LiveFilter('noir', 'Noir', [
    0.2976, 1.0013, 0.1011, 0, -51, //
    0.2976, 1.0013, 0.1011, 0, -51,
    0.2976, 1.0013, 0.1011, 0, -51,
    0, 0, 0, 1, 0,
  ]),
];

LiveFilter liveFilterById(String? id) =>
    liveFilters.firstWhere((f) => f.id == id, orElse: () => liveFilters.first);

Widget applyLiveFilter(String? id, Widget child) {
  final matrix = liveFilterById(id).matrix;
  if (matrix == null) return child;
  return ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child);
}

/// Animated overlays drawn above the video for everyone.
class LiveEffect {
  final String id;
  final String name;
  final String icon;

  const LiveEffect(this.id, this.name, this.icon);
}

const liveEffects = <LiveEffect>[
  LiveEffect('none', 'None', '🚫'),
  LiveEffect('hearts', 'Hearts', '💖'),
  LiveEffect('sparkles', 'Sparkle', '✨'),
  LiveEffect('snow', 'Snow', '❄️'),
  LiveEffect('confetti', 'Party', '🎉'),
  LiveEffect('flowers', 'Flowers', '🌸'),
  LiveEffect('sale', 'Sale', '🔥'),
];

class LiveEffectLayer extends StatefulWidget {
  const LiveEffectLayer({super.key, required this.effectId});

  final String? effectId;

  @override
  State<LiveEffectLayer> createState() => _LiveEffectLayerState();
}

class _LiveEffectLayerState extends State<LiveEffectLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiveEffectLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final on = (widget.effectId ?? 'none') != 'none';
    if (on && !_t.isAnimating) {
      _t.repeat();
    } else if (!on && _t.isAnimating) {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.effectId ?? 'none';
    if (id == 'none') return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _t,
          builder: (context, _) => switch (id) {
            'hearts' => _particles(box, ['💖', '💕', '❤️', '💗'], rising: true, count: 14),
            'sparkles' => _sparkles(box),
            'snow' => _particles(box, ['❄️', '❅', '❆'], rising: false, count: 22, sway: 18),
            'confetti' => _particles(box, ['🎉', '🎊', '✨', '🟠', '🟡'], rising: false, count: 20, spin: true),
            'flowers' => _flowerFrame(box),
            'sale' => _saleBanner(),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _particles(
    BoxConstraints box,
    List<String> glyphs, {
    required bool rising,
    required int count,
    double sway = 24,
    bool spin = false,
  }) {
    final r = math.Random(id.hashCode);
    final children = <Widget>[];
    for (var i = 0; i < count; i++) {
      final x = r.nextDouble();
      final speed = 0.6 + r.nextDouble() * 0.9;
      final offset = r.nextDouble();
      final size = 16 + r.nextDouble() * 16;
      final glyph = glyphs[i % glyphs.length];
      final p = (_t.value * speed + offset) % 1.0;
      final y = rising ? (1 - p) * (box.maxHeight + 40) - 20 : p * (box.maxHeight + 40) - 30;
      final dx = math.sin((p + offset) * math.pi * 4) * sway;
      final fade = rising ? (p < 0.85 ? 1.0 : (1 - p) / 0.15) : 1.0;
      children.add(Positioned(
        left: x * (box.maxWidth - 30) + dx,
        top: y,
        child: Opacity(
          opacity: fade.clamp(0.0, 1.0) * 0.9,
          child: Transform.rotate(
            angle: spin ? p * math.pi * 6 : 0,
            child: Text(glyph, style: TextStyle(fontSize: size)),
          ),
        ),
      ));
    }
    return Stack(children: children);
  }

  String get id => widget.effectId ?? 'none';

  Widget _sparkles(BoxConstraints box) {
    final r = math.Random(7);
    return Stack(
      children: [
        for (var i = 0; i < 18; i++)
          () {
            final x = r.nextDouble();
            final y = r.nextDouble();
            final phase = r.nextDouble();
            final size = 14 + r.nextDouble() * 18;
            final o = (math.sin((_t.value * 6 + phase) * math.pi * 2) + 1) / 2;
            return Positioned(
              left: x * (box.maxWidth - 24),
              top: y * (box.maxHeight - 24),
              child: Opacity(
                opacity: o,
                child: Transform.scale(
                  scale: 0.6 + o * 0.6,
                  child: Text('✨', style: TextStyle(fontSize: size)),
                ),
              ),
            );
          }(),
      ],
    );
  }

  Widget _flowerFrame(BoxConstraints box) {
    final pulse = 1 + math.sin(_t.value * math.pi * 8) * 0.06;
    Widget f(String g, double size) =>
        Transform.scale(scale: pulse, child: Text(g, style: TextStyle(fontSize: size)));
    final spots = <(double, double, String, double)>[
      (0.02, 0.10, '🌸', 40),
      (0.14, 0.13, '🌼', 26),
      (0.80, 0.10, '🌺', 40),
      (0.68, 0.13, '🌸', 26),
      (0.02, 0.86, '🌷', 36),
      (0.80, 0.86, '🌸', 36),
      (0.86, 0.48, '🌼', 26),
      (0.02, 0.48, '🌺', 26),
    ];
    return Stack(
      children: [
        for (final s in spots)
          Positioned(
            left: s.$1 * box.maxWidth,
            top: s.$2 * box.maxHeight,
            child: f(s.$3, s.$4),
          ),
      ],
    );
  }

  Widget _saleBanner() {
    final pulse = 1 + math.sin(_t.value * math.pi * 10) * 0.04;
    return Align(
      alignment: const Alignment(0, -0.62),
      child: Transform.scale(
        scale: pulse,
        child: Transform.rotate(
          angle: -0.05,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF2D55), Color(0xFFFF8A00)]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
            ),
            child: const Text(
              '🔥 LIVE SALE 🔥',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Snapchat-style carousel of filters and effects. Returns nothing; reports picks live.
Future<void> showLiveLookPicker(
  BuildContext context, {
  required String filter,
  required String effect,
  required ValueChanged<String> onFilter,
  required ValueChanged<String> onEffect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: Colors.transparent,
    backgroundColor: Colors.black.withValues(alpha: 0.72),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _LookPicker(
      filter: filter,
      effect: effect,
      onFilter: onFilter,
      onEffect: onEffect,
    ),
  );
}

class _LookPicker extends StatefulWidget {
  const _LookPicker({
    required this.filter,
    required this.effect,
    required this.onFilter,
    required this.onEffect,
  });

  final String filter;
  final String effect;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onEffect;

  @override
  State<_LookPicker> createState() => _LookPickerState();
}

class _LookPickerState extends State<_LookPicker> {
  late String _filter = widget.filter;
  late String _effect = widget.effect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Label('Filters'),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: liveFilters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final f = liveFilters[i];
                  final on = f.id == _filter;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _filter = f.id);
                      widget.onFilter(f.id);
                    },
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: on ? const Color(0xFFFF8A00) : Colors.white24,
                              width: on ? 3 : 1.5,
                            ),
                          ),
                          child: ClipOval(
                            child: applyLiveFilter(f.id, const _Swatch()),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(f.name,
                            style: TextStyle(
                              color: on ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const _Label('Effects'),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: liveEffects.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final e = liveEffects[i];
                  final on = e.id == _effect;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _effect = e.id);
                      widget.onEffect(e.id);
                    },
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: on ? 0.22 : 0.08),
                            border: Border.all(
                              color: on ? const Color(0xFFFF8A00) : Colors.white24,
                              width: on ? 3 : 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(e.icon, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(e.name,
                            style: TextStyle(
                              color: on ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      );
}

/// Colourful sample so each filter's look shows in its thumbnail.
class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: SweepGradient(colors: [
            Color(0xFFFF8A00),
            Color(0xFFFF2D55),
            Color(0xFF8E44FF),
            Color(0xFF2D9CFF),
            Color(0xFF2ECC71),
            Color(0xFFFFD54F),
            Color(0xFFFF8A00),
          ]),
        ),
        child: SizedBox.expand(),
      );
}
