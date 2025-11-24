import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vero360_app/Pages/homepage.dart';
import 'login_screen.dart';




/// Shared brand colors
class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const greenStart = Color(0xFFE7FAE6);
  static const greenEnd = Color(0xFFFDFEFE);
  static const pinkStart = Color(0xFFF7E9FB);
  static const pinkEnd = Color(0xFFFFFFFF);
  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const dotInactive = Color(0xFFE1E1E1);
}

/// --------------------- SPLASH ---------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => const OnboardingScreen(),
            transitionsBuilder: (_, a, __, child) =>
                FadeTransition(opacity: a, child: child),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandOrange,
      body: Stack(
        children: const [
          Center(child: _LogoFallback()),
          _HomeIndicator(color: Colors.white70),
        ],
      ),
    );
  }
}

/// --------------------- ONBOARDING ---------------------
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

void _next() {
  if (_index < 1) {
    _page.nextPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  } else {
   Navigator.of(context).pushReplacement(
  MaterialPageRoute(builder: (_) => const Vero360Homepage(email: '',)),
);

  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _index == 0
                ? const [AppColors.greenStart, AppColors.greenEnd]
                : const [AppColors.pinkStart, AppColors.pinkEnd],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
          
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: _TopBar(onSkip: _next),
              ),
              Expanded(
                child: PageView(
                  controller: _page,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: const [_PageOne(), _PageTwo()],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    Dots(count: 2, index: _index),
                    const Spacer(),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandOrange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        onPressed: _next,
                        child: const Text(
                          'Next',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const _HomeIndicator(color: Colors.black54),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSkip;
  const _TopBar({required this.onSkip});


  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.brandOrange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.asset(
                'assets/logo_mark.jpg',
                fit: BoxFit.contain,
                color: Colors.white,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'VeroTech',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const Spacer(),
        TextButton(
          onPressed: onSkip,
          child: const Text(
            'Skip',
            style:
                TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PageOne extends StatelessWidget {
  const _PageOne();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/veggies.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _ImagePlaceholder(
                      label: 'veggies.jpg',
                      bg: Color(0xFFDFF3E0),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Title(text: 'Affordable Organic\nfor Everyone', emoji: ' 🥗'),
          const SizedBox(height: 8),
          const _Body(
            text:
                'Get affordable organic groceries made\nfor everyone, every single day.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PageTwo extends StatelessWidget {
  const _PageTwo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: const [
                  _ConcentricFrame(size: Size(280, 360)),
                  _BasketCard(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Title(text: 'Your Grocery\nList In One Place', emoji: ' 🧺'),
          const SizedBox(height: 8),
          const _Body(
            text:
                'Manage your grocery list easily, all in one\nconvenient, organized place.',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BasketCard extends StatelessWidget {
  const _BasketCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.asset(
          'assets/basket.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _ImagePlaceholder(
            label: 'basket.jpg',
            bg: Color(0xFFF0DAF6),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  final String emoji;
  const _Title({required this.text, this.emoji = ''});
  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.left,
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.title,
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        children: [
          TextSpan(text: text),
          if (emoji.isNotEmpty)
            TextSpan(text: emoji, style: const TextStyle(fontSize: 26)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.left,
      style: const TextStyle(
        color: AppColors.body,
        fontSize: 14.5,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class Dots extends StatelessWidget {
  final int count;
  final int index;
  const Dots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(right: 6),
          height: 6,
          width: active ? 18 : 6,
          decoration: BoxDecoration(
            color: active ? AppColors.brandOrange : AppColors.dotInactive,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  final Color color;
  const _HomeIndicator({required this.color});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 10,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 120,
          height: 4.5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}



class _LogoFallback extends StatelessWidget {
  const _LogoFallback();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(Icons.eco, size: 56, color: AppColors.brandOrange),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final String label;
  final Color bg;
  const _ImagePlaceholder({required this.label, required this.bg});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.body,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConcentricFrame extends StatelessWidget {
  final Size size;
  const _ConcentricFrame({required this.size});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: size, painter: _ConcentricRRectPainter());
  }
}

class _ConcentricRRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: size.width, height: size.height),
      const Radius.circular(36),
    );
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6;

    const rings = 12;
    for (int i = 0; i < rings; i++) {
      final t = i / (rings - 1);
      final shrink = 8.0 + t * 48.0;
      final r = baseR.deflate(shrink);
      p.color = Colors.white.withValues(alpha: 0.22 - t * 0.18);
      canvas.drawRRect(r, p);
    }
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.45);
    canvas.drawRRect(baseR.deflate(56), fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
