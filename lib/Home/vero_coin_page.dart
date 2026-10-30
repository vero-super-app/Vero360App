import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
    with TickerProviderStateMixin {
  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF1A120B);
  static const _muted = Color(0xFF7A6A5C);

  bool _redeeming = false;
  bool _spinning = false;
  bool _cashOutEnabled = true;
  bool _earningEnabled = true;
  double _wheelTurns = 0;
  String? _lastSpinMessage;
  final _scrollCtrl = ScrollController();
  final _spinKey = GlobalKey();
  StreamSubscription<({bool cashOutEnabled, bool earningEnabled})>?
      _financeSub;

  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();

    _financeSub = VeroRewardsService.watchFinanceFlags().listen((flags) {
      if (!mounted) return;
      setState(() {
        _cashOutEnabled = flags.cashOutEnabled;
        _earningEnabled = flags.earningEnabled;
      });
    });

    if (widget.celebrateSpin) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 280));
        if (!mounted) return;
        _scrollToSpin();
        setState(() {
          _lastSpinMessage = 'Free spin unlocked — give it a whirl.';
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
        alignment: 0.12,
      );
      return;
    }
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        220,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _financeSub?.cancel();
    _stopCruise();
    _clearSettleListener();
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    _enterCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_redeeming || !_cashOutEnabled) return;
    setState(() => _redeeming = true);
    try {
      final res = await VeroRewardsService.redeemCoinsIfEligible()
          .timeout(const Duration(seconds: 35));
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        res.message,
        isSuccess: res.ok,
        errorMessage: '',
      );
    } on TimeoutException {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Cash-out timed out. Please try again.',
        isSuccess: false,
        errorMessage: '',
      );
    } catch (_) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not cash out right now. Try again.',
        isSuccess: false,
        errorMessage: '',
      );
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  VoidCallback? _cruiseListener;
  VoidCallback? _settleListener;

  void _stopCruise() {
    final cruise = _cruiseListener;
    if (cruise == null) return;
    _spinCtrl.removeListener(cruise);
    _cruiseListener = null;
    if (_spinCtrl.isAnimating) _spinCtrl.stop();
  }

  void _clearSettleListener() {
    final settle = _settleListener;
    if (settle == null) return;
    _spinCtrl.removeListener(settle);
    _settleListener = null;
  }

  /// Keep the wheel moving while Firestore decides the prize.
  void _startCruise() {
    _stopCruise();
    _clearSettleListener();
    _spinCtrl.duration = const Duration(milliseconds: 380);
    _spinCtrl.reset();
    var last = _spinCtrl.value;
    void cruise() {
      if (!mounted) return;
      final v = _spinCtrl.value;
      var delta = v - last;
      if (delta < 0) delta += 1;
      last = v;
      // ~3.7 turns/sec — matches the opening speed of the ease-out settle.
      setState(() => _wheelTurns += delta * 1.4);
    }

    _cruiseListener = cruise;
    _spinCtrl.addListener(cruise);
    _spinCtrl.repeat();
  }

  /// Pointer sits at 12 o'clock. Painter draws prize 0 from the top, clockwise.
  /// Positive [Transform.rotate] is clockwise, so the winning center lands under
  /// the pointer when the wheel's fractional turn is `1 - (i + 0.5) / n`.
  double _endTurnsForPrize(VeroSpinPrize target) {
    final prizes = VeroRewardsService.spinPrizes;
    var index = prizes.indexWhere((p) => p.id == target.id);
    if (index < 0) index = 0;
    final n = prizes.length;
    final segment = 1.0 / n;
    final centerFrac = (1.0 - (index * segment + segment / 2)) % 1.0;
    // Stay inside the slice so a neighbour never wins the visual.
    final jitter = (math.Random().nextDouble() - 0.5) * segment * 0.5;
    var desiredFrac = (centerFrac + jitter) % 1.0;
    if (desiredFrac < 0) desiredFrac += 1.0;

    final current = _wheelTurns;
    final currentFrac = current - current.floorToDouble();
    var delta = desiredFrac - currentFrac;
    if (delta < 0.2) delta += 1.0;
    const extraTurns = 3;
    return current + extraTurns + delta;
  }

  Future<void> _settleTo(double endTurns) async {
    _clearSettleListener();
    final begin = _wheelTurns;
    _spinCtrl.duration = const Duration(milliseconds: 2200);
    _spinCtrl.reset();
    final anim = Tween<double>(begin: begin, end: endTurns).animate(
      CurvedAnimation(parent: _spinCtrl, curve: Curves.easeOutCubic),
    );
    void listener() {
      if (!mounted) return;
      setState(() => _wheelTurns = anim.value);
    }

    _settleListener = listener;
    anim.addListener(listener);
    try {
      await _spinCtrl.forward();
    } on TickerCanceled {
      return;
    } finally {
      anim.removeListener(listener);
      if (_settleListener == listener) _settleListener = null;
    }
    if (mounted) setState(() => _wheelTurns = endTurns);
  }

  Future<void> _spin(bool canSpin) async {
    if (_spinning || !canSpin) return;
    setState(() {
      _spinning = true;
      _lastSpinMessage = null;
    });
    _startCruise();

    final res = await VeroRewardsService.spin();
    if (!mounted) return;
    _stopCruise();

    final prizes = VeroRewardsService.spinPrizes;
    final target = res.ok
        ? (res.displayPrize ?? res.prize ?? prizes.first)
        : prizes.first;

    await _settleTo(_endTurnsForPrize(target));
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _lastSpinMessage = res.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final minCashMwk =
        VeroRewardsService.formatMwk(VeroRewardsService.minCashOutMwk);
    final coinMwk =
        VeroRewardsService.formatMwk(VeroRewardsService.mwkPerCoin);
    final jackpot =
        VeroRewardsService.formatMwk(VeroRewardsService.maxSpinMwk);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF7F0),
      appBar: AppBar(
        title: const Text(
          'Vero Coin',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFE85D04).withValues(alpha: 0.96),
                    const Color(0xFFFF6B00).withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to earn Vero Coins.'))
          : Stack(
              children: [
                const _AmbientBackdrop(),
                StreamBuilder<VeroRewardsBalance>(
                  stream: VeroRewardsService.watchBalance(uid),
                  builder: (context, snap) {
                    final b = snap.data ?? const VeroRewardsBalance();
                    final canRedeem = _cashOutEnabled &&
                        VeroRewardsService.canCashOutCoins(b.coins);
                    final cashCoins = b.coins;
                    final cashMwk = VeroRewardsService.formatMwk(
                      cashCoins * VeroRewardsService.mwkPerCoin,
                    );
                    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _enterCtrl,
                        curve: Curves.easeOut,
                      ),
                      child: ListView(
                        controller: _scrollCtrl,
                        padding: EdgeInsets.fromLTRB(20, topPad, 20, 48),
                        children: [
                          SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.08),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _enterCtrl,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            child: _balanceHero(b, coinMwk),
                          ),
                          const SizedBox(height: 22),
                          KeyedSubtree(
                            key: _spinKey,
                            child: _spinStage(b),
                          ),
                          const SizedBox(height: 20),
                          _sectionShell(
                            emoji: '🎁',
                            title: 'Prize values',
                            subtitle: 'What the wheel can land on',
                            gradient: const [
                              Color(0xFFFFF1E0),
                              Color(0xFFFFE0C2),
                            ],
                            accent: const Color(0xFFFF6B00),
                            child: Column(
                              children: [
                                for (final p in VeroRewardsService.spinPrizes)
                                  _prizeRow(p),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8EF),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFFFD7A8),
                                    ),
                                  ),
                                  child: Text(
                                    '🏆 Jackpot sits at MWK $jackpot. Land it if you dare.',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.4,
                                      color: Color(0xFF8A4B12),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionShell(
                            emoji: '👋',
                            title: 'Show-up bonus',
                            subtitle: 'Open the app, earn quietly',
                            gradient: const [
                              Color(0xFFE8F8F0),
                              Color(0xFFD4F0E2),
                            ],
                            accent: const Color(0xFF0F9F6E),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                b.visitWeekCapReached
                                    ? '✅ Weekly show-up bonus done (${b.visitPointsThisWeek}/${VeroRewardsService.visitPointsPerWeek} this week). Come back next week 💚'
                                    : b.pointEarnedToday
                                        ? '🎉 Today’s show-up bonus done (1 point = 1 coin = MWK $coinMwk). ${b.visitPointsLeftThisWeek} left this week.'
                                        : '📱 Open the app ${b.visitsNeededToday} more time${b.visitsNeededToday == 1 ? '' : 's'} today → 1 point = 1 coin = MWK $coinMwk.\n📅 This week: ${b.visitPointsThisWeek}/${VeroRewardsService.visitPointsPerWeek} show-up bonuses used.',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  height: 1.45,
                                  color: Color(0xFF1F3D32),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _sectionShell(
                            emoji: '✨',
                            title: 'How it works',
                            subtitle: 'Short rules, fair odds',
                            gradient: const [
                              Color(0xFFFFF4D6),
                              Color(0xFFFFE8B0),
                            ],
                            accent: const Color(0xFFD97706),
                            child: Column(
                              children: [
                                _Rule(
                                  emoji: '🪙',
                                  text: '1 point = 1 coin = MWK $coinMwk',
                                ),
                                _Rule(
                                  emoji: '💸',
                                  text:
                                      'Cash out from MWK $minCashMwk. The full balance pays out (MWK $coinMwk each).',
                                ),
                                const _Rule(
                                  emoji: '📲',
                                  text: 'Open app 3 times a day → 1 point',
                                ),
                                const _Rule(
                                  emoji: '📆',
                                  text: 'Show-up bonus max 3 times a week',
                                ),
                                const _Rule(
                                  emoji: '🎡',
                                  text: 'Free spin every day',
                                ),
                                const _Rule(
                                  emoji: '🛒',
                                  text:
                                      'Earn a spin after marketplace, food, courier, ride, or stay payment',
                                ),
                                _Rule(
                                  emoji: '🏆',
                                  text: 'Jackpot = MWK $jackpot',
                                ),
                                const _Rule(
                                  emoji: '🤝',
                                  text: 'For customers and merchants',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          _cashOutButton(
                            canRedeem: canRedeem,
                            minCashMwk: minCashMwk,
                            cashCoins: cashCoins,
                            cashMwk: cashMwk,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _balanceHero(VeroRewardsBalance b, String coinMwk) {
    final walletFmt = VeroRewardsService.formatMwk(b.rewardEarningsMwk);
    final coinsWorth = VeroRewardsService.formatMwk(
      b.coins * VeroRewardsService.mwkPerCoin,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFC2410C), Color(0xFFFF6B00), Color(0xFFFFB347)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: _orange.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -24,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final t = 0.85 + (_pulseCtrl.value * 0.15);
                return Transform.scale(
                  scale: t,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 28,
            bottom: -36,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: const Icon(
                      Icons.monetization_on_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your balance',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${b.points} pt${b.points == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '${b.coins}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  letterSpacing: -1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Vero Coins',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip('1 coin = MWK $coinMwk'),
                  _heroChip('Wallet MWK $walletFmt'),
                  _heroChip('Worth ≈ MWK $coinsWorth'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Reward wallet shows spin & cash-out earnings only',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _spinStage(VeroRewardsBalance b) {
    final canSpin = _earningEnabled && b.canSpin && !_spinning;
    final spinsReady =
        b.availableSpins > 0 ? b.availableSpins : (b.dailySpinAvailable ? 1 : 0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFFFE0C2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B00).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vero Daily Spin',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        letterSpacing: -0.5,
                        color: _orange,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Fast spin. Come back tomorrow 🤓.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: spinsReady > 0
                      ? const Color(0xFFFFF0E0)
                      : const Color(0xFFF3F0EC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  spinsReady > 0
                      ? '$spinsReady ready'
                      : 'None left',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: spinsReady > 0 ? _orange : _muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            spinsReady > 0
                ? 'You have $spinsReady spin${spinsReady == 1 ? '' : 's'}. Make it count.'
                : 'No spins yet. Finish an order — or open the app tomorrow for a free spin.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 318,
            width: 318,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final glow = 0.12 + (_pulseCtrl.value * 0.1);
                    return Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _orange.withValues(alpha: glow),
                            blurRadius: 36,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Container(
                  width: 308,
                  height: 308,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 6,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: _wheelTurns * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(292, 292),
                    painter: _WheelPainter(VeroRewardsService.spinPrizes),
                  ),
                ),
                Positioned(
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _orange,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _orange.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFE0C2), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.casino_rounded,
                    color: _spinning ? const Color(0xFFEA580C) : _orange,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_lastSpinMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFE0C2)),
              ),
              child: Text(
                _lastSpinMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: _ink,
                  height: 1.35,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: canSpin ? () => _spin(true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                disabledBackgroundColor: const Color(0xFFFFD8B0),
                foregroundColor: Colors.white,
                elevation: canSpin ? 2 : 0,
                shadowColor: _orange.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _spinning
                    ? 'Spinning…'
                    : !_earningEnabled
                        ? 'Spins temporarily paused'
                        : canSpin
                            ? 'Spin now'
                            : 'Earn a spin to play',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _prizeRow(VeroSpinPrize p) {
    final emoji = switch (p.id) {
      'try_again' => '🔁',
      '1_coin' => '🪙',
      '1_point' => '⭐',
      '2_points' => '🌟',
      '5_points' => '🔥',
      'jackpot' => '🏆',
      _ => '🎁',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Color(p.colorValue).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(p.colorValue).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.label.replaceAll('\n', ' '),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: _ink,
              ),
            ),
          ),
          Text(
            p.valueLabel,
            style: TextStyle(
              color: Color(p.colorValue).withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionShell({
    required String emoji,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.3,
                        color: accent.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: accent.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _cashOutButton({
    required bool canRedeem,
    required String minCashMwk,
    required int cashCoins,
    required String cashMwk,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed:
            canRedeem && _cashOutEnabled && !_redeeming ? _redeem : null,
        style: FilledButton.styleFrom(
          backgroundColor: _ink,
          disabledBackgroundColor: const Color(0xFFD9D0C7),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
                !_cashOutEnabled
                    ? 'Cash-outs temporarily paused'
                    : canRedeem
                        ? 'Cash out $cashCoins coins → MWK $cashMwk'
                        : 'Need MWK $minCashMwk to cash out',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
      ),
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFE4CC),
                  Color(0xFFFFF7F0),
                  Color(0xFFFFFBF7),
                ],
                stops: [0.0, 0.28, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB347).withValues(alpha: 0.14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String text;
  final String emoji;
  const _Rule({required this.text, this.emoji = '•'});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF3D3229),
                fontWeight: FontWeight.w700,
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
          ..strokeWidth = 1.8
          ..color = Colors.white.withValues(alpha: 0.75),
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
            shadows: [
              Shadow(
                color: Colors.black38,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: 68);
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
        ..strokeWidth = 5
        ..color = const Color(0xFFFF6B00),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.prizes != prizes;
}
