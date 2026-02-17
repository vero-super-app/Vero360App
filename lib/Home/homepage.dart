// lib/Pages/homepage.dart
//
// ✅ Full corrected Vero360 Homepage (single file)
// - No duplicate imports
// - Single LatestArrivalsSection
// - Latest Arrivals:
//    * loads from API (LatestArrivalServices)
//    * resolves images from URL / base64 / gs:// / storage path / Firestore doc
//    * tap product card/photo => details bottomsheet (compact, not full screen)
//    * bottomsheet has Add to Cart + Buy Now (Buy Now -> CheckoutFromCartPage)
//    * ✅ Uses ToastHelper for feedback ON TOP of bottomsheet (not behind)
//
// NOTE: Make sure toasthelper.dart is fixed/working. This file calls:
// ToastHelper.showCustomToast(context, message, isSuccess: ..., errorMessage: ...)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ✅ Firebase (for Latest Arrivals images + cart)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:vero360_app/Quickservices/social.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
//import 'package:vero360_app/features/Accomodation/Presentation/pages/Accomodation.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/bike_ride_share_map_screen.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_share_map_screen.dart';

// ✅ Cart + checkout
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';

// Feature pages

import 'package:vero360_app/Quickservices/ExchangeRate.dart';

import 'package:vero360_app/features/AirportPickup/AirportPresenter/airportpickup.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food.dart';
import 'package:vero360_app/Quickservices/jobs.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/verocourier.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/config/paychangu_config.dart';

// Latest arrivals (API)
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/Latest_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/MarkeplaceMerchantServices/latest_Services.dart';

// ✅ Toast helper
import 'package:vero360_app/utils/toasthelper.dart';

// ✅ Providers
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';

class AppColors {
  static const brandOrange = Color(0xFFFF8A00);
  static const brandOrangeSoft = Color(0xFFFFEAD1);
  static const brandOrangePale = Color(0xFFFFF4E6);

  static const title = Color(0xFF101010);
  static const body = Color(0xFF6B6B6B);
  static const chip = Color(0xFFF9F5EF);
  static const card = Color(0xFFFFFFFF);
  static const bgBottom = Color(0xFFFFFFFF);
}

/// Tunable gaps
const double kGapAfterNearby = 6;

/* ───────────────────────────────────────────
   MINI ICON MODEL
─────────────────────────────────────────── */
class Mini {
  final String keyId;
  final String label;
  final IconData icon;
  const Mini(this.keyId, this.label, this.icon);
}

/* ───────────────────────────────────────────
   QUICK SERVICES: single source of truth
─────────────────────────────────────────── */
const List<Mini> kQuickServices = [
  Mini('taxi', 'Vero ride/Taxi', Icons.local_taxi_rounded),
  Mini('airport_pickup', 'Airport pickup', Icons.flight_takeoff_rounded),
  Mini('courier', 'Vero courier', Icons.local_shipping_rounded),
  Mini('vero_bike', 'Vero bike', Icons.pedal_bike_rounded),
  Mini('fx', 'Exchange rates', Icons.currency_exchange_rounded),
  Mini('food', 'Food', Icons.fastfood_rounded),
  Mini('jobs', 'Jobs', Icons.business_center_rounded),
  Mini('accommodation', 'Accomodation', Icons.hotel_rounded),
];

/* ───────────────────────────────────────────
   DIGITAL & VIRTUAL SERVICES — model & data
─────────────────────────────────────────── */
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
    key: 'spotify',
    name: 'Spotify Premium',
    subtitle: '1-month subscription',
    price: 'MWK 8,000',
    logoAsset: 'assets/brands/spotify.png',
    icon: Icons.music_note_rounded,
  ),
  DigitalProduct(
    key: 'apple_music',
    name: 'Apple Music',
    subtitle: '1-month subscription',
    price: 'MWK 8,000',
    logoAsset: 'assets/brands/apple_music.png',
    icon: Icons.music_note_rounded,
  ),
  DigitalProduct(
    key: 'netflix',
    name: 'Netflix',
    subtitle: '1-month subscription',
    price: 'MWK 12,000',
    logoAsset: 'assets/brands/netflix.png',
    icon: Icons.movie_creation_outlined,
  ),
  DigitalProduct(
    key: 'chatgpt_plus',
    name: 'ChatGPT Plus',
    subtitle: '1-month subscription',
    price: 'MWK 16,000',
    logoAsset: 'assets/brands/chatgpt.png',
    icon: Icons.chat_bubble_outline_rounded,
  ),
];

class Vero360Homepage extends ConsumerStatefulWidget {
  final String email;
  const Vero360Homepage({super.key, required this.email});

  @override
  ConsumerState<Vero360Homepage> createState() => _Vero360HomepageState();
}

class _Vero360HomepageState extends ConsumerState<Vero360Homepage> {
  final _search = TextEditingController();
  int _promoIndex = 0;
  bool _animateIn = false;

  String _firstNameFromEmail(String email) {
    final user = email.split('@').first;
    if (user.isEmpty) return 'there';
    final cleaned = user.replaceAll(RegExp(r'[^a-zA-Z]'), ' ');
    final parts = cleaned.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : 'there';
    if (first.isEmpty) return 'there';
    return '${first[0].toUpperCase()}${first.substring(1).toLowerCase()}';
  }

  final List<_Promo> _promos = const [
    _Promo(
      title: 'Marketplace',
      subtitle: 'order anything',
      code: '',
      image: 'assets/happy.jpg',
      bg: Color(0xFFFDF2E9),
      tint: AppColors.brandOrange,
      cta: 'Order now',
      serviceKey: 'food',
    ),
    _Promo(
      title: 'Free Delivery',
      subtitle: 'all week long',
      code: 'Use code FREEDEL',
      image: 'assets/Queens-Tavern-Steak.jpg',
      bg: Color(0xFFFFF4E6),
      tint: AppColors.brandOrange,
      cta: 'Order now',
      serviceKey: 'food',
    ),
    _Promo(
      title: 'Vero Ride',
      subtitle: 'Ride • 15% off',
      code: 'Use code GO15',
      image: 'assets/uber-cabs-1024x576.webp',
      bg: Color(0xFFFFF0E1),
      tint: AppColors.brandOrange,
      cta: 'Book a ride',
      serviceKey: 'taxi',
    ),
    _Promo(
      title: 'Vero AI',
      subtitle: 'Ask VeroAI',
      code: 'anything, anytime',
      image: 'assets/veroai.png',
      bg: Color(0xFFFFF4E6),
      tint: AppColors.brandOrange,
      cta: 'Chat now',
      serviceKey: 'Vero Chat',
    ),
  ];

  String? _resolvedGreetingName;
  bool _greetingResolved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateIn = true);
    });
    _resolveGreetingName();
  }

  Future<void> _resolveGreetingName() async {
    if (widget.email.isNotEmpty) return;
    final name = await AuthStorage.userNameFromToken();
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
      final cleaned = _resolvedGreetingName!.replaceAll(RegExp(r'[^a-zA-Z]'), ' ').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      final first = parts.isNotEmpty ? parts.first : 'there';
      if (first.isEmpty) return 'there';
      return '${first[0].toUpperCase()}${first.substring(1).toLowerCase()}';
    }
    return _greetingResolved ? 'there' : '...';
  }

  @override
  Widget build(BuildContext context) {
    final greeting = 'Hi, ${_displayName()} 👋';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: false,
        body: SafeArea(
          top: true,
          bottom: false,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFFBF6), AppColors.bgBottom],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Top: brand + search
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      children: [
                        const _BrandBar(
                          appName: 'Vero360',
                          logoPath: 'assets/logo_mark.png',
                        ),
                        const SizedBox(height: 12),
                        _TopSection(
                          animateIn: _animateIn,
                          greeting: greeting,
                          searchController: _search,
                          onSearchTap: _onSearchTap,
                        ),
                      ],
                    ),
                  ),
                ),

                // Promos
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _PromoCarousel(
                      promos: _promos,
                      onIndex: (i) => setState(() => _promoIndex = i),
                      onTap: _onPromoTap,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _Dots(count: _promos.length, index: _promoIndex),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                const SliverToBoxAdapter(child: _QuickStrip()),
                const SliverToBoxAdapter(child: SizedBox(height: 27)),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: _SectionCard(
                      title: 'Discover Our Quick Services',
                      child: _MiniIconsGrid(
                        items: kQuickServices,
                        onOpen: (key) => key == 'taxi'
                            ? _openService(key)
                            : _openServiceStatic(context, key),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                const SliverToBoxAdapter(child: _NearYouCarousel()),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                const SliverToBoxAdapter(child: _DealsStrip()),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 16, 0),
                    child: DigitalServicesSection(onBuy: _openDigitalDetail),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 10)),

                // ✅ Latest arrivals section
                const SliverToBoxAdapter(
                  child: Padding(
                    // Symmetric horizontal padding so cards sit closer to the edges
                    padding: EdgeInsets.fromLTRB(6, 12, 6, 16),
                    child: LatestArrivalsSection(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  void _onPromoTap(_Promo p) {
    if (p.serviceKey != null && p.serviceKey!.isNotEmpty) {
      p.serviceKey == 'taxi'
          ? _openService(p.serviceKey!)
          : _openServiceStatic(context, p.serviceKey!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coming soon')),
      );
    }
  }

  Future<void> _openDigitalDetail(DigitalProduct p) async {
    // Pull name, phone, email from user (SharedPreferences like checkout_page)
    String? initialName;
    String? initialPhone;
    String initialEmail = widget.email;
    try {
      final prefs = await SharedPreferences.getInstance();
      initialName = prefs.getString('name');
      initialPhone = prefs.getString('phone');
      if (initialEmail.trim().isEmpty) {
        initialEmail = prefs.getString('email') ?? '';
      }
      final suggestedName = _displayName();
      if ((initialName == null || initialName.isEmpty) &&
          suggestedName != 'there' && suggestedName != '...') {
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

  void _openService(String key) {
    // Special handling for taxi service
    if (key == 'taxi' || key == 'car_hire') {
      // ✅ Always open user/passenger mode when clicking ride share icon
      // Drivers access DriverDashboard automatically on login
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RideShareMapScreen()),
      );
    } else {
      _openServiceStatic(context, key);
    }
  }

  static void _openServiceStatic(BuildContext context, String key) {
    Widget page;
    switch (key) {
      case 'food':
      case 'grocery':
        page = FoodPage();
        break;
      case 'more':
        page = const BikeRideShareMapScreen();
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
      // case 'hostels':
      // case 'hotels':
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
}

/// BRAND BAR
class _BrandBar extends StatelessWidget {
  final String appName;
  final String logoPath;
  const _BrandBar({required this.appName, required this.logoPath});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.brandOrange, Color(0xFFFFB85C)],
            ),
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: Image.asset(
                logoPath,
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.eco,
                  size: 22,
                  color: AppColors.brandOrange,
                ),
              ),
            ),
          ),
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
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () {},
          icon: const Icon(Icons.notifications_active_outlined,
              color: AppColors.title),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// TOP SECTION
class _TopSection extends StatelessWidget {
  final bool animateIn;
  final String greeting;
  final TextEditingController searchController;
  final VoidCallback onSearchTap;

  const _TopSection({
    required this.animateIn,
    required this.greeting,
    required this.searchController,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: animateIn ? 1 : 0,
      duration: const Duration(milliseconds: 500),
      child: AnimatedSlide(
        offset: animateIn ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppColors.title,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onSearchTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.brandOrangeSoft),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Row(
                        children: [
                          Icon(Icons.search_rounded, color: Colors.grey),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'what are you looking for?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.body,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(Icons.expand_more_rounded, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: onSearchTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.brandOrange, Color(0xFFFFB85C)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33FF8A00),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Search',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Promo model
class _Promo {
  final String title, subtitle, code, image;
  final Color bg, tint;
  final String cta;
  final String? serviceKey;

  const _Promo({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.image,
    required this.bg,
    required this.tint,
    this.cta = 'Order now',
    this.serviceKey,
  });
}

/// Promo carousel
class _PromoCarousel extends StatelessWidget {
  final List<_Promo> promos;
  final ValueChanged<int> onIndex;
  final void Function(_Promo) onTap;

  const _PromoCarousel({
    required this.promos,
    required this.onIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CarouselSlider.builder(
      itemCount: promos.length,
      options: CarouselOptions(
        height: 160,
        autoPlay: true,
        enlargeCenterPage: true,
        viewportFraction: 0.92,
        onPageChanged: (i, _) => onIndex(i),
      ),
      itemBuilder: (_, i, __) {
        final p = promos[i];
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.bg, Colors.white],
                begin: const Alignment(-0.6, -1),
                end: const Alignment(1, 1),
              ),
              border: Border.all(color: AppColors.brandOrangeSoft),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                    child: Image.asset(
                      p.image,
                      width: 180,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 180,
                        color: const Color(0xFFEDEDED),
                        child: const Center(
                          child: Icon(Icons.image_not_supported_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 180, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        style: TextStyle(
                          color: p.tint,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.subtitle,
                        style: const TextStyle(
                          color: AppColors.title,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.code,
                        style: const TextStyle(
                          color: AppColors.body,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => onTap(p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          p.cta,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dots for carousels
class _Dots extends StatelessWidget {
  final int count, index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 6,
            width: active ? 18 : 6,
            decoration: BoxDecoration(
              color: active ? AppColors.brandOrange : const Color(0xFFE1E1E1),
              borderRadius: BorderRadius.circular(10),
            ),
          );
        }),
      ),
    );
  }
}

/// Chips strip
class _QuickStrip extends StatelessWidget {
  const _QuickStrip();
  @override
  Widget build(BuildContext context) {
    final items = const [
      ['⚡', 'Lightning deals'],
      ['🗺️', 'Explore nearby'],
      ['⭐', 'Top rated'],
      ['🛟', 'Support'],
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.chip,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.brandOrangeSoft),
          ),
          child: Center(
            child: Text(
              '${items[i][0]}  ${items[i][1]}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.title,
              ),
            ),
          ),
        ),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }
}

/* ───────────────────────────────────────────
   SECTION CARD + GRID
─────────────────────────────────────────── */
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandOrangeSoft.withOpacity(0.55)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.title,
              )),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _MiniIconsGrid extends StatelessWidget {
  final List<Mini> items;
  final void Function(String key) onOpen;
  const _MiniIconsGrid({required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;

      const crossSpacing = 8.0;
      const mainSpacing = 10.0;
      const minTileW = 92.0;

      int cross = (w / minTileW).floor().clamp(3, 6);
      double tileW = (w - (cross - 1) * crossSpacing) / cross;

      if (tileW < 88 && cross > 3) {
        cross -= 1;
        tileW = (w - (cross - 1) * crossSpacing) / cross;
      }

      final textScale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.2);
      const iconH = 48.0;
      const gapH = 6.0;
      const padH = 6.0;
      const font = 11.0;
      final twoLines = font * 1.25 * 2 * textScale;
      final minHeight = iconH + gapH + twoLines + padH;

      final ratio = (tileW / (minHeight + 2)).clamp(0.86, 1.10);

      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler:
              MediaQuery.of(context).textScaler.clamp(maxScaleFactor: 1.2),
        ),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: crossSpacing,
            mainAxisSpacing: mainSpacing,
            childAspectRatio: ratio,
          ),
          itemBuilder: (_, i) {
            final m = items[i];
            return _MiniIconTile(
              icon: m.icon,
              label: m.label,
              onTap: () => onOpen(m.keyId),
            );
          },
        ),
      );
    });
  }
}

class _MiniIconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniIconTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.brandOrangePale,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandOrange),
            ),
            child: Icon(icon, size: 22, color: AppColors.title),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.title,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      ['🚕', 'Vero Ride', '4.8'],
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
      child: Column(
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
              autoPlayAnimationDuration: const Duration(milliseconds: 600),
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
class _DealsStrip extends StatelessWidget {
  const _DealsStrip();
  @override
  Widget build(BuildContext context) {
    final deals = const [
      ['🚕', 'Vero Ride: available 24/7'],
      ['🍔', 'Food: order food on vero'],
      ['🏨', 'Stay: All nights, pay now'],
      ['💼', 'Utility: home cleaning deals'],
      ['💳', 'Mobile money: send and receive money'],
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient:
                const LinearGradient(colors: [Color(0xFFFFE2BF), Colors.white]),
            border: Border.all(color: AppColors.brandOrangeSoft),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              '${deals[i][0]}  ${deals[i][1]}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.title,
              ),
            ),
          ),
        ),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: deals.length,
      ),
    );
  }
}

/* ───────────────────────────────────────────
   DIGITAL & VIRTUAL SERVICES — circle tiles
─────────────────────────────────────────── */
class DigitalServicesSection extends StatelessWidget {
  final void Function(DigitalProduct p) onBuy;
  const DigitalServicesSection({super.key, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Digital & Virtual Services',
      action: TextButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('See all digital services')),
        ),
        child: const Text(
          'See all',
          style: TextStyle(
            color: AppColors.brandOrange,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        final w = c.maxWidth;
        const spacing = 10.0;
        const minTileW = 90.0;

        int cross = (w / minTileW).floor().clamp(3, 6);
        double tileW = (w - (cross - 1) * spacing) / cross;

        if (tileW < 86 && cross > 3) {
          cross -= 1;
          tileW = (w - (cross - 1) * spacing) / cross;
        }

        final textScale = MediaQuery.textScaleFactorOf(ctx).clamp(1.0, 1.2);
        const circle = 52.0;
        const gap = 4.0;
        final twoLines = 11.0 * 1.25 * 2 * textScale;
        final minHeight = circle + gap + twoLines + 6.0;

        final ratio = (tileW / minHeight).clamp(0.86, 1.15);

        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler:
                MediaQuery.of(ctx).textScaler.clamp(maxScaleFactor: 1.2),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: kDigitalProducts.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 8,
              childAspectRatio: ratio,
            ),
            itemBuilder: (_, i) {
              final p = kDigitalProducts[i];
              return _DigitalCircleTile(
                p: p,
                onTap: () => onBuy(p),
              );
            },
          ),
        );
      }),
    );
  }
}

class _DigitalCircleTile extends StatelessWidget {
  final DigitalProduct p;
  final VoidCallback onTap;
  const _DigitalCircleTile({required this.p, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brandOrangePale,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandOrange),
            ),
            child: ClipOval(
              child: p.logoAsset != null
                  ? Image.asset(
                      p.logoAsset!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        p.icon ?? Icons.shopping_bag,
                        color: AppColors.title,
                      ),
                    )
                  : Icon(
                      p.icon ?? Icons.shopping_bag,
                      size: 24,
                      color: AppColors.title,
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              p.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.title,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────────────────────
   ✅ LATEST ARRIVALS SECTION (FULL LOGIC)
   - Tap card => details bottomsheet
   - Bottomsheet: Add to Cart + Buy Now (goes to checkout)
   - ✅ Feedback uses ToastHelper ON the sheet context
   - Image resolver supports Firestore + Firebase Storage
─────────────────────────────────────────── */
class LatestArrivalsSection extends StatefulWidget {
  const LatestArrivalsSection({super.key});
  @override
  State<LatestArrivalsSection> createState() => _LatestArrivalsSectionState();
}

class _LatestArrivalsSectionState extends State<LatestArrivalsSection> {
  final _service = LatestArrivalServices();

  late final CartService _cart =
      CartService('', apiPrefix: ApiConfig.apiPrefix);
  late Future<List<LatestArrivalModels>> _future;

  final Map<String, Future<String?>> _imgCache = {};

  @override
  void initState() {
    super.initState();
    _future = _service.fetchLatestArrivals();
  }

  String _fmtKwacha(int n) {
    final s = n.toString();
    // Insert commas every three digits from the right: 1000 -> 1,000
    return s.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  int _fnv1a32(String input) {
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffset;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  Uint8List? _tryDecodeBase64(String v) {
    if (v.isEmpty) return null;
    try {
      var cleaned = v.trim().replaceAll(RegExp(r'\s+'), '');
      final commaIndex = cleaned.indexOf(',');
      if (cleaned.startsWith('data:image') && commaIndex != -1) {
        cleaned = cleaned.substring(commaIndex + 1);
      }
      final mod = cleaned.length % 4;
      if (mod != 0) cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
      final bytes = base64Decode(cleaned);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveImageString(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('data:image/')) return s;

    if (s.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance.refFromURL(s).getDownloadURL();
      } catch (_) {}
    }

    if (s.contains('/') && !s.contains(' ')) {
      try {
        return await FirebaseStorage.instance.ref(s).getDownloadURL();
      } catch (_) {}
    }

    if (s.contains('.') && !s.contains(' ')) {
      final guesses = <String>[
        'latest/$s',
        'latest_arrivals/$s',
        'uploads/$s',
        'products/$s',
      ];
      for (final path in guesses) {
        try {
          return await FirebaseStorage.instance.ref(path).getDownloadURL();
        } catch (_) {}
      }
    }

    return null;
  }

  Future<String?> _resolveImage(LatestArrivalModels it) async {
    final direct = await _resolveImageString(it.imageUrl);
    if (direct != null) return direct;

    Future<String?> fromDoc(String col, String docId) async {
      try {
        final doc =
            await FirebaseFirestore.instance.collection(col).doc(docId).get();
        if (!doc.exists) return null;
        final d = doc.data() ?? {};
        final candidate = (d['imageUrl'] ??
                d['image'] ??
                d['thumbnail'] ??
                d['storagePath'] ??
                d['gsUrl'] ??
                d['path'] ??
                '')
            .toString()
            .trim();
        return await _resolveImageString(candidate);
      } catch (_) {
        return null;
      }
    }

    Future<String?> fromNameQuery(String col) async {
      try {
        final q = await FirebaseFirestore.instance
            .collection(col)
            .where('name', isEqualTo: it.name.trim())
            .limit(1)
            .get();
        if (q.docs.isEmpty) return null;
        final d = q.docs.first.data();
        final candidate = (d['imageUrl'] ??
                d['image'] ??
                d['thumbnail'] ??
                d['storagePath'] ??
                d['gsUrl'] ??
                d['path'] ??
                '')
            .toString()
            .trim();
        return await _resolveImageString(candidate);
      } catch (_) {
        return null;
      }
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
    final d = await fromNameQuery('latest_arrivals');
    if (d != null) return d;

    return null;
  }

  Future<String?> _imgFuture(LatestArrivalModels it) {
    final key = it.id.isNotEmpty ? it.id : '${it.name}_${it.price}';
    return _imgCache.putIfAbsent(key, () => _resolveImage(it));
  }

  CartModel _makeCartModel(
    LatestArrivalModels it,
    String resolvedImageUrl, {
    required int qty,
  }) {
    final parsed = int.tryParse(it.id.trim());
    final itemId = parsed ?? _fnv1a32('latest:${it.id}:${it.name}');

    const merchantId = 'marketplace';
    const merchantName = 'Marketplace';
    const serviceType = 'marketplace';

    final userKey = FirebaseAuth.instance.currentUser?.uid ?? '';

    return CartModel(
      userId: userKey,
      item: itemId,
      quantity: qty,
      name: it.name,
      image: resolvedImageUrl,
      price: it.price.toDouble(),
      description: '',
      comment: null,
      merchantId: merchantId,
      merchantName: merchantName,
      serviceType: serviceType,
    );
  }

  Future<void> _addToCart(
    LatestArrivalModels it, {
    required int qty,
    required BuildContext sheetCtx, // ✅ toast overlays the sheet
  }) async {
    if (qty <= 0) return;

    // ✅ Require login before allowing add-to-cart from Latest Arrivals
    if (FirebaseAuth.instance.currentUser == null) {
      ToastHelper.showCustomToast(
        sheetCtx,
        'Please log in to add items from Latest Arrivals.',
        isSuccess: false,
        errorMessage: 'Not logged in',
      );
      return;
    }

    try {
      final img = (await _resolveImage(it)) ?? it.imageUrl;
      final cartItem = _makeCartModel(it, img, qty: qty);

      await _cart.addToCart(cartItem);

      if (!mounted) return;
      ToastHelper.showCustomToast(
        sheetCtx,
        '${it.name} added to cart successfully',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        sheetCtx,
        'Failed to add ${it.name} to cart,log in to add to cart',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _buyNow(
    LatestArrivalModels it, {
    required int qty,
    required BuildContext sheetCtx, // ✅ close only the sheet
  }) async {
    if (qty <= 0) return;

    // ✅ Require login before allowing Buy Now from Latest Arrivals
    if (FirebaseAuth.instance.currentUser == null) {
      ToastHelper.showCustomToast(
        sheetCtx,
        'Please log in to buy from Latest Arrivals.',
        isSuccess: false,
        errorMessage: 'Not logged in',
      );
      return;
    }

    final img = (await _resolveImage(it)) ?? it.imageUrl;
    final cartItem = _makeCartModel(it, img, qty: qty);

    // optional: keep offline-first truth
    try {
      await _cart.addToCart(cartItem);
    } catch (_) {}

    if (!mounted) return;

    // ✅ close ONLY the bottomsheet
    if (Navigator.of(sheetCtx).canPop()) {
      Navigator.of(sheetCtx).pop();
    }

    // ✅ then navigate
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutFromCartPage(items: [cartItem]),
      ),
    );
  }

  void _openDetails(LatestArrivalModels it) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      // ✅ IMPORTANT: use sheet context here (so toasts appear above the sheet)
      builder: (sheetCtx) => _LatestDetailsSheet(
        item: it,
        imageFuture: _imgFuture(it),
        fmtPrice: (n) => 'MWK ${_fmtKwacha(n)}',
        tryDecodeBase64: _tryDecodeBase64,
        onAddToCart: (qty) async =>
            _addToCart(it, qty: qty, sheetCtx: sheetCtx),
        onBuyNow: (qty) async => _buyNow(it, qty: qty, sheetCtx: sheetCtx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(5, 12, 5, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Latest Arrivals",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<LatestArrivalModels>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Could not load arrivals.\n${snap.error}',
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
                  child: Center(
                    child: Text(
                      'No items yet.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              final width = MediaQuery.of(context).size.width;
              final cols = width >= 1200
                  ? 4
                  : width >= 800
                      ? 3
                      : 2;
              final ratio = width >= 1200
                  ? 0.95
                  : width >= 800
                      ? 0.85
                      : 0.72;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: ratio,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return _ProductCardFromApi(
                    item: it,
                    priceText: 'MWK ${_fmtKwacha(it.price)}',
                    imageFuture: _imgFuture(it),
                    tryDecodeBase64: _tryDecodeBase64,
                    onTap: () => _openDetails(it),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductCardFromApi extends StatelessWidget {
  final LatestArrivalModels item;
  final String priceText;
  final Future<String?> imageFuture;
  final Uint8List? Function(String) tryDecodeBase64;
  final VoidCallback onTap;

  const _ProductCardFromApi({
    required this.item,
    required this.priceText,
    required this.imageFuture,
    required this.tryDecodeBase64,
    required this.onTap,
  });

  Widget _placeholder() => const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        elevation: 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder<String?>(
                future: imageFuture,
                builder: (context, snap) {
                  final v = (snap.data ?? item.imageUrl).trim();
                  if (v.isEmpty) return _placeholder();

                  if (v.startsWith('data:image/')) {
                    final bytes = tryDecodeBase64(v);
                    if (bytes == null) return _placeholder();
                    return Image.memory(bytes, fit: BoxFit.cover);
                  }

                  if (v.startsWith('http://') || v.startsWith('https://')) {
                    return Image.network(
                      v,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, prog) {
                        if (prog == null) return child;
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => _placeholder(),
                    );
                  }

                  return _placeholder();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
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

class _LatestDetailsSheet extends StatefulWidget {
  final LatestArrivalModels item;
  final Future<String?> imageFuture;
  final String Function(int) fmtPrice;
  final Uint8List? Function(String) tryDecodeBase64;
  final Future<void> Function(int qty) onAddToCart;
  final Future<void> Function(int qty) onBuyNow;

  const _LatestDetailsSheet({
    required this.item,
    required this.imageFuture,
    required this.fmtPrice,
    required this.tryDecodeBase64,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  @override
  State<_LatestDetailsSheet> createState() => _LatestDetailsSheetState();
}

class _LatestDetailsSheetState extends State<_LatestDetailsSheet> {
  int qty = 1;

  Widget _placeholder() => const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) {
    final it = widget.item;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min, // ✅ keeps it compact (not huge)
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String?>(
                  future: widget.imageFuture,
                  builder: (context, snap) {
                    final v = (snap.data ?? it.imageUrl).trim();
                    Widget img;

                    if (v.isEmpty) {
                      img = _placeholder();
                    } else if (v.startsWith('data:image/')) {
                      final bytes = widget.tryDecodeBase64(v);
                      img = bytes == null
                          ? _placeholder()
                          : Image.memory(bytes, fit: BoxFit.cover);
                    } else if (v.startsWith('http://') ||
                        v.startsWith('https://')) {
                      img = Image.network(
                        v,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      );
                    } else {
                      img = _placeholder();
                    }

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: img,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  it.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.fmtPrice(it.price),
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Quantity',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      onPressed: qty <= 1 ? null : () => setState(() => qty--),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$qty',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
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
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: const Text(
                          'Add to Cart',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandOrange,
                          side: const BorderSide(color: AppColors.brandOrange),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Buy Now',
                          style: TextStyle(fontWeight: FontWeight.w900),
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
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDEDED),
      child: const Center(
        child: Icon(Icons.image_not_supported_rounded, color: Colors.black38),
      ),
    );
  }
}

/// Generic section wrapper
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  final bool tight;
  final double gapAfterTitle;

  const _Section({
    required this.title,
    required this.child,
    this.action,
    this.tight = false,
    this.gapAfterTitle = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: tight ? 0 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, tight ? 0 : 10, 16, 0),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.title,
                  ),
                ),
                const Spacer(),
                if (action != null) action!,
              ],
            ),
          ),
          SizedBox(height: gapAfterTitle),
          child,
        ],
      ),
    );
  }
}

/// Minimal Utility placeholder
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

/* ───────────────────────────────────────────
   DIGITAL PRODUCT DETAIL / CHECKOUT PAGE
─────────────────────────────────────────── */
class DigitalProductDetailPage extends StatefulWidget {
  final DigitalProduct product;
  final String? initialEmail;
  final String? initialPhone;
  final String? initialName;

  const DigitalProductDetailPage({
    super.key,
    required this.product,
    this.initialEmail,
    this.initialPhone,
    this.initialName,
  });

  @override
  State<DigitalProductDetailPage> createState() =>
      _DigitalProductDetailPageState();
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
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
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

  /// Parse price string like "MWK 8,000" or "MWK 12000" to number.
  static double _parsePrice(String priceStr) {
    final digits = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(digits) ?? 0;
  }

  /// Normalize Malawi phone to E.164 (+265...) for Paychangu.
  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 && (digits.startsWith('0') || digits.startsWith('265'))) {
      final rest = digits.startsWith('265') ? digits.substring(3) : digits.substring(1);
      return '+265$rest';
    }
    return raw.trim().isEmpty ? '+265888000000' : (raw.startsWith('+') ? raw : '+$raw');
  }

  Future<void> _payNow() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      final parts = name.split(' ');
      final firstName = parts.isNotEmpty ? parts.first : 'Customer';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final amount = _parsePrice(widget.product.price);
      if (amount <= 0) {
        ToastHelper.showCustomToast(
          context,
          'Invalid price for ${widget.product.name}.',
          isSuccess: false,
          errorMessage: 'Invalid amount',
        );
        return;
      }

      try {
        await InternetAddress.lookup('api.paychangu.com');
      } on SocketException catch (_) {
        throw Exception(
            'Cannot connect to payment service. Please check your internet connection.');
      }

      final txRef = 'vero-digital-${DateTime.now().millisecondsSinceEpoch}';
      final description =
          'Digital: ${widget.product.name} • ${widget.product.subtitle}';

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
              'amount': amount.round().toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero 360 Payment',
                'description': description,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseJson =
            json.decode(response.body) as Map<String, dynamic>;
        final status =
            (responseJson['status'] ?? '').toString().toLowerCase();
        if (status == 'success') {
          final checkoutUrl =
              responseJson['data']['checkout_url'] as String;
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InAppPaymentPage(
                checkoutUrl: checkoutUrl,
                txRef: txRef,
                totalAmount: amount,
                rootContext: context,
                digitalProductName: widget.product.name,
              ),
            ),
          );
        } else {
          throw Exception(
              responseJson['message'] ?? 'Payment failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } on SocketException catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Network error. Please check your internet connection.',
        isSuccess: false,
        errorMessage: e.message,
      );
    } on TimeoutException {
      ToastHelper.showCustomToast(
        context,
        'Connection timeout. Please try again.',
        isSuccess: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Payment error: $e',
        isSuccess: false,
        errorMessage: 'Payment failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Scaffold(
      appBar: AppBar(
        title: Text('Buy ${p.name}'),
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.brandOrangeSoft),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.brandOrangePale,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.brandOrange),
                      ),
                      child: ClipOval(
                        child: p.logoAsset != null
                            ? Image.asset(
                                p.logoAsset!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  p.icon ?? Icons.shopping_bag,
                                  color: AppColors.title,
                                ),
                              )
                            : Icon(p.icon ?? Icons.shopping_bag,
                                size: 26, color: AppColors.title),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.body,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.price,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _LabeledField(
                      label: 'Full name',
                      controller: _nameCtrl,
                      keyboardType: TextInputType.name,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.length < 2) return 'Enter your name';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: 'Phone Number',
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (!_isValidMwLocalPhone(t)) {
                          return 'Enter 10 digits starting with 08 or 09';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: 'Email address',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Enter your email';
                        final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t);
                        if (!ok) return 'Enter a valid email';
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
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_outline_rounded),
                  label: Text(_submitting ? 'Processing...' : 'Pay Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'Secure checkout • Contact support for your code or instructions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.body,
                    fontWeight: FontWeight.w600,
                  ),
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
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.brandOrangeSoft),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.title,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: AppColors.brandOrange),
            ),
            errorBorder: border.copyWith(
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: border.copyWith(
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            fillColor: Colors.white,
            filled: true,
            hintText: label,
          ),
        ),
      ],
    );
  }
}
