import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:vero360_app/Quickservices/social.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/bike_ride_share_map_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_share_map_screen.dart';

import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';

import 'package:vero360_app/Quickservices/ExchangeRate.dart';
import 'package:vero360_app/features/AirportPickup/AirportPresenter/airportpickup.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food.dart';
import 'package:vero360_app/Quickservices/jobs.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/verocourier.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/config/paychangu_config.dart';

import 'package:vero360_app/features/Marketplace/MarkeplaceModel/Latest_model.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/latest_Services.dart';

import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/Home/notifications_page.dart';
import 'package:vero360_app/Home/story_section.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

/* ═══════════════════════════════════════════════════
   DESIGN TOKENS
═══════════════════════════════════════════════════ */
class AppColors {
  static const brandOrange     = Color(0xFFFF6B00);
  static const brandOrangeDeep = Color(0xFFD94F00);
  static const brandOrangeLight= Color(0xFFFF9A3C);
  static const brandOrangeSoft = Color(0xFFFFE8CC);
  static const brandOrangePale = Color(0xFFFFF4E6);
  static const title           = Color(0xFF111111);
  static const body            = Color(0xFF666666);
  static const pageBg          = Color(0xFFFFFBF6);
  static const card            = Color(0xFFFFFFFF);
}

const kBrandGradient = LinearGradient(
  colors: [AppColors.brandOrange, AppColors.brandOrangeLight],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kHeroGradient = LinearGradient(
  colors: [AppColors.brandOrangeDeep, AppColors.brandOrangeLight],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/* ═══════════════════════════════════════════════════
   DATA MODELS
═══════════════════════════════════════════════════ */
class Mini {
  final String keyId;
  final String label;
  final IconData icon;
  const Mini(this.keyId, this.label, this.icon);
}

const List<Mini> kQuickServices = [
  Mini('taxi',          'Vero Ride',     Icons.local_taxi_rounded),
  Mini('airport_pickup','Airport Pickup',Icons.flight_takeoff_rounded),
  Mini('courier',       'Courier',       Icons.local_shipping_rounded),
  Mini('vero_bike',     'Vero Bike',     Icons.pedal_bike_rounded),
  Mini('fx',            'Forex Rates',   Icons.currency_exchange_rounded),
  Mini('food',          'Food',          Icons.fastfood_rounded),
  Mini('jobs',          'Jobs',          Icons.business_center_rounded),
  Mini('accommodation', 'Stay',          Icons.hotel_rounded),
];

const Map<String, String> kQuickServiceGuideNotes = {
  'taxi':          'Request a taxi ride in minutes.',
  'airport_pickup':'Schedule airport pickup or drop-off.',
  'courier':       'Send parcels and track deliveries.',
  'vero_bike':     'Book fast, affordable bike rides.',
  'fx':            'Check live exchange rates instantly.',
  'food':          'Browse restaurants and order food.',
  'jobs':          'Discover job opportunities near you.',
  'accommodation': 'Find hotels and places to stay.',
};

class DigitalProduct {
  final String key;
  final String name;
  final String subtitle;
  final String price;
  final IconData? icon;
  final String? logoAsset;
  const DigitalProduct({
    required this.key,
    required this.name,
    required this.subtitle,
    required this.price,
    this.icon,
    this.logoAsset,
  });
}

const List<DigitalProduct> kDigitalProducts = [
  DigitalProduct(
    key: 'spotify', name: 'Spotify Premium',
    subtitle: '1-month subscription', price: 'MWK 8,000',
    logoAsset: 'assets/brands/spotify.jpg',
    icon: Icons.music_note_rounded,
  ),
  DigitalProduct(
    key: 'apple_music', name: 'Apple Music',
    subtitle: '1-month subscription', price: 'MWK 8,000',
    logoAsset: 'assets/brands/apple_music.png',
    icon: Icons.music_note_rounded,
  ),
  DigitalProduct(
    key: 'netflix', name: 'Netflix',
    subtitle: '1-month subscription', price: 'MWK 12,000',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
  ),
  DigitalProduct(
    key: 'chatgpt_plus', name: 'ChatGPT Plus',
    subtitle: '1-month subscription', price: 'MWK 25,000',
    logoAsset: 'assets/brands/chatgpt.png',
    icon: Icons.chat_bubble_outline_rounded,
  ),
];

/* ═══════════════════════════════════════════════════
   HOMEPAGE
═══════════════════════════════════════════════════ */
class Vero360Homepage extends ConsumerStatefulWidget {
  final String email;
  const Vero360Homepage({super.key, required this.email});

  @override
  ConsumerState<Vero360Homepage> createState() => _Vero360HomepageState();
}

class _Vero360HomepageState extends ConsumerState<Vero360Homepage>
    with TickerProviderStateMixin {

  final GlobalKey _servicesCardKey = GlobalKey();
  final Map<String, GlobalKey> _serviceTileKeys = {
    for (final item in kQuickServices) item.keyId: GlobalKey()
  };

  bool _animateIn         = false;
  bool _showLatestArrivals= false;
  bool _showServicesHint  = false;
  int  _guideIndex        = 0;

  late final AnimationController _heroCtrl;
  late final Animation<double>   _heroFade;
  late final Animation<Offset>   _heroSlide;

  String? _resolvedGreetingName;
  bool    _greetingResolved = false;

  /* ── helpers ─────────────────────────────────── */
  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstNameFromEmail(String email) {
    final user = email.split('@').first;
    if (user.isEmpty) return 'there';
    final cleaned = user.replaceAll(RegExp(r'[^a-zA-Z]'), ' ');
    final parts   = cleaned.trim().split(RegExp(r'\s+'));
    final first   = parts.isNotEmpty ? parts.first : 'there';
    if (first.isEmpty) return 'there';
    return '${first[0].toUpperCase()}${first.substring(1).toLowerCase()}';
  }

<<<<<<< HEAD
  String _displayName() {
    if (widget.email.isNotEmpty) return _firstNameFromEmail(widget.email);
    if (_resolvedGreetingName != null && _resolvedGreetingName!.isNotEmpty) {
      final cleaned = _resolvedGreetingName!
          .replaceAll(RegExp(r'[^a-zA-Z]'), ' ').trim();
=======
  String? _resolvedGreetingName;
  bool _greetingResolved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateIn = true);
    });
    _resolveGreetingName();

    // Defer heavy latest-arrivals grid slightly so the first frame
    // (brand bar, search, quick services) renders faster.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() => _showLatestArrivals = true);
    });
  }

  Future<void> _resolveGreetingName() async {
    if (widget.email.isNotEmpty) return;
    // Prefer name from SharedPreferences (set at login) so "Hi, chawezi" not "Hi, Phone" for phone users.
    String? name;
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('fullName') ?? prefs.getString('name');
    if (name != null && name.trim().isNotEmpty && !name.contains('@')) {
      // Use prefs name (not an email)
    } else {
      name = await AuthStorage.userNameFromToken();
      // If token only has email (e.g. 0992695612@phone.vero360.app), don't use "Phone" from the local part.
      if (name != null && name.contains('@')) {
        final local = name.split('@').first.trim();
        if (RegExp(r'^\d+$').hasMatch(local))
          name = null; // all digits => don't use as display name
        else
          name = local;
      }
    }
    if (!mounted) return;
    setState(() {
      _resolvedGreetingName = name;
      _greetingResolved = true;
    });
  }

  @override
  void didUpdateWidget(Vero360Homepage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email && widget.email.isEmpty) {
      _resolveGreetingName();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _displayName() {
    if (widget.email.isNotEmpty) return _firstNameFromEmail(widget.email);
    if (_resolvedGreetingName != null && _resolvedGreetingName!.isNotEmpty) {
      final cleaned =
          _resolvedGreetingName!.replaceAll(RegExp(r'[^a-zA-Z]'), ' ').trim();
>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
      final parts = cleaned.split(RegExp(r'\s+'));
      final first = parts.isNotEmpty ? parts.first : 'there';
      if (first.isEmpty) return 'there';
      return '${first[0].toUpperCase()}${first.substring(1).toLowerCase()}';
    }
    return _greetingResolved ? 'there' : '...';
  }

  List<ServiceGuideStep> get _guideSteps => kQuickServices
      .map((item) => ServiceGuideStep(
            keyId:       item.keyId,
            title:       item.label,
            description: kQuickServiceGuideNotes[item.keyId] ?? 'Open this service.',
          ))
      .toList();

  /* ── lifecycle ───────────────────────────────── */
  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heroFade  = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _animateIn = true);
        _heroCtrl.forward();
      }
    });

    _resolveGreetingName();
    _maybeShowServicesHint();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) setState(() => _showLatestArrivals = true);
    });
  }

  @override
  void didUpdateWidget(Vero360Homepage old) {
    super.didUpdateWidget(old);
    if (old.email != widget.email && widget.email.isEmpty) {
      _resolveGreetingName();
    }
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  /* ── data fetching ───────────────────────────── */
  Future<void> _resolveGreetingName() async {
    if (widget.email.isNotEmpty) return;
    String? name;
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('fullName') ?? prefs.getString('name');
    if (name != null && name.trim().isNotEmpty && !name.contains('@')) {
      // use prefs name as-is
    } else {
      name = await AuthStorage.userNameFromToken();
      if (name != null && name.contains('@')) {
        final local = name.split('@').first.trim();
        name = RegExp(r'^\d+$').hasMatch(local) ? null : local;
      }
    }
    if (!mounted) return;
    setState(() {
      _resolvedGreetingName = name;
      _greetingResolved     = true;
    });
  }

  Future<void> _maybeShowServicesHint() async {
    final prefs = await SharedPreferences.getInstance();
    final seen  = prefs.getBool('home_services_hint_v1') ?? false;
    if (seen || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _showServicesHint = true);
  }

  Future<void> _finishServicesGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_services_hint_v1', true);
    if (!mounted) return;
    setState(() {
      _showServicesHint = false;
      _guideIndex       = 0;
    });
  }

  /* ── build ───────────────────────────────────── */
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor:                 Colors.transparent,
        statusBarIconBrightness:        Brightness.light,
        statusBarBrightness:            Brightness.dark,
        systemNavigationBarColor:       Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                /* ── Hero SliverAppBar ───────────────────── */
                SliverAppBar(
                  expandedHeight: 220,
                  floating:  false,
                  pinned:    true,
                  elevation: 0,
                  backgroundColor: AppColors.brandOrangeDeep,
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    background: _HeroHeader(
                      greeting:  _greeting(),
                      name:      _displayName(),
                      heroFade:  _heroFade,
                      heroSlide: _heroSlide,
                      onNotifTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationsPage()),
                      ),
                      onSearchTap: _onSearchTap,
                    ),
                    title: _CollapsedBar(
                      onSearchTap: _onSearchTap,
                      onNotifTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationsPage()),
                      ),
                    ),
                    titlePadding: EdgeInsets.zero,
                  ),
                  actions: const [],
                ),

                /* ── Stories ─────────────────────────────── */
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(0, 14, 0, 0),
                    child: StorySection(),
                  ),
                ),

                /* ── Filter chips ────────────────────────── */
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: _FilterChips(),
                  ),
                ),

                /* ── Quick Services ──────────────────────── */
                SliverToBoxAdapter(
                  child: Padding(
                    key:     _servicesCardKey,
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: _ServicesCard(
                      items:    kQuickServices,
                      tileKeys: _serviceTileKeys,
                      onOpen: (key) => key == 'taxi'
                          ? _openService(key)
                          : _openServiceStatic(context, key),
                    ),
                  ),
                ),

                /* ── Nearby ──────────────────────────────── */
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: _NearbySection(
                      onOpenService: (key) => _openServiceStatic(context, key),
                    ),
                  ),
                ),

                /* ── Deals strip ─────────────────────────── */
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: _DealsStrip(),
                  ),
                ),

                /* ── Promo banner ────────────────────────── */
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: _PromoBanner(),
                  ),
                ),

                /* ── Digital services ────────────────────── */
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: DigitalServicesSection(onBuy: _openDigitalDetail),
                  ),
                ),

                /* ── Latest arrivals ─────────────────────── */
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _showLatestArrivals
                          ? const LatestArrivalsSection()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),

            /* ── Coach overlay ───────────────────────────── */
            if (_showServicesHint)
              Builder(
                builder: (ctx) => QuickServicesCoachOverlay(
                  stackContext: ctx,
                  currentIndex: _guideIndex,
                  steps:       _guideSteps,
                  tileKeys:    _serviceTileKeys,
                  onSkip: _finishServicesGuide,
                  onNext: () async {
                    if (_guideIndex >= _guideSteps.length - 1) {
                      await _finishServicesGuide();
                      return;
                    }
                    if (!mounted) return;
                    setState(() => _guideIndex += 1);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /* ── navigation helpers ──────────────────────── */
  Future<void> _onSearchTap() async {
    final picked = await showSearch<Mini?>(
      context: context,
      delegate: QuickServiceSearchDelegate(services: kQuickServices),
    );
    if (picked != null) {
      picked.keyId == 'taxi'
          ? _openService(picked.keyId)
          : _openServiceStatic(context, picked.keyId);
    }
  }

<<<<<<< HEAD
=======
  /// Keep only real profile phone numbers and drop Firebase placeholders.
  String? _merchantProfilePhoneOrNull(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower.startsWith('+firebase_') || lower.contains('firebase_')) {
      return null;
    }
    if (lower.contains('@phone.vero360.app') || lower.contains('@')) {
      return null;
    }
    return t;
  }

  Future<void> _openDigitalDetail(DigitalProduct p) async {
    // Pull name, phone, email from user (SharedPreferences like checkout_page)
    String? initialName;
    String? initialPhone;
    String initialEmail = widget.email;
    try {
      final prefs = await SharedPreferences.getInstance();
      initialName = prefs.getString('name');
      // Use only merchant-profile phone set from merchant dashboard/profile sources.
      // Do not fall back to generic login/Firebase phone if missing.
      initialPhone = _merchantProfilePhoneOrNull(
          prefs.getString('merchant_profile_phone'));
      if (initialEmail.trim().isEmpty) {
        initialEmail = prefs.getString('email') ?? '';
      }
      final suggestedName = _displayName();
      if ((initialName == null || initialName.isEmpty) &&
          suggestedName != 'there' &&
          suggestedName != '...') {
        initialName = suggestedName;
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DigitalProductDetailPage(
          product: p,
          initialEmail: initialEmail,
          initialPhone: initialPhone,
          initialName: initialName,
        ),
      ),
    );
  }

>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
  void _openService(String key) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RideShareMapScreen()),
    );
  }

  static void _openServiceStatic(BuildContext context, String key) {
    Widget page;
    switch (key) {
      case 'mainmarketplace':
        page = MarketPage(cartService: CartService('', apiPrefix: ApiConfig.apiPrefix));
        break;
      case 'food':
      case 'grocery':
        page = FoodPage();
        break;
      case 'jobs':
        page = JobsPage();
        break;
      case 'courier':
        page = const VerocourierPage();
        break;
      case 'airport_pickup':
        page = const Airportpickuppage();
        break;
      case 'taxi':
      case 'car_hire':
        page = const RideShareMapScreen();
        break;
      case 'Vero Chat':
        page = const SocialPage();
        break;
      case 'accommodation':
        page = const AccommodationMainPage();
        break;
      case 'fx':
        page = const ExchangeRateScreen();
        break;
      default:
        page = const BikeRideShareMapScreen();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  String? _merchantProfilePhoneOrNull(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower.startsWith('+firebase_') || lower.contains('firebase_')) return null;
    if (lower.contains('@phone.vero360.app') || lower.contains('@')) return null;
    return t;
  }

  Future<void> _openDigitalDetail(DigitalProduct p) async {
    String? initialName;
    String? initialPhone;
    String  initialEmail = widget.email;
    try {
      final prefs = await SharedPreferences.getInstance();
      initialName  = prefs.getString('name');
      initialPhone = _merchantProfilePhoneOrNull(prefs.getString('merchant_profile_phone'));
      if (initialEmail.trim().isEmpty) initialEmail = prefs.getString('email') ?? '';
      final suggestedName = _displayName();
      if ((initialName == null || initialName.isEmpty) &&
          suggestedName != 'there' && suggestedName != '...') {
        initialName = suggestedName;
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DigitalProductDetailPage(
        product:      p,
        initialEmail: initialEmail,
        initialPhone: initialPhone,
        initialName:  initialName,
      ),
    ));
  }
}

/* ═══════════════════════════════════════════════════
   HERO HEADER
═══════════════════════════════════════════════════ */
class _HeroHeader extends StatelessWidget {
  final String            greeting;
  final String            name;
  final Animation<double> heroFade;
  final Animation<Offset> heroSlide;
  final VoidCallback      onSearchTap;
  final VoidCallback      onNotifTap;

  const _HeroHeader({
    required this.greeting,
    required this.name,
    required this.heroFade,
    required this.heroSlide,
    required this.onSearchTap,
    required this.onNotifTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kHeroGradient),
      child: Stack(
        children: [
          /* decorative blobs */
          Positioned(
            top: -50, right: -50,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.09),
              ),
            ),
          ),
<<<<<<< HEAD
          Positioned(
            bottom: 20, left: -40,
            child: Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
=======
        ),
        const SizedBox(width: 10),
        Text(
          appName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.title,
          ),
        ),
        const Spacer(),
        ListenableBuilder(
          listenable: NotificationStore.instance,
          builder: (_, __) {
            final count = NotificationStore.instance.unreadCount;
            final labelText = count > 99 ? '99+' : '$count';
            return Badge(
              isLabelVisible: count > 0,
              backgroundColor: Colors.red,
              textColor: Colors.white,
              alignment: Alignment(1.15, -0.6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              label: Text(
                labelText,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
              ),
            ),
          ),
          Positioned(
            top: 80, right: 60,
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /* top row */
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/logo_mark.png',
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const CircleAvatar(
                              radius: 17,
                              backgroundColor: AppColors.brandOrangePale,
                              child: Icon(Icons.eco, size: 18, color: AppColors.brandOrange),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Vero360',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const Spacer(),
                      ListenableBuilder(
                        listenable: NotificationStore.instance,
                        builder: (_, __) {
                          final count = NotificationStore.instance.unreadCount;
                          return Badge(
                            isLabelVisible: count > 0,
                            backgroundColor: Colors.red,
                            textColor:       Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            label: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                            child: GestureDetector(
                              onTap: onNotifTap,
                              child: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.18),
                                  border: Border.all(color: Colors.white.withOpacity(0.30)),
                                ),
                                child: const Icon(Icons.notifications_outlined,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /* greeting */
                  FadeTransition(
                    opacity: heroFade,
                    child: SlideTransition(
                      position: heroSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting 👋',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.80),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Hi, $name',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                          ),
                          Text(
                            'What do you need today?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  /* search row */
                  GestureDetector(
                    onTap: onSearchTap,
                    child: Container(
                      height: 48,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:        Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: const Row(
                        children: [
                          Icon(Icons.search_rounded, color: Color(0xFFBBBBBB), size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'what are you looking for?',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color:      Color(0xFF999999),
                                fontWeight: FontWeight.w600,
                                fontSize:   13,
                              ),
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
        ],
      ),
    );
  }
}

/* ── Collapsed bar (shown when scrolled) ───────── */
class _CollapsedBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onNotifTap;
  const _CollapsedBar({required this.onSearchTap, required this.onNotifTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.95),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/logo_mark.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.eco,
                    size: 14,
                    color: AppColors.brandOrange,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Vero360',
              style: TextStyle(
                color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w900, letterSpacing: -0.4,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onSearchTap,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text('Search',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onNotifTap,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  Colors.white.withOpacity(0.20),
                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                ),
                child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ═══════════════════════════════════════════════════
   FILTER CHIPS
═══════════════════════════════════════════════════ */
class _FilterChips extends StatefulWidget {
  const _FilterChips();
  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  int _active = 0;
  static const _items = [
    ['⚡', 'Lightning deals'],
    ['🗺️', 'Explore nearby'],
    ['⭐', 'Top rated'],
    ['🛟', 'Support'],
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final active = i == _active;
          return GestureDetector(
            onTap: () => setState(() => _active = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve:    Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient:     active ? kBrandGradient : null,
                color:        active ? null : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border:       Border.all(
                  color: active ? Colors.transparent : AppColors.brandOrangeSoft,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color:      AppColors.brandOrange.withOpacity(0.35),
                          blurRadius: 10,
                          offset:     const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '${_items[i][0]}  ${_items[i][1]}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize:   12,
                    color:      active ? Colors.white : AppColors.title,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/* ═══════════════════════════════════════════════════
   SERVICES CARD
═══════════════════════════════════════════════════ */
class _ServicesCard extends StatelessWidget {
  final List<Mini>          items;
  final Map<String, GlobalKey> tileKeys;
  final void Function(String) onOpen;
  const _ServicesCard({required this.items, required this.tileKeys, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Quick Services', subtitle: 'Everything at your fingertips'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: AppColors.brandOrangeSoft),
            boxShadow: [
              BoxShadow(
                color:      AppColors.brandOrange.withOpacity(0.07),
                blurRadius: 16,
                offset:     const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          child: _MiniIconsGrid(items: items, tileKeys: tileKeys, onOpen: onOpen),
        ),
      ],
    );
  }
}

/* ── Mini icons grid ─────────────────────────────── */
class _MiniIconsGrid extends StatelessWidget {
  final List<Mini>          items;
  final Map<String, GlobalKey> tileKeys;
  final void Function(String) onOpen;
  const _MiniIconsGrid({required this.items, required this.tileKeys, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final w            = c.maxWidth;
      const crossSpacing = 8.0;
      const mainSpacing  = 12.0;
      const minTileW     = 80.0;
      int    cross       = (w / minTileW).floor().clamp(4, 6);
      double tileW       = (w - (cross - 1) * crossSpacing) / cross;
      if (tileW < 76 && cross > 4) {
        cross -= 1;
        tileW  = (w - (cross - 1) * crossSpacing) / cross;
      }
      final textScale  = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.2);
      final twoLines   = 11.0 * 1.25 * 2 * textScale;
      final minHeight  = 52.0 + 6 + twoLines + 8;
      final ratio      = (tileW / (minHeight + 2)).clamp(0.86, 1.10);

      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.of(context).textScaler.clamp(maxScaleFactor: 1.2),
        ),
        child: GridView.builder(
          shrinkWrap:        true,
          physics:           const NeverScrollableScrollPhysics(),
          padding:           EdgeInsets.zero,
          itemCount:         items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:  cross,
            crossAxisSpacing: crossSpacing,
            mainAxisSpacing:  mainSpacing,
            childAspectRatio: ratio,
          ),
          itemBuilder: (_, i) {
            final m = items[i];
            return _MiniIconTile(
              tileKey: tileKeys[m.keyId],
              icon:    m.icon,
              label:   m.label,
              onTap:   () => onOpen(m.keyId),
            );
          },
        ),
      );
    });
  }
}

class _MiniIconTile extends StatefulWidget {
  final Key?         tileKey;
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  const _MiniIconTile({this.tileKey, required this.icon, required this.label, required this.onTap});

  @override
  State<_MiniIconTile> createState() => _MiniIconTileState();
}

class _MiniIconTileState extends State<_MiniIconTile> with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key:       widget.tileKey,
      onTapDown: (_) => _press.forward(),
      onTapUp:   (_) { _press.reverse(); widget.onTap(); },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - _press.value * 0.08,
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color:  AppColors.brandOrangePale,
                shape:  BoxShape.circle,
                border: Border.all(color: AppColors.brandOrangeSoft, width: 1.5),
              ),
              child: Icon(widget.icon, size: 22, color: AppColors.brandOrange),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                widget.label,
                textAlign:  TextAlign.center,
                maxLines:   2,
                overflow:   TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize:   10.5,
                  fontWeight: FontWeight.w700,
                  color:      AppColors.title,
                  height:     1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ═══════════════════════════════════════════════════
   NEARBY SECTION
═══════════════════════════════════════════════════ */
class _NearbySection extends StatefulWidget {
  final void Function(String) onOpenService;
  const _NearbySection({required this.onOpenService});

  @override
  State<_NearbySection> createState() => _NearbySectionState();
}

class _NearbySectionState extends State<_NearbySection> {
  static const _items = [
    ['🍔', 'Food & Restaurants', '4.6', 'food'],
    ['🏨', 'Accommodations',     '4.7', 'accommodation'],
    ['💼', 'Utility Services',   '4.9', 'more'],
  ];
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SectionHeader(
            title:    'Nearby Services',
            subtitle: 'Popular around you',
            action: TextButton(
              onPressed: () => widget.onOpenService('more'),
              child: const Text(
                'See all',
                style: TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ),
        CarouselSlider.builder(
          itemCount: _items.length,
          options: CarouselOptions(
            height:                    90,
            viewportFraction:          0.88,
            enableInfiniteScroll:      true,
            autoPlay:                  true,
            autoPlayInterval:          const Duration(seconds: 4),
            autoPlayAnimationDuration: const Duration(milliseconds: 600),
            onPageChanged:             (i, _) => setState(() => _index = i),
          ),
          itemBuilder: (_, i, __) {
            final it = _items[i];
            return _NearbyCard(
              emoji:  it[0],
              name:   it[1],
              rating: it[2],
              onOpen: () => widget.onOpenService(it[3]),
            );
          },
        ),
        const SizedBox(height: 8),
        _Dots(count: _items.length, index: _index),
      ],
    );
  }
}

class _NearbyCard extends StatelessWidget {
  final String emoji, name, rating;
  final VoidCallback onOpen;
  const _NearbyCard({required this.emoji, required this.name, required this.rating, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:       Border.all(color: AppColors.brandOrangeSoft),
        boxShadow: [
          BoxShadow(
            color:      AppColors.brandOrange.withOpacity(0.06),
            blurRadius: 12,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color:  AppColors.brandOrangePale,
              shape:  BoxShape.circle,
              border: Border.all(color: AppColors.brandOrangeSoft),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment:  MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.title),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
                    const SizedBox(width: 4),
                    Text(rating,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.body),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient:     kBrandGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color:      AppColors.brandOrange.withOpacity(0.35),
                    blurRadius: 8,
                    offset:     const Offset(0, 3),
                  ),
                ],
              ),
              child: const Text('Open',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

<<<<<<< HEAD
/* ═══════════════════════════════════════════════════
   DEALS STRIP
═══════════════════════════════════════════════════ */
=======
/// Search delegate for Quick Services
class QuickServiceSearchDelegate extends SearchDelegate<Mini?> {
  final List<Mini> services;
  QuickServiceSearchDelegate({required this.services})
      : super(searchFieldLabel: 'Search quick services');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle:
            const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
    );
  }

  static final Map<String, String> _aliases = {
    'taxi': 'taxi',
    'vero ride': 'taxi',
    'ride': 'taxi',
    'cab': 'taxi',
    'bike': 'vero_bike',
    'bicycle': 'vero_bike',
    'verobike': 'vero_bike',
    'airport': 'airport_pickup',
    'pickup': 'airport_pickup',
    'courier': 'courier',
    'parcel': 'courier',
    'delivery': 'courier',
    'car hire': 'car_hire',
    'rent': 'car_hire',
    'rental': 'car_hire',
    'accommodation': 'accommodation',
    'accomodation': 'accommodation',
    'hotel': 'accommodation',
    'hostel': 'accommodation',
    'rooms': 'accommodation',
    'fx': 'fx',
    'forex': 'fx',
    'exchange rate': 'fx',
    'rates': 'fx',
    'food': 'food',
    'restaurant': 'food',
    'order': 'food',
    'jobs': 'jobs',
    'work': 'jobs',
    'vacancies': 'jobs',
    'more': 'more'
  };

  Iterable<Mini> _filter(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return services;

    final aliasKey = _aliases[t];
    if (aliasKey != null) {
      return services.where((m) => m.keyId == aliasKey);
    }

    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return services.where((m) {
      final l = m.label.toLowerCase();
      return l.contains(t) || words.any(l.contains);
    });
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      final popular = const [
        'Taxi',
        'Bike',
        'Airport pickup',
        'Food',
        'Hotel',
        'FX',
        'Jobs',
        'Courier'
      ];
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in popular)
              ActionChip(
                label: Text(p),
                onPressed: () {
                  query = p.toLowerCase();
                  showSuggestions(context);
                },
                backgroundColor: AppColors.brandOrangePale,
                shape: StadiumBorder(
                    side: BorderSide(color: AppColors.brandOrangeSoft)),
              ),
          ],
        ),
      );
    }

    final results = _filter(query).toList();
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No matches. Try: taxi, bike, airport, hotel, forex, food, jobs...',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemBuilder: (_, i) {
        final m = results[i];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.brandOrangeSoft),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.brandOrangePale,
              child: Icon(m.icon, color: AppColors.brandOrange),
            ),
            title: Text(m.label,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(m.keyId),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: AppColors.body),
            onTap: () => close(context, m),
          ),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );
}

/// NEAR YOU
class _NearYouCarousel extends StatefulWidget {
  const _NearYouCarousel();
  @override
  State<_NearYouCarousel> createState() => _NearYouCarouselState();
}

class _NearYouCarouselState extends State<_NearYouCarousel> {
  int _index = 0;

  void _openNearby(BuildContext context, String name) {
    final t = name.toLowerCase();
    String serviceKey;
    if (t.contains('ride')) {
      serviceKey = 'taxi';
    } else if (t.contains('food')) {
      serviceKey = 'food';
    } else if (t.contains('accom')) {
      serviceKey = 'accommodation';
    } else {
      serviceKey = 'more';
    }
    _Vero360HomepageState._openServiceStatic(context, serviceKey);
  }

  @override
  Widget build(BuildContext context) {
    final items = const [
      ['🍔', 'Food & Restaurants', '4.6'],
      ['🏨', 'Accomodations', '4.7'],
      ['💼', 'Utility', '4.9'],
    ];

    return _Section(
      title: 'Nearby Services',
      tight: true,
      gapAfterTitle: kGapAfterNearby,
      action: TextButton(
        onPressed: () =>
            _Vero360HomepageState._openServiceStatic(context, 'more'),
        child: const Text(
          'See all',
          style: TextStyle(
            color: AppColors.brandOrange,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: items.isEmpty
          ? Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text(
                'more nearby service coming soon',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.title,
                ),
              ),
            )
          : Column(
              children: [
                CarouselSlider.builder(
                  itemCount: items.length,
                  options: CarouselOptions(
                    height: 120,
                    viewportFraction: 0.82,
                    enlargeCenterPage: true,
                    enableInfiniteScroll: true,
                    autoPlay: true,
                    autoPlayInterval: const Duration(seconds: 4),
                    autoPlayAnimationDuration:
                        const Duration(milliseconds: 600),
                    onPageChanged: (i, _) => setState(() => _index = i),
                  ),
                  itemBuilder: (_, i, __) {
                    final it = items[i];
                    return _ProviderCard(
                      emoji: it[0],
                      name: it[1],
                      rating: it[2],
                      onOpen: () => _openNearby(context, it[1]),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _Dots(count: items.length, index: _index),
              ],
            ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final String emoji, name, rating;
  final VoidCallback onOpen;
  const _ProviderCard({
    required this.emoji,
    required this.name,
    required this.rating,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.brandOrangeSoft),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.brandOrangePale,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 16, color: Color(0xFFFFC107)),
                      const SizedBox(width: 4),
                      Text(
                        rating,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.body,
                        ),
                      )
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: onOpen,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: AppColors.brandOrange),
              ),
              child: const Text(
                'Open',
                style: TextStyle(
                  color: AppColors.brandOrange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// DEALS STRIP
>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
class _DealsStrip extends StatelessWidget {
  const _DealsStrip();

  @override
  Widget build(BuildContext context) {
    final deals = const [
      ['🗺️', 'Nearby coming soon'],
      ['🍔', 'Order food on Vero'],
      ['🏨', 'Stay · Pay now'],
      ['💼', 'Home cleaning deals'],
      ['💳', 'Send money now'],
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding:         const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount:       deals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFF0D9), Colors.white]),
            border:   Border.all(color: AppColors.brandOrangeSoft),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              '${deals[i][0]}  ${deals[i][1]}',
<<<<<<< HEAD
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.title),
=======
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.title,
              ),
>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
            ),
          ),
        ),
      ),
    );
  }
}

/* ═══════════════════════════════════════════════════
   PROMO BANNER
═══════════════════════════════════════════════════ */
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandOrangeDeep, AppColors.brandOrange],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color:      AppColors.brandOrange.withOpacity(0.40),
            blurRadius: 20,
            offset:     const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -20, top: -20,
              child: Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              left: -10, bottom: -30,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color:        Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'LIMITED OFFER',
                            style: TextStyle(
                              fontSize:   9,
                              fontWeight: FontWeight.w800,
                              color:      Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'First ride free\nwith Vero360',
                          style: TextStyle(
                            fontSize:   17,
                            fontWeight: FontWeight.w900,
                            color:      Colors.white,
                            height:     1.25,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use code HELLO360',
                          style: TextStyle(
                            fontSize:   12,
                            fontWeight: FontWeight.w600,
                            color:      Colors.white.withOpacity(0.80),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    decoration: BoxDecoration(
                      color:        Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:      Colors.black.withOpacity(0.10),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Claim →',
                      style: TextStyle(
                        color:      AppColors.brandOrange,
                        fontWeight: FontWeight.w900,
                        fontSize:   13,
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

/* ═══════════════════════════════════════════════════
   DIGITAL SERVICES SECTION
═══════════════════════════════════════════════════ */
class DigitalServicesSection extends StatelessWidget {
  final void Function(DigitalProduct) onBuy;
  const DigitalServicesSection({super.key, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title:    'Digital Services',
          subtitle: 'Subscriptions & top-ups',
          action: TextButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('More digital services coming soon'))),
            child: const Text('See all',
              style: TextStyle(color: AppColors.brandOrange, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics:    const NeverScrollableScrollPhysics(),
          padding:    EdgeInsets.zero,
          itemCount:  kDigitalProducts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   4,
            crossAxisSpacing: 10,
            mainAxisSpacing:  8,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (_, i) {
            final p = kDigitalProducts[i];
            return _DigitalTile(p: p, onTap: () => onBuy(p));
          },
        ),
      ],
    );
  }
}

class _DigitalTile extends StatefulWidget {
  final DigitalProduct p;
  final VoidCallback   onTap;
  const _DigitalTile({required this.p, required this.onTap});

  @override
  State<_DigitalTile> createState() => _DigitalTileState();
}

class _DigitalTileState extends State<_DigitalTile> with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _press.forward(),
      onTapUp:     (_) { _press.reverse(); widget.onTap(); },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) => Transform.scale(scale: 1.0 - _press.value * 0.08, child: child),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color:  AppColors.brandOrangePale,
                shape:  BoxShape.circle,
                border: Border.all(color: AppColors.brandOrangeSoft, width: 1.5),
              ),
              child: ClipOval(
                child: widget.p.logoAsset != null
                    ? Image.asset(widget.p.logoAsset!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(widget.p.icon ?? Icons.shopping_bag,
                                color: AppColors.brandOrange, size: 22))
                    : Icon(widget.p.icon ?? Icons.shopping_bag,
                        size: 22, color: AppColors.brandOrange),
              ),
            ),
            const SizedBox(height: 5),
            Flexible(
              child: Text(widget.p.name,
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.title, height: 1.3),
              ),
            ),
            Text(widget.p.price,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                  color: AppColors.brandOrange),
            ),
          ],
        ),
      ),
    );
  }
}

/* ═══════════════════════════════════════════════════
   LATEST ARRIVALS SECTION
═══════════════════════════════════════════════════ */
class LatestArrivalsSection extends StatefulWidget {
  const LatestArrivalsSection({super.key});

  @override
  State<LatestArrivalsSection> createState() => _LatestArrivalsSectionState();
}

class _LatestArrivalsSectionState extends State<LatestArrivalsSection> {
  final _service = LatestArrivalServices();
  late final CartService _cart = CartService('', apiPrefix: ApiConfig.apiPrefix);
  late Future<List<LatestArrivalModels>> _future;
  final Map<String, Future<String?>> _imgCache = {};

  @override
  void initState() {
    super.initState();
    _future = _service.fetchLatestArrivals();
  }

  String _fmtKwacha(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  int _fnv1a32(String input) {
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime  = 0x01000193;
    int hash = fnvOffset;
    for (final cu in input.codeUnits) {
      hash ^= cu;
      hash  = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  Uint8List? _tryDecodeBase64(String v) {
    if (v.isEmpty) return null;
    try {
      var cleaned = v.trim().replaceAll(RegExp(r'\s+'), '');
      final ci    = cleaned.indexOf(',');
      if (cleaned.startsWith('data:image') && ci != -1) cleaned = cleaned.substring(ci + 1);
      final mod = cleaned.length % 4;
      if (mod != 0) cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
      final bytes = base64Decode(cleaned);
      return bytes.isEmpty ? null : bytes;
    } catch (_) { return null; }
  }

  Future<String?> _resolveImageString(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('data:image/')) return s;
    if (s.startsWith('gs://')) {
      try { return await FirebaseStorage.instance.refFromURL(s).getDownloadURL(); } catch (_) {}
    }
    if (s.contains('/') && !s.contains(' ')) {
      try { return await FirebaseStorage.instance.ref(s).getDownloadURL(); } catch (_) {}
    }
    if (s.contains('.') && !s.contains(' ')) {
      for (final path in ['latest/$s', 'latest_arrivals/$s', 'uploads/$s', 'products/$s']) {
        try { return await FirebaseStorage.instance.ref(path).getDownloadURL(); } catch (_) {}
      }
    }
    return null;
  }

  Future<String?> _resolveImage(LatestArrivalModels it) async {
    final direct = await _resolveImageString(it.imageUrl);
    if (direct != null) return direct;

    Future<String?> fromDoc(String col, String docId) async {
      try {
        final doc = await FirebaseFirestore.instance.collection(col).doc(docId).get();
        if (!doc.exists) return null;
        final d = doc.data() ?? {};
        final candidate = (d['imageUrl'] ?? d['image'] ?? d['thumbnail'] ??
            d['storagePath'] ?? d['gsUrl'] ?? d['path'] ?? '').toString().trim();
        return await _resolveImageString(candidate);
      } catch (_) { return null; }
    }

    Future<String?> fromNameQuery(String col) async {
      try {
        final q = await FirebaseFirestore.instance
            .collection(col).where('name', isEqualTo: it.name.trim()).limit(1).get();
        if (q.docs.isEmpty) return null;
        final d = q.docs.first.data();
        final candidate = (d['imageUrl'] ?? d['image'] ?? d['thumbnail'] ??
            d['storagePath'] ?? d['gsUrl'] ?? d['path'] ?? '').toString().trim();
        return await _resolveImageString(candidate);
      } catch (_) { return null; }
    }

    final id = it.id.trim();
    if (id.isNotEmpty) {
      final a = await fromDoc('latestarrivals', id);
      if (a != null) return a;
      final b = await fromDoc('latest_arrivals', id);
      if (b != null) return b;
    }
    final c = await fromNameQuery('latestarrivals');
    if (c != null) return c;
    return await fromNameQuery('latest_arrivals');
  }

  Future<String?> _imgFuture(LatestArrivalModels it) {
    final key = it.id.isNotEmpty ? it.id : '${it.name}_${it.price}';
    return _imgCache.putIfAbsent(key, () => _resolveImage(it));
  }

  CartModel _makeCartModel(LatestArrivalModels it, String img, {required int qty}) {
    final parsed    = int.tryParse(it.id.trim());
    final itemId    = parsed ?? _fnv1a32('latest:${it.id}:${it.name}');
    final userKey   = FirebaseAuth.instance.currentUser?.uid ?? '';
    return CartModel(
      userId: userKey, item: itemId, quantity: qty,
      name: it.name, image: img, price: it.price.toDouble(),
      description: '', comment: null,
      merchantId: 'marketplace', merchantName: 'Marketplace', serviceType: 'marketplace',
    );
  }

  Future<void> _addToCart(LatestArrivalModels it, {required int qty, required BuildContext sheetCtx}) async {
    if (qty <= 0) return;
    if (FirebaseAuth.instance.currentUser == null) {
      ToastHelper.showCustomToast(sheetCtx, 'Please log in to add items.', isSuccess: false, errorMessage: '');
      return;
    }
    try {
      final img = (await _resolveImage(it)) ?? it.imageUrl;
      await _cart.addToCart(_makeCartModel(it, img, qty: qty));
      if (!mounted) return;
      ToastHelper.showCustomToast(sheetCtx, '${it.name} added to cart', isSuccess: true, errorMessage: '');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(sheetCtx, 'Failed to add to cart — please log in', isSuccess: false, errorMessage: e.toString());
    }
  }

  Future<void> _buyNow(LatestArrivalModels it, {required int qty, required BuildContext sheetCtx}) async {
    if (qty <= 0) return;
    if (FirebaseAuth.instance.currentUser == null) {
      ToastHelper.showCustomToast(sheetCtx, 'Please log in to buy.', isSuccess: false, errorMessage: '');
      return;
    }
    final img      = (await _resolveImage(it)) ?? it.imageUrl;
    final cartItem = _makeCartModel(it, img, qty: qty);
    try { await _cart.addToCart(cartItem); } catch (_) {}
    if (!mounted) return;
    if (Navigator.of(sheetCtx).canPop()) Navigator.of(sheetCtx).pop();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CheckoutFromCartPage(items: [cartItem])),
    );
  }

  void _openDetails(LatestArrivalModels it) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => _LatestDetailsSheet(
        item:            it,
        imageFuture:     _imgFuture(it),
        fmtPrice:        (n) => 'MWK ${_fmtKwacha(n)}',
        tryDecodeBase64: _tryDecodeBase64,
        onAddToCart:     (qty) async => _addToCart(it, qty: qty, sheetCtx: sheetCtx),
        onBuyNow:        (qty) async => _buyNow(it,    qty: qty, sheetCtx: sheetCtx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: "Today's Arrivals", subtitle: 'Fresh items just in'),
        const SizedBox(height: 12),
        FutureBuilder<List<LatestArrivalModels>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const AppSkeletonLatestArrivalsGrid();
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Could not load arrivals.\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }
            final items = snap.data ?? const <LatestArrivalModels>[];
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No arrivals today.', style: TextStyle(color: Colors.red))),
              );
            }
            final width = MediaQuery.of(context).size.width;
            final cols  = width >= 1200 ? 4 : width >= 800 ? 3 : 2;
            final ratio = width >= 1200 ? 0.95 : width >= 800 ? 0.85 : 0.72;

            return GridView.builder(
              shrinkWrap: true,
              physics:    const NeverScrollableScrollPhysics(),
              padding:    EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:   cols,
                crossAxisSpacing: 10,
                mainAxisSpacing:  10,
                childAspectRatio: ratio,
              ),
              itemCount:   items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                return _ProductCard(
                  item:            it,
                  priceText:       'MWK ${_fmtKwacha(it.price)}',
                  imageFuture:     _imgFuture(it),
                  tryDecodeBase64: _tryDecodeBase64,
                  onTap:           () => _openDetails(it),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final LatestArrivalModels         item;
  final String                      priceText;
  final Future<String?>             imageFuture;
  final Uint8List? Function(String) tryDecodeBase64;
  final VoidCallback                onTap;

  const _ProductCard({
    required this.item, required this.priceText,
    required this.imageFuture, required this.tryDecodeBase64, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        shape:        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation:    0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder<String?>(
                future: imageFuture,
                builder: (_, snap) {
                  final v = (snap.data ?? item.imageUrl).trim();
                  if (v.isEmpty) return const _ImgPlaceholder();
                  if (v.startsWith('data:image/')) {
                    final bytes = tryDecodeBase64(v);
                    return bytes == null ? const _ImgPlaceholder() : Image.memory(bytes, fit: BoxFit.cover);
                  }
                  if (v.startsWith('http://') || v.startsWith('https://')) {
                    return Image.network(v, fit: BoxFit.cover,
                      loadingBuilder: (_, child, prog) =>
                          prog == null ? child : const Center(child: SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                      errorBuilder: (_, __, ___) => const _ImgPlaceholder(),
                    );
                  }
                  return const _ImgPlaceholder();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(priceText, maxLines: 1,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green),
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

class _LatestDetailsSheet extends StatefulWidget {
  final LatestArrivalModels         item;
  final Future<String?>             imageFuture;
  final String Function(int)        fmtPrice;
  final Uint8List? Function(String) tryDecodeBase64;
  final Future<void> Function(int)  onAddToCart;
  final Future<void> Function(int)  onBuyNow;

  const _LatestDetailsSheet({
    required this.item, required this.imageFuture, required this.fmtPrice,
    required this.tryDecodeBase64, required this.onAddToCart, required this.onBuyNow,
  });

  @override
  State<_LatestDetailsSheet> createState() => _LatestDetailsSheetState();
}

class _LatestDetailsSheetState extends State<_LatestDetailsSheet> {
  int qty = 1;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String?>(
                  future: widget.imageFuture,
                  builder: (_, snap) {
                    final v = (snap.data ?? it.imageUrl).trim();
                    Widget img;
                    if (v.isEmpty) { img = const _ImgPlaceholder(); }
                    else if (v.startsWith('data:image/')) {
                      final bytes = widget.tryDecodeBase64(v);
                      img = bytes == null ? const _ImgPlaceholder() : Image.memory(bytes, fit: BoxFit.cover);
                    } else if (v.startsWith('http://') || v.startsWith('https://')) {
                      img = Image.network(v, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _ImgPlaceholder());
                    } else { img = const _ImgPlaceholder(); }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(height: 220, width: double.infinity, child: img),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(it.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(widget.fmtPrice(it.price),
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      onPressed: qty <= 1 ? null : () => setState(() => qty--),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    IconButton(
                      onPressed: qty >= 99 ? null : () => setState(() => qty++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onAddToCart(qty),
                        icon:  const Icon(Icons.shopping_cart_outlined),
                        label: const Text('Add to Cart',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandOrange,
                          side:  const BorderSide(color: AppColors.brandOrange),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => widget.onBuyNow(qty),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Buy Now', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFEDEDED),
    child: const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.black38)),
  );
}

/* ═══════════════════════════════════════════════════
   COACH OVERLAY — SERVICE GUIDE
═══════════════════════════════════════════════════ */
class ServiceGuideStep {
  final String keyId;
  final String title;
  final String description;
  const ServiceGuideStep({required this.keyId, required this.title, required this.description});
}

class QuickServicesCoachOverlay extends StatefulWidget {
  const QuickServicesCoachOverlay({
    super.key,
    required this.stackContext,
    required this.currentIndex,
    required this.steps,
    required this.tileKeys,
    required this.onSkip,
    required this.onNext,
  });

  final BuildContext                  stackContext;
  final List<ServiceGuideStep>        steps;
  final int                           currentIndex;
  final Map<String, GlobalKey>        tileKeys;
  final Future<void> Function()       onSkip;
  final Future<void> Function()       onNext;

  @override
  State<QuickServicesCoachOverlay> createState() => _QuickServicesCoachOverlayState();
}

class _QuickServicesCoachOverlayState extends State<QuickServicesCoachOverlay>
    with TickerProviderStateMixin {

  late final AnimationController _entranceCtrl;
  late final Animation<double>   _backdropFade;
  late final Animation<double>   _cardScale;
  late final Animation<double>   _cardFade;
  late final Animation<Offset>   _cardSlide;

  late final AnimationController _stepCtrl;
  late final Animation<double>   _stepFade;
  late final Animation<Offset>   _stepSlide;

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  late final AnimationController _orbCtrl;
  late final Animation<double>   _orbAnim;

  Rect? _targetRect;
  bool  _transitioning = false;

  ServiceGuideStep get _step => widget.steps[widget.currentIndex];

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _backdropFade = CurvedAnimation(
        parent: _entranceCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
    _cardScale = Tween<double>(begin: 0.80, end: 1.0).animate(
        CurvedAnimation(parent: _entranceCtrl,
            curve: const Interval(0.25, 1.0, curve: Curves.elasticOut)));
    _cardFade  = CurvedAnimation(
        parent: _entranceCtrl, curve: const Interval(0.2, 0.7, curve: Curves.easeOut));
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero).animate(
        CurvedAnimation(parent: _entranceCtrl,
            curve: const Interval(0.2, 0.85, curve: Curves.easeOutCubic)));

    _stepCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _stepFade  = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.easeIn));
    _stepSlide = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.07, 0.0))
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.easeIn));

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _orbAnim = CurvedAnimation(parent: _orbCtrl, curve: Curves.easeInOut);

    _entranceCtrl.forward();
    _measure();
  }

  @override
  void didUpdateWidget(covariant QuickServicesCoachOverlay old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) _animateStep();
  }

  Future<void> _animateStep() async {
    if (_transitioning) return;
    _transitioning = true;
    await _stepCtrl.forward();
    if (!mounted) return;
    _measure();
    await _stepCtrl.reverse();
    _transitioning = false;
  }

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key     = widget.tileKeys[_step.keyId];
      final tileCtx = key?.currentContext;
      final stackRb = widget.stackContext.findRenderObject() as RenderBox?;
      if (tileCtx == null || stackRb == null || !stackRb.hasSize) return;
      final tileRb  = tileCtx.findRenderObject() as RenderBox?;
      if (tileRb == null || !tileRb.hasSize) return;
      final tl = stackRb.globalToLocal(tileRb.localToGlobal(Offset.zero));
      if (mounted) setState(() => _targetRect = tl & tileRb.size);
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _stepCtrl.dispose();
    _pulseCtrl.dispose();
    _orbCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent  = AppColors.brandOrange;
    final total   = widget.steps.length;
    final idx     = widget.currentIndex;
    final isLast  = idx == total - 1;
    final screenW = MediaQuery.sizeOf(context).width;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entranceCtrl, _stepCtrl, _pulseCtrl, _orbCtrl]),
        builder: (ctx, _) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              /* frosted backdrop */
              Opacity(
                opacity: _backdropFade.value,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Container(color: Colors.black.withOpacity(0.50)),
                ),
              ),

              /* floating orbs */
              if (_targetRect != null) ...[
                _Orb(anim: _orbAnim, left: _targetRect!.center.dx - 110,
                    top: _targetRect!.top - 270, size: 190,
                    color: accent.withOpacity(0.16), phase: 0.0),
                _Orb(anim: _orbAnim, left: _targetRect!.center.dx + 40,
                    top: _targetRect!.top - 190, size: 90,
                    color: accent.withOpacity(0.08), phase: 0.55),
              ],

              /* spotlight ring */
              if (_targetRect != null)
                Positioned(
                  left: _targetRect!.left - 7,
                  top:  _targetRect!.top  - 7,
                  child: _SpotlightRing(
                    w:     _targetRect!.width  + 14,
                    h:     _targetRect!.height + 14,
                    pulse: _pulseAnim.value,
                    color: accent,
                  ),
                ),

              /* bobbing arrow */
              if (_targetRect != null)
                Positioned(
                  left: (_targetRect!.center.dx - 18).clamp(8.0, screenW - 44),
                  top:  (_targetRect!.top - 58).clamp(8.0, 99999.0),
                  child: _BobArrow(pulse: _pulseAnim.value, color: accent),
                ),

              /* guide card */
              Positioned(
                left:   16,
                right:  16,
                top:    _targetRect != null
                    ? (_targetRect!.top - 240).clamp(8.0, 99999.0)
                    : null,
                bottom: _targetRect == null ? 40 : null,
                child: FadeTransition(
                  opacity: _stepFade,
                  child: SlideTransition(
                    position: _stepSlide,
                    child: ScaleTransition(
                      scale: _cardScale,
                      child: FadeTransition(
                        opacity: _cardFade,
                        child: SlideTransition(
                          position: _cardSlide,
                          child: _GuideCard(
                            step:    _step,
                            idx:     idx,
                            total:   total,
                            accent:  accent,
                            isLast:  isLast,
                            onSkip:  widget.onSkip,
                            onNext:  widget.onNext,
                          ),
                        ),
                      ),
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
}

/* ── Guide card ──────────────────────────────────── */
class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.step,  required this.idx,   required this.total,
    required this.accent,required this.isLast,required this.onSkip, required this.onNext,
  });

  final ServiceGuideStep         step;
  final int                      idx;
  final int                      total;
  final Color                    accent;
  final bool                     isLast;
  final Future<void> Function()  onSkip;
  final Future<void> Function()  onNext;

  static const Map<String, IconData> _icons = {
    'taxi':          Icons.local_taxi_rounded,
    'airport_pickup':Icons.flight_takeoff_rounded,
    'courier':       Icons.local_shipping_rounded,
    'vero_bike':     Icons.pedal_bike_rounded,
    'fx':            Icons.currency_exchange_rounded,
    'food':          Icons.fastfood_rounded,
    'jobs':          Icons.business_center_rounded,
    'accommodation': Icons.hotel_rounded,
  };

  Color _darken(Color c, double amt) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - amt).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final icon     = _icons[step.keyId] ?? Icons.star_rounded;
    final progress = (idx + 1) / total;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color:      accent.withOpacity(0.25),
              blurRadius: 36,
              spreadRadius: 2,
              offset:     const Offset(0, 10),
            ),
            const BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /* gradient header */
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withOpacity(0.70)],
                    begin:  Alignment.topLeft,
                    end:    Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color:  Colors.white.withOpacity(0.20),
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.55), width: 1.5),
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                            style: const TextStyle(color: Colors.white, fontSize: 16,
                                fontWeight: FontWeight.w900, letterSpacing: -0.2),
                          ),
                          const SizedBox(height: 2),
                          Text('Step ${idx + 1} of $total',
                            style: TextStyle(color: Colors.white.withOpacity(0.80),
                                fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              /* animated progress bar */
              LayoutBuilder(builder: (ctx, c) {
                return Stack(
                  children: [
                    Container(height: 3, color: const Color(0xFFEEEEEE)),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 430),
                      curve:    Curves.easeOutCubic,
                      height:   3,
                      width:    c.maxWidth * progress,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [accent, accent.withOpacity(0.5)]),
                      ),
                    ),
                  ],
                );
              }),

              /* body */
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.description,
                      style: const TextStyle(
                        fontSize: 13.5, height: 1.55,
                        color: AppColors.body, fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),

                    /* step dots */
                    Row(
                      children: List.generate(total, (i) {
                        final active = i == idx;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve:    Curves.easeOutCubic,
                          margin:   const EdgeInsets.only(right: 5),
                          width:    active ? 22 : 7,
                          height:   7,
                          decoration: BoxDecoration(
                            color:        active ? accent : const Color(0xFFDDDDDD),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 14),

                    /* action buttons */
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: onSkip,
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:        AppColors.brandOrange.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Text('Skip tour',
                                style: TextStyle(color: AppColors.brandOrange,
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: onNext,
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [accent, _darken(accent, 0.09)],
                                  begin:  Alignment.topLeft,
                                  end:    Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                    color:      accent.withOpacity(0.38),
                                    blurRadius: 12,
                                    offset:     const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isLast ? 'Finish' : 'Next',
                                    style: const TextStyle(color: Colors.white,
                                        fontWeight: FontWeight.w800, fontSize: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    isLast ? Icons.check_circle_outline_rounded
                                           : Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 17,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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

/* ── Spotlight ring ──────────────────────────────── */
class _SpotlightRing extends StatelessWidget {
  const _SpotlightRing({required this.w, required this.h, required this.pulse, required this.color});
  final double w, h, pulse;
  final Color  color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: w, height: h,
    child: CustomPaint(painter: _RingPainter(pulse: pulse, color: color)),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.pulse, required this.color});
  final double pulse;
  final Color  color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, size.height / 2),
          width: size.width, height: size.height),
      const Radius.circular(14),
    );
    canvas.drawRRect(rrect, Paint()
      ..color       = color.withOpacity(0.28 * pulse)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 9));
    canvas.drawRRect(rrect, Paint()
      ..color       = color.withOpacity(0.50 + 0.50 * pulse)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.pulse != pulse || o.color != color;
}

/* ── Bobbing arrow ───────────────────────────────── */
class _BobArrow extends StatelessWidget {
  const _BobArrow({required this.pulse, required this.color});
  final double pulse;
  final Color  color;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(0, -5 * pulse + 2.5),
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.42 * pulse), blurRadius: 18, spreadRadius: 2)],
      ),
      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 22),
    ),
  );
}

/* ── Floating orb ────────────────────────────────── */
class _Orb extends StatelessWidget {
  const _Orb({required this.anim, required this.left, required this.top,
      required this.size, required this.color, required this.phase});
  final Animation<double> anim;
  final double left, top, size, phase;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final dy = math.sin((anim.value + phase) * math.pi * 2) * 12;
    return Positioned(
      left: left, top: top + dy,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/* ═══════════════════════════════════════════════════
   SEARCH DELEGATE
═══════════════════════════════════════════════════ */
class QuickServiceSearchDelegate extends SearchDelegate<Mini?> {
  final List<Mini> services;
  QuickServiceSearchDelegate({required this.services})
      : super(searchFieldLabel: 'Search quick services');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        iconTheme:       const IconThemeData(color: Colors.white),
        titleTextStyle:  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        border:    InputBorder.none,
      ),
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    );
  }

  static const Map<String, String> _aliases = {
    'taxi': 'taxi',       'vero ride': 'taxi',   'ride': 'taxi',    'cab': 'taxi',
    'bike': 'vero_bike',  'bicycle': 'vero_bike', 'verobike': 'vero_bike',
    'airport': 'airport_pickup', 'pickup': 'airport_pickup',
    'courier': 'courier', 'parcel': 'courier',   'delivery': 'courier',
    'accommodation': 'accommodation', 'accomodation': 'accommodation',
    'hotel': 'accommodation', 'hostel': 'accommodation', 'rooms': 'accommodation',
    'fx': 'fx',           'forex': 'fx',          'exchange rate': 'fx', 'rates': 'fx',
    'food': 'food',       'restaurant': 'food',   'order': 'food',
    'jobs': 'jobs',       'work': 'jobs',         'vacancies': 'jobs',
  };

  Iterable<Mini> _filter(String q) {
    final t        = q.trim().toLowerCase();
    if (t.isEmpty) return services;
    final aliasKey = _aliases[t];
    if (aliasKey != null) return services.where((m) => m.keyId == aliasKey);
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return services.where((m) {
      final l = m.label.toLowerCase();
      return l.contains(t) || words.any(l.contains);
    });
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      final popular = ['Taxi', 'Bike', 'Airport pickup', 'Food', 'Hotel', 'FX', 'Jobs', 'Courier'];
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            for (final p in popular)
              ActionChip(
                label:           Text(p),
                onPressed:       () { query = p.toLowerCase(); showSuggestions(context); },
                backgroundColor: AppColors.brandOrangePale,
                shape: StadiumBorder(side: const BorderSide(color: AppColors.brandOrangeSoft)),
              ),
          ],
        ),
      );
    }
    final results = _filter(query).toList();
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No matches. Try: taxi, bike, airport, hotel, forex, food, jobs...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount:       results.length,
      separatorBuilder:(_, __) => const SizedBox(height: 6),
      padding:         const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemBuilder: (_, i) {
        final m = results[i];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.brandOrangeSoft),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.brandOrangePale,
              child: Icon(m.icon, color: AppColors.brandOrange),
            ),
            title:    Text(m.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(m.keyId),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.body),
            onTap:    () => close(context, m),
          ),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        icon:      const Icon(Icons.clear),
        onPressed: () { query = ''; showSuggestions(context); },
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
}

/* ═══════════════════════════════════════════════════
   SHARED WIDGETS
═══════════════════════════════════════════════════ */
class _Dots extends StatelessWidget {
  final int count, index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin:   const EdgeInsets.symmetric(horizontal: 3),
          height:   6,
          width:    active ? 18 : 6,
          decoration: BoxDecoration(
            color:        active ? AppColors.brandOrange : const Color(0xFFE1E1E1),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String  title;
  final String? subtitle;
  final Widget? action;
  const _SectionHeader({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
              style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w900,
                color: AppColors.title, letterSpacing: -0.3,
              ),
            ),
            if (subtitle != null)
              Text(subtitle!,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppColors.body.withOpacity(0.80),
                ),
              ),
          ],
        ),
        if (action != null) action!,
      ],
    );
  }
}

/* ═══════════════════════════════════════════════════
   DIGITAL PRODUCT DETAIL / CHECKOUT PAGE
═══════════════════════════════════════════════════ */
class DigitalProductDetailPage extends StatefulWidget {
  final DigitalProduct product;
  final String?        initialEmail;
  final String?        initialPhone;
  final String?        initialName;

  const DigitalProductDetailPage({
    super.key,
    required this.product,
    this.initialEmail,
    this.initialPhone,
    this.initialName,
  });

  @override
  State<DigitalProductDetailPage> createState() => _DigitalProductDetailPageState();
}

class _DigitalProductDetailPageState extends State<DigitalProductDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.initialName  ?? '');
    _phoneCtrl = TextEditingController(text: widget.initialPhone ?? '');
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidMwLocalPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^0[89]\d{8}$').hasMatch(digits);
  }

  static double _parsePrice(String priceStr) {
    final digits = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(digits) ?? 0;
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

  Future<void> _payNow() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final name      = _nameCtrl.text.trim();
      final email     = _emailCtrl.text.trim();
      final phone     = _normalizePhone(_phoneCtrl.text.trim());
      final parts     = name.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : 'Customer';
      final lastName  = parts.length > 1  ? parts.sublist(1).join(' ') : '';
      final amount    = _parsePrice(widget.product.price);
      if (amount <= 0) {
        ToastHelper.showCustomToast(context, 'Invalid price.', isSuccess: false, errorMessage: '');
        return;
      }
      try { await InternetAddress.lookup('api.paychangu.com'); }
      on SocketException catch (_) {
        throw Exception('Cannot connect to payment service. Check your internet connection.');
      }
      final txRef       = 'vero-digital-${DateTime.now().millisecondsSinceEpoch}';
      final description = 'Digital: ${widget.product.name} • ${widget.product.subtitle}';
      final response    = await http.post(
        PayChanguConfig.paymentUri,
        headers: PayChanguConfig.authHeaders,
        body: json.encode({
          'tx_ref':         txRef,
          'first_name':     firstName,
          'last_name':      lastName,
          'email':          email,
          'phone_number':   phone,
          'currency':       'MWK',
          'amount':         amount.round().toString(),
          'payment_methods':['card', 'mobile_money', 'bank'],
          'callback_url':   PayChanguConfig.callbackUrl,
          'return_url':     PayChanguConfig.returnUrl,
          'customization':  {'title': 'Vero 360 Payment', 'description': description},
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
<<<<<<< HEAD
        final Map<String, dynamic> json2 = jsonDecode(response.body) as Map<String, dynamic>;
        if ((json2['status'] ?? '').toString().toLowerCase() == 'success') {
          final checkoutUrl = json2['data']['checkout_url'] as String;
=======
        final Map<String, dynamic> responseJson =
            json.decode(response.body) as Map<String, dynamic>;
        final status = (responseJson['status'] ?? '').toString().toLowerCase();
        if (status == 'success') {
          final checkoutUrl = responseJson['data']['checkout_url'] as String;
>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InAppPaymentPage(
              checkoutUrl:        checkoutUrl,
              txRef:              txRef,
              totalAmount:        amount,
              rootContext:        context,
              digitalProductName: widget.product.name,
            ),
          ));
        } else {
<<<<<<< HEAD
          throw Exception(json2['message'] ?? 'Payment failed');
=======
          throw Exception(responseJson['message'] ?? 'Payment failed');
>>>>>>> c3039d1f1c03f21ef70abd1f02f2d8f3c994c351
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(context, 'Network error. Check your connection.',
          isSuccess: false, errorMessage: e.message);
    } on TimeoutException {
      ToastHelper.showCustomToast(context, 'Connection timeout. Please try again.',
          isSuccess: false, errorMessage: 'Request timed out');
    } catch (e) {
      ToastHelper.showCustomToast(context, 'Payment error: $e',
          isSuccess: false, errorMessage: 'Payment failed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(
        title:           Text('Buy ${p.name}'),
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        elevation:       0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /* product summary card */
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color:        Colors.white,
                  border:       Border.all(color: AppColors.brandOrangeSoft),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: const Color(0x14000000), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color:  AppColors.brandOrangePale,
                        shape:  BoxShape.circle,
                        border: Border.all(color: AppColors.brandOrange),
                      ),
                      child: ClipOval(
                        child: p.logoAsset != null
                            ? Image.asset(p.logoAsset!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Icon(p.icon ?? Icons.shopping_bag, color: AppColors.title))
                            : Icon(p.icon ?? Icons.shopping_bag, size: 26, color: AppColors.title),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.body, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(p.price,
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              /* form */
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _LabeledField(
                      label:        'Full name',
                      controller:   _nameCtrl,
                      keyboardType: TextInputType.name,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.length < 2) return 'Enter your name';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label:        'Phone Number',
                      controller:   _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (!_isValidMwLocalPhone(t)) return 'Enter 10 digits starting with 08 or 09';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label:        'Email address',
                      controller:   _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final t  = v?.trim() ?? '';
                        if (t.isEmpty) return 'Enter your email';
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t)) return 'Enter a valid email';
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _payNow,
                  icon: _submitting
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_outline_rounded),
                  label: Text(_submitting ? 'Processing...' : 'Pay Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandOrange,
                    foregroundColor: Colors.white,
                    elevation:       0,
                    padding:  const EdgeInsets.symmetric(vertical: 14),
                    shape:    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'Secure checkout • Check your notifications and email for instructions',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.body, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String                    label;
  final TextEditingController     controller;
  final TextInputType?            keyboardType;
  final String? Function(String?) validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide:   const BorderSide(color: AppColors.brandOrangeSoft),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.title, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller:   controller,
          keyboardType: keyboardType,
          validator:    validator,
          decoration: InputDecoration(
            isDense:         true,
            contentPadding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            enabledBorder:   border,
            focusedBorder:   border.copyWith(borderSide: const BorderSide(color: AppColors.brandOrange)),
            errorBorder:     border.copyWith(borderSide: const BorderSide(color: Colors.redAccent)),
            focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Colors.redAccent)),
            fillColor:       Colors.white,
            filled:          true,
            hintText:        label,
          ),
        ),
      ],
    );
  }
}

/* ═══════════════════════════════════════════════════
   UTILITY
═══════════════════════════════════════════════════ */
class UtilityPage extends StatelessWidget {
  final String title;
  const UtilityPage({super.key, this.title = 'Utility'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$title coming soon')),
    );
  }
}