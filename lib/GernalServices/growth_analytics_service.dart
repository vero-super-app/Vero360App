import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/utils/firebase_bootstrap.dart';

/// Product / growth analytics (Firebase Analytics + first-touch attribution).
/// Separate from car-hire [AnalyticsService].
class GrowthAnalyticsService {
  GrowthAnalyticsService._();
  static final GrowthAnalyticsService instance = GrowthAnalyticsService._();

  static const _prefsFirstTouch = 'growth_first_touch_v1';
  FirebaseAnalytics? _analytics;

  FirebaseAnalytics get analytics {
    _analytics ??= FirebaseAnalytics.instance;
    return _analytics!;
  }

  Future<void> bootstrap() async {
    try {
      await ensureFirebaseApp();
      await analytics.setAnalyticsCollectionEnabled(true);
      await logAppOpen();
    } catch (e) {
      if (kDebugMode) debugPrint('[GrowthAnalytics] bootstrap failed: $e');
    }
  }

  Future<void> logAppOpen() async {
    try {
      await analytics.logAppOpen();
    } catch (_) {}
  }

  Future<void> logLogin({String? method}) async {
    try {
      await analytics.logLogin(loginMethod: method ?? 'unknown');
    } catch (_) {}
  }

  Future<void> logSignUp({String? method}) async {
    try {
      await analytics.logSignUp(signUpMethod: method ?? 'unknown');
      await _stampUserAttributionIfNeeded();
    } catch (_) {}
  }

  Future<void> logServiceOrder({
    required String service,
    String? orderId,
    double? valueMwk,
  }) async {
    try {
      await analytics.logEvent(
        name: 'service_order',
        parameters: {
          'service': service,
          if (orderId != null) 'order_id': orderId,
          if (valueMwk != null) 'value': valueMwk,
          'currency': 'MWK',
        },
      );
    } catch (_) {}
  }

  Future<void> logScreen(String name) async {
    try {
      await analytics.logScreenView(screenName: name);
    } catch (_) {}
  }

  /// Capture UTM / campaign params from deep links and store first-touch.
  Future<void> captureAttributionFromUri(Uri uri) async {
    final q = uri.queryParameters;
    final utmSource = (q['utm_source'] ?? '').trim();
    final utmMedium = (q['utm_medium'] ?? '').trim();
    final utmCampaign = (q['utm_campaign'] ?? '').trim();
    final campaignId = (q['campaign_id'] ?? q['campaignId'] ?? '').trim();
    if (utmSource.isEmpty &&
        utmMedium.isEmpty &&
        utmCampaign.isEmpty &&
        campaignId.isEmpty) {
      return;
    }

    try {
      if (utmSource.isNotEmpty) {
        await analytics.setUserProperty(name: 'utm_source', value: utmSource);
      }
      if (utmMedium.isNotEmpty) {
        await analytics.setUserProperty(name: 'utm_medium', value: utmMedium);
      }
      if (utmCampaign.isNotEmpty) {
        await analytics.setUserProperty(
          name: 'utm_campaign',
          value: utmCampaign,
        );
      }
      await analytics.logEvent(
        name: 'campaign_attribution',
        parameters: {
          if (utmSource.isNotEmpty) 'utm_source': utmSource,
          if (utmMedium.isNotEmpty) 'utm_medium': utmMedium,
          if (utmCampaign.isNotEmpty) 'utm_campaign': utmCampaign,
          if (campaignId.isNotEmpty) 'campaign_id': campaignId,
          'path': uri.path,
        },
      );
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsFirstTouch);
    if (existing == null || existing.isEmpty) {
      final payload = [
        utmSource,
        utmMedium,
        utmCampaign,
        campaignId,
        DateTime.now().toUtc().toIso8601String(),
      ].join('|');
      await prefs.setString(_prefsFirstTouch, payload);
    }

    await _stampUserAttributionIfNeeded();
  }

  Future<void> _stampUserAttributionIfNeeded() async {
    try {
      final ok = await ensureFirebaseApp();
      if (!ok) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsFirstTouch);
      if (raw == null || raw.isEmpty) return;
      final parts = raw.split('|');
      final firstTouch = <String, dynamic>{
        if (parts.isNotEmpty && parts[0].isNotEmpty) 'utmSource': parts[0],
        if (parts.length > 1 && parts[1].isNotEmpty) 'utmMedium': parts[1],
        if (parts.length > 2 && parts[2].isNotEmpty) 'utmCampaign': parts[2],
        if (parts.length > 3 && parts[3].isNotEmpty) 'campaignId': parts[3],
        if (parts.length > 4 && parts[4].isNotEmpty) 'capturedAt': parts[4],
      };
      if (firstTouch.isEmpty) return;

      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final data = snap.data();
      final existing = data?['attribution'];
      if (existing is Map && existing['firstTouch'] != null) return;

      await ref.set(
        {
          'attribution': {
            'firstTouch': firstTouch,
            'lastTouch': firstTouch,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GrowthAnalytics] stamp attribution failed: $e');
      }
    }
  }
}
