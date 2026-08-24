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
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

/// Fixed weekly rate to appear on the homepage advert slider.
const int kHomepageAdvertWeeklyMwk = 5000;
const int kHomepageAdvertDurationDays = 7;

class _AdColors {
  static const brandOrange = Color(0xFFFF6B00);
  static const brandOrangeDeep = Color(0xFFD94F00);
  static const brandOrangeLight = Color(0xFFFF9A3C);
  static const brandOrangeSoft = Color(0xFFFFE8CC);
  static const title = Color(0xFF111111);
  static const body = Color(0xFF666666);
  static const pageBg = Color(0xFFFFFBF6);
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
  final String status;
  final DateTime? endsAt;
  final DateTime? startsAt;

  const HomepageAdvert({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.userId,
    required this.status,
    this.endsAt,
    this.startsAt,
  });

  factory HomepageAdvert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final j = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return HomepageAdvert(
      id: doc.id,
      title: (j['title'] ?? '').toString().trim(),
      description: (j['description'] ?? '').toString().trim(),
      imageUrl: (j['imageUrl'] ?? '').toString().trim(),
      userId: (j['userId'] ?? '').toString(),
      status: (j['status'] ?? '').toString().toLowerCase(),
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

  /// Guests can advertise: reuse existing Firebase session, else anonymous.
  static Future<User> ensureAuth() async {
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return existing;
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final user = cred.user;
    if (user == null) {
      throw Exception('Could not start advert session. Try again.');
    }
    return user;
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
    String? userName,
    String? userEmail,
    String? phone,
  }) async {
    final doc = _col.doc();
    await doc.set({
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'phone': phone,
      'status': 'pending_payment',
      'priceMwk': kHomepageAdvertWeeklyMwk,
      'durationDays': kHomepageAdvertDurationDays,
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
    final now = DateTime.now();
    final ends = now.add(const Duration(days: kHomepageAdvertDurationDays));
    await _col.doc(advertId).set({
      'status': 'active',
      'active': true,
      'txRef': txRef,
      'paidAt': FieldValue.serverTimestamp(),
      'startsAt': Timestamp.fromDate(now),
      'endsAt': Timestamp.fromDate(ends),
      'updatedAt': FieldValue.serverTimestamp(),
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

  void _openAdvertise() {
    Navigator.of(context).push(
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
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ResilientCachedNetworkImage(
                    url: ad.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                ad.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _AdColors.title,
                ),
              ),
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
            ],
          ),
        );
      },
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
                            'MK $kHomepageAdvertWeeklyMwk / week',
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
    final subtitle = advert.description.isEmpty
        ? 'Tap to view'
        : advert.description;

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

/// Submit title, description, image and pay MK 5000 / week.
class AdvertiseHerePage extends StatefulWidget {
  const AdvertiseHerePage({super.key});

  @override
  State<AdvertiseHerePage> createState() => _AdvertiseHerePageState();
}

class _AdvertiseHerePageState extends State<AdvertiseHerePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  File? _imageFile;
  bool _submitting = false;
  bool _prefillDone = false;

  @override
  void initState() {
    super.initState();
    _prefillContact();
  }

  Future<void> _prefillContact() async {
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
      final phone = (prefs.getString('phone') ??
              user?.phoneNumber ??
              '')
          .trim();
      if (!mounted) return;
      setState(() {
        if (name.isNotEmpty) _nameCtrl.text = name;
        if (email.isNotEmpty) _emailCtrl.text = email;
        if (phone.isNotEmpty &&
            !phone.toLowerCase().startsWith('+firebase_')) {
          _phoneCtrl.text = phone;
        }
        _prefillDone = true;
      });
    } catch (_) {
      if (mounted) setState(() => _prefillDone = true);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
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
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null) {
      ToastHelper.showCustomToast(
        context,
        'Add a picture for your advert',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    setState(() => _submitting = true);
    String? advertId;
    try {
      final user = await HomepageAdvertService.ensureAuth();
      final title = _titleCtrl.text.trim();
      final description = _descCtrl.text.trim();
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      final parts = name.split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : 'Advertiser';
      final lastName =
          parts.length > 1 ? parts.sublist(1).join(' ') : 'Vero360';

      final imageUrl = await HomepageAdvertService.uploadImage(
        userId: user.uid,
        file: _imageFile!,
      );

      final shortUid = user.uid.length >= 6
          ? user.uid.substring(0, 6)
          : user.uid;
      final txRef =
          'vero-ad-$shortUid-${DateTime.now().millisecondsSinceEpoch}';

      advertId = await HomepageAdvertService.createPendingAdvert(
        userId: user.uid,
        title: title,
        description: description,
        imageUrl: imageUrl,
        txRef: txRef,
        userName: name,
        userEmail: email,
        phone: phone,
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
              'amount': kHomepageAdvertWeeklyMwk.toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero360 Homepage Ad',
                'description': 'Homepage advert - 1 week - $title',
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
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InAppPaymentPage(
            checkoutUrl: checkoutUrl,
            txRef: txRef,
            totalAmount: kHomepageAdvertWeeklyMwk.toDouble(),
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
                  'Advert live for $kHomepageAdvertDurationDays days. '
                  'Thank you!',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AdColors.pageBg,
      appBar: AppBar(
        title: const Text(
          'Advertise here',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _AdColors.title,
        elevation: 0,
      ),
      body: AbsorbPointer(
        absorbing: _submitting,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: _adBrandGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Homepage advert',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'MK $kHomepageAdvertWeeklyMwk per week. Your image and title '
                    'slide on the home screen for 7 days after payment.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _AdColors.brandOrangeSoft),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _imageFile != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_imageFile!, fit: BoxFit.cover),
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
                                    child: const Text(
                                      'Change photo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 40,
                                  color: _AdColors.brandOrange.withOpacity(0.9),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Add advert picture',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _AdColors.title,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Recommended 16:9',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'e.g. Fresh juice - Blantyre',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter a title';
                      }
                      if (v.trim().length < 3) return 'Title is too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'What should people know?',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter a short description';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Billing contact',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _AdColors.title,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty || !t.contains('@')) {
                        return 'Valid email required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (Malawi)',
                      hintText: '088... or 099...',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      final digits =
                          (v ?? '').replaceAll(RegExp(r'\D'), '');
                      if (!RegExp(r'^(0|265)?[89]\d{8}$')
                          .hasMatch(digits)) {
                        return 'Enter a valid MW phone';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _AdColors.brandOrange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: (_submitting || !_prefillDone)
                        ? null
                        : _submitAndPay,
                    child: _submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Pay MK $kHomepageAdvertWeeklyMwk · Go live',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
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
