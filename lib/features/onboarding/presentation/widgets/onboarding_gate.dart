import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/features/onboarding/presentation/pages/app_onboarding_page.dart';
import 'package:vero360_app/widgets/vero_launch_splash.dart';

/// Full-screen onboarding before the main shell (e.g. [Bottomnavbar] from `BottomNavbar.dart`).
///
/// [onCompleted] runs after the user finishes or skips onboarding — use this to
/// re-run cached role redirects (merchant / driver vs customer).
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.child,
    this.onCompleted,
  });

  final Widget child;

  /// Called after `onboarding_completed_v1` is persisted and the gate shows [child].
  final VoidCallback? onCompleted;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  // Optimistic: returning users skip the splash gate frame when prefs are warm.
  bool _loading = true;
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(milliseconds: 250));
      final done = prefs.getBool('onboarding_completed_v1') ?? false;
      if (!mounted) return;
      setState(() {
        _onboardingDone = done;
        _loading = false;
      });
    } catch (_) {
      // Prefs slow/unavailable — prefer home over a long branded wait.
      if (!mounted) return;
      setState(() {
        _onboardingDone = true;
        _loading = false;
      });
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed_v1', true);
    if (!mounted) return;
    setState(() => _onboardingDone = true);
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const VeroLaunchSplash(
        title: 'Opening…',
        message: 'Loading your home…',
        showSpinner: true,
      );
    }
    if (!_onboardingDone) {
      return AppOnboardingPage(
        onFinish: () {
          _finishOnboarding();
        },
      );
    }
    return widget.child;
  }
}
