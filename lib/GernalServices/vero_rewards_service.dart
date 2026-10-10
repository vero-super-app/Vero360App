import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';

/// Retention rewards for **customers and merchants**: open the app → earn
/// Vero Points → Vero Coins → MWK credited to their wallet.
///
/// Rules:
/// - 3 app opens in one day → +1 Vero Point (once per day)
/// - Visit bonus max 3 times per week (then no show-up earnings until next week)
/// - 1 Vero Point = 1 Vero Coin = MWK 50
/// - Cash out from MWK 1,000. The full coin balance pays out (MWK 50 each).
/// - Earn spins: free daily + after marketplace / food / courier / ride / stay
/// - Spin jackpot MWK 5,000
class VeroRewardsService {
  VeroRewardsService._();

  static final _db = FirebaseFirestore.instance;

  static const String collection = 'vero_rewards';
  static const String configPath = 'app_config/vero_rewards';

  /// Remote kill switches from admin (defaults ON if doc missing).
  static Future<({bool cashOutEnabled, bool earningEnabled})>
      getFinanceFlags() async {
    try {
      final snap = await _db.doc(configPath).get();
      if (!snap.exists) {
        return (cashOutEnabled: true, earningEnabled: true);
      }
      final d = snap.data() ?? <String, dynamic>{};
      return (
        cashOutEnabled: d['cashOutEnabled'] != false,
        earningEnabled: d['earningEnabled'] != false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[VeroRewards] getFinanceFlags: $e');
      // Fail open so a config read blip does not freeze rewards.
      return (cashOutEnabled: true, earningEnabled: true);
    }
  }

  static Stream<({bool cashOutEnabled, bool earningEnabled})>
      watchFinanceFlags() {
    return _db.doc(configPath).snapshots().map((snap) {
      if (!snap.exists) {
        return (cashOutEnabled: true, earningEnabled: true);
      }
      final d = snap.data() ?? <String, dynamic>{};
      return (
        cashOutEnabled: d['cashOutEnabled'] != false,
        earningEnabled: d['earningEnabled'] != false,
      );
    });
  }

  static const int visitsForPoint = 3;
  static const int coinsPerPoint = 1;
  static const int visitPointsPerWeek = 3;
  static const double mwkPerCoin = 50;
  /// Cash-out opens at this MWK value. The gate is money, not a coin count.
  static const double minCashOutMwk = 1000;
  static const double mwkPerRedeem = minCashOutMwk;

  static double coinsWorthMwk(int coins) => coins * mwkPerCoin;

  static bool canCashOutCoins(int coins) => coinsWorthMwk(coins) >= minCashOutMwk;
  static const double maxSpinMwk = 5000;
  static const int maxSpinCoins = 100; // 5,000 / 50

  static const String sourceDaily = 'daily';
  static const String sourceMarketplace = 'marketplace';
  static const String sourceFood = 'food';
  static const String sourceCourier = 'courier';
  static const String sourceRide = 'ride';
  static const String sourceAccommodation = 'accommodation';

  static String formatMwk(num amount) {
    final n = amount.round();
    final s = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  /// Wheel segments. Biased hard toward try-again; jackpot is tiny.
  static const List<VeroSpinPrize> spinPrizes = [
    VeroSpinPrize(
      id: 'try_again',
      label: 'Try again',
      valueLabel: 'Try tomorrow',
      colorValue: 0xFF6B7280,
      kind: VeroSpinKind.tryAgain,
      weight: 955,
    ),
    VeroSpinPrize(
      id: '1_coin',
      label: '1 Coin',
      valueLabel: 'MWK 50',
      colorValue: 0xFFF59E0B,
      kind: VeroSpinKind.coins,
      coins: 1,
      weight: 28,
    ),
    VeroSpinPrize(
      id: '1_point',
      label: '1 Point',
      valueLabel: '1 coin · MWK 50',
      colorValue: 0xFFEA580C,
      kind: VeroSpinKind.points,
      points: 1,
      coins: 1,
      weight: 10,
    ),
    VeroSpinPrize(
      id: '2_points',
      label: '2 Points',
      valueLabel: '2 coins · MWK 100',
      colorValue: 0xFFD97706,
      kind: VeroSpinKind.points,
      points: 2,
      coins: 2,
      weight: 5,
    ),
    VeroSpinPrize(
      id: '5_points',
      label: '5 Points',
      valueLabel: '5 coins · MWK 250',
      colorValue: 0xFFDC2626,
      kind: VeroSpinKind.points,
      points: 5,
      coins: 5,
      weight: 1,
    ),
    VeroSpinPrize(
      id: 'jackpot',
      label: 'MWK 5,000',
      valueLabel: 'Jackpot · MWK 5,000',
      colorValue: 0xFFB45309,
      kind: VeroSpinKind.coins,
      coins: maxSpinCoins,
      weight: 1,
    ),
  ];

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Monday-start week id (YYYY-MM-DD of that Monday).
  static String _weekKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
    final mm = monday.month.toString().padLeft(2, '0');
    final dd = monday.day.toString().padLeft(2, '0');
    return '${monday.year}-$mm-$dd';
  }

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection(collection).doc(uid);

  static Stream<VeroRewardsBalance> watchBalance(String uid) {
    return _doc(uid).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      return VeroRewardsBalance.fromMap(data);
    });
  }

  static Future<VeroRewardsBalance> getBalance(String uid) async {
    final snap = await _doc(uid).get();
    return VeroRewardsBalance.fromMap(snap.data() ?? const {});
  }

  /// Ensure a MWK wallet exists for this user (customer or merchant).
  static Future<void> ensureUserWallet({
    required String uid,
    String? displayName,
  }) async {
    final name = (displayName ?? '').trim().isEmpty
        ? 'Vero360 User'
        : displayName!.trim();
    await FirebaseWalletService.getOrCreateWallet(
      merchantId: uid,
      merchantName: name,
    );
  }

  /// Back-compat alias.
  static Future<void> ensureCustomerWallet({
    required String uid,
    String? displayName,
  }) =>
      ensureUserWallet(uid: uid, displayName: displayName);

  /// Call once when homepage opens (signed-in users only).
  /// Returns award info when a point was just granted.
  static Future<VeroVisitResult> recordAppOpen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const VeroVisitResult(skipped: true);
    }

    final flags = await getFinanceFlags();
    if (!flags.earningEnabled) {
      return const VeroVisitResult(skipped: true);
    }

    final uid = user.uid;
    final today = _todayKey();
    final now = DateTime.now();

    try {
      await ensureUserWallet(
        uid: uid,
        displayName: user.displayName ?? user.email,
      );

      return await _db.runTransaction((tx) async {
        final ref = _doc(uid);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};

        var coins = (data['coins'] as num?)?.toInt() ?? 0;
        var points = (data['points'] as num?)?.toInt() ?? 0;
        var dayKey = (data['visitDay'] ?? '').toString();
        var visits = (data['visitCountToday'] as num?)?.toInt() ?? 0;
        final rewardedDay = (data['pointRewardedDay'] ?? '').toString();

        final week = _weekKey(now);
        var visitWeek = (data['visitPointWeek'] ?? '').toString();
        var visitPointsThisWeek =
            (data['visitPointsThisWeek'] as num?)?.toInt() ?? 0;
        if (visitWeek != week) {
          visitWeek = week;
          visitPointsThisWeek = 0;
        }

        if (dayKey != today) {
          dayKey = today;
          visits = 0;
        }

        // Count this open (cap so we don't inflate forever).
        if (visits < visitsForPoint + 5) {
          visits += 1;
        }

        var awardedPoint = false;
        var awardedCoins = 0;
        final weekCapReached = visitPointsThisWeek >= visitPointsPerWeek;
        if (visits >= visitsForPoint &&
            rewardedDay != today &&
            !weekCapReached) {
          points += 1;
          awardedCoins = coinsPerPoint;
          coins += awardedCoins;
          awardedPoint = true;
          visitPointsThisWeek += 1;
        }

        var availableSpins = (data['availableSpins'] as num?)?.toInt() ?? 0;
        final dailySpinDay = (data['dailySpinDay'] ?? '').toString();
        var grantedDailySpin = false;
        if (dailySpinDay != today) {
          availableSpins += 1;
          grantedDailySpin = true;
        }

        tx.set(
          ref,
          {
            'uid': uid,
            'coins': coins,
            'points': points,
            'visitDay': dayKey,
            'visitCountToday': visits,
            'visitPointWeek': visitWeek,
            'visitPointsThisWeek': visitPointsThisWeek,
            if (awardedPoint) 'pointRewardedDay': today,
            'availableSpins': availableSpins,
            if (grantedDailySpin) 'dailySpinDay': today,
            'updatedAt': Timestamp.fromDate(now),
            'createdAt': data['createdAt'] ?? Timestamp.fromDate(now),
          },
          SetOptions(merge: true),
        );

        return VeroVisitResult(
          visitsToday: visits,
          coins: coins,
          points: points,
          awardedPoint: awardedPoint,
          awardedCoins: awardedCoins,
        );
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[VeroRewards] recordAppOpen failed: $e');
      return const VeroVisitResult(skipped: true);
    }
  }

  /// Grant +1 spin after a successful marketplace / food / courier / ride / stay.
  /// Pass [reference] (txRef, order id, ride id, …) so the same action is not
  /// rewarded twice.
  static Future<bool> grantSpinForSuccessfulAction({
    required String source,
    String? reference,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final flags = await getFinanceFlags();
    if (!flags.earningEnabled) return false;

    final uid = user.uid;
    final refKey = _spinGrantKey(source: source, reference: reference);

    try {
      return await _db.runTransaction((tx) async {
        final docRef = _doc(uid);
        final snap = await tx.get(docRef);
        final data = snap.data() ?? <String, dynamic>{};

        final grants = Map<String, dynamic>.from(
          (data['spinGrants'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
        if (grants.containsKey(refKey)) return false;

        grants[refKey] = true;
        // Keep the map bounded.
        if (grants.length > 80) {
          final keys = grants.keys.toList()..sort();
          for (final k in keys.take(grants.length - 60)) {
            grants.remove(k);
          }
        }

        final spins = ((data['availableSpins'] as num?)?.toInt() ?? 0) + 1;
        tx.set(
          docRef,
          {
            'uid': uid,
            'availableSpins': spins,
            'spinGrants': grants,
            'lastSpinGrantSource': source,
            'lastSpinGrantAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return true;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VeroRewards] grantSpinForSuccessfulAction failed: $e');
      }
      return false;
    }
  }

  static String _spinGrantKey({
    required String source,
    String? reference,
  }) {
    final r = (reference ?? '').trim();
    if (r.isNotEmpty) return '${source}_$r';
    // No stable id — still grant once, keyed by second bucket (best effort).
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${source}_$bucket';
  }

  /// Cash out every coin once the balance is worth at least [minCashOutMwk].
  static Future<VeroRedeemResult> redeemCoinsIfEligible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const VeroRedeemResult(ok: false, message: 'Sign in to redeem.');
    }

    final flags = await getFinanceFlags();
    if (!flags.cashOutEnabled) {
      return const VeroRedeemResult(
        ok: false,
        message:
            'Cash-outs are temporarily paused. Please try again later.',
      );
    }

    final uid = user.uid;

    final balance = await getBalance(uid);
    if (!canCashOutCoins(balance.coins)) {
      return VeroRedeemResult(
        ok: false,
        message:
            'You need MWK ${formatMwk(minCashOutMwk)} to cash out (you have MWK ${formatMwk(coinsWorthMwk(balance.coins))}). Almost… not quite.',
        coins: balance.coins,
      );
    }

    try {
      // Spend the live balance in full once it is worth at least MWK 1,000.
      final spent = await _db.runTransaction((tx) async {
        final ref = _doc(uid);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final coins = _asInt(data['coins']);
        if (!canCashOutCoins(coins)) {
          throw Exception('Not enough coins');
        }
        final payout = coins * mwkPerCoin;
        final prevEarnings =
            (data['rewardEarningsMwk'] as num?)?.toDouble() ?? 0;
        tx.set(
          ref,
          {
            'coins': 0,
            'rewardEarningsMwk': prevEarnings + payout,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastRedeemAt': FieldValue.serverTimestamp(),
            'lastRedeemMwk': payout,
            'lastRedeemCoins': coins,
          },
          SetOptions(merge: true),
        );
        return (coins: coins, mwk: payout);
      });
      final coinsToSpend = spent.coins;
      final mwk = spent.mwk;

      var platformDebited = false;
      try {
        await ensureUserWallet(
          uid: uid,
          displayName: user.displayName ?? user.email,
        );

        final reference =
            'VERO_COIN_$uid-${DateTime.now().millisecondsSinceEpoch}';
        // Treasury move: not a user withdrawal, so KYC and a short
        // platform balance must not block 800 or 1,000 coin cash-outs.
        await FirebaseWalletService.debitWallet(
          merchantId: FirebaseWalletService.superAdminUserId,
          amount: mwk,
          description: 'Vero Coin reward payout ($coinsToSpend coins)',
          reference: reference,
          requireKyc: false,
          allowNegative: true,
        );
        platformDebited = true;
        await FirebaseWalletService.creditWallet(
          merchantId: uid,
          amount: mwk,
          description: 'Vero Coin reward ($coinsToSpend coins)',
          reference: reference,
          type: 'credit',
        );
      } catch (e) {
        await _doc(uid).set(
          {
            'coins': FieldValue.increment(coinsToSpend),
            'rewardEarningsMwk': FieldValue.increment(-mwk),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (platformDebited) {
          try {
            await FirebaseWalletService.creditWallet(
              merchantId: FirebaseWalletService.superAdminUserId,
              amount: mwk,
              description:
                  'Vero Coin reward payout reversed ($coinsToSpend coins)',
              reference: 'VERO_COIN_REV_$uid-${DateTime.now().millisecondsSinceEpoch}',
              type: 'credit',
            );
          } catch (rev) {
            if (kDebugMode) {
              debugPrint('[VeroRewards] platform reversal failed: $rev');
            }
          }
        }
        rethrow;
      }

      final fresh = await getBalance(uid);
      return VeroRedeemResult(
        ok: true,
        message: 'MWK ${formatMwk(mwk)} landed in your reward wallet. Nice.',
        coins: fresh.coins,
        mwkCredited: mwk,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[VeroRewards] redeem failed: $e');
      return VeroRedeemResult(
        ok: false,
        message: e.toString().contains('Insufficient')
            ? 'Platform wallet needs funds. Try again later.'
            : 'Could not redeem right now. Try again.',
      );
    }
  }

  /// Spend one available spin. Impossible prizes resolve to "try again".
  static Future<VeroSpinResult> spinDaily() => spin();

  static Future<VeroSpinResult> spin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const VeroSpinResult(
        ok: false,
        message: 'Sign in to spin.',
      );
    }

    final flags = await getFinanceFlags();
    if (!flags.earningEnabled) {
      return const VeroSpinResult(
        ok: false,
        message: 'Spins are temporarily paused. Please try again later.',
      );
    }

    final uid = user.uid;
    final today = _todayKey();

    try {
      // Consume one spin credit first.
      final claimed = await _db.runTransaction((tx) async {
        final ref = _doc(uid);
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        var spins = (data['availableSpins'] as num?)?.toInt() ?? 0;
        final dailySpinDay = (data['dailySpinDay'] ?? '').toString();
        var usingDailyGrant = false;

        // Fallback: one free daily spin if none queued yet.
        if (spins <= 0 && dailySpinDay != today) {
          spins = 1;
          usingDailyGrant = true;
        }

        if (spins <= 0) return false;

        tx.set(
          ref,
          {
            'uid': uid,
            'availableSpins': spins - 1,
            'spinDay': today,
            if (usingDailyGrant) 'dailySpinDay': today,
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return true;
      });

      if (!claimed) {
        return const VeroSpinResult(
          ok: false,
          alreadySpun: true,
          message:
              'No spins left. Finish an order to earn one — or come back tomorrow for a free spin. Patience is a virtue 🤓.',
          prize: VeroSpinPrize(
            id: 'try_again',
            label: 'Try again',
            valueLabel: 'Try tomorrow 🤓',
            colorValue: 0xFF6B7280,
            kind: VeroSpinKind.tryAgain,
            weight: 0,
          ),
        );
      }

      final prize = _pickWeightedPrize();

      var awardedCoins = 0;
      var awardedPoints = 0;
      if (prize.kind == VeroSpinKind.coins || prize.kind == VeroSpinKind.points) {
        awardedCoins = prize.coins;
        awardedPoints = prize.points;
        await _doc(uid).set(
          {
            'coins': FieldValue.increment(awardedCoins),
            'points': FieldValue.increment(awardedPoints),
            'lastSpinPrizeId': prize.id,
            'lastSpinAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        await _doc(uid).set(
          {
            'lastSpinPrizeId': prize.id,
            'lastSpinAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      final message = switch (prize.kind) {
        VeroSpinKind.tryAgain =>
          'Try again — come back tomorrow for another free spin.',
        VeroSpinKind.coins => prize.id == 'jackpot'
            ? 'JACKPOT! MWK ${formatMwk(maxSpinMwk)} (${maxSpinCoins} coins) is on your balance.'
            : 'You won ${prize.coins} Vero Coin${prize.coins == 1 ? '' : 's'}!',
        VeroSpinKind.points => prize.points == 5
            ? 'You won exactly 5 points (5 coins)! Not 6. We counted twice.'
            : 'You won ${prize.points} point${prize.points == 1 ? '' : 's'} (${prize.coins} coin${prize.coins == 1 ? '' : 's'})!',
        VeroSpinKind.impossible =>
          'Try again — come back tomorrow for another free spin.',
      };

      return VeroSpinResult(
        ok: true,
        message: message,
        prize: prize,
        displayPrize: prize,
        awardedCoins: awardedCoins,
        awardedPoints: awardedPoints,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[VeroRewards] spin failed: $e');
      return const VeroSpinResult(
        ok: false,
        message: 'Spin failed. Try again later.',
      );
    }
  }

  static VeroSpinPrize _pickWeightedPrize() {
    final playable = spinPrizes.where((p) => p.weight > 0).toList();
    final total = playable.fold<int>(0, (s, p) => s + p.weight);
    var roll = DateTime.now().microsecondsSinceEpoch % total;
    for (final p in playable) {
      if (roll < p.weight) return p;
      roll -= p.weight;
    }
    return playable.first;
  }
}

enum VeroSpinKind { tryAgain, coins, points, impossible }

class VeroSpinPrize {
  final String id;
  final String label;
  final String valueLabel;
  final int colorValue;
  final VeroSpinKind kind;
  final int weight;
  final int coins;
  final int points;

  const VeroSpinPrize({
    required this.id,
    required this.label,
    required this.valueLabel,
    required this.colorValue,
    required this.kind,
    required this.weight,
    this.coins = 0,
    this.points = 0,
  });
}

class VeroSpinResult {
  final bool ok;
  final bool alreadySpun;
  final String message;
  final VeroSpinPrize? prize;
  /// Segment to animate toward (may be an impossible prize for tease).
  final VeroSpinPrize? displayPrize;
  final int awardedCoins;
  final int awardedPoints;

  const VeroSpinResult({
    required this.ok,
    this.alreadySpun = false,
    this.message = '',
    this.prize,
    this.displayPrize,
    this.awardedCoins = 0,
    this.awardedPoints = 0,
  });
}

class VeroRewardsBalance {
  final int coins;
  final int points;
  final int visitCountToday;
  final String visitDay;
  final bool pointEarnedToday;
  final int visitPointsThisWeek;
  final bool visitWeekCapReached;
  final int availableSpins;
  final bool dailySpinAvailable;
  final bool spunToday;
  /// MWK earned from spin cash-outs / rewards only (not marketplace sales).
  final double rewardEarningsMwk;

  const VeroRewardsBalance({
    this.coins = 0,
    this.points = 0,
    this.visitCountToday = 0,
    this.visitDay = '',
    this.pointEarnedToday = false,
    this.visitPointsThisWeek = 0,
    this.visitWeekCapReached = false,
    this.availableSpins = 0,
    this.dailySpinAvailable = false,
    this.spunToday = false,
    this.rewardEarningsMwk = 0,
  });

  bool get canSpin => availableSpins > 0 || dailySpinAvailable;

  factory VeroRewardsBalance.fromMap(Map<String, dynamic> data) {
    final today = VeroRewardsService._todayKey();
    final week = VeroRewardsService._weekKey();
    final visitDay = (data['visitDay'] ?? '').toString();
    final rewarded = (data['pointRewardedDay'] ?? '').toString();
    final dailySpinDay = (data['dailySpinDay'] ?? '').toString();
    final spins = (data['availableSpins'] as num?)?.toInt() ?? 0;
    final dailyFree = dailySpinDay != today;
    final visitWeek = (data['visitPointWeek'] ?? '').toString();
    final rawWeekPoints = (data['visitPointsThisWeek'] as num?)?.toInt() ?? 0;
    final weekPoints = visitWeek == week ? rawWeekPoints : 0;
    return VeroRewardsBalance(
      coins: VeroRewardsService._asInt(data['coins']),
      points: (data['points'] as num?)?.toInt() ?? 0,
      visitCountToday: visitDay == today
          ? ((data['visitCountToday'] as num?)?.toInt() ?? 0)
          : 0,
      visitDay: visitDay,
      pointEarnedToday: rewarded == today,
      visitPointsThisWeek: weekPoints,
      visitWeekCapReached: weekPoints >= VeroRewardsService.visitPointsPerWeek,
      availableSpins: spins < 0 ? 0 : spins,
      dailySpinAvailable: dailyFree && spins <= 0,
      // Kept for older UI; prefer [canSpin] / [availableSpins].
      spunToday: spins <= 0 && !dailyFree,
      rewardEarningsMwk:
          (data['rewardEarningsMwk'] as num?)?.toDouble() ?? 0,
    );
  }

  int get visitPointsLeftThisWeek {
    if (visitWeekCapReached) return 0;
    final left =
        VeroRewardsService.visitPointsPerWeek - visitPointsThisWeek;
    return left < 0 ? 0 : left;
  }

  int get visitsNeededToday {
    if (pointEarnedToday || visitWeekCapReached) return 0;
    final left = VeroRewardsService.visitsForPoint - visitCountToday;
    return left < 0 ? 0 : left;
  }
}

class VeroVisitResult {
  final bool skipped;
  final int visitsToday;
  final int coins;
  final int points;
  final bool awardedPoint;
  final int awardedCoins;

  const VeroVisitResult({
    this.skipped = false,
    this.visitsToday = 0,
    this.coins = 0,
    this.points = 0,
    this.awardedPoint = false,
    this.awardedCoins = 0,
  });
}

class VeroRedeemResult {
  final bool ok;
  final String message;
  final int coins;
  final double mwkCredited;

  const VeroRedeemResult({
    required this.ok,
    this.message = '',
    this.coins = 0,
    this.mwkCredited = 0,
  });
}
