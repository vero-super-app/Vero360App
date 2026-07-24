import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/latest_Services.dart';
import 'package:vero360_app/features/Promotions/promotion_service.dart';

/// Keeps Vero360 “alive” with light engagement alerts (promos, arrivals, marketplace).
///
/// - Max **2** local digests per calendar day, at least **10 hours** apart.
/// - Subscribes users to FCM topic [fcmTopic] so server/Cloud Functions can push
///   the same style of reminders when the app is closed.
class EngagementNotificationService {
  EngagementNotificationService._();

  static final EngagementNotificationService instance =
      EngagementNotificationService._();

  static const String fcmTopic = 'vero360_engagement';
  static const String prefEnabled = 'pref_notifications_engagement';
  static const String _prefLastDigestMs = 'engagement_last_digest_ms';
  static const String _prefDigestCountDay = 'engagement_digest_count_day';
  static const String _prefDigestDayKey = 'engagement_digest_day_key';
  static const String _prefLastPromoId = 'engagement_last_seen_promo_id';
  static const String _prefLastArrivalId = 'engagement_last_seen_arrival_id';
  static const String _prefLastMarketMs = 'engagement_last_seen_market_ms';

  static const Duration _minGap = Duration(hours: 10);
  static const int _maxPerDay = 2;

  bool _running = false;

  /// Call after [NotificationService.initialize] and on login / settings change.
  Future<void> syncTopicSubscription({bool? enabledOverride}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final masterOn = prefs.getBool('pref_notifications_enabled') ?? true;
      final engagementOn =
          enabledOverride ?? (prefs.getBool(prefEnabled) ?? true);
      final user = FirebaseAuth.instance.currentUser;
      final messaging = FirebaseMessaging.instance;

      if (user != null && masterOn && engagementOn) {
        await messaging.subscribeToTopic(fcmTopic);
        if (kDebugMode) debugPrint('Subscribed to FCM topic $fcmTopic');
      } else {
        await messaging.unsubscribeFromTopic(fcmTopic);
        if (kDebugMode) debugPrint('Unsubscribed from FCM topic $fcmTopic');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Engagement topic sync failed: $e');
    }
  }

  /// Soft check: if enough time passed and there is fresh content, notify once.
  Future<void> maybeSendDailyDigest({bool force = false}) async {
    if (_running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final masterOn = prefs.getBool('pref_notifications_enabled') ?? true;
      final engagementOn = prefs.getBool(prefEnabled) ?? true;
      if (!masterOn || !engagementOn) return;
      if (FirebaseAuth.instance.currentUser == null) return;

      if (!force && !await _canSendDigest(prefs)) return;

      final snapshot = await _gatherFreshContent(prefs);
      if (snapshot == null) return;

      await NotificationService.instance.showManualNotification(
        title: snapshot.title,
        body: snapshot.body,
        payload:
            '{"type":"${snapshot.type}","badgeRoute":"${snapshot.badgeRoute}"}',
      );

      await _markDigestSent(prefs, snapshot);
      if (kDebugMode) {
        debugPrint('Engagement digest sent: ${snapshot.title}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Engagement digest failed: $e');
    } finally {
      _running = false;
    }
  }

  Future<bool> _canSendDigest(SharedPreferences prefs) async {
    final now = DateTime.now();
    final dayKey = _dayKey(now);
    final storedDay = prefs.getString(_prefDigestDayKey) ?? '';
    var count = prefs.getInt(_prefDigestCountDay) ?? 0;
    if (storedDay != dayKey) {
      count = 0;
    }
    if (count >= _maxPerDay) return false;

    final lastMs = prefs.getInt(_prefLastDigestMs) ?? 0;
    if (lastMs > 0) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (now.difference(last) < _minGap) return false;
    }
    return true;
  }

  Future<_DigestSnapshot?> _gatherFreshContent(SharedPreferences prefs) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final lastPromoId = prefs.getInt(_prefLastPromoId) ?? 0;
    final lastArrivalId = prefs.getString(_prefLastArrivalId) ?? '';
    final lastMarketMs = prefs.getInt(_prefLastMarketMs) ??
        cutoff.millisecondsSinceEpoch;

    String? promoTitle;
    int? newestPromoId;
    String? arrivalName;
    String? newestArrivalId;
    int marketCount = 0;
    int newestMarketMs = lastMarketMs;
    String? marketTitle;

    try {
      final promos = await PromoService().fetchActivePromos();
      for (final p in promos) {
        if (p.createdAt.isBefore(cutoff)) continue;
        if (p.id <= lastPromoId) continue;
        if (newestPromoId == null || p.id > newestPromoId) {
          newestPromoId = p.id;
          promoTitle = p.title.trim();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Engagement promo fetch: $e');
    }

    try {
      final arrivals = await LatestArrivalServices().fetchLatestArrivals();
      for (final a in arrivals) {
        if (a.id.isEmpty || a.id == lastArrivalId) continue;
        // Prefer first new item (list is usually newest-first).
        arrivalName ??= a.name.trim();
        newestArrivalId ??= a.id;
        break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Engagement arrivals fetch: $e');
    }

    try {
      final since = Timestamp.fromMillisecondsSinceEpoch(lastMarketMs);
      final snap = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .where('createdAt', isGreaterThan: since)
          .orderBy('createdAt', descending: true)
          .limit(12)
          .get();
      marketCount = snap.docs.length;
      if (snap.docs.isNotEmpty) {
        final first = snap.docs.first;
        final data = first.data();
        marketTitle = (data['name'] ?? data['title'] ?? data['productName'] ?? '')
            .toString()
            .trim();
        final created = data['createdAt'];
        if (created is Timestamp) {
          newestMarketMs = created.millisecondsSinceEpoch;
        } else {
          newestMarketMs = DateTime.now().millisecondsSinceEpoch;
        }
      }
    } catch (e) {
      // Some items use serverTimestamp field names / missing index — soft fail.
      if (kDebugMode) debugPrint('Engagement marketplace fetch: $e');
      try {
        final snap = await FirebaseFirestore.instance
            .collection('marketplace_items')
            .orderBy('createdAt', descending: true)
            .limit(8)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final created = data['createdAt'];
          DateTime? dt;
          if (created is Timestamp) dt = created.toDate();
          if (dt == null || dt.isBefore(cutoff)) continue;
          if (dt.millisecondsSinceEpoch <= lastMarketMs) continue;
          marketCount++;
          marketTitle ??=
              (data['name'] ?? data['title'] ?? data['productName'] ?? '')
                  .toString()
                  .trim();
          if (dt.millisecondsSinceEpoch > newestMarketMs) {
            newestMarketMs = dt.millisecondsSinceEpoch;
          }
        }
      } catch (e2) {
        if (kDebugMode) debugPrint('Engagement marketplace fallback: $e2');
      }
    }

    final hasPromo = promoTitle != null && promoTitle.isNotEmpty;
    final hasArrival = arrivalName != null && arrivalName.isNotEmpty;
    final hasMarket = marketCount > 0;

    if (!hasPromo && !hasArrival && !hasMarket) return null;

    // Prefer one clear CTA — promotions first, then arrivals, then marketplace.
    if (hasPromo) {
      return _DigestSnapshot(
        title: 'New on Vero360',
        body: 'Check out “$promoTitle” and more promotions today.',
        type: 'promo_digest',
        badgeRoute: NotificationStore.kBadgePromotions,
        newestPromoId: newestPromoId,
        newestArrivalId: newestArrivalId,
        newestMarketMs: hasMarket ? newestMarketMs : null,
      );
    }
    if (hasArrival) {
      return _DigestSnapshot(
        title: "Today's arrivals",
        body: 'Fresh on Vero360: $arrivalName. See what’s new.',
        type: 'arrivals_digest',
        badgeRoute: NotificationStore.kBadgePostArrival,
        newestPromoId: newestPromoId,
        newestArrivalId: newestArrivalId,
        newestMarketMs: hasMarket ? newestMarketMs : null,
      );
    }
    final label = (marketTitle != null && marketTitle.isNotEmpty)
        ? marketTitle
        : 'new listings';
    final more = marketCount > 1 ? ' +${marketCount - 1} more' : '';
    return _DigestSnapshot(
      title: 'New on Marketplace',
      body: 'Just listed: $label$more. Open Vero360 to browse.',
      type: 'marketplace_digest',
      badgeRoute: '',
      newestPromoId: newestPromoId,
      newestArrivalId: newestArrivalId,
      newestMarketMs: newestMarketMs,
    );
  }

  Future<void> _markDigestSent(
    SharedPreferences prefs,
    _DigestSnapshot snapshot,
  ) async {
    final now = DateTime.now();
    final dayKey = _dayKey(now);
    final storedDay = prefs.getString(_prefDigestDayKey) ?? '';
    var count = prefs.getInt(_prefDigestCountDay) ?? 0;
    if (storedDay != dayKey) count = 0;

    await prefs.setInt(_prefLastDigestMs, now.millisecondsSinceEpoch);
    await prefs.setString(_prefDigestDayKey, dayKey);
    await prefs.setInt(_prefDigestCountDay, count + 1);

    if (snapshot.newestPromoId != null && snapshot.newestPromoId! > 0) {
      await prefs.setInt(_prefLastPromoId, snapshot.newestPromoId!);
    }
    if (snapshot.newestArrivalId != null &&
        snapshot.newestArrivalId!.isNotEmpty) {
      await prefs.setString(_prefLastArrivalId, snapshot.newestArrivalId!);
    }
    if (snapshot.newestMarketMs != null && snapshot.newestMarketMs! > 0) {
      await prefs.setInt(_prefLastMarketMs, snapshot.newestMarketMs!);
    }
  }

  static String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _DigestSnapshot {
  final String title;
  final String body;
  final String type;
  final String badgeRoute;
  final int? newestPromoId;
  final String? newestArrivalId;
  final int? newestMarketMs;

  const _DigestSnapshot({
    required this.title,
    required this.body,
    required this.type,
    required this.badgeRoute,
    this.newestPromoId,
    this.newestArrivalId,
    this.newestMarketMs,
  });
}
