// lib/features/Auth/AuthPresenter/oauth_buttons.dart
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SocialButton(
          asset: 'assets/google.png',
          label: 'Continue with Google',
          semanticLabel: 'Continue with Google',
          darkBg: false,
          onPressed: onGoogle,
          fallbackIcon: Icons.g_mobiledata, // safe, always available
        ),
        SizedBox(height: gap),
        _SocialButton(
          asset: 'assets/apple.webp',
          label: 'Continue with Apple',
          semanticLabel: 'Continue with Apple',
          darkBg: true,
          onPressed: Platform.isIOS ? onApple : null, // enabled tap only on iOS
          fallbackIcon: Icons.phone_iphone, // safe fallback (no Cupertino dependency)
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String asset;
  final String label;
  final String semanticLabel;
  final bool darkBg;
  final VoidCallback? onPressed;
  final IconData fallbackIcon;

  const _SocialButton({
    required this.asset,
    required this.label,
    required this.semanticLabel,
    required this.darkBg,
    required this.onPressed,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final btn = Container(
      height: 52,
      decoration: BoxDecoration(
        color: darkBg ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: darkBg
              ? Colors.black
              : Colors.black.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Image.asset(
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
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: darkBg ? Colors.white : Colors.black87,
                  ) ??
                  TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: darkBg ? Colors.white : Colors.black87,
                  ),
            ),
          ),
        ],
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

