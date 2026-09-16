import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/vero_rewards_service.dart';
import 'package:vero360_app/Home/vero_coin_page.dart';

/// Shared Vero Coin chip for customer home and merchant dashboards.
class VeroCoinIconButton extends StatelessWidget {
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final double size;
  final double iconSize;
  final Color? badgeBackground;
  final Color? badgeTextColor;

  const VeroCoinIconButton({
    super.key,
    this.iconColor = Colors.white,
    this.backgroundColor = const Color(0x2EFFFFFF),
    this.borderColor = const Color(0x4DFFFFFF),
    this.size = 40,
    this.iconSize = 18,
    this.badgeBackground,
    this.badgeTextColor,
  });

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VeroCoinPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(color: borderColor),
      ),
      child: Icon(Icons.monetization_on_rounded, color: iconColor, size: iconSize),
    );

    if (uid == null) {
      return IconButton(
        tooltip: 'Vero Coin',
        onPressed: () => _open(context),
        icon: icon,
      );
    }

    return StreamBuilder<VeroRewardsBalance>(
      stream: VeroRewardsService.watchBalance(uid),
      builder: (context, snap) {
        final b = snap.data;
        final spins = b?.availableSpins ?? 0;
        final coins = b?.coins ?? 0;
        final badgeValue = spins > 0 ? spins : coins;
        final showSpinBadge = spins > 0;
        return IconButton(
          tooltip: showSpinBadge ? 'Vero Coin — spin ready' : 'Vero Coin',
          onPressed: () => _open(context),
          icon: Badge(
            isLabelVisible: badgeValue > 0,
            backgroundColor: showSpinBadge
                ? const Color(0xFFFF6B00)
                : (badgeBackground ?? Colors.white),
            textColor: showSpinBadge
                ? Colors.white
                : (badgeTextColor ?? const Color(0xFFD94F00)),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            label: Text(
              badgeValue > 99 ? '99+' : '$badgeValue',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
            ),
            child: icon,
          ),
        );
      },
    );
  }
}
