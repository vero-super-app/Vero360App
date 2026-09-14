import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final Animation<double> _pulseScale;

  static const _orange = Color(0xFFFF6B00);
  static const _pageBg = Color(0xFFFFF8F2);
  static const _title = Color(0xFF1A1A1A);
  static const _body = Color(0xFF6B6B6B);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: _pageBg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 0.92,
    );
    _fade = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeOut),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.03).animate(
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
    final logoSize = (MediaQuery.sizeOf(context).shortestSide * 0.42)
        .clamp(160.0, 240.0);

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
              Color(0xFFFFF1E4),
              Color(0xFFFFF8F2),
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
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.scale(
                          scale: _pulseScale.value,
                          child: Container(
                            width: logoSize,
                            height: logoSize,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: _orange.withValues(alpha: 0.14),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(18),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/logo_mark.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          widget.slogan,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _body,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _title,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _body,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (widget.showSpinner)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: _orange,
                            ),
                          ),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
