import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/firebase_wallet_service.dart';
import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/utils/profile_open_helper.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Homepage advert packages.
class AdvertPlan {
  final String id;
  final String label;
  final String subtitle;
  final int priceMwk;
  final Duration duration;

  const AdvertPlan({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.priceMwk,
    required this.duration,
  });

  int get durationHours => duration.inHours;
  int get durationDays => (duration.inHours / 24).ceil();

  String get priceLabel => 'MK ${_fmt(priceMwk)}';

  static String formatMwk(num n) {
    final whole = n.round();
    return 'MK ${_fmt(whole)}';
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

const kAdvertPlans = <AdvertPlan>[
  AdvertPlan(
    id: '24h',
    label: '24 hours',
    subtitle: 'Quick boost',
    priceMwk: 1000,
    duration: Duration(hours: 24),
  ),
  AdvertPlan(
    id: '3d',
    label: '3 days',
    subtitle: 'Best value',
    priceMwk: 2500,
    duration: Duration(days: 3),
  ),
  AdvertPlan(
    id: '7d',
    label: '1 week',
    subtitle: 'Max reach',
    priceMwk: 5000,
    duration: Duration(days: 7),
  ),
];

const kAdvertCategories = <String>[
  'Food & Drinks',
  'Electronics',
  'Fashion',
  'Services',
  'Real Estate',
  'Events',
  'Transport',
  'Other',
];

class _AdColors {
  static const brandOrange = Color(0xFFFF6B00);
  static const brandOrangeDeep = Color(0xFFD94F00);
  static const brandOrangeLight = Color(0xFFFF9A3C);
  static const brandOrangeSoft = Color(0xFFFFE8CC);
  static const title = Color(0xFF111111);
  static const body = Color(0xFF666666);
  static const pageBg = Color(0xFFFFFBF6);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFF0E6DA);
}

const _adBrandGradient = LinearGradient(
  colors: [_AdColors.brandOrange, _AdColors.brandOrangeLight],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class HomepageAdvert {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String userId;
  final String userName;
  final String status;
  final String category;
  final int? backendUserId;
  /// Selling price for Buy now (optional). Not the advert package fee.
  final double? productPrice;
  final DateTime? endsAt;
  final DateTime? startsAt;

  const HomepageAdvert({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.userId,
    required this.status,
    this.userName = '',
    this.category = '',
    this.backendUserId,
    this.productPrice,
    this.endsAt,
    this.startsAt,
  });

  String get displayName {
    if (userName.trim().isNotEmpty) return userName.trim();
    if (title.trim().isNotEmpty) return title.trim();
    return 'Advertiser';
  }

  bool get hasBuyNow => productPrice != null && productPrice! > 0;

  String? get productPriceLabel =>
      hasBuyNow ? AdvertPlan.formatMwk(productPrice!) : null;

  factory HomepageAdvert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    int? backendId;
    final rawBackend = j['backendUserId'] ?? j['user_id'];
    if (rawBackend is int) {
      backendId = rawBackend;
    } else if (rawBackend != null) {
      backendId = int.tryParse(rawBackend.toString());
    }

    double? productPrice;
    final rawPrice = j['productPrice'] ?? j['sellingPrice'];
    if (rawPrice is num) {
      productPrice = rawPrice.toDouble();
    } else if (rawPrice != null) {
      productPrice = double.tryParse(rawPrice.toString().replaceAll(',', ''));
    }
    if (productPrice != null && productPrice <= 0) productPrice = null;

    return HomepageAdvert(
      id: doc.id,
      title: (j['title'] ?? '').toString().trim(),
      description: (j['description'] ?? '').toString().trim(),
      imageUrl: (j['imageUrl'] ?? '').toString().trim(),
      userId: (j['userId'] ?? '').toString().trim(),
      userName: (j['userName'] ?? '').toString().trim(),
      status: (j['status'] ?? '').toString().toLowerCase(),
      category: (j['category'] ?? '').toString().trim(),
      backendUserId: (backendId != null && backendId > 0) ? backendId : null,
      productPrice: productPrice,
      endsAt: ts(j['endsAt']),
      startsAt: ts(j['startsAt']),
    );
  }

  bool get isLive {
    if (status != 'active') return false;
    final end = endsAt;
    if (end == null) return true;
    return end.isAfter(DateTime.now());
  }
}

class HomepageAdvertService {
  HomepageAdvertService._();

  static final _col =
      FirebaseFirestore.instance.collection('homepage_adverts');

  /// Real account required — no anonymous advertising.
  static Future<User> requireLoggedInUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('Please log in to place an advert.');
    }
    if (!await AuthHandler.isAuthenticated()) {
      throw Exception('Please log in to place an advert.');
    }
    return user;
  }

  static Future<bool> isProperlyLoggedIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;
    return AuthHandler.isAuthenticated();
  }

  static Stream<List<HomepageAdvert>> watchActiveAdverts() {
    return _col
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(HomepageAdvert.fromDoc)
          .where((a) => a.isLive && a.imageUrl.isNotEmpty)
          .toList();
      list.sort((a, b) {
        final ae = a.endsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final be = b.endsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return be.compareTo(ae);
      });
      return list;
    });
  }

  static Future<String> uploadImage({
    required String userId,
    required File file,
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt =
        (ext == 'png' || ext == 'webp' || ext == 'jpg' || ext == 'jpeg')
            ? ext
            : 'jpg';
    final path =
        'homepage_adverts/$userId/${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final ref = FirebaseStorage.instance.ref().child(path);
    final mime = safeExt == 'png'
        ? 'image/png'
        : safeExt == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    await ref.putFile(file, SettableMetadata(contentType: mime));
    return ref.getDownloadURL();
  }

  static Future<String> createPendingAdvert({
    required String userId,
    required String title,
    required String description,
    required String imageUrl,
    required String txRef,
    required String category,
    required AdvertPlan plan,
    String? userName,
    String? userEmail,
    String? phone,
    int? backendUserId,
    double? productPrice,
  }) async {
    final doc = _col.doc();
    await doc.set({
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'userId': userId,
      'merchantId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'phone': phone,
      if (backendUserId != null && backendUserId > 0)
        'backendUserId': backendUserId,
      if (productPrice != null && productPrice > 0) 'productPrice': productPrice,
      'category': category,
      'planId': plan.id,
      'status': 'pending_payment',
      'priceMwk': plan.priceMwk,
      'durationHours': plan.durationHours,
      'durationDays': plan.durationDays,
      'txRef': txRef,
      'active': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> activateAfterPayment({
    required String advertId,
    required String txRef,
  }) async {
    final ref = _col.doc(advertId);
    final snap = await ref.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final hours = (data['durationHours'] as num?)?.toInt() ??
        (((data['durationDays'] as num?)?.toInt() ?? 7) * 24);
    final amount = (data['priceMwk'] as num?)?.toDouble() ?? 0;
    final title = (data['title'] ?? 'Homepage advert').toString().trim();
    final alreadyCredited = data['platformFeeCredited'] == true;
    final now = DateTime.now();
    final ends = now.add(Duration(hours: hours));

    var feeCreditedNow = false;
    if (!alreadyCredited && amount > 0) {
      try {
        await FirebaseWalletService.creditPlatformServiceFee(
          amount: amount,
          description: 'Homepage advert fee · $title',
          reference: txRef.isNotEmpty ? txRef : 'homepage_ad:$advertId',
        );
        feeCreditedNow = true;
      } catch (_) {
        // Admin dashboard can backfill via "Credit platform fee".
      }
    }

    await ref.set({
      'status': 'active',
      'active': true,
      'txRef': txRef,
      'paidAt': FieldValue.serverTimestamp(),
      'startsAt': Timestamp.fromDate(now),
      'endsAt': Timestamp.fromDate(ends),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!alreadyCredited && feeCreditedNow) ...{
        'platformFeeCredited': true,
        'platformFeeCreditedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }
}

/// Sliding homepage adverts + always-on "Advertise here" slide.
class HomepageAdvertsSection extends StatefulWidget {
  const HomepageAdvertsSection({super.key});

  @override
  State<HomepageAdvertsSection> createState() => _HomepageAdvertsSectionState();
}

class _HomepageAdvertsSectionState extends State<HomepageAdvertsSection> {
  int _index = 0;

  Future<void> _openAdvertise() async {
    final ok = await HomepageAdvertService.isProperlyLoggedIn();
    if (!ok) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Log in to advertise on the homepage',
        isSuccess: false,
        errorMessage: '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted) return;
      if (!await HomepageAdvertService.isProperlyLoggedIn()) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdvertiseHerePage()),
    );
  }

  void _openAdvert(HomepageAdvert ad) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            24 + MediaQuery.of(ctx).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              GestureDetector(
                onTap: () => _viewAdvertPicture(ad.imageUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ResilientCachedNetworkImage(
                          url: ad.imageUrl,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'View picture',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (ad.category.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _AdColors.brandOrangeSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    ad.category,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _AdColors.brandOrangeDeep,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                ad.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _AdColors.title,
                ),
              ),
              if (ad.hasBuyNow) ...[
                const SizedBox(height: 8),
                Text(
                  ad.productPriceLabel!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _AdColors.brandOrangeDeep,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
              if (ad.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  ad.description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: _AdColors.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (ad.hasBuyNow) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _AdvertActionButton(
                    icon: Icons.shopping_bag_rounded,
                    label: 'Buy now',
                    filled: true,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _buyNowFromAdvert(ad);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AdvertActionButton(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Message',
                      filled: !ad.hasBuyNow,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _messageAdvertiser(ad);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AdvertActionButton(
                      icon: Icons.storefront_rounded,
                      label: 'View shop',
                      filled: false,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _viewAdvertiserShop(ad);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _messageAdvertiser(HomepageAdvert ad) async {
    final merchantId = ad.userId.trim();
    if (merchantId.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'This advertiser is not available for messaging yet.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    if (!await AuthHandler.isAuthenticated() ||
        FirebaseAuth.instance.currentUser == null ||
        FirebaseAuth.instance.currentUser!.isAnonymous) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Log in to message this advertiser',
        isSuccess: false,
        errorMessage: '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted) return;
      if (!await AuthHandler.isAuthenticated()) return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isNotEmpty && me == merchantId) {
      ToastHelper.showCustomToast(
        context,
        'You can’t message your own advert.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: _AdColors.brandOrange),
      ),
    );

    try {
      final result = await BackendChatService.startMerchantChat(
        merchantId: merchantId,
        sellerUserId: ad.backendUserId?.toString(),
        ownerId: ad.backendUserId,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessagePageBackendApi(
            peerId: result.chat.id,
            peerName: ad.displayName,
            peerMerchantId: merchantId,
            peerUserId: result.sellerId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // loading
        ToastHelper.showCustomToast(
          context,
          UserFacingError.from(
            e,
            fallback: 'Could not open chat. Try again.',
          ),
          isSuccess: false,
          errorMessage: 'Chat failed',
        );
      }
    }
  }

  Future<void> _viewAdvertiserShop(HomepageAdvert ad) async {
    final merchantId = ad.userId.trim();
    if (merchantId.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Shop is not available for this advert yet.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    await openMerchantOrDriverProfile(
      context,
      profileId: merchantId,
      displayName: ad.displayName,
    );
  }

  void _viewAdvertPicture(String imageUrl) {
    final url = imageUrl.trim();
    if (url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AdvertPictureViewer(imageUrl: url),
      ),
    );
  }

  int _stablePositiveId(String input) {
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final cu in input.codeUnits) {
      hash ^= cu;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    final v = hash & 0x7FFFFFFF;
    return v == 0 ? 1 : v;
  }

  Future<void> _buyNowFromAdvert(HomepageAdvert ad) async {
    if (!ad.hasBuyNow) return;

    if (!await AuthHandler.isAuthenticated() ||
        FirebaseAuth.instance.currentUser == null ||
        FirebaseAuth.instance.currentUser!.isAnonymous) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Log in to buy this item',
        isSuccess: false,
        errorMessage: '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted) return;
      if (!await AuthHandler.isAuthenticated()) return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isNotEmpty && me == ad.userId.trim()) {
      ToastHelper.showCustomToast(
        context,
        'You can’t buy your own advert.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    final merchantId = ad.userId.trim();
    final checkoutItem = MarketplaceDetailModel(
      id: _stablePositiveId('homepage_ad:${ad.id}'),
      name: ad.title.isEmpty ? 'Homepage advert' : ad.title,
      image: ad.imageUrl,
      price: ad.productPrice!,
      description: ad.description,
      location: '',
      category: ad.category.isEmpty ? null : ad.category,
      merchantId: merchantId.isEmpty ? null : merchantId,
      merchantName: ad.displayName,
      sellerUserId: ad.backendUserId?.toString() ??
          (merchantId.isEmpty ? null : merchantId),
      merchantBackendId: ad.backendUserId,
      firestoreDocId: ad.id,
      serviceType: 'homepage_advert',
      stockQuantity: 99,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutPage(item: checkoutItem),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HomepageAdvert>>(
      stream: HomepageAdvertService.watchActiveAdverts(),
      builder: (context, snap) {
        final ads = snap.data ?? const <HomepageAdvert>[];
        // Last slide is always the advertise CTA.
        final count = ads.length + 1;
        final pageIndex = _index.clamp(0, count - 1);

        // Same footprint as homepage [_PromoBanner]: 16 inset, ~104 tall.
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CarouselSlider.builder(
                itemCount: count,
                options: CarouselOptions(
                  height: 104,
                  viewportFraction: 1,
                  enableInfiniteScroll: count > 1,
                  autoPlay: count > 1,
                  autoPlayInterval: const Duration(seconds: 5),
                  autoPlayAnimationDuration:
                      const Duration(milliseconds: 650),
                  enlargeCenterPage: false,
                  padEnds: false,
                  onPageChanged: (i, _) => setState(() => _index = i),
                ),
                itemBuilder: (_, i, __) {
                  if (i == ads.length) {
                    return _AdvertiseCtaSlide(onTap: _openAdvertise);
                  }
                  return _AdvertSlide(
                    advert: ads[i],
                    onTap: () => _openAdvert(ads[i]),
                  );
                },
              ),
            ),
            if (count > 1) ...[
              const SizedBox(height: 8),
              _AdvertDots(count: count, index: pageIndex),
            ],
          ],
        );
      },
    );
  }
}

class _AdvertPictureViewer extends StatelessWidget {
  final String imageUrl;
  const _AdvertPictureViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: ResilientCachedNetworkImage(
                  url: imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.white.withOpacity(0.15),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvertActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _AdvertActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : _AdColors.brandOrangeDeep;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            gradient: filled ? _adBrandGradient : null,
            color: filled ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: _AdColors.brandOrange.withOpacity(0.45)),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: _AdColors.brandOrange.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvertDots extends StatelessWidget {
  final int count;
  final int index;
  const _AdvertDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: on ? _AdColors.brandOrange : _AdColors.brandOrangeSoft,
          ),
        );
      }),
    );
  }
}

class _AdvertiseCtaSlide extends StatelessWidget {
  final VoidCallback onTap;
  const _AdvertiseCtaSlide({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_AdColors.brandOrangeDeep, _AdColors.brandOrange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _AdColors.brandOrange.withOpacity(0.40),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.10),
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: -30,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Advertise',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Advertise on Vero360',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'From MK 1,000',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.80),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: const Text(
                            'Advertise here',
                            style: TextStyle(
                              color: _AdColors.brandOrange,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvertSlide extends StatelessWidget {
  final HomepageAdvert advert;
  final VoidCallback onTap;
  const _AdvertSlide({required this.advert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = advert.title.isEmpty ? 'Sponsored' : advert.title;
    final subtitle = advert.hasBuyNow
        ? advert.productPriceLabel!
        : (advert.category.isNotEmpty
            ? advert.category
            : (advert.description.isEmpty ? 'Tap to view' : advert.description));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _AdColors.brandOrange.withOpacity(0.40),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ResilientCachedNetworkImage(
              url: advert.imageUrl,
              fit: BoxFit.cover,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withOpacity(0.72),
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.15),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'Ad',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.80),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create a homepage advert — login required, plans + categories.
class AdvertiseHerePage extends StatefulWidget {
  const AdvertiseHerePage({super.key});

  @override
  State<AdvertiseHerePage> createState() => _AdvertiseHerePageState();
}

class _AdvertiseHerePageState extends State<AdvertiseHerePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _productPriceCtrl = TextEditingController();

  File? _imageFile;
  bool _submitting = false;
  bool _checkingAuth = true;
  bool _loggedIn = false;
  bool _enableBuyNow = false;

  AdvertPlan _plan = kAdvertPlans[1];
  String? _category;

  String _accountName = '';
  String _accountEmail = '';
  String _accountPhone = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final ok = await HomepageAdvertService.isProperlyLoggedIn();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _checkingAuth = false;
        _loggedIn = false;
      });
      return;
    }
    await _loadAccount();
    if (!mounted) return;
    setState(() {
      _checkingAuth = false;
      _loggedIn = true;
    });
  }

  Future<void> _loadAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final name = (prefs.getString('name') ??
              prefs.getString('userName') ??
              user?.displayName ??
              '')
          .trim();
      final email =
          (prefs.getString('email') ?? user?.email ?? '').trim();
      var phone = (prefs.getString('phone') ??
              user?.phoneNumber ??
              '')
          .trim();
      if (phone.toLowerCase().startsWith('+firebase_')) phone = '';
      if (!mounted) return;
      setState(() {
        _accountName = name.isNotEmpty ? name : 'Vero360 member';
        _accountEmail = email;
        _accountPhone = phone;
      });
    } catch (_) {}
  }

  Future<void> _goLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (!mounted) return;
    await _bootstrap();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _productPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 900,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() => _imageFile = File(x.path));
  }

  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 &&
        (digits.startsWith('0') || digits.startsWith('265'))) {
      final rest =
          digits.startsWith('265') ? digits.substring(3) : digits.substring(1);
      return '+265$rest';
    }
    return raw.trim().isEmpty
        ? '+265888000000'
        : (raw.startsWith('+') ? raw : '+$raw');
  }

  Future<void> _submitAndPay() async {
    if (!_loggedIn) {
      await _goLogin();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_category == null || _category!.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Choose a category for your advert',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    if (_imageFile == null) {
      ToastHelper.showCustomToast(
        context,
        'Add a picture for your advert',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    if (_accountEmail.isEmpty || !_accountEmail.contains('@')) {
      ToastHelper.showCustomToast(
        context,
        'Your account needs a valid email. Update your profile, then try again.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    double? productPrice;
    if (_enableBuyNow) {
      final raw = _productPriceCtrl.text.trim().replaceAll(',', '');
      productPrice = double.tryParse(raw);
      if (productPrice == null || productPrice <= 0) {
        ToastHelper.showCustomToast(
          context,
          'Enter a valid product price for Buy now',
          isSuccess: false,
          errorMessage: '',
        );
        return;
      }
    }

    setState(() => _submitting = true);
    String? advertId;
    try {
      final user = await HomepageAdvertService.requireLoggedInUser();
      final title = _titleCtrl.text.trim();
      final description = _descCtrl.text.trim();
      final name = _accountName.trim().isEmpty
          ? 'Vero360 member'
          : _accountName.trim();
      final email = _accountEmail.trim();
      final phone = _normalizePhone(_accountPhone);
      final parts = name.split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : 'Advertiser';
      final lastName =
          parts.length > 1 ? parts.sublist(1).join(' ') : 'Vero360';

      final imageUrl = await HomepageAdvertService.uploadImage(
        userId: user.uid,
        file: _imageFile!,
      );

      final shortUid =
          user.uid.length >= 6 ? user.uid.substring(0, 6) : user.uid;
      final txRef =
          'vero-ad-$shortUid-${DateTime.now().millisecondsSinceEpoch}';

      final backendUserId = await AuthStorage.userIdFromToken();

      advertId = await HomepageAdvertService.createPendingAdvert(
        userId: user.uid,
        title: title,
        description: description,
        imageUrl: imageUrl,
        txRef: txRef,
        category: _category!,
        plan: _plan,
        userName: name,
        userEmail: email,
        phone: phone,
        backendUserId: backendUserId,
        productPrice: productPrice,
      );

      final response = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode({
              'tx_ref': txRef,
              'first_name': firstName,
              'last_name': lastName,
              'email': email,
              'phone_number': phone,
              'currency': 'MWK',
              'amount': _plan.priceMwk.toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero360 Homepage Ad',
                'description':
                    'Homepage advert · ${_plan.label} · $_category · $title',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status != 'success') {
        throw Exception(data['message']?.toString() ?? 'Payment init failed');
      }
      final checkoutUrl = data['data']?['checkout_url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('No checkout URL from payment provider');
      }

      if (!mounted) return;
      final paidId = advertId;
      final planLabel = _plan.label;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InAppPaymentPage(
            checkoutUrl: checkoutUrl,
            txRef: txRef,
            totalAmount: _plan.priceMwk.toDouble(),
            rootContext: context,
            popOnlyOnSuccess: true,
            onSuccessNavigate: (rootCtx) async {
              try {
                await HomepageAdvertService.activateAfterPayment(
                  advertId: paidId,
                  txRef: txRef,
                );
              } catch (_) {}
              if (rootCtx.mounted) {
                ToastHelper.showCustomToast(
                  rootCtx,
                  'Advert live for $planLabel. Thank you!',
                  isSuccess: true,
                  errorMessage: '',
                );
                Navigator.of(rootCtx).popUntil((r) => r.isFirst);
              }
            },
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Connection timeout. Please try again.',
        isSuccess: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        UserFacingError.from(
          e,
          fallback: 'Could not start payment. Please try again.',
        ),
        isSuccess: false,
        errorMessage: 'Payment failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDeco({
    required String label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _AdColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AdColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AdColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _AdColors.brandOrange, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AdColors.pageBg,
      body: _checkingAuth
          ? const Center(
              child: CircularProgressIndicator(color: _AdColors.brandOrange),
            )
          : !_loggedIn
              ? _LoginGate(onLogin: _goLogin)
              : Column(
                  children: [
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: _submitting,
                        child: CustomScrollView(
                          slivers: [
                            SliverAppBar(
                              pinned: true,
                              expandedHeight: 148,
                              backgroundColor: _AdColors.brandOrange,
                              foregroundColor: Colors.white,
                              flexibleSpace: FlexibleSpaceBar(
                                background: Container(
                                  decoration: const BoxDecoration(
                                    gradient: _adBrandGradient,
                                  ),
                                  child: SafeArea(
                                    bottom: false,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          56, 12, 20, 20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          const Text(
                                            'Advertise here',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 24,
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Reach the Vero360 homepage. From MK 1,000.',
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withOpacity(0.9),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  const _SectionLabel('Duration'),
                                  const SizedBox(height: 10),
                                  ...kAdvertPlans.map((p) {
                                    final selected = _plan.id == p.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _PlanTile(
                                        plan: p,
                                        selected: selected,
                                        onTap: () =>
                                            setState(() => _plan = p),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 8),
                                  const _SectionLabel('Category'),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: kAdvertCategories.map((c) {
                                      final on = _category == c;
                                      return ChoiceChip(
                                        label: Text(c),
                                        selected: on,
                                        onSelected: (_) =>
                                            setState(() => _category = c),
                                        selectedColor:
                                            _AdColors.brandOrangeSoft,
                                        labelStyle: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: on
                                              ? _AdColors.brandOrangeDeep
                                              : _AdColors.body,
                                          fontSize: 13,
                                        ),
                                        side: BorderSide(
                                          color: on
                                              ? _AdColors.brandOrange
                                              : _AdColors.line,
                                        ),
                                        backgroundColor: Colors.white,
                                        showCheckmark: false,
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 18),
                                  const _SectionLabel('Creative'),
                                  const SizedBox(height: 10),
                                  Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        GestureDetector(
                                          onTap: _pickImage,
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            height: 180,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                color: _imageFile == null
                                                    ? _AdColors.line
                                                    : _AdColors.brandOrange
                                                        .withOpacity(0.45),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.04),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: _imageFile != null
                                                ? Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      Image.file(
                                                        _imageFile!,
                                                        fit: BoxFit.cover,
                                                      ),
                                                      Positioned(
                                                        right: 10,
                                                        bottom: 10,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .black54,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        99),
                                                          ),
                                                          child: const Text(
                                                            'Change photo',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Container(
                                                        width: 52,
                                                        height: 52,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: _AdColors
                                                              .brandOrangeSoft,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      16),
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .add_photo_alternate_outlined,
                                                          color: _AdColors
                                                              .brandOrange,
                                                          size: 26,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 10),
                                                      const Text(
                                                        'Add advert picture',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              _AdColors.title,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 4),
                                                      Text(
                                                        'Recommended 16:9',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade600,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _titleCtrl,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: _fieldDeco(
                                            label: 'Title',
                                            hint: 'e.g. Fresh juice · Blantyre',
                                          ),
                                          validator: (v) {
                                            if (v == null ||
                                                v.trim().isEmpty) {
                                              return 'Enter a title';
                                            }
                                            if (v.trim().length < 3) {
                                              return 'Title is too short';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _descCtrl,
                                          maxLines: 3,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: _fieldDeco(
                                            label: 'Description',
                                            hint: 'What should people know?',
                                          ),
                                          validator: (v) {
                                            if (v == null ||
                                                v.trim().isEmpty) {
                                              return 'Enter a short description';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: _AdColors.line,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              SwitchListTile.adaptive(
                                                contentPadding: EdgeInsets.zero,
                                                activeColor:
                                                    _AdColors.brandOrange,
                                                title: const Text(
                                                  'Enable Buy now',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                    color: _AdColors.title,
                                                  ),
                                                ),
                                                subtitle: const Text(
                                                  'Add a product price so buyers can checkout',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: _AdColors.body,
                                                  ),
                                                ),
                                                value: _enableBuyNow,
                                                onChanged: (v) => setState(
                                                    () => _enableBuyNow = v),
                                              ),
                                              if (_enableBuyNow) ...[
                                                const SizedBox(height: 8),
                                                TextFormField(
                                                  controller:
                                                      _productPriceCtrl,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                    decimal: true,
                                                  ),
                                                  decoration: _fieldDeco(
                                                    label:
                                                        'Product price (MWK)',
                                                    hint: 'e.g. 15000',
                                                  ),
                                                  validator: (v) {
                                                    if (!_enableBuyNow) {
                                                      return null;
                                                    }
                                                    final n = double.tryParse(
                                                      (v ?? '')
                                                          .trim()
                                                          .replaceAll(',', ''),
                                                    );
                                                    if (n == null || n <= 0) {
                                                      return 'Enter a valid price';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(
                              color: _AdColors.line.withOpacity(0.9),
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 18,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _submitting ? null : _submitAndPay,
                            borderRadius: BorderRadius.circular(16),
                            child: Ink(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: _submitting
                                    ? null
                                    : _adBrandGradient,
                                color: _submitting
                                    ? _AdColors.brandOrange.withOpacity(0.55)
                                    : null,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: _submitting
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: _AdColors.brandOrange
                                              .withOpacity(0.35),
                                          blurRadius: 14,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                              ),
                              child: Center(
                                child: _submitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.bolt_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Pay ${_plan.priceLabel}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.white.withOpacity(0.22),
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                            child: Text(
                                              _plan.label,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 15,
        color: _AdColors.title,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final AdvertPlan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? _AdColors.brandOrangeSoft.withOpacity(0.55)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _AdColors.brandOrange : _AdColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      selected ? _AdColors.brandOrange : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? _AdColors.brandOrange
                        : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: _AdColors.title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: _AdColors.body,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                plan.priceLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: selected
                      ? _AdColors.brandOrangeDeep
                      : _AdColors.title,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginGate extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoginGate({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const Spacer(),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: _adBrandGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _AdColors.brandOrange.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Log in to advertise',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _AdColors.title,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'We use your account details for payment. '
              'Sign in to create a homepage advert.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: _AdColors.body,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _AdColors.brandOrange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onLogin,
                child: const Text(
                  'Log in',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
