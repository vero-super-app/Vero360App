import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

/// Full-screen branded launcher shown while the app boots / self-heals.
class VeroLaunchSplash extends StatefulWidget {
  const VeroLaunchSplash({
    super.key,
    this.title = 'Starting…',
    this.message = 'Preparing and optimizing your app.',
    this.showSpinner = true,
    this.actionLabel,
    this.onAction,
    this.slogan = 'Buy anything, anytime',
  });

  final String title;
  final String message;
  final bool showSpinner;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String slogan;

  @override
  State<VeroLaunchSplash> createState() => _VeroLaunchSplashState();
}

class _VeroLaunchSplashState extends State<VeroLaunchSplash>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _pulse;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  late final Animation<double> _pulseScale;

  static const _orange = Color(0xFFFF6B00);
  static const _orangeSoft = Color(0xFFFFE8CC);
  static const _pageBg = Color(0xFFFFFBF6);
  static const _title = Color(0xFF111111);
  static const _body = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    // Start mostly visible so the branded launcher beats any white frame.
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 0.92,
    );
    _fade = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeOut),
    );
    _slide = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.035).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    unawaited(_enter.forward());
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF4E6),
              Color(0xFFFFFBF6),
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_enter, _pulse]),
            builder: (context, _) {
              return Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.scale(
                              scale: _pulseScale.value,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: _orangeSoft),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _orange.withValues(alpha: 0.12),
                                      blurRadius: 28,
                                      offset: const Offset(0, 14),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2A2A2A),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Image.asset(
                                        'assets/logo_mark.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Text(
                                      'Vero360App',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: _title,
                                        letterSpacing: -0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              widget.slogan,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _title,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: _title,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: _body,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 28),
                            if (widget.showSpinner) ...[
                              const AppSkeletonBootLines(),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  color: _orange.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                            if (!widget.showSpinner &&
                                widget.actionLabel != null &&
                                widget.onAction != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: widget.onAction,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      widget.actionLabel!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
