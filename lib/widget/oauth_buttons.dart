// lib/widgets/oauth_buttons.dart
import 'dart:io';
import 'package:flutter/material.dart';

class OAuthButtonsRow extends StatelessWidget {
  final VoidCallback? onGoogle;
  final VoidCallback? onApple;
  final bool dense;

  const OAuthButtonsRow({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final gap = dense ? 10.0 : 14.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialIconButton(
          asset: 'assets/google.png',
          semanticLabel: 'Continue with Google',
          darkBg: false,
          onPressed: onGoogle,
          fallbackIcon: Icons.g_mobiledata, // safe, always available
        ),
        SizedBox(width: gap),
        _SocialIconButton(
          asset: 'assets/apple.webp',
          semanticLabel: 'Continue with Apple',
          darkBg: true,
          onPressed: Platform.isIOS ? onApple : null, // visible on all, tap only on iOS
          fallbackIcon: Icons.phone_iphone, // safe fallback (no Cupertino dependency)
        ),
      ],
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  final String asset;
  final String semanticLabel;
  final bool darkBg;
  final VoidCallback? onPressed;
  final IconData fallbackIcon;

  const _SocialIconButton({
    required this.asset,
    required this.semanticLabel,
    required this.darkBg,
    required this.onPressed,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: darkBg ? Colors.black : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Image.asset(
        asset,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          fallbackIcon,
          size: 24,
          color: darkBg ? Colors.white : Colors.black87,
        ),
      ),
    );

    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(40),
        child: btn,
      ),
    );
  }
}
