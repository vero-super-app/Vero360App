import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vero360_app/features/Reels/Live/live_service.dart';
import 'package:vero360_app/features/Reels/reel_feed_view.dart';

const kLiveRed = Color(0xFFFF2D55);
const kLiveOrange = Color(0xFFFF8A00);

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kLiveRed, Color(0xFFFF5E3A)]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: small ? 10 : 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class LiveViewerPill extends StatelessWidget {
  const LiveViewerPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(reelCompact(count),
              style: const TextStyle(
                  color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Latest comments over the video, newest at the bottom.
class LiveChatOverlay extends StatelessWidget {
  const LiveChatOverlay({super.key, required this.liveId, this.hostId});

  final String liveId;
  final String? hostId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveChatMessage>>(
      stream: LiveService.instance.watchChat(liveId),
      builder: (context, snap) {
        final items = snap.data ?? const <LiveChatMessage>[];
        return ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white],
            stops: [0, 0.25, 1],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.only(top: 40),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[items.length - 1 - i];
              final isHost = m.uid == hostId;
              if (m.type == 'join') {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${m.name} joined 👋',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ReelAvatar(url: m.photo, name: m.name, size: 24),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: isHost ? '${m.name} · Host  ' : '${m.name}  ',
                                style: TextStyle(
                                  color: isHost ? kLiveOrange : Colors.white70,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(text: m.text),
                            ]),
                            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Hearts that float up from the like button.
class FloatingHearts extends StatefulWidget {
  const FloatingHearts({super.key});

  @override
  State<FloatingHearts> createState() => FloatingHeartsState();
}

class FloatingHeartsState extends State<FloatingHearts> with TickerProviderStateMixin {
  final _hearts = <_HeartData>[];
  final _rand = math.Random();
  static const _colors = [kLiveRed, kLiveOrange, Color(0xFFFFC107), Color(0xFFFF6FB5)];

  void burst([int count = 1]) {
    for (var i = 0; i < count; i++) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 1800 + _rand.nextInt(700)),
      );
      final h = _HeartData(
        controller: c,
        drift: (_rand.nextDouble() - 0.5) * 70,
        color: _colors[_rand.nextInt(_colors.length)],
        size: 22 + _rand.nextDouble() * 12,
      );
      setState(() => _hearts.add(h));
      c.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _hearts.remove(h));
        c.dispose();
      });
    }
  }

  @override
  void dispose() {
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 90,
        height: 260,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final h in _hearts)
              AnimatedBuilder(
                animation: h.controller,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(h.controller.value);
                  return Positioned(
                    bottom: t * 240,
                    left: 33 + math.sin(t * math.pi * 2) * 12 + h.drift * t,
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.6 + math.min(t * 3, 0.6),
                        child: Icon(Icons.favorite_rounded, color: h.color, size: h.size),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _HeartData {
  _HeartData({
    required this.controller,
    required this.drift,
    required this.color,
    required this.size,
  });

  final AnimationController controller;
  final double drift;
  final Color color;
  final double size;
}

/// Rounded translucent comment field used by host and viewers.
class LiveCommentField extends StatelessWidget {
  const LiveCommentField({super.key, required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 200,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: kLiveOrange,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Say something…',
                hintStyle: TextStyle(color: Colors.white60),
                border: InputBorder.none,
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, color: kLiveOrange, size: 20),
          ),
        ],
      ),
    );
  }
}

class LiveRoundButton extends StatelessWidget {
  const LiveRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.background,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? Colors.black.withValues(alpha: 0.38),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      ),
    );
  }
}

String liveDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
