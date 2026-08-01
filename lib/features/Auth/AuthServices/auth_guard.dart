import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

const _kOrange = Color(0xFFFF8A00);
const _kOrangeDark = Color(0xFFE07000);
const _kOrangeLight = Color(0xFFFFF0D9);

class AuthGuard extends StatefulWidget {
  final Widget child;

  /// Optional label used in the dialog message
  final String featureName;

  /// If true: when not logged in, show child behind a blocking overlay (no real access).
  /// Used inside [Bottomnavbar] IndexedStack — do NOT auto-prompt; the shell
  /// owns the “Sign in required” dialog when a protected tab is tapped.
  /// If false: when not logged in, do not show protected content — redirect only.
  final bool showChildBehindDialog;

  const AuthGuard({
    super.key,
    required this.child,
    this.featureName = 'this feature',
    this.showChildBehindDialog = false,
  });

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> with WidgetsBindingObserver {
  bool _isLoggedIn = false;
  bool _loading = true;

  bool _dialogShown = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _checkAuthStatus();
    });

    _checkAuthStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAuthStatus();
    }
  }

  Future<void> _checkAuthStatus() async {
    final loggedIn = await AuthHandler.isAuthenticated();

    if (!mounted) return;

    setState(() {
      _isLoggedIn = loggedIn;
      _loading = false;
      if (loggedIn) _dialogShown = false;
    });

    // Bottom-nav tabs stay mounted in IndexedStack. Auto-prompting here after
    // logout stacks the old dialog over Home and traps the user. The shell
    // prompts with its own dialog when a protected tab is tapped.
    if (widget.showChildBehindDialog) return;

    if (!_isLoggedIn && !_dialogShown) {
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoggedIn) _showAuthDialog();
      });
    }
  }

  void _goHome() {
    openVeroMainShell(context, email: '', tabIndex: 0);
  }

  void _showAuthDialog() {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _kOrange.withValues(alpha: 0.18),
                          _kOrangeLight.withValues(alpha: 0.65),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _kOrange.withValues(alpha: 0.22),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_person_rounded,
                      size: 36,
                      color: _kOrangeDark,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Sign in required',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: onSurface,
                          height: 1.15,
                        ) ??
                        TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: onSurface,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in to access ${widget.featureName}. '
                    'It only takes a moment.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          color: onSurface.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w500,
                        ) ??
                        TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: onSurface.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            if (mounted) _goHome();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: onSurface.withValues(alpha: 0.85),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            side: BorderSide(
                              color: onSurface.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Text(
                            'Not now',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            Navigator.pushNamed(context, '/login');
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                _kOrange.withValues(alpha: 0.38),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Sign in',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      if (mounted && !_isLoggedIn) {
        _dialogShown = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: AppSkeletonListPlaceholder(items: 10),
      );
    }

    if (_isLoggedIn) return widget.child;

    if (widget.showChildBehindDialog) {
      return Stack(
        children: [
          AbsorbPointer(absorbing: true, child: widget.child),
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.04),
              alignment: Alignment.center,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 8),
                      color: Colors.black12,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline),
                    SizedBox(width: 10),
                    Text(
                      'Login to continue',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return const Scaffold(
      body: AppSkeletonListPlaceholder(items: 10),
    );
  }
}
