import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/vero_rewards_service.dart';
import 'package:vero360_app/Home/vero_coin_page.dart';
import 'package:vero360_app/app_nav_key.dart';

/// After a successful order / ride / courier / stay: grant a spin, show a
/// banner, then open the Vero Coin page so the user can spin immediately.
class VeroSpinRewardPrompt {
  VeroSpinRewardPrompt._();

  static bool _showing = false;

  static String _labelForSource(String source) {
    return switch (source) {
      VeroRewardsService.sourceMarketplace => 'marketplace order',
      VeroRewardsService.sourceFood => 'food order',
      VeroRewardsService.sourceCourier => 'courier booking',
      VeroRewardsService.sourceRide => 'Vero Ride',
      VeroRewardsService.sourceAccommodation => 'stay payment',
      _ => 'action',
    };
  }

  /// Grant +1 spin (idempotent via [reference]) then pop banner → coin page.
  static Future<bool> grantAndPrompt({
    required String source,
    String? reference,
  }) async {
    final granted = await VeroRewardsService.grantSpinForSuccessfulAction(
      source: source,
      reference: reference,
    );
    if (!granted) return false;
    await prompt(source: source);
    return true;
  }

  /// Banner + auto-open Vero Coin (when a spin was already granted).
  static Future<void> prompt({String? source}) async {
    if (_showing) return;
    _showing = true;
    try {
      // Let payment / success navigation settle first.
      await Future<void>.delayed(const Duration(milliseconds: 650));

      final nav = appNavKey.currentState;
      final overlayCtx = nav?.overlay?.context ?? nav?.context;
      if (nav == null || overlayCtx == null || !overlayCtx.mounted) return;

      final action = _labelForSource(source ?? '');
      final open = Completer<void>();

      showDialog<void>(
        context: overlayCtx,
        useRootNavigator: true,
        barrierDismissible: true,
        builder: (ctx) {
          // Auto-continue so users don’t have to hunt for Vero Coin.
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (ctx.mounted && Navigator.of(ctx, rootNavigator: true).canPop()) {
              Navigator.of(ctx, rootNavigator: true).pop();
            }
            if (!open.isCompleted) open.complete();
          });

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD94F00), Color(0xFFFF9A3C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B00).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.casino_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You earned a free spin!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: Color(0xFF101010),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    source == null || source.isEmpty
                        ? 'Opening Vero Coin so you can spin for coins now.'
                        : 'Nice $action. Opening Vero Coin so you can spin for coins now.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        if (Navigator.of(ctx, rootNavigator: true).canPop()) {
                          Navigator.of(ctx, rootNavigator: true).pop();
                        }
                        if (!open.isCompleted) open.complete();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Spin now',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Taking you there automatically…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ).whenComplete(() {
        if (!open.isCompleted) open.complete();
      });

      await open.future;
      if (!nav.mounted) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const VeroCoinPage(celebrateSpin: true),
        ),
      );
    } finally {
      _showing = false;
    }
  }
}
