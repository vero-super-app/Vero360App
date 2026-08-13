import 'package:flutter/material.dart';

import 'package:vero360_app/features/Auth/AuthServices/signup_password_rules.dart';

class AuthPalette {
  static const orange = Color(0xFFFF8A00);
  static const orangeDeep = Color(0xFFE67700);
  static const ink = Color(0xFF101010);
  static const muted = Color(0xFF6B6B6B);
  static const cream = Color(0xFFFFF7EE);
  static const mist = Color(0xFFF3F6FB);
  static const field = Color(0xFFF6F4F1);
  static const line = Color(0xFFE8E2D9);
  static const card = Colors.white;
}

class AuthBackground extends StatelessWidget {
  final bool warm;
  final Widget child;

  const AuthBackground({super.key, this.warm = true, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: warm
                  ? const [Color(0xFFFFF1E3), Color(0xFFFFFBFA), Colors.white]
                  : const [Color(0xFFEEF3FF), Color(0xFFF8FAFC), Colors.white],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -60,
          child: _blob(
            warm ? const Color(0xFFFFD7A8) : const Color(0xFFC9DBFF),
            220,
          ),
        ),
        Positioned(
          top: 120,
          left: -80,
          child: _blob(
            warm ? const Color(0xFFFFE6C7) : const Color(0xFFDCE8FF),
            180,
          ),
        ),
        child,
      ],
    );
  }

  static Widget _blob(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class AuthLogoMark extends StatelessWidget {
  const AuthLogoMark({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    final inner = size - 10;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuthPalette.orange, Color(0xFFFFB85C)],
        ),
        boxShadow: [
          BoxShadow(
            color: AuthPalette.orange.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: CircleAvatar(
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image.asset(
            'assets/logo_mark.png',
            width: inner,
            height: inner,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.eco_rounded,
              size: 40,
              color: AuthPalette.orange,
            ),
          ),
        ),
      ),
    );
  }
}

class AuthHeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AuthLogoMark(),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AuthPalette.ink,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AuthPalette.muted,
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AuthPalette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AuthPalette.line.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

InputDecoration authFieldDecoration({
  required String label,
  required String hint,
  required IconData icon,
  Widget? trailing,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, color: AuthPalette.muted),
    suffixIcon: trailing,
    filled: true,
    fillColor: AuthPalette.field,
    labelStyle: const TextStyle(
      color: AuthPalette.muted,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: TextStyle(color: AuthPalette.muted.withValues(alpha: 0.7)),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    enabledBorder: border(Colors.transparent),
    border: border(Colors.transparent),
    focusedBorder: border(AuthPalette.orange, 1.4),
    errorBorder: border(const Color(0xFFD32F2F)),
    focusedErrorBorder: border(const Color(0xFFD32F2F), 1.4),
  );
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFA033), AuthPalette.orangeDeep],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AuthPalette.orange.withValues(alpha: 0.34),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.15,
                  ),
                ),
        ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: TextStyle(
              color: AuthPalette.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}

class AuthPasswordStrengthMeter extends StatelessWidget {
  final String password;

  const AuthPasswordStrengthMeter({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final score = SignupPasswordRules.strengthScore(password);
    if (password.isEmpty) return const SizedBox.shrink();

    final colors = <Color>[
      const Color(0xFFE53935),
      const Color(0xFFFB8C00),
      const Color(0xFF43A047),
    ];
    final active = score.clamp(1, 3);
    final color = colors[active - 1];

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: i < active
                        ? color
                        : AuthPalette.line.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            SignupPasswordRules.strengthLabel(score),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
