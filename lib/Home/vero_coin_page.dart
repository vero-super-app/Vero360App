import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/GernalServices/vero_rewards_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Balance, daily spin wheel, and how Vero Coin / Points work.
class VeroCoinPage extends StatefulWidget {
  /// When true, scroll to the spin wheel after opening from a reward prompt.
  final bool celebrateSpin;

  const VeroCoinPage({super.key, this.celebrateSpin = false});

  @override
  State<VeroCoinPage> createState() => _VeroCoinPageState();
}

class _VeroCoinPageState extends State<VeroCoinPage>
    with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFFF6B00);
  bool _redeeming = false;
  bool _spinning = false;
  double? _walletMwk;
  double _wheelTurns = 0;
  String? _lastSpinMessage;
  final _scrollCtrl = ScrollController();
  final _spinKey = GlobalKey();

  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6800),
    );
    _loadWallet();
    if (widget.celebrateSpin) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 280));
        if (!mounted) return;
        _scrollToSpin();
        setState(() {
          _lastSpinMessage = 'Your free spin is ready — tap Spin now!';
        });
      });
    }
  }

  void _scrollToSpin() {
    final ctx = _spinKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
      return;
    }
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        180,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await VeroRewardsService.ensureUserWallet(uid: uid);
      final w = await FirebaseWalletService.getOrCreateWallet(
        merchantId: uid,
        merchantName:
            FirebaseAuth.instance.currentUser?.displayName ?? 'Vero360 User',
      );
      if (mounted) setState(() => _walletMwk = w.balance);
    } catch (_) {}
  }

  Future<void> _redeem() async {
    if (_redeeming) return;
    setState(() => _redeeming = true);
    try {
      final res = await VeroRewardsService.redeemCoinsIfEligible();
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        res.message,
        isSuccess: res.ok,
        errorMessage: '',
      );
      if (res.ok) await _loadWallet();
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _spin(bool canSpin) async {
    if (_spinning || !canSpin) return;
    setState(() {
      _spinning = true;
      _lastSpinMessage = null;
    });

    final res = await VeroRewardsService.spin();
    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _spinning = false;
        _lastSpinMessage = res.message;
      });
      ToastHelper.showCustomToast(
        context,
        res.message,
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    final prizes = VeroRewardsService.spinPrizes;
    final target = res.displayPrize ?? res.prize ?? prizes.first;
    final index = prizes.indexWhere((p) => p.id == target.id).clamp(0, prizes.length - 1);
    final segment = 1.0 / prizes.length;
    // Pointer is at top; rotate so segment center lands under pointer.
    final targetCenter = index * segment + segment / 2;
    final extraTurns = 8 + math.Random().nextInt(4);
    final endTurns = _wheelTurns.floor() + extraTurns + (1 - targetCenter);

    final anim = Tween<double>(begin: _wheelTurns, end: endTurns).animate(
      CurvedAnimation(parent: _spinCtrl, curve: Curves.easeOutCubic),
    );
    void listener() {
      setState(() => _wheelTurns = anim.value);
    }

    anim.addListener(listener);
    _spinCtrl.forward(from: 0);
    await Future<void>.delayed(
      _spinCtrl.duration ?? const Duration(milliseconds: 6800),
    );
    anim.removeListener(listener);

    if (!mounted) return;
    setState(() {
      _spinning = false;
      _lastSpinMessage = res.message;
      _wheelTurns = endTurns;
    });
    ToastHelper.showCustomToast(
      context,
      res.message,
      isSuccess: res.awardedCoins > 0 || res.awardedPoints > 0,
      errorMessage: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: AppBar(
        title: const Text('Vero Coin'),
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to earn Vero Coins.'))
          : StreamBuilder<VeroRewardsBalance>(
              stream: VeroRewardsService.watchBalance(uid),
              builder: (context, snap) {
                final b = snap.data ?? const VeroRewardsBalance();
                final canRedeem = b.coins >= VeroRewardsService.coinsPerRedeem;

                return ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    _balanceCard(b),
                    const SizedBox(height: 18),
                    KeyedSubtree(
                      key: _spinKey,
                      child: _spinCard(b),
                    ),
                    const SizedBox(height: 14),
                    _card(
                      title: 'Prize values',
                      child: Column(
                        children: [
                          for (final p in VeroRewardsService.spinPrizes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Color(p.colorValue),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      p.label.replaceAll('\n', ' '),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    p.valueLabel,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Biggest cash spin is MWK 20,000.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      title: 'Show-up bonus',
                      child: Text(
                        b.visitWeekCapReached
                            ? 'Weekly show-up bonus done (${b.visitPointsThisWeek}/${VeroRewardsService.visitPointsPerWeek} this week). Come back next week.'
                            : b.pointEarnedToday
                                ? 'Today’s show-up bonus done (1 point = 1 coin = MWK 100). ${b.visitPointsLeftThisWeek} left this week.'
                                : 'Open the app ${b.visitsNeededToday} more time${b.visitsNeededToday == 1 ? '' : 's'} today → 1 point = 1 coin = MWK 100.\nThis week: ${b.visitPointsThisWeek}/${VeroRewardsService.visitPointsPerWeek} show-up bonuses used.',
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: Color(0xFF444444),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      title: 'Simple rules',
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Rule('1 point = 1 coin = MWK 100'),
                          _Rule('5 coins = MWK 1,000 in your wallet'),
                          _Rule('Open app 3 times a day → 1 point'),
                          _Rule(
                            'Show-up bonus max 3 times a week — then no more until next week',
                          ),
                          _Rule('Free spin every day'),
                          _Rule(
                            'Also earn a spin after marketplace, food, courier, ride, or stay payment',
                          ),
                          _Rule('Highest spin = MWK 20,000'),
                          _Rule('For customers and merchants'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: canRedeem && !_redeeming ? _redeem : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _orange,
                          disabledBackgroundColor: const Color(0xFFFFD8B0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _redeeming
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                canRedeem
                                    ? 'Cash out 5 coins → MWK 1,000'
                                    : 'Need 5 coins (MWK 1,000) to cash out',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _balanceCard(VeroRewardsBalance b) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD94F00), Color(0xFFFF9A3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on_rounded, color: Colors.white, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${b.coins}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vero Coins  ·  ${b.points} points',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '1 coin = MWK 100  ·  Wallet MWK ${(_walletMwk ?? 0).toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your coins ≈ MWK ${(b.coins * VeroRewardsService.mwkPerCoin).toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _spinCard(VeroRewardsBalance b) {
    final canSpin = b.canSpin && !_spinning;
    final spinsReady =
        b.availableSpins > 0 ? b.availableSpins : (b.dailySpinAvailable ? 1 : 0);
    return _card(
      title: 'Vero spin',
      child: Column(
        children: [
          Text(
            spinsReady > 0
                ? 'You have $spinsReady spin${spinsReady == 1 ? '' : 's'} ready.'
                : 'No spins yet. Finish an order, ride, courier, or stay — or open the app tomorrow for a free spin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 304,
            width: 304,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: _wheelTurns * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(304, 304),
                    painter: _WheelPainter(VeroRewardsService.spinPrizes),
                  ),
                ),
                const Positioned(
                  top: 0,
                  child: Icon(Icons.arrow_drop_down, size: 46, color: _orange),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 8),
                    ],
                  ),
                  child: const Icon(Icons.casino_rounded, color: _orange, size: 30),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_lastSpinMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _lastSpinMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF333333),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: canSpin ? () => _spin(true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                disabledBackgroundColor: const Color(0xFFFFD8B0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _spinning
                    ? 'Spinning…'
                    : canSpin
                        ? 'Spin now'
                        : 'Earn a spin to play',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE8CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String text;
  const _Rule(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Color(0xFF444444),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<VeroSpinPrize> prizes;
  _WheelPainter(this.prizes);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweep = 2 * math.pi / prizes.length;
    var start = -math.pi / 2;

    for (final p in prizes) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = Color(p.colorValue);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        paint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.7),
      );

      final mid = start + sweep / 2;
      final labelPos = Offset(
        center.dx + math.cos(mid) * radius * 0.62,
        center.dy + math.sin(mid) * radius * 0.62,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: p.label.replaceAll('\n', ' '),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: 64);
      canvas.save();
      canvas.translate(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();

      start += sweep;
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFFF6B00),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}
