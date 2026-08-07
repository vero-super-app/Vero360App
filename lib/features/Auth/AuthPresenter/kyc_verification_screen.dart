import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends State<KycVerificationScreen>
    with SingleTickerProviderStateMixin {
  // Vero brand + calm neutrals — warm, trustworthy, not generic purple.
  static const _ink = Color(0xFF141414);
  static const _muted = Color(0xFF6B6B6B);
  static const _cream = Color(0xFFFFFBF7);

  bool _busy = false;
  String? _error;

  late final AnimationController _intro;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _startVerification() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createDiditSession')
          .call();

      final data = result.data;
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      final sessionToken =
          (map?['session_token'] ?? map?['sessionToken'])?.toString().trim();
      var url = (map?['url'] ?? map?['session_url'] ?? map?['sessionUrl'])
          ?.toString()
          .trim();

      if ((url == null || url.isEmpty) &&
          sessionToken != null &&
          sessionToken.isNotEmpty) {
        url = 'https://verify.didit.me/session/$sessionToken';
      }

      if (url == null || url.isEmpty) {
        throw Exception('Could not start verification. Try again.');
      }

      if (!mounted) return;

      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _KycWebViewPage(verificationUrl: url!),
        ),
      );

      if (!mounted) return;

      if (completed == true) {
        ToastHelper.showCustomToast(
          context,
          'Verification submitted — under review',
          isSuccess: true,
          errorMessage: '',
        );
        Navigator.of(context).pop(true);
      } else if (completed == false) {
        setState(() {
          _error = 'Verification was cancelled. You can try again.';
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      String msg;
      if (code == 'not-found' || code == 'not_found') {
        msg =
            'Verification service is not available yet. '
            'Ask support to deploy createDiditSession, then try again.';
      } else if (code == 'unauthenticated') {
        msg = 'Please sign in again, then retry verification.';
      } else if (code == 'unavailable') {
        msg = 'Network issue reaching verification. Check connection and retry.';
      } else if (e.message?.trim().isNotEmpty == true) {
        msg = e.message!;
      } else {
        msg = 'Could not start verification. Try again.';
      }
      setState(() => _error = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _cream,
        body: Stack(
          children: [
            const Positioned.fill(child: _KycAtmosphere()),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    onClose: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                  Expanded(
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              const Center(child: _ShieldMark()),
                              const SizedBox(height: 28),
                              const Text(
                                'Verify your\nidentity',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 34,
                                  height: 1.12,
                                  letterSpacing: -0.8,
                                  color: _ink,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'A quick ID scan and face check so we can keep '
                                'Vero360 safe for everyone. About one minute.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _muted.withValues(alpha: 0.95),
                                  fontSize: 15.5,
                                  height: 1.45,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 32),
                              const _StepRail(
                                steps: [
                                  _StepData(
                                    icon: Icons.badge_outlined,
                                    title: 'ID document',
                                    subtitle: 'National ID ready',
                                  ),
                                  _StepData(
                                    icon: Icons.photo_camera_outlined,
                                    title: 'Camera',
                                    subtitle: 'Allow access',
                                  ),
                                  _StepData(
                                    icon: Icons.face_retouching_natural_outlined,
                                    title: 'Liveness',
                                    subtitle: 'Face match',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              const _TrustStrip(),
                              if (_error != null) ...[
                                const SizedBox(height: 20),
                                _ErrorBanner(message: _error!),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, math.max(16, bottom)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PrimaryCta(
                          busy: _busy,
                          label: _busy
                              ? 'Starting session…'
                              : (_error != null
                                  ? 'Try again'
                                  : 'Start verification'),
                          onPressed: _busy ? null : _startVerification,
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: _muted,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Not now',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Visual pieces ───────────────────────────────────────────────────────────

class _KycAtmosphere extends StatelessWidget {
  const _KycAtmosphere();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Container(color: const Color(0xFFFFFBF7)),
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(
              size: 260,
              colors: [
                const Color(0xFFFF8A00).withValues(alpha: 0.18),
                const Color(0xFFFFB347).withValues(alpha: 0.05),
              ],
            ),
          ),
          Positioned(
            top: 180,
            left: -100,
            child: _Blob(
              size: 220,
              colors: [
                const Color(0xFFFFC978).withValues(alpha: 0.22),
                const Color(0xFFFFFBF7).withValues(alpha: 0.0),
              ],
            ),
          ),
          Positioned(
            bottom: 40,
            right: -40,
            child: _Blob(
              size: 180,
              colors: [
                const Color(0xFFE8F4FF).withValues(alpha: 0.7),
                const Color(0xFFFFFBF7).withValues(alpha: 0.0),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _Blob({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback? onClose;

  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Color(0xFF141414)),
            tooltip: 'Close',
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8E0D6)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 14, color: Color(0xFFFF8A00)),
                SizedBox(width: 6),
                Text(
                  'Secure · Encrypted',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A4A4A),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShieldMark extends StatefulWidget {
  const _ShieldMark();

  @override
  State<_ShieldMark> createState() => _ShieldMarkState();
}

class _ShieldMarkState extends State<_ShieldMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulse.value);
        return Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.18 + t * 0.12),
                blurRadius: 28 + t * 12,
                spreadRadius: 2,
              ),
            ],
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF9A1F),
                Color(0xFFE86F00),
              ],
            ),
          ),
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.verified_user_rounded,
          size: 48,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _StepData {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StepData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _StepRail extends StatelessWidget {
  final List<_StepData> steps;

  const _StepRail({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8E0D6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141414).withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 2,
                    height: 14,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFFF8A00).withValues(alpha: 0.45),
                          const Color(0xFFFF8A00).withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _StepRow(index: i + 1, data: steps[i]),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final _StepData data;

  const _StepRow({required this.index, required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF3E6), Color(0xFFFFE4C4)],
            ),
            border: Border.all(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.22),
            ),
          ),
          child: Icon(data.icon, size: 20, color: const Color(0xFFE86F00)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  color: Color(0xFF141414),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B6B6B),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        Text(
          '0$index',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFF8A00).withValues(alpha: 0.55),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _TrustChip(
            icon: Icons.timer_outlined,
            label: '~1 min',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _TrustChip(
            icon: Icons.privacy_tip_outlined,
            label: 'Private',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _TrustChip(
            icon: Icons.verified_outlined,
            label: 'Didit',
          ),
        ),
      ],
    );
  }
}

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E6).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E0D6)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFE86F00)),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A4A4A),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD4D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFD14343), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8B2E2E),
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  const _PrimaryCta({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: onPressed == null
              ? [const Color(0xFFFFC978), const Color(0xFFFFB347)]
              : [const Color(0xFFFF9A1F), const Color(0xFFE86F00)],
        ),
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Hosted Didit verification (works without the native SDK / Dart 3.11+).
class _KycWebViewPage extends StatefulWidget {
  final String verificationUrl;

  const _KycWebViewPage({required this.verificationUrl});

  @override
  State<_KycWebViewPage> createState() => _KycWebViewPageState();
}

class _KycWebViewPageState extends State<_KycWebViewPage> {
  static const _orange = Color(0xFFFF8A00);
  static const _ink = Color(0xFF141414);

  late final WebViewController _controller;
  bool _loading = true;
  bool _finished = false;
  double _progress = 0.08;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = (p / 100).clamp(0.08, 1.0));
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _progress = 0.08;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _loading = false;
                _progress = 1;
              });
            }
            _maybeComplete(url);
          },
          onNavigationRequest: (request) {
            _maybeComplete(request.url);
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.verificationUrl));
  }

  void _maybeComplete(String url) {
    if (_finished) return;
    final u = url.toLowerCase();
    final done = u.contains('status=approved') ||
        u.contains('status=completed') ||
        u.contains('/success') ||
        u.contains('verification-complete') ||
        u.contains('decision=approved');
    if (!done) return;
    _finished = true;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Identity check',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _ink,
              ),
            ),
            Text(
              'Powered by Didit',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Color(0xFF6B6B6B),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: _orange),
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: AnimatedOpacity(
            opacity: _loading ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 3,
              backgroundColor: const Color(0xFFFFF3E6),
              color: _orange,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Color(0xFFFFFBF7),
              child: Center(child: _WebLoadingCard()),
            ),
        ],
      ),
    );
  }
}

class _WebLoadingCard extends StatelessWidget {
  const _WebLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9A1F), Color(0xFFE86F00)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Opening secure session…',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Color(0xFF141414),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Keep this screen open',
          style: TextStyle(
            fontSize: 13,
            color: const Color(0xFF6B6B6B).withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}
