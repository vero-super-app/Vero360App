import 'package:flutter/material.dart';

class AppOnboardingPage extends StatefulWidget {
  const AppOnboardingPage({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<AppOnboardingPage> createState() => _AppOnboardingPageState();
}

class _AppOnboardingPageState extends State<AppOnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  static const Color _brandOrange = Color(0xFFFF8A00);

  static const _pages = <({
    IconData icon,
    String title,
    String body,
  })>[
    (
      icon: Icons.explore_rounded,
      title: 'Welcome to Vero360',
      body:
          'Find rides, food, marketplace deals, accommodation, courier and digital services in one app.',
    ),
    (
      icon: Icons.grid_view_rounded,
      title: 'Everything in reach',
      body:
          'Book rides and deliveries, browse the market, chat, and checkout from one app.',
    ),
    (
      icon: Icons.shopping_bag_rounded,
      title: 'Book, chat, and checkout safely',
      body:
          'Open any service, compare options, chat with providers, add to cart, and complete checkout from one place.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _pages.length - 1) {
      widget.onFinish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onFinish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Color(0xFF6B6B6B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (v) => setState(() => _index = v),
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: _brandOrange.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon, size: 46, color: _brandOrange),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111111),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: Color(0xFF565656),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? _brandOrange : const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _index == _pages.length - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
