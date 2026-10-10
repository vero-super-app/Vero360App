import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/promote_packages_catalog.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

/// Product vertical for promote / boost packages.
enum PromoteVertical {
  marketplace,
  food,
  accommodation,
}

extension PromoteVerticalX on PromoteVertical {
  String get id {
    switch (this) {
      case PromoteVertical.marketplace:
        return 'marketplace';
      case PromoteVertical.food:
        return 'food';
      case PromoteVertical.accommodation:
        return 'accommodation';
    }
  }

  String get feedLabel {
    switch (this) {
      case PromoteVertical.marketplace:
        return 'Marketplace';
      case PromoteVertical.food:
        return 'Food';
      case PromoteVertical.accommodation:
        return 'Stay';
    }
  }

  String get itemsCollection {
    switch (this) {
      case PromoteVertical.marketplace:
        return 'marketplace_items';
      case PromoteVertical.food:
        return 'food_menu_items';
      case PromoteVertical.accommodation:
        return 'accommodation_rooms';
    }
  }

  /// Firestore channel for feed-top boosts.
  String get topChannel {
    switch (this) {
      case PromoteVertical.marketplace:
        return 'marketplace_top';
      case PromoteVertical.food:
        return 'food_top';
      case PromoteVertical.accommodation:
        return 'accommodation_top';
    }
  }

  String get noun {
    switch (this) {
      case PromoteVertical.marketplace:
        return 'product';
      case PromoteVertical.food:
        return 'dish';
      case PromoteVertical.accommodation:
        return 'property';
    }
  }

  static PromoteVertical fromId(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'food':
        return PromoteVertical.food;
      case 'accommodation':
      case 'stay':
        return PromoteVertical.accommodation;
      default:
        return PromoteVertical.marketplace;
    }
  }

  static PromoteVertical? fromTopChannel(String channel) {
    switch (channel) {
      case 'marketplace_top':
        return PromoteVertical.marketplace;
      case 'food_top':
        return PromoteVertical.food;
      case 'accommodation_top':
        return PromoteVertical.accommodation;
      default:
        return null;
    }
  }
}

/// Promote packages (feed top + Facebook ad orders).
class MarketplacePromotePlan {
  final String id;
  final String label;
  final String subtitle;
  final String channel; // *_top | facebook_ads
  final int priceMwk;
  final Duration duration;
  final String reachLabel;

  const MarketplacePromotePlan({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.channel,
    required this.priceMwk,
    required this.duration,
    this.reachLabel = '',
  });

  int get durationHours => duration.inHours;

  String get priceLabel {
    final s = priceMwk.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return 'MWK $buf';
  }

  bool get isFeedTop => channel.endsWith('_top');
  bool get isMarketplaceTop => channel == 'marketplace_top';
  bool get isFacebookAds => channel == 'facebook_ads';
}

List<MarketplacePromotePlan> promotePlansFor(PromoteVertical vertical) {
  final feed = vertical.feedLabel;
  final top = vertical.topChannel;
  final prefix = vertical == PromoteVertical.marketplace
      ? 'mp'
      : (vertical == PromoteVertical.food ? 'food' : 'stay');
  final catalog = PromotePackagesCatalog.instance;
  final top24 = catalog.package('top_24h');
  final top7 = catalog.package('top_7d');
  final fb3 = catalog.package('fb_3d_local');
  final fb7 = catalog.package('fb_7d_wider');

  final plans = <MarketplacePromotePlan>[
    if (top24.active)
      MarketplacePromotePlan(
        id: '${prefix}_24h',
        label: top24.label.isNotEmpty ? top24.label : '24 hours on top',
        subtitle: top24.subtitle.isNotEmpty
            ? top24.subtitle
            : 'Stay at the top of $feed for 24 hours',
        channel: top,
        priceMwk: top24.priceMwk,
        duration: Duration(hours: top24.durationHours),
      ),
    if (top7.active)
      MarketplacePromotePlan(
        id: '${prefix}_7d',
        label: top7.label.isNotEmpty ? top7.label : '1 week on top',
        subtitle: top7.subtitle.isNotEmpty
            ? top7.subtitle
            : 'Stay at the top of $feed for 7 days',
        channel: top,
        priceMwk: top7.priceMwk,
        duration: Duration(hours: top7.durationHours),
      ),
    if (fb3.active)
      MarketplacePromotePlan(
        id: 'fb_3d_local',
        label: fb3.label.isNotEmpty ? fb3.label : 'Facebook ads · 3 days',
        subtitle: fb3.subtitle.isNotEmpty
            ? fb3.subtitle
            : 'Local reach · Vero360 runs the campaign for you',
        channel: 'facebook_ads',
        priceMwk: fb3.priceMwk,
        duration: Duration(hours: fb3.durationHours),
        reachLabel: fb3.reachLabel,
      ),
    if (fb7.active)
      MarketplacePromotePlan(
        id: 'fb_7d_wider',
        label: fb7.label.isNotEmpty ? fb7.label : 'Facebook ads · 7 days',
        subtitle: fb7.subtitle.isNotEmpty
            ? fb7.subtitle
            : 'Wider reach · Vero360 runs the campaign for you',
        channel: 'facebook_ads',
        priceMwk: fb7.priceMwk,
        duration: Duration(hours: fb7.durationHours),
        reachLabel: fb7.reachLabel,
      ),
  ];

  // Never return empty — fall back to defaults if admin disabled everything.
  if (plans.isEmpty) {
    return [
      MarketplacePromotePlan(
        id: '${prefix}_24h',
        label: '24 hours on top',
        subtitle: 'Stay at the top of $feed for 24 hours',
        channel: top,
        priceMwk: 2000,
        duration: const Duration(hours: 24),
      ),
    ];
  }
  return plans;
}

/// Back-compat alias for marketplace-only callers.
List<MarketplacePromotePlan> get kMarketplacePromotePlans =>
    promotePlansFor(PromoteVertical.marketplace);

class MarketplacePromoteService {
  MarketplacePromoteService._();

  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _promos =>
      _db.collection('marketplace_promotions');

  static DateTime? parsePromotedUntil(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  static bool isPromotedNow(Map<String, dynamic> item) {
    final until = parsePromotedUntil(item['promotedUntil']);
    if (until == null) return false;
    return until.isAfter(DateTime.now());
  }

  static bool isPromotedUntilLive(DateTime? until) {
    if (until == null) return false;
    return until.isAfter(DateTime.now());
  }

  static Future<String> createPendingPromotion({
    required String itemId,
    required Map<String, dynamic> item,
    required MarketplacePromotePlan plan,
    required String merchantId,
    String? merchantName,
    required String txRef,
    PromoteVertical vertical = PromoteVertical.marketplace,
  }) async {
    final doc = _promos.doc();
    final fallbackName = vertical == PromoteVertical.food
        ? 'Food dish'
        : (vertical == PromoteVertical.accommodation
            ? 'Stay property'
            : 'Marketplace item');
    final name = (item['name'] ?? fallbackName).toString().trim();
    final image = (item['imageUrl'] ?? item['image'] ?? '').toString().trim();
    await doc.set({
      'itemId': itemId,
      'itemName': name,
      'itemImage': image.startsWith('http') ? image : '',
      'merchantId': merchantId,
      'merchantName': (merchantName ?? '').trim(),
      'vertical': vertical.id,
      'planId': plan.id,
      'channel': plan.channel,
      'amountMwk': plan.priceMwk,
      'durationHours': plan.durationHours,
      'reachLabel': plan.reachLabel,
      'status': 'pending_payment',
      'txRef': txRef,
      'createdAt': FieldValue.serverTimestamp(),
      if (plan.isFacebookAds) 'fulfillmentStatus': 'queued',
      'adminNotes': '',
    });
    return doc.id;
  }

  /// Confirms PayChangu payment on the server, then activates boost / FB ad order.
  /// Clients cannot write status=paid/active (Firestore rules + CF verify).
  static Future<void> activateAfterPayment({
    required String promoId,
    required String txRef,
  }) async {
    final callable = FirebaseFunctions.instance
        .httpsCallable('activateMarketplacePromotion');
    try {
      await callable.call(<String, dynamic>{
        'promoId': promoId,
        'txRef': txRef,
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(
        (e.message ?? e.code).toString().trim().isEmpty
            ? 'Could not activate promotion'
            : (e.message ?? e.code),
      );
    }

    // Platform fee bookkeeping (optional; CF already set active/paid).
    final ref = _promos.doc(promoId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    if (data['platformFeeCredited'] == true) return;

    final amount = (data['amountMwk'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return;

    final planId = (data['planId'] ?? '').toString();
    final channel = (data['channel'] ?? '').toString();
    final itemName = (data['itemName'] ?? 'Promote').toString();
    final vertical = PromoteVerticalX.fromTopChannel(channel) ??
        PromoteVerticalX.fromId(data['vertical']?.toString());

    try {
      await FirebaseWalletService.creditPlatformServiceFee(
        amount: amount,
        description: '${vertical.feedLabel} promote · $itemName · $planId',
        reference: txRef.isNotEmpty ? txRef : 'promo:$promoId',
        service: 'promotions',
      );
      await ref.set({
        'platformFeeCredited': true,
        'platformFeeAmount': amount,
        'platformFeeMode': 'full',
        'platformFeeCreditedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Admin dashboard can backfill via "Credit platform fee".
    }
  }

  static Future<void> startCheckout({
    required BuildContext context,
    required String itemId,
    required Map<String, dynamic> item,
    required MarketplacePromotePlan plan,
    PromoteVertical vertical = PromoteVertical.marketplace,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please log in to promote this ${vertical.noun}.');
    }

    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('name') ??
            prefs.getString('fullName') ??
            user.displayName ??
            'Merchant')
        .trim();
    final email = (prefs.getString('email') ?? user.email ?? '').trim();
    var phone = (prefs.getString('phone') ?? prefs.getString('phoneNumber') ?? '')
        .trim();
    if (phone.isEmpty) phone = '0990000000';
    if (email.isEmpty || !email.contains('@')) {
      throw StateError('Add a valid email on your profile before paying.');
    }

    final shortUid =
        user.uid.length >= 6 ? user.uid.substring(0, 6) : user.uid;
    final txPrefix = vertical == PromoteVertical.food
        ? 'vero-food'
        : (vertical == PromoteVertical.accommodation
            ? 'vero-stay'
            : 'vero-mp');
    final txRef =
        '$txPrefix-$shortUid-${DateTime.now().millisecondsSinceEpoch}';

    final merchantName = (item['merchantName'] ??
            item['businessName'] ??
            prefs.getString('business_name') ??
            name)
        .toString();

    final promoId = await createPendingPromotion(
      itemId: itemId,
      item: item,
      plan: plan,
      merchantId: user.uid,
      merchantName: merchantName,
      txRef: txRef,
      vertical: vertical,
    );

    await AuthStorage.userIdFromToken();

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InAppPaymentPage(
          txRef: txRef,
          totalAmount: plan.priceMwk.toDouble(),
          rootContext: context,
          popOnlyOnSuccess: true,
          onSuccessNavigate: (rootCtx) async {
            try {
              await activateAfterPayment(promoId: promoId, txRef: txRef);
              if (rootCtx.mounted) {
                final msg = plan.isFeedTop
                    ? '${vertical.feedLabel} listing promoted for ${plan.label} — also sharing to Facebook Page.'
                    : 'Promotion paid — sharing to Facebook Page and queuing your campaign.';
                ToastHelper.showCustomToast(
                  rootCtx,
                  msg,
                  isSuccess: true,
                  errorMessage: '',
                );
                if (Navigator.of(rootCtx).canPop()) {
                  Navigator.of(rootCtx).pop(true);
                }
              }
            } catch (e) {
              if (rootCtx.mounted) {
                ToastHelper.showCustomToast(
                  rootCtx,
                  'Payment received, but promote activation failed. Open Promoted ads in admin and tap Verify & mark paid, or try again.',
                  isSuccess: false,
                  errorMessage: UserFacingError.from(e),
                );
                if (Navigator.of(rootCtx).canPop()) {
                  Navigator.of(rootCtx).pop(false);
                }
              }
            }
          },
        ),
      ),
    );
  }

  static Future<void> presentPromoteSheet({
    required BuildContext context,
    required String itemId,
    required Map<String, dynamic> item,
    PromoteVertical vertical = PromoteVertical.marketplace,
  }) async {
    await PromotePackagesCatalog.instance.ensureLoaded();
    final plans = promotePlansFor(vertical);
    MarketplacePromotePlan? selected = plans.first;
    var paying = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final promoted = isPromotedNow(item);
            final until = parsePromotedUntil(item['promotedUntil']);
            // Rebuild when admin updates prices while sheet is open.
            return AnimatedBuilder(
              animation: PromotePackagesCatalog.instance,
              builder: (ctx, _) {
                final livePlans = promotePlansFor(vertical);
                if (selected == null ||
                    !livePlans.any((p) => p.id == selected!.id)) {
                  selected = livePlans.first;
                }
                return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(ctx).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (item['name'] ?? 'Promote ${vertical.noun}').toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    promoted && until != null
                        ? 'Currently boosted until ${_fmtWhen(until)}'
                        : 'Choose how to promote this ${vertical.noun}',
                    style: TextStyle(
                      color: promoted ? const Color(0xFF166534) : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...livePlans.map((plan) {
                    final on = selected?.id == plan.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: on
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: paying
                              ? null
                              : () => setModal(() => selected = plan),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  on
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: on
                                      ? const Color(0xFFFF8A00)
                                      : Colors.black38,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        plan.subtitle,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (plan.reachLabel.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          plan.reachLabel,
                                          style: const TextStyle(
                                            color: Color(0xFFC2410C),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Text(
                                  plan.priceLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFFF8A00),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: paying || selected == null
                        ? null
                        : () async {
                            setModal(() => paying = true);
                            try {
                              await startCheckout(
                                context: ctx,
                                itemId: itemId,
                                item: item,
                                plan: selected!,
                                vertical: vertical,
                              );
                            } catch (e) {
                              if (ctx.mounted) {
                                ToastHelper.showCustomToast(
                                  ctx,
                                  UserFacingError.from(
                                    e,
                                    fallback: 'Could not start payment',
                                  ),
                                  isSuccess: false,
                                  errorMessage: 'Promote failed',
                                );
                              }
                            } finally {
                              if (ctx.mounted) setModal(() => paying = false);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      paying
                          ? 'Starting…'
                          : 'Pay ${selected!.priceLabel}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// After a successful post — teach first-time (and returning) sellers about boost.
  static Future<void> presentPostSuccessBoostPrompt({
    required BuildContext context,
    required String itemId,
    required Map<String, dynamic> item,
    PromoteVertical vertical = PromoteVertical.marketplace,
  }) async {
    if (!context.mounted || itemId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final seenBefore = prefs.getBool('vero_boost_tip_seen_v1') ?? false;
    await prefs.setBool('vero_boost_tip_seen_v1', true);
    if (!context.mounted) return;

    final noun = vertical.noun;
    final feed = vertical.feedLabel;
    final pending = (item['reviewStatus']?.toString() ?? '') == 'pending' ||
        item['isActive'] != true;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(ctx).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFFFF8A00),
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                seenBefore ? 'Boost this $noun?' : 'New: boost your $noun',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                seenBefore
                    ? 'Promote this $noun so more buyers see it at the top of $feed.'
                    : 'Did you know? You can boost any $noun to the top of $feed. '
                        'Look for the megaphone / Promote button on your items.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
              if (pending) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    'Your $noun is under review. You can pick a boost package now — '
                    'it helps as soon as the listing goes live.',
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop('boost'),
                icon: const Icon(Icons.rocket_launch_rounded),
                label: const Text(
                  'Boost / Promote',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8A00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('later'),
                child: Text(
                  'Not now',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (action != 'boost' || !context.mounted) return;
    await presentPromoteSheet(
      context: context,
      itemId: itemId,
      item: item,
      vertical: vertical,
    );
  }

  static String _fmtWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
