// lib/services/auth_guard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';

import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/register_screen.dart';

class AuthGuard extends StatefulWidget {
  final Widget child;

  /// Optional label used in the dialog message
  final String featureName;

  /// If true: when not logged in, show child behind a blocking overlay (no real access).
  /// If false: when not logged in, do not show protected content — redirect only.
  final bool showChildBehindDialog;

  const AuthGuard({
    Key? key,
    required this.child,
    this.featureName = 'this feature',
    this.showChildBehindDialog = false,
  }) : super(key: key);

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

    // React to Firebase sign-out / sign-in
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

  String? _readToken(SharedPreferences prefs) {
    return prefs.getString("jwt_token") ??
        prefs.getString("token") ??
        prefs.getString("authToken");
  }

  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _readToken(prefs);
    final fbUser = FirebaseAuth.instance.currentUser;

    final loggedIn =
        (token != null && token.trim().isNotEmpty) || (fbUser != null);

    if (!mounted) return;

    setState(() {
      _isLoggedIn = loggedIn;
      _loading = false;
    });

    // Same behavior as your original: pop dialog when not logged in
    if (!_isLoggedIn && !_dialogShown) {
      _dialogShown = true;
      Future.delayed(Duration.zero, () => _showAuthDialog(context));
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Bottomnavbar(email: '')),
      (_) => false,
    );
  }

  void _showAuthDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true, // ✅ keep your old behavior
      builder: (context) => AlertDialog(
        title: const Text("Login Required"),
        content: Text(
          "You need to log in or sign up to access ${widget.featureName}.\n\n"
          "Only public pages can be accessed without logging in.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _goHome(); // ✅ don’t leave them stuck on protected screen
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            child: const Text("Login"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RegisterScreen()),
              );
            },
            child: const Text("Sign Up"),
          ),
        ],
      ),
    ).then((_) {
      // If still logged out after closing dialog, keep blocking
      if (mounted && !_isLoggedIn) {
        // allow dialog to show again if they come back later
        _dialogShown = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isLoggedIn) return widget.child;

    // ✅ Key fix: keep “old feel” (child visible) BUT block interaction
    if (widget.showChildBehindDialog) {
      return Stack(
        children: [
          AbsorbPointer(absorbing: true, child: widget.child),
          // subtle lock overlay
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.04),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(blurRadius: 18, offset: Offset(0, 8), color: Colors.black12),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline),
                    const SizedBox(width: 10),
                    Text(
                      "Login to continue",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Do not show protected content — blocking screen; dialog is shown by _checkAuthStatus.
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
