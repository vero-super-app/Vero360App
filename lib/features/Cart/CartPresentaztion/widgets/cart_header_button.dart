import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';

/// Cart icon with an item-count badge for page headers. Opens [CartPage].
class CartHeaderButton extends StatefulWidget {
  const CartHeaderButton({
    super.key,
    this.size = 40,
    this.iconColor = Colors.white,
    this.background,
    this.border,
  });

  final double size;
  final Color iconColor;
  final Color? background;
  final Color? border;

  @override
  State<CartHeaderButton> createState() => _CartHeaderButtonState();
}

class _CartHeaderButtonState extends State<CartHeaderButton> {
  static String? _warmedForUid;

  @override
  void initState() {
    super.initState();
    _warmCount();
  }

  /// Cart is no longer a tab that loads at startup; fill the badge once per account.
  void _warmCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || _warmedForUid == user.uid) return;
    _warmedForUid = user.uid;
    unawaited(
      CartServiceProvider.getInstance().loadLocalCart().then((_) {}, onError: (_) {}),
    );
  }

  Future<void> _open() async {
    final loggedIn = await AuthHandler.isAuthenticated();
    if (!mounted) return;
    if (!loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Sign in to see your cart.'),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: () => Navigator.of(context).pushNamed('/login'),
        ),
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CartPage(cartService: CartServiceProvider.getInstance()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CartService.itemCount,
      builder: (context, count, _) {
        return Badge(
          isLabelVisible: count > 0,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          label: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
          child: Semantics(
            button: true,
            label: 'Cart',
            child: GestureDetector(
              onTap: _open,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.background ?? Colors.white.withValues(alpha: 0.18),
                  border: Border.all(
                    color: widget.border ?? Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  color: widget.iconColor,
                  size: widget.size * 0.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
