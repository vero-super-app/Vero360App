import 'package:flutter/material.dart';

class CourierOnboardingPage extends StatefulWidget {
  const CourierOnboardingPage({super.key});

  @override
  State<CourierOnboardingPage> createState() => _CourierOnboardingPageState();
}

class _CourierOnboardingPageState extends State<CourierOnboardingPage> {
  static const _veroOrange = Color(0xFFFF8A00);
  static const _veroSoft = Color(0xFFFFF3E0);

  final PageController _pageController = PageController();
  int _index = 0;

  static const _slides = [
    _OnboardingSlide(
      imagePath: 'assets/courier/onboarding_1.jpg',
      title: 'Your package in safe hands',
      subtitle: 'Book pickup in seconds with a clean modern courier experience.',
    ),
    _OnboardingSlide(
      imagePath: 'assets/courier/onboarding_2.jpg',
      title: 'Track every delivery',
      subtitle: 'Follow statuses from PENDING to DELIVERED in one place.',
    ),
    _OnboardingSlide(
      imagePath: 'assets/courier/onboarding_3.jpg',
      title: 'Fast and reliable logistics',
      subtitle: 'Designed for quick booking, updates, and simple management.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _veroSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping_rounded, size: 16, color: _veroOrange),
                        SizedBox(width: 6),
                        Text(
                          'Vero Courier',
                          style: TextStyle(fontWeight: FontWeight.w700, color: _veroOrange),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: _veroSoft,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              s.imagePath,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF5E5E5E), fontSize: 15),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _index == i ? 26 : 8,
                  decoration: BoxDecoration(
                    color: _index == i ? _veroOrange : const Color(0xFFE5E5E5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _veroOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    if (_index == _slides.length - 1) {
                      Navigator.of(context).pop(true);
                      return;
                    }
                    await _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Text(_index == _slides.length - 1 ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final String imagePath;
  final String title;
  final String subtitle;

  const _OnboardingSlide({
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });
}

