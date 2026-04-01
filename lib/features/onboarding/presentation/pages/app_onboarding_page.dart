import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppOnboardingPage extends StatefulWidget {
  const AppOnboardingPage({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<AppOnboardingPage> createState() => _AppOnboardingPageState();
}

class _AppOnboardingPageState extends State<AppOnboardingPage>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _index = 0;

  late AnimationController _bgAnimController;
  late AnimationController _contentAnimController;
  late AnimationController _floatAnimController;

  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;
  late Animation<double> _floatAnim;

  static const _pages = <({
    String emoji,
    String tag,
    String title,
    String body,
    List<Color> gradient,
    List<Color> bubbleColors,
  })>[
    (
      emoji: '🌍',
      tag: 'ALL-IN-ONE',
      title: 'Your city,\nunlocked.',
      body:
          'Rides, food, market deals, courier, accommodation and digital services — one tap away.',
      gradient: [Color(0xFFD94F00), Color(0xFFFF7A1A)],
      bubbleColors: [Color(0xFFE85A00), Color(0xFFFF9140), Color(0xFFBF3D00)],
    ),
    (
      emoji: '⚡',
      tag: 'SEAMLESS',
      title: 'Everything\nin reach.',
      body:
          'Book rides and deliveries, browse the marketplace, chat with vendors, and checkout — without switching apps.',
      gradient: [Color(0xFFFF6B00), Color(0xFFFFAA3C)],
      bubbleColors: [Color(0xFFFF8C1A), Color(0xFFFFBD70), Color(0xFFE55A00)],
    ),
    (
      emoji: '🛡️',
      tag: 'SECURE',
      title: 'Safe from\nstart to end.',
      body:
          'Compare, chat, add to cart, and complete checkout — all in a protected, trusted environment.',
      gradient: [Color(0xFFFF8A00), Color(0xFFFFCC44)],
      bubbleColors: [Color(0xFFFFAA1A), Color(0xFFFFDD77), Color(0xFFE07800)],
    ),
  ];

  @override
  void initState() {
    super.initState();

    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _contentAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _floatAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _contentFade = CurvedAnimation(
      parent: _contentAnimController,
      curve: Curves.easeOut,
    );

    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentAnimController,
      curve: Curves.easeOutCubic,
    ));

    _floatAnim = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatAnimController, curve: Curves.easeInOut),
    );

    _contentAnimController.forward();
    _bgAnimController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _bgAnimController.dispose();
    _contentAnimController.dispose();
    _floatAnimController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_index == _pages.length - 1) {
      widget.onFinish();
      return;
    }
    _contentAnimController.reset();
    await _controller.nextPage(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
    _contentAnimController.forward();
  }

  void _onPageChanged(int v) {
    setState(() => _index = v);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    final size = MediaQuery.of(context).size;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: page.gradient,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              // Decorative background blobs
              ..._buildBackgroundBlobs(size, page.bubbleColors),

              // Main content
              Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Logo wordmark
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Vero',
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              TextSpan(
                                text: '360',
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.75),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onFinish,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.30)),
                            ),
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Page view (illustration area)
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, i) {
                        return _buildIllustration(_pages[i]);
                      },
                    ),
                  ),

                  // Bottom card
                  _buildBottomCard(page),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBackgroundBlobs(
      Size size, List<Color> bubbleColors) {
    return [
      // Top-right large blob
      Positioned(
        top: -size.width * 0.3,
        right: -size.width * 0.25,
        child: AnimatedBuilder(
          animation: _floatAnim,
          builder: (_, __) => Transform.translate(
            offset: Offset(_floatAnim.value * 0.5, _floatAnim.value),
            child: Container(
              width: size.width * 0.75,
              height: size.width * 0.75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bubbleColors[0].withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      ),
      // Bottom-left small blob
      Positioned(
        bottom: size.height * 0.28,
        left: -size.width * 0.15,
        child: AnimatedBuilder(
          animation: _floatAnim,
          builder: (_, __) => Transform.translate(
            offset: Offset(_floatAnim.value * -0.7, _floatAnim.value * 0.5),
            child: Container(
              width: size.width * 0.45,
              height: size.width * 0.45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bubbleColors[2].withValues(alpha: 0.20),
              ),
            ),
          ),
        ),
      ),
      // Mid-right tiny orb
      Positioned(
        top: size.height * 0.35,
        right: size.width * 0.05,
        child: AnimatedBuilder(
          animation: _floatAnim,
          builder: (_, __) => Transform.translate(
            offset: Offset(_floatAnim.value * 0.3, _floatAnim.value * -0.8),
            child: Container(
              width: size.width * 0.22,
              height: size.width * 0.22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bubbleColors[1].withValues(alpha: 0.30),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildIllustration(dynamic page) {
    return Center(
      child: AnimatedBuilder(
        animation: _floatAnim,
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _floatAnim.value),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              // Mid ring
              Container(
                width: 175,
                height: 175,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              // Inner ring / main circle
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 32,
                      spreadRadius: -4,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    page.emoji,
                    style: const TextStyle(fontSize: 52),
                  ),
                ),
              ),

              // Orbiting dots
              _OrbitingDots(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCard(dynamic page) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 40,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tag chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: page.gradient[0].withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                page.tag,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: page.gradient[0],
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Title
            FadeTransition(
              opacity: _contentFade,
              child: SlideTransition(
                position: _contentSlide,
                child: Text(
                  page.title,
                  style: const TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111111),
                    height: 1.15,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Body
            FadeTransition(
              opacity: _contentFade,
              child: SlideTransition(
                position: _contentSlide,
                child: Text(
                  page.body,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: Color(0xFF666666),
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Dots + button row
            Row(
              children: [
                // Dot indicators
                Row(
                  children: List.generate(_pages.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 6),
                      width: active ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? page.gradient[0]
                            : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
                const Spacer(),

                // CTA button
                GestureDetector(
                  onTap: _next,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          _index == _pages.length - 1 ? 22 : 0,
                      vertical: 0,
                    ),
                    width: _index == _pages.length - 1 ? null : 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: page.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: page.gradient[0].withValues(alpha: 0.45),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _index == _pages.length - 1
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text(
                                  'Get Started',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 18),
                              ],
                            )
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Orbiting dots decoration
// ---------------------------------------------------------------------------
class _OrbitingDots extends StatefulWidget {
  const _OrbitingDots({required this.color});
  final Color color;

  @override
  State<_OrbitingDots> createState() => _OrbitingDotsState();
}

class _OrbitingDotsState extends State<_OrbitingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 230,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return CustomPaint(
            painter: _OrbitPainter(
              angle: _ctrl.value * 2 * math.pi,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double angle;
  final Color color;
  _OrbitPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final orbitR = size.width / 2 - 4;

    final specs = [
      (offset: 0.0, r: 5.5, alpha: 0.55),
      (offset: math.pi * 2 / 3, r: 4.0, alpha: 0.40),
      (offset: math.pi * 4 / 3, r: 3.0, alpha: 0.28),
    ];

    for (final s in specs) {
      final a = angle + s.offset;
      final dx = cx + orbitR * math.cos(a);
      final dy = cy + orbitR * math.sin(a);
      canvas.drawCircle(
        Offset(dx, dy),
        s.r,
        Paint()..color = color.withValues(alpha: s.alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.angle != angle || old.color != color;
}