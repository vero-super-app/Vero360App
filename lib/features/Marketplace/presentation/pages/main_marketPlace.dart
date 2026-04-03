// lib/Pages/marketPlace.dart
// ─────────────────────────────────────────────
// VERO360 MARKETPLACE  – 2025 Luxury Editorial Redesign
//   • Warm amber/cream luxury palette
//   • Glass-morphism cards with depth shadows
//   • Animated entrance + micro-interactions
//   • Hero image aspect-ratio cards
//   • Frosted search bar with live suggestion carousel
//   • All original logic 100% preserved
// ─────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as core;

import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/utils/toasthelper.dart';

import 'package:vero360_app/Home/Messages.dart';
import 'package:vero360_app/GernalServices/chat_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/serviceprovider_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/serviceprovider_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS — Warm Luxury Editorial
// ─────────────────────────────────────────────
const _kAmber       = Color(0xFFFF8A00);
const _kAmberDark   = Color(0xFFE07800);
const _kAmberLight  = Color(0xFFFFF0D9);
const _kAmberGlow   = Color(0x33FF8A00);
const _kCream       = Color(0xFFFAF7F2);
const _kCreamDark   = Color(0xFFF0EBE1);
const _kBlue        = Color(0xFF1E88E5);
const _kBlueBg      = Color(0xFFE8F2FD);
const _kInk         = Color(0xFF1A1109);
const _kInkMid      = Color(0xFF4A3F32);
const _kInkLight    = Color(0xFF8C7B6B);
const _kCard        = Color(0xFFFFFFFF);
const _kShadow      = Color(0x1AFF8A00);
const _kShadowDeep  = Color(0x26000000);
const _kSuccess     = Color(0xFF2E7D32);
const _kSuccessBg   = Color(0xFFE8F5E9);

// Category icon map
const Map<String, IconData> _kCategoryIcons = {
  'food':        Icons.restaurant_rounded,
  'drinks':      Icons.local_bar_rounded,
  'electronics': Icons.devices_rounded,
  'clothes':     Icons.checkroom_rounded,
  'shoes':       Icons.hiking_rounded,
  'other':       Icons.category_rounded,
};

const Map<String, Color> _kCategoryColors = {
  'food':        Color(0xFFFF7043),
  'drinks':      Color(0xFF7C4DFF),
  'electronics': Color(0xFF1E88E5),
  'clothes':     Color(0xFFE91E63),
  'shoes':       Color(0xFF00897B),
  'other':       Color(0xFF8D6E63),
};

// ─────────────────────────────────────────────
// GRID LAYOUT (unchanged logic)
// ─────────────────────────────────────────────
({
  int crossAxisCount,
  double childAspectRatio,
  double gridSpacing,
  double gridPadH,
}) _marketplaceSliverGridLayout({
  required bool comfortable,
  required double width,
}) {
  final w = width.isFinite && width > 0 ? width : 360.0;
  final tight = w < 400;
  final gridSpacing = tight ? 10.0 : (w < 720 ? 12.0 : 14.0);
  final gridPadH = gridSpacing;

  if (comfortable) {
    final cross = w >= 1000 ? 3 : (w >= 560 ? 2 : 1);
    final aspect = cross == 1 ? 1.30 : cross == 2 ? (w >= 840 ? 1.00 : 1.08) : 0.94;
    return (crossAxisCount: cross, childAspectRatio: aspect, gridSpacing: gridSpacing, gridPadH: gridPadH);
  }

  var cross = w >= 1280 ? 6 : w >= 1100 ? 5 : w >= 840 ? 4 : w >= 600 ? 3 : 2;
  double innerFor(int c) => w - gridPadH * 2 - gridSpacing * (c - 1);
  var cellW = innerFor(cross) / cross;
  const minCell = 118.0;
  while (cross > 1 && cellW < minCell) { cross -= 1; cellW = innerFor(cross) / cross; }
  final aspect = switch (cross) {
    1 => 0.88, 2 => cellW < 150 ? 0.62 : (cellW < 172 ? 0.68 : 0.72),
    3 => 0.70, 4 => 0.66, 5 => 0.64, _ => 0.60,
  };
  return (crossAxisCount: cross, childAspectRatio: aspect, gridSpacing: gridSpacing, gridPadH: gridPadH);
}

// ─────────────────────────────────────────────
// SHIMMER (beautiful amber shimmer)
// ─────────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _anim = Tween<double>(begin: -2.0, end: 3.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Color(0xFFEDE8E0), Color(0xFFFFF8F0),
            Color(0xFFFFEDD5), Color(0xFFFFF8F0), Color(0xFFEDE8E0),
          ],
          stops: [
            (_anim.value - 1.0).clamp(0.0, 1.0), (_anim.value - 0.3).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),           (_anim.value + 0.3).clamp(0.0, 1.0),
            (_anim.value + 1.0).clamp(0.0, 1.0),
          ],
        ).createShader(bounds),
        child: child!,
      ),
      child: widget.child,
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height, this.radius = 10});
  final double? width;
  final double height;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    width: width, height: height,
    decoration: BoxDecoration(color: const Color(0xFFE8E0D4), borderRadius: BorderRadius.circular(radius)),
  );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  @override
  Widget build(BuildContext context) => _Shimmer(
    child: Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: _kShadow, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 6, child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFE8E0D4),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        )),
        Expanded(flex: 5, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _SkeletonBox(width: double.infinity, height: 14),
            const SizedBox(height: 6),
            const _SkeletonBox(width: 90, height: 12),
            const SizedBox(height: 6),
            const _SkeletonBox(width: 70, height: 12),
            const Spacer(),
            Row(children: const [
              Expanded(child: _SkeletonBox(width: double.infinity, height: 36, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: _SkeletonBox(width: double.infinity, height: 36, radius: 12)),
            ]),
          ]),
        )),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────
// SCROLL BEHAVIOR
// ─────────────────────────────────────────────
class _NoBarsScrollBehavior extends MaterialScrollBehavior {
  const _NoBarsScrollBehavior();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ─────────────────────────────────────────────
// LOCAL MODEL (unchanged)
// ─────────────────────────────────────────────
class MarketplaceDetailModel {
  final String id;
  final int? sqlItemId;
  final String name;
  final String category;
  final double price;
  final String image;
  final Uint8List? imageBytes;
  final String? description;
  final String? location;
  final bool isActive;
  final DateTime? createdAt;
  final String? merchantId;
  final String? merchantName;
  final String? serviceType;
  final List<String> gallery;
  final String? sellerBusinessName;
  final String? sellerOpeningHours;
  final String? sellerStatus;
  final String? sellerBusinessDescription;
  final double? sellerRating;
  final String? sellerLogoUrl;
  final String? serviceProviderId;
  final String? sellerUserId;

  MarketplaceDetailModel({
    required this.id, required this.name, required this.category,
    required this.price, required this.image,
    this.sqlItemId, this.imageBytes, this.description, this.location,
    this.isActive = true, this.createdAt, this.gallery = const [],
    this.sellerBusinessName, this.sellerOpeningHours, this.sellerStatus,
    this.sellerBusinessDescription, this.sellerRating, this.sellerLogoUrl,
    this.serviceProviderId, this.sellerUserId, this.merchantId,
    this.merchantName, this.serviceType = 'marketplace',
  });

  bool get hasValidSqlItemId => sqlItemId != null && sqlItemId! > 0;
  bool get hasValidMerchantInfo =>
      merchantId != null && merchantId!.isNotEmpty && merchantId != 'unknown' &&
      merchantName != null && merchantName!.isNotEmpty && merchantName != 'Unknown Merchant';

  factory MarketplaceDetailModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawImage = (data['image'] ?? data['imageUrl'] ?? data['photo'] ?? data['picture'] ?? '').toString().trim();
    bool looksLikeBase64(String s) {
      final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
      if (x.length < 150) return false;
      return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
    }
    Uint8List? bytes;
    if (rawImage.isNotEmpty && looksLikeBase64(rawImage)) {
      try { final bp = rawImage.contains(',') ? rawImage.split(',').last : rawImage; bytes = base64Decode(bp); } catch (_) { bytes = null; }
    }
    DateTime? created;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) created = createdRaw.toDate();
    else if (createdRaw is DateTime) created = createdRaw;
    double price = 0;
    final p = data['price'];
    if (p is num) price = p.toDouble();
    else if (p != null) price = double.tryParse(p.toString()) ?? 0;
    int? parseInt(dynamic v) { if (v == null) return null; if (v is num) return v.toInt(); return int.tryParse(v.toString().replaceAll(RegExp(r'[^\d]'), '')); }
    final rawSql = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'] ?? data['id'];
    final sqlId = parseInt(rawSql);
    final cat = (data['category'] ?? '').toString().toLowerCase();
    List<String> parseGalleryField(dynamic field) {
      if (field is List) return field.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      if (field is String) { final raw = field.trim(); if (raw.isEmpty) return const []; try { final decoded = jsonDecode(raw); if (decoded is List) return decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList(); } catch (_) {} return raw.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList(); }
      return const [];
    }
    final fromGallery = parseGalleryField(data['gallery']);
    final fromGalleryUrls = parseGalleryField(data['galleryUrls']);
    final seen = <String>{}; final gallery = <String>[];
    for (final s in [...fromGallery, ...fromGalleryUrls]) { final t = s.trim(); if (t.isEmpty || seen.contains(t)) continue; seen.add(t); gallery.add(t); }
    double? sellerRating;
    final r = data['sellerRating'];
    if (r is num) sellerRating = r.toDouble();
    else if (r != null) sellerRating = double.tryParse(r.toString());
    return MarketplaceDetailModel(
      id: doc.id, name: (data['name'] ?? '').toString(), category: cat, price: price,
      image: rawImage, imageBytes: bytes, description: data['description']?.toString(),
      location: data['location']?.toString(), isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      createdAt: created, sqlItemId: sqlId, gallery: gallery,
      sellerBusinessName: data['sellerBusinessName']?.toString(), sellerOpeningHours: data['sellerOpeningHours']?.toString(),
      sellerStatus: data['sellerStatus']?.toString(), sellerBusinessDescription: data['sellerBusinessDescription']?.toString(),
      sellerRating: sellerRating, sellerLogoUrl: data['sellerLogoUrl']?.toString(),
      serviceProviderId: data['serviceProviderId']?.toString(), sellerUserId: data['sellerUserId']?.toString(),
      merchantId: data['merchantId']?.toString(), merchantName: data['merchantName']?.toString(),
      serviceType: data['serviceType']?.toString() ?? 'marketplace',
    );
  }
}

// ─────────────────────────────────────────────
// SELLER INFO (unchanged)
// ─────────────────────────────────────────────
class _SellerInfo {
  String? businessName, openingHours, status, description, logoUrl;
  double? rating;
  String? serviceProviderId;
  _SellerInfo({this.businessName, this.openingHours, this.status, this.description, this.rating, this.logoUrl, this.serviceProviderId});
}

Future<_SellerInfo> _loadSellerForItem(MarketplaceDetailModel i) async {
  final info = _SellerInfo(businessName: i.sellerBusinessName, openingHours: i.sellerOpeningHours, status: i.sellerStatus, description: i.sellerBusinessDescription, rating: i.sellerRating, logoUrl: i.sellerLogoUrl, serviceProviderId: i.serviceProviderId);
  final missing = info.businessName == null || info.openingHours == null || info.status == null || info.description == null || info.rating == null || info.logoUrl == null;
  final spId = info.serviceProviderId?.trim();
  if (missing && spId != null && spId.isNotEmpty) {
    try {
      final ServiceProvider? sp = await ServiceProviderServicess.fetchByNumber(spId);
      if (sp != null) {
        info.businessName ??= sp.businessName; info.openingHours ??= sp.openingHours; info.status ??= sp.status; info.description ??= sp.businessDescription; info.logoUrl ??= sp.logoUrl;
        final r = sp.rating; if (info.rating == null && r != null) { info.rating = (r is num) ? r.toDouble() : double.tryParse('$r'); }
      }
    } catch (_) {}
  }
  return info;
}

// ─────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────
String? _closingFromHours(String? openingHours) {
  if (openingHours == null || openingHours.trim().isEmpty) return null;
  final parts = openingHours.replaceAll('–', '-').split('-');
  return parts.length == 2 ? parts[1].trim() : null;
}

String _fmtRating(double? r) {
  if (r == null) return '—';
  final whole = r.truncateToDouble();
  return r == whole ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}

// ─────────────────────────────────────────────
// BEAUTIFUL RATING STARS
// ─────────────────────────────────────────────
Widget _ratingStars(double? rating) {
  final rr = ((rating ?? 0).clamp(0, 5)).toDouble();
  final filled = rr.floor();
  final hasHalf = (rr - filled) >= 0.5 && filled < 5;
  final empty = 5 - filled - (hasHalf ? 1 : 0);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    for (int i = 0; i < filled; i++) const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
    if (hasHalf) const Icon(Icons.star_half_rounded, size: 14, color: Color(0xFFFFB300)),
    for (int i = 0; i < empty; i++) const Icon(Icons.star_outline_rounded, size: 14, color: Color(0xFFFFB300)),
    const SizedBox(width: 4),
    Text(_fmtRating(rr), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: _kInkMid)),
  ]);
}

Widget _infoRow(String label, String? value, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[Icon(icon, size: 15, color: _kAmber), const SizedBox(width: 8)],
      SizedBox(width: 110, child: Text(label, style: const TextStyle(color: _kInkLight, fontSize: 12))),
      const SizedBox(width: 6),
      Expanded(child: Text((value ?? '').isNotEmpty ? value! : '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kInk))),
    ]),
  );
}

Widget _statusChip(String? status) {
  final s = (status ?? '').toLowerCase().trim();
  Color bg = _kCreamDark; Color fg = _kInkLight;
  if (s == 'open') { bg = _kSuccessBg; fg = _kSuccess; }
  else if (s == 'closed') { bg = const Color(0xFFFFEBEE); fg = const Color(0xFFD32F2F); }
  else if (s == 'busy') { bg = const Color(0xFFFFF8E1); fg = const Color(0xFFE65100); }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text((status ?? '—').toUpperCase(), style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 0.8)),
  );
}

// ─────────────────────────────────────────────
// MARKET PAGE
// ─────────────────────────────────────────────
class MarketPage extends StatefulWidget {
  final CartService cartService;
  const MarketPage({required this.cartService, super.key});
  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> with TickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _askQuestionCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollCtrl = ScrollController();

  late final NumberFormat _mwkFmt = NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
  String _mwk(num v) => _mwkFmt.format(v);

  static const List<String> _kCategories = ['food', 'drinks', 'electronics', 'clothes', 'shoes', 'other'];
  String? _selectedCategory;

  Timer? _debounce;
  Timer? _suggestionTimer;
  String _lastQuery = '';
  bool _loading = false;
  bool _photoMode = false;
  bool _comfortableView = false;
  bool _forYouMode = true;
  int _suggestionIndex = 0;
  static const List<String> _searchSuggestions = [
    'iphone 13 near me', 'nike shoes size 42', 'ps5 controller',
    'laptop under 500k', 'kitchen blender', 'office chair',
  ];

  List<String> _activeSearchSuggestions = const [];
  bool _aiSearchMode = false;
  bool _veroAiLoading = false;
  late Future<List<MarketplaceDetailModel>> _future;

  Set<String> _followedMerchantIdsCache = {};
  DateTime _followedMerchantIdsFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kFollowedMerchantsCacheTtl = Duration(minutes: 2);

  String _aiSummary = '';
  final Map<String, Future<String?>> _dlUrlCache = {};
  static const String _prefsPersonalizationPrefix = 'marketplace_personalization_v1_';

  // Animation controllers
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _fabCtrl;
  late Animation<double> _fabAnim;
  bool _showHeaderBlur = false;

  List<String> _keywordsFromText(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
    if (clean.isEmpty) return const [];
    const stop = {'the','and','for','with','this','that','from','you','your','item','items','new','used','very','good','best','all','are','was','were','has','have','had','not','but','can','will','its','our','their'};
    return clean.split(RegExp(r'\s+')).where((w) => w.length >= 3 && !stop.contains(w)).toList();
  }

  Future<String> _personalizationStorageKey() async {
    final uid = await _getCurrentUserId();
    final safe = (uid == null || uid.trim().isEmpty) ? 'guest' : uid.trim();
    return '$_prefsPersonalizationPrefix$safe';
  }

  Future<Map<String, dynamic>> _readPersonalizationProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final k = await _personalizationStorageKey();
      final raw = prefs.getString(k);
      if (raw == null || raw.isEmpty) return {'cat': <String, num>{}, 'merchant': <String, num>{}, 'kw': <String, num>{}, 'last': <String, int>{}};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return {'cat': Map<String, num>.from(decoded['cat'] ?? const {}), 'merchant': Map<String, num>.from(decoded['merchant'] ?? const {}), 'kw': Map<String, num>.from(decoded['kw'] ?? const {}), 'last': Map<String, int>.from(decoded['last'] ?? const {})};
    } catch (_) {}
    return {'cat': <String, num>{}, 'merchant': <String, num>{}, 'kw': <String, num>{}, 'last': <String, int>{}};
  }

  Future<void> _writePersonalizationProfile(Map<String, dynamic> profile) async {
    try { final prefs = await SharedPreferences.getInstance(); final k = await _personalizationStorageKey(); await prefs.setString(k, jsonEncode(profile)); } catch (_) {}
  }

  Future<void> _trackInteraction(MarketplaceDetailModel item, {double weight = 1.0}) async {
    final profile = await _readPersonalizationProfile();
    final cat = Map<String, num>.from(profile['cat'] ?? const {});
    final merchant = Map<String, num>.from(profile['merchant'] ?? const {});
    final kw = Map<String, num>.from(profile['kw'] ?? const {});
    final last = Map<String, int>.from(profile['last'] ?? const {});
    final c = item.category.trim().toLowerCase();
    if (c.isNotEmpty) cat[c] = (cat[c] ?? 0) + weight;
    final m = (item.merchantName ?? item.sellerBusinessName ?? '').trim().toLowerCase();
    if (m.isNotEmpty) merchant[m] = (merchant[m] ?? 0) + (weight * 0.8);
    final keywords = _keywordsFromText('${item.name} ${item.description ?? ''} ${item.location ?? ''}');
    for (final w in keywords.take(8)) kw[w] = (kw[w] ?? 0) + (weight * 0.45);
    last[item.id] = DateTime.now().millisecondsSinceEpoch;
    if (last.length > 120) { final sorted = last.entries.toList()..sort((a, b) => a.value.compareTo(b.value)); for (final e in sorted.take(last.length - 120)) last.remove(e.key); }
    profile['cat'] = cat; profile['merchant'] = merchant; profile['kw'] = kw; profile['last'] = last;
    await _writePersonalizationProfile(profile);
  }

  Future<void> _trackCategoryInterest(String? cat) async {
    final c = (cat ?? '').trim().toLowerCase();
    if (c.isEmpty) return;
    final profile = await _readPersonalizationProfile();
    final catMap = Map<String, num>.from(profile['cat'] ?? const {});
    catMap[c] = (catMap[c] ?? 0) + 1.4;
    profile['cat'] = catMap;
    await _writePersonalizationProfile(profile);
  }

  Future<void> _trackSearchInterest(String raw) async {
    final words = _keywordsFromText(raw);
    if (words.isEmpty) return;
    final profile = await _readPersonalizationProfile();
    final kw = Map<String, num>.from(profile['kw'] ?? const {});
    for (final w in words.take(8)) kw[w] = (kw[w] ?? 0) + 0.35;
    profile['kw'] = kw;
    await _writePersonalizationProfile(profile);
  }

  Future<Set<String>> _fetchFollowedMerchantIds() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return {};
    try {
      final qs = await _firestore.collectionGroup('followers').where(FieldPath.documentId, isEqualTo: uid).limit(300).get();
      final out = <String>{};
      for (final doc in qs.docs) { final merchantRef = doc.reference.parent.parent; if (merchantRef == null) continue; final id = merchantRef.id.trim(); if (id.isNotEmpty) out.add(id); }
      return out;
    } catch (e) { if (kDebugMode) debugPrint('followed merchants: $e'); return {}; }
  }

  Future<Set<String>> _getFollowedMerchantIdsCached() async {
    final now = DateTime.now();
    if (_followedMerchantIdsFetchedAt.millisecondsSinceEpoch > 0 && now.difference(_followedMerchantIdsFetchedAt) < _kFollowedMerchantsCacheTtl) return _followedMerchantIdsCache;
    final fresh = await _fetchFollowedMerchantIds();
    _followedMerchantIdsCache = fresh; _followedMerchantIdsFetchedAt = now;
    return fresh;
  }

  Future<void> _refreshSearchSuggestionsFromProfile() async {
    try {
      final profile = await _readPersonalizationProfile();
      final kwMap = Map<String, num>.from(profile['kw'] ?? const {});
      final catMap = Map<String, num>.from(profile['cat'] ?? const {});
      final merchantMap = Map<String, num>.from(profile['merchant'] ?? const {});
      final suggestions = <String>[];
      void addSorted(Map<String, num> map, int take, String Function(String k) toText) {
        final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        for (final e in entries.take(take)) { final text = toText(e.key); if (text.isNotEmpty) suggestions.add(text); }
      }
      addSorted(kwMap, 4, (k) => k); addSorted(catMap, 2, (k) => '$k near me'); addSorted(merchantMap, 2, (k) => k);
      final seen = <String>{}; final out = <String>[];
      for (final s in suggestions) { final t = s.trim(); if (t.isEmpty || seen.contains(t)) continue; seen.add(t); out.add(t); }
      if (out.isEmpty) out.addAll(_searchSuggestions);
      final finalOut = out.take(6).toList();
      if (!mounted) return;
      setState(() { _activeSearchSuggestions = finalOut; _suggestionIndex = 0; });
    } catch (_) {}
  }

  Future<List<MarketplaceDetailModel>> _rankByPersonalization(List<MarketplaceDetailModel> items) async {
    if (items.length < 2) return items;
    final profile = await _readPersonalizationProfile();
    final followedMerchants = await _getFollowedMerchantIdsCached();
    final cat = Map<String, num>.from(profile['cat'] ?? const {});
    final merchant = Map<String, num>.from(profile['merchant'] ?? const {});
    final kw = Map<String, num>.from(profile['kw'] ?? const {});
    final last = Map<String, int>.from(profile['last'] ?? const {});
    bool _itemIsFromFollowedSeller(MarketplaceDetailModel i) {
      if (followedMerchants.isEmpty) return false;
      final mid = (i.merchantId ?? '').trim();
      if (mid.isNotEmpty && followedMerchants.contains(mid)) return true;
      final sid = (i.sellerUserId ?? '').trim();
      return sid.isNotEmpty && followedMerchants.contains(sid);
    }
    double score(MarketplaceDetailModel i) {
      var s = 0.0;
      final c = i.category.trim().toLowerCase();
      if (c.isNotEmpty) s += (cat[c] ?? 0).toDouble() * 1.3;
      final m = (i.merchantName ?? i.sellerBusinessName ?? '').trim().toLowerCase();
      if (m.isNotEmpty) s += (merchant[m] ?? 0).toDouble() * 1.1;
      final words = _keywordsFromText('${i.name} ${i.description ?? ''} ${i.location ?? ''}');
      for (final w in words.take(10)) s += (kw[w] ?? 0).toDouble() * 0.45;
      final t = last[i.id];
      if (t != null) { final days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(t)).inHours / 24.0; s += (days <= 7 ? 2.2 : 1.2 / (1 + days / 7)); }
      if (_itemIsFromFollowedSeller(i)) s += 22.0;
      return s;
    }
    final ranked = List<MarketplaceDetailModel>.from(items);
    ranked.sort((a, b) { final sb = score(b); final sa = score(a); final byScore = sb.compareTo(sa); if (byScore != 0) return byScore; final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0); final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0); return db.compareTo(da); });
    return ranked;
  }

  void _setSuggestionsFromItems(List<MarketplaceDetailModel> items) {
    if (!mounted) return; if (items.isEmpty) return;
    final seen = <String>{}; final out = <String>[];
    for (final it in items) { final n = it.name.trim(); if (n.isEmpty) continue; final k = n.toLowerCase(); if (seen.contains(k)) continue; seen.add(k); out.add(n); if (out.length >= 6) break; }
    if (out.isEmpty) return;
    setState(() { _activeSearchSuggestions = out; _suggestionIndex = 0; });
  }

  Future<List<MarketplaceDetailModel>> _sortByNewest(List<MarketplaceDetailModel> items) async {
    final copy = List<MarketplaceDetailModel>.from(items);
    copy.sort((a, b) { final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0); final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0); return db.compareTo(da); });
    return copy;
  }

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    _searchCtrl.addListener(_onSearchChanged);

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _fabCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fabAnim = CurvedAnimation(parent: _fabCtrl, curve: Curves.elasticOut);
    _fabCtrl.forward();

    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 20;
      if (show != _showHeaderBlur) setState(() => _showHeaderBlur = show);
    });

    _startSuggestionTimer();
    _refreshSearchSuggestionsFromProfile();
  }

  @override
  void dispose() {
    _debounce?.cancel(); _suggestionTimer?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose(); _askQuestionCtrl.dispose();
    _fadeCtrl.dispose(); _fabCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── IMAGE HELPERS (unchanged) ───
  bool _isHttp(String s) { final l = s.toLowerCase(); return l.startsWith('http://') || l.startsWith('https://'); }
  bool _isGs(String s) => s.startsWith('gs://');
  bool _isRelativePath(String s) => s.isNotEmpty && !s.contains('://') && !_looksLikeBase64(s);
  bool _looksLikeBase64(String s) { final x = s.contains(',') ? s.split(',').last.trim() : s.trim(); if (x.isEmpty) return false; return x.length >= 40 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x); }
  Future<String> _backendUrlForPath(String path) async { final base = await ApiConfig.readBase(); final baseNorm = base.endsWith('/') ? base : '$base/'; final p = path.startsWith('/') ? path.substring(1) : path; return '$baseNorm$p'; }

  Future<String?> _toDownloadUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (_isHttp(s)) return s;
    if (s.startsWith('/')) { try { final url = await _backendUrlForPath(s); if (url.isNotEmpty) return url; } catch (_) {} return null; }
    if (_dlUrlCache.containsKey(s)) { try { return await _dlUrlCache[s]!; } catch (_) { _dlUrlCache.remove(s); } }
    Future<String?> fut() async {
      try { if (_isGs(s)) return await FirebaseStorage.instance.refFromURL(s).getDownloadURL(); return await FirebaseStorage.instance.ref(s).getDownloadURL(); }
      catch (_) { if (_isRelativePath(s)) { try { return await _backendUrlForPath(s); } catch (_) {} } return null; }
    }
    _dlUrlCache[s] = fut();
    return _dlUrlCache[s]!;
  }

  Widget _imageFromAnySource(String raw, {BoxFit fit = BoxFit.cover, double? width, double? height, BorderRadius? radius}) {
    final s = raw.trim();
    Widget wrap(Widget child) { if (radius == null) return child; return ClipRRect(borderRadius: radius, child: child); }
    if (s.isEmpty) return wrap(Container(width: width, height: height, color: _kCreamDark, alignment: Alignment.center, child: const Icon(Icons.image_not_supported_rounded, color: _kInkLight)));
    if (_looksLikeBase64(s)) { try { final base64Part = s.contains(',') ? s.split(',').last : s; final bytes = base64Decode(base64Part); return wrap(Image.memory(bytes, fit: fit, width: width, height: height)); } catch (_) {} }
    if (_isHttp(s)) return wrap(ResilientCachedNetworkImage(url: s, fit: fit, width: width, height: height));
    return FutureBuilder<String?>(
      future: _toDownloadUrl(s),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) return wrap(_Shimmer(child: Container(width: width, height: height, color: _kCreamDark)));
        return wrap(ResilientCachedNetworkImage(url: url, fit: fit, width: width, height: height));
      },
    );
  }

  Widget _circleAvatarFromAnySource(String? raw, {double radius = 18}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return CircleAvatar(radius: radius, backgroundColor: _kAmberLight, child: Icon(Icons.storefront_rounded, color: _kAmber, size: radius * 0.85));
    if (_looksLikeBase64(s)) { try { final bp = s.contains(',') ? s.split(',').last : s; final bytes = base64Decode(bp); return CircleAvatar(radius: radius, backgroundImage: MemoryImage(bytes)); } catch (_) {} }
    if (_isHttp(s)) return CircleAvatar(radius: radius, backgroundImage: NetworkImage(s));
    return FutureBuilder<String?>(future: _toDownloadUrl(s), builder: (_, snap) {
      final url = snap.data;
      if (url == null || url.isEmpty) return CircleAvatar(radius: radius, backgroundColor: _kAmberLight, child: Icon(Icons.storefront_rounded, color: _kAmber, size: radius * 0.85));
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
    });
  }

  void _startSuggestionTimer() {
    _suggestionTimer?.cancel();
    _suggestionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_aiSearchMode) return;
      if (_searchCtrl.text.trim().isNotEmpty) return;
      final suggestions = _activeSearchSuggestions;
      if (suggestions.length <= 1) return;
      final current = _suggestionIndex % suggestions.length;
      int next;
      if (suggestions.length == 2) { next = 1 - current; }
      else { final rng = Random(); next = current; while (next == current) next = rng.nextInt(suggestions.length); }
      setState(() => _suggestionIndex = next);
    });
  }

  void _stopSuggestionTimer() { _suggestionTimer?.cancel(); _suggestionTimer = null; }

  Future<String?> _getCurrentUserId() async {
    try { final User? user = FirebaseAuth.instance.currentUser; if (user != null) return user.uid; final SharedPreferences prefs = await SharedPreferences.getInstance(); return prefs.getString('uid'); } catch (_) { return null; }
  }

  Future<String?> _getAuthToken() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('token') ?? prefs.getString('jwt_token');
      if (token != null && token.isNotEmpty) return token;
      final User? firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) { final String? ft = await firebaseUser.getIdToken(); if (ft != null && ft.isNotEmpty) { await prefs.setString('firebase_token', ft); return ft; } }
      return prefs.getString('firebase_token');
    } catch (_) { return null; }
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '${weeks}w ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  int _stablePositiveIdFromString(String s) {
    int hash = 0;
    for (final code in s.codeUnits) hash = (hash * 31 + code) & 0x7fffffff;
    if (hash == 0) hash = 1;
    return hash;
  }

  Future<List<MarketplaceDetailModel>> _loadAll({String? category}) async {
    setState(() { _loading = true; _photoMode = false; _selectedCategory = category; });
    try {
      QuerySnapshot? snapshot;
      try {
        snapshot = await _firestore.collection('marketplace_items').orderBy('createdAt', descending: true).get(const GetOptions(source: Source.cache));
        if (snapshot.docs.isNotEmpty) {
          final all = snapshot.docs.map((doc) => MarketplaceDetailModel.fromFirestore(doc)).where((item) => item.isActive).toList();
          if (category == null || category.isEmpty) { final result = _forYouMode ? await _rankByPersonalization(all) : await _sortByNewest(all); _setSuggestionsFromItems(result); return result; }
          final c = category.toLowerCase();
          final filtered = all.where((item) => item.category.toLowerCase() == c).toList();
          final result = _forYouMode ? await _rankByPersonalization(filtered) : await _sortByNewest(filtered);
          _setSuggestionsFromItems(result); return result;
        }
      } catch (_) {}
      try {
        snapshot = await _firestore.collection('marketplace_items').orderBy('createdAt', descending: true).get(const GetOptions(source: Source.server));
        final all = snapshot.docs.map((doc) => MarketplaceDetailModel.fromFirestore(doc)).where((item) => item.isActive).toList();
        if (category == null || category.isEmpty) { final result = _forYouMode ? await _rankByPersonalization(all) : await _sortByNewest(all); _setSuggestionsFromItems(result); return result; }
        final c = category.toLowerCase();
        final filtered = all.where((item) => item.category.toLowerCase() == c).toList();
        final result = _forYouMode ? await _rankByPersonalization(filtered) : await _sortByNewest(filtered);
        _setSuggestionsFromItems(result); return result;
      } catch (serverError) {
        final err = serverError.toString().toLowerCase();
        if ((err.contains('unavailable') || err.contains('network') || err.contains('offline')) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('You are offline. Showing cached items.'), backgroundColor: _kAmber, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
        }
        return [];
      }
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<List<MarketplaceDetailModel>> _searchByName(String raw) async {
    final q = raw.trim();
    unawaited(_trackSearchInterest(q));
    if (q.isEmpty || q.length < 2) { _aiSummary = ''; return _loadAll(category: _selectedCategory); }
    setState(() { _loading = true; _photoMode = false; });
    try {
      final all = await _loadAll(category: _selectedCategory);
      final lower = q.toLowerCase();
      final words = lower.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
      List<MarketplaceDetailModel> matches;
      if (_aiSearchMode && words.length > 1) {
        matches = all.where((item) { final searchable = '${item.name} ${item.description ?? ''} ${item.category} ${item.location ?? ''}'.toLowerCase(); return words.every((w) => searchable.contains(w)); }).toList();
      } else {
        matches = all.where((item) { final searchable = '${item.name} ${item.description ?? ''} ${item.category} ${item.location ?? ''}'.toLowerCase(); return searchable.contains(lower); }).toList();
      }
      if (_aiSearchMode && matches.isNotEmpty) _aiSummary = _buildAiSummary(q, matches);
      else _aiSummary = '';
      final result = _forYouMode ? await _rankByPersonalization(matches) : await _sortByNewest(matches);
      _setSuggestionsFromItems(result); return result;
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String _buildAiSummary(String query, List<MarketplaceDetailModel> items) {
    final catCounts = <String, int>{};
    for (final i in items) { final c = i.category.isEmpty ? 'other' : i.category; catCounts[c] = (catCounts[c] ?? 0) + 1; }
    final topCats = catCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final catsText = topCats.take(3).map((e) => _titleCase(e.key)).join(', ');
    final priceMin = items.map((i) => i.price).reduce((a, b) => a < b ? a : b);
    final priceMax = items.map((i) => i.price).reduce((a, b) => a > b ? a : b);
    return 'Found ${items.length} results for "$query" across ${topCats.length} categories${topCats.isNotEmpty ? ' ($catsText)' : ''}. Prices: MWK ${priceMin.toStringAsFixed(0)} – MWK ${priceMax.toStringAsFixed(0)}.';
  }

  String _getAiHighlight(MarketplaceDetailModel item) {
    final sb = StringBuffer();
    final rating = item.sellerRating ?? 0;
    if (rating >= 4.5) sb.write('Top-rated seller');
    else if (rating >= 4) sb.write('Reliable seller');
    if (sb.isNotEmpty && item.price > 0) sb.write(' · ');
    sb.write(_mwk(item.price));
    if ((item.description ?? '').toLowerCase().contains('new') || (item.description ?? '').toLowerCase().contains('brand')) { if (sb.isNotEmpty) sb.write(' · '); sb.write('Like new'); }
    return sb.toString().trim().isEmpty ? _mwk(item.price) : sb.toString();
  }

  core.MarketplaceDetailModel _toCoreDetailModel(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId ? item.sqlItemId! : _stablePositiveIdFromString(item.id);
    return core.MarketplaceDetailModel(id: id, name: item.name, category: item.category, price: item.price, image: item.image, description: item.description ?? '', location: item.location ?? '', comment: null, gallery: item.gallery, videos: const [], sellerBusinessName: item.sellerBusinessName, sellerOpeningHours: item.sellerOpeningHours, sellerStatus: item.sellerStatus, sellerBusinessDescription: item.sellerBusinessDescription, sellerRating: item.sellerRating, sellerLogoUrl: item.sellerLogoUrl, serviceProviderId: item.serviceProviderId, sellerUserId: item.sellerUserId, merchantId: item.merchantId, merchantName: item.merchantName, serviceType: item.serviceType ?? 'marketplace', createdAt: item.createdAt);
  }

  void _openDetailsPage(MarketplaceDetailModel item) {
    unawaited(_trackInteraction(item, weight: 1.2));
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(item: _toCoreDetailModel(item), cartService: widget.cartService)));
  }

  MarketplaceDetailModel _fromCoreMarketplace(core.MarketplaceDetailModel c) {
    return MarketplaceDetailModel(id: c.id.toString(), sqlItemId: c.id, name: c.name, category: (c.category ?? '').toLowerCase(), price: c.price, image: c.image, imageBytes: null, description: c.description.isEmpty ? null : c.description, location: c.location.isEmpty ? null : c.location, isActive: true, createdAt: null, gallery: c.gallery, sellerBusinessName: c.sellerBusinessName, sellerOpeningHours: c.sellerOpeningHours, sellerStatus: c.sellerStatus, sellerBusinessDescription: c.sellerBusinessDescription, sellerRating: c.sellerRating, sellerLogoUrl: c.sellerLogoUrl, serviceProviderId: c.serviceProviderId, sellerUserId: c.sellerUserId, merchantId: c.merchantId, merchantName: c.merchantName, serviceType: c.serviceType ?? 'marketplace');
  }

  Future<List<MarketplaceDetailModel>> _searchByPhoto(dynamic imageSource) async {
    setState(() { _loading = true; _photoMode = true; _selectedCategory = null; _aiSummary = ''; });
    try {
      final Uint8List bytes; final String filename;
      if (imageSource is XFile) { bytes = await imageSource.readAsBytes(); final path = imageSource.path.toLowerCase(); filename = path.endsWith('.png') ? 'photo.png' : path.endsWith('.webp') ? 'photo.webp' : 'photo.jpg'; }
      else if (imageSource is File) { bytes = await imageSource.readAsBytes(); final path = imageSource.path.toLowerCase(); filename = path.endsWith('.png') ? 'photo.png' : path.endsWith('.webp') ? 'photo.webp' : 'photo.jpg'; }
      else throw StateError('Invalid image source');
      final service = MarketplaceService();
      final firebaseResults = await service.searchByPhotoBytes(bytes, filename: filename);
      final converted = firebaseResults.map(_fromCoreMarketplace).toList();
      if (mounted && converted.isNotEmpty) { _setSuggestionsFromItems(converted); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found ${converted.length} product${converted.length == 1 ? '' : 's'} from photo.'), backgroundColor: _kSuccess, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))); }
      else if (mounted && converted.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('No similar products found. Showing all.'), backgroundColor: _kAmber, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))); return _loadAll(category: null); }
      return converted;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Photo search error: $e\n$st');
      if (mounted) { final msg = e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '').split('\n').first; final err = e.toString().toLowerCase(); final isNetErr = err.contains('socket') || err.contains('network') || err.contains('failed host') || err.contains('connection') || err.contains('timeout') || err.contains('unavailable') || err.contains('offline'); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isNetErr ? 'Cannot reach Firebase now.' : 'Photo search failed: ${msg.length > 60 ? '${msg.substring(0, 60)}...' : msg}'), backgroundColor: Colors.red, duration: const Duration(seconds: 5))); }
      return _loadAll(category: null);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<bool> _isUserLoggedIn() async { final token = await AuthHandler.getTokenForApi(); return token != null && token.isNotEmpty; }

  Future<bool> _requireLoginForCart() async {
    final isLoggedIn = await _isUserLoggedIn();
    if (!isLoggedIn && mounted) ToastHelper.showCustomToast(context, 'Please log in to add items to cart.', isSuccess: false, errorMessage: '');
    return isLoggedIn;
  }

  Future<bool> _requireLoginForChat() async {
    final isLoggedIn = await _isUserLoggedIn();
    if (!isLoggedIn && mounted) ToastHelper.showCustomToast(context, 'Please log in to chat with merchant.', isSuccess: false, errorMessage: '');
    return isLoggedIn;
  }

  void _shareProductFromSheet(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId ? item.sqlItemId! : _stablePositiveIdFromString(item.id);
    final merchantName = item.merchantName ?? item.sellerBusinessName ?? 'A merchant';
    final productUrl = 'https://vero360.app/marketplace/$id';
    final priceStr = NumberFormat('#,###', 'en').format(item.price.truncate());
    Share.share('$merchantName is selling this on Vero360 - Check out ${item.name} - MWK $priceStr\n$productUrl');
  }

  void _copyProductLinkFromSheet(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId ? item.sqlItemId! : _stablePositiveIdFromString(item.id);
    Clipboard.setData(ClipboardData(text: 'https://vero360.app/marketplace/$id'));
    if (!mounted) return;
    ToastHelper.showCustomToast(context, 'Product link copied', isSuccess: true, errorMessage: 'OK');
  }

  Future<void> _addToCart(MarketplaceDetailModel item, {String? note}) async {
    final isLoggedIn = await _requireLoginForCart();
    if (!isLoggedIn) return;
    if (!item.hasValidMerchantInfo) { ToastHelper.showCustomToast(context, 'This item cannot be added to cart: Missing merchant information.', isSuccess: false, errorMessage: 'Invalid merchant info'); return; }
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _kAmber)), const SizedBox(width: 16), const Flexible(child: Text('Adding to cart...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)))]))));
    try {
      final userId = await _getCurrentUserId() ?? 'unknown';
      final int numericItemId = item.hasValidSqlItemId ? item.sqlItemId! : _stablePositiveIdFromString(item.id);
      final cartItem = CartModel(userId: userId, item: numericItemId, quantity: 1, image: item.image, name: item.name, price: item.price, description: item.description ?? '', merchantId: item.merchantId ?? 'unknown', merchantName: item.merchantName ?? 'Unknown Merchant', serviceType: item.serviceType ?? 'marketplace', comment: note);
      await widget.cartService.addToCart(cartItem);
      unawaited(_trackInteraction(item, weight: 3.0));
      if (mounted) Navigator.of(context).pop();
      ToastHelper.showCustomToast(context, '${item.name} added to cart', isSuccess: true, errorMessage: 'OK');
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ToastHelper.showCustomToast(context, 'Failed to add item: $e', isSuccess: false, errorMessage: 'Add to cart failed');
    }
  }

  Future<void> _openChatWithMerchant(MarketplaceDetailModel item) async {
    if (!await _requireLoginForChat()) return;
    final peerAppId = (item.serviceProviderId ?? item.sellerUserId ?? '').trim();
    if (peerAppId.isEmpty) { if (!mounted) return; ToastHelper.showCustomToast(context, 'Seller chat unavailable', isSuccess: false, errorMessage: 'Seller id missing'); return; }
    final merchantName = (item.merchantName ?? '').trim();
    final sellerName = merchantName.isNotEmpty ? merchantName : ((item.sellerBusinessName ?? 'Seller').trim());
    final rawAvatar = (item.sellerLogoUrl ?? '').trim();
    final sellerAvatar = (await _toDownloadUrl(rawAvatar)) ?? rawAvatar;
    await ChatService.ensureFirebaseAuth();
    final me = await ChatService.myAppUserId();
    await ChatService.ensureThread(myAppId: me, peerAppId: peerAppId, peerName: sellerName, peerAvatar: sellerAvatar);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => MessagePage(peerAppId: peerAppId, peerName: sellerName, peerAvatarUrl: sellerAvatar, peerId: '')));
  }

  Future<void> _goToCheckoutFromBottomSheet(MarketplaceDetailModel item) async {
    if (!mounted) return;
    final core.MarketplaceDetailModel checkoutItem = core.MarketplaceDetailModel(id: item.hasValidSqlItemId ? item.sqlItemId! : _stablePositiveIdFromString(item.id), name: item.name, category: item.category, price: item.price, image: item.image, description: item.description ?? '', location: item.location ?? '', gallery: item.gallery, sellerBusinessName: item.sellerBusinessName, sellerOpeningHours: item.sellerOpeningHours, sellerStatus: item.sellerStatus, sellerBusinessDescription: item.sellerBusinessDescription, sellerRating: item.sellerRating, sellerLogoUrl: item.sellerLogoUrl, serviceProviderId: item.serviceProviderId, sellerUserId: item.sellerUserId, merchantId: item.merchantId, merchantName: item.merchantName, serviceType: item.serviceType);
    Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutPage(item: checkoutItem)));
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final typingNow = _searchCtrl.text.trim().isNotEmpty;
    if (typingNow) { _stopSuggestionTimer(); setState(() {}); }
    else { if (!_aiSearchMode && _suggestionTimer == null) _startSuggestionTimer(); }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final txt = _searchCtrl.text;
      if (txt == _lastQuery) return;
      _lastQuery = txt;
      setState(() => _future = _searchByName(txt));
    });
  }

  void _onSubmit(String value) { _debounce?.cancel(); setState(() => _future = _searchByName(value)); }

  void _setCategory(String? cat) {
    unawaited(_trackCategoryInterest(cat));
    _searchCtrl.clear(); _lastQuery = ''; _aiSummary = '';
    setState(() => _future = _loadAll(category: cat));
  }

  Future<void> _refresh() async {
    _searchCtrl.clear(); _lastQuery = ''; _aiSummary = '';
    _followedMerchantIdsFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
    setState(() => _future = _loadAll(category: _selectedCategory));
    await _future;
  }

  Future<void> _showPhotoPickerSheet() async {
    if (kIsWeb) { await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1280); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo search works best in mobile builds.'))); return; }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24)]),
        child: SafeArea(
          child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16, left: 0), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const Text('Search by Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _kInk)),
            const SizedBox(height: 16),
            _PhotoPickerOption(iconBg: _kAmber, icon: Icons.camera_alt_rounded, title: 'Use Camera', subtitle: 'Take a photo now', onTap: () async {
              Navigator.pop(context);
              final XFile? picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1280);
              if (picked != null) setState(() => _future = _searchByPhoto(picked));
            }),
            const SizedBox(height: 10),
            _PhotoPickerOption(iconBg: _kBlue, icon: Icons.photo_library_rounded, title: 'Choose from Gallery', subtitle: 'Pick an existing photo', onTap: () async {
              Navigator.pop(context);
              final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1280);
              if (picked != null) setState(() => _future = _searchByPhoto(picked));
            }),
            const SizedBox(height: 8),
          ])),
        ),
      ),
    );
  }

  String _titleCase(String s) => s.isEmpty ? s : (s[0].toUpperCase() + s.substring(1));


  // ─────────────────────────────────────────────
  // BEAUTIFUL ITEM IMAGE WIDGET
  // ─────────────────────────────────────────────
  Widget _buildItemImageWidget(MarketplaceDetailModel item) {
    final mainImage = item.image.trim();
    final sources = <String>[
      if (mainImage.isNotEmpty) mainImage,
      ...item.gallery.map((e) => e.toString().trim()),
    ].where((s) => s.isNotEmpty).toList();

    if (sources.isEmpty && item.imageBytes != null) {
      return Image.memory(item.imageBytes!, fit: BoxFit.cover, width: double.infinity);
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final src in sources) {
      if (seen.add(src)) deduped.add(src);
    }

    if (deduped.length <= 1) {
      return _imageFromAnySource(
        deduped.isEmpty ? '' : deduped.first,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return _AutoSlideImageCarousel(
      key: ValueKey('item-media-${item.id}-${deduped.length}'),
      sources: deduped,
      interval: const Duration(seconds: 3),
      showIndicators: true,
      itemBuilder: (src) => _imageFromAnySource(
        src,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BEAUTIFUL PRODUCT CARD
  // ─────────────────────────────────────────────
  Widget _buildMarketItem(MarketplaceDetailModel item) {
    final cat = item.category.trim();
    final merchant = (item.merchantName ?? '').trim();
    final isSold = !item.isActive;
    final catColor = _kCategoryColors[cat] ?? _kAmber;
    final catIcon = _kCategoryIcons[cat] ?? Icons.category_rounded;
    final VoidCallback? onTapCard = isSold ? null : () => _openDetailsPage(item);

    return _AnimatedProductCard(
      onTap: onTapCard,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: _kShadow, blurRadius: 20, offset: const Offset(0, 8)),
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── HERO IMAGE ──
          Expanded(
            flex: 58,
            child: Stack(children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: ColorFiltered(
                    colorFilter: isSold
                        ? const ColorFilter.mode(Color(0x88000000), BlendMode.darken)
                        : const ColorFilter.mode(Colors.transparent, BlendMode.srcOver),
                    child: _buildItemImageWidget(item),
                  ),
                ),
              ),
              // Gradient overlay for text legibility
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.transparent, Colors.black.withOpacity(0.45)],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              // Category badge
              if (cat.isNotEmpty)
                Positioned(top: 9, left: 9, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.90),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: catColor.withOpacity(0.4), blurRadius: 8)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(catIcon, size: 10, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(_titleCase(cat), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                  ]),
                )),
              // SOLD ribbon
              if (isSold)
                Positioned(right: -28, top: 16,
                  child: Transform.rotate(angle: 0.6,
                    child: Container(
                      width: 110, padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)]),
                        boxShadow: [BoxShadow(color: Color(0x44D32F2F), blurRadius: 8)],
                      ),
                      child: const Center(child: Text('SOLD', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
                    ),
                  ),
                ),
              // Bottom price tag
              Positioned(
                left: 9, right: 9, bottom: 9,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kAmber,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: _kAmber.withOpacity(0.5), blurRadius: 8)],
                    ),
                    child: Text(_mwk(item.price), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                  )),
                  if (item.createdAt != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                      child: Text(_formatTimeAgo(item.createdAt!), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ]),
          ),

          // ── INFO PANEL ──
          Container(
            decoration: const BoxDecoration(
              color: _kAmberLight,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _kInk, height: 1.2)),
                  if (_aiSearchMode && _lastQuery.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.auto_awesome_rounded, size: 10, color: _kAmberDark),
                      const SizedBox(width: 4),
                      Expanded(child: Text(_getAiHighlight(item), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: _kAmberDark, fontWeight: FontWeight.w600))),
                    ]),
                  ],
                  if (item.location != null && item.location!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.location_on_rounded, size: 10, color: _kAmber),
                      const SizedBox(width: 3),
                      Expanded(child: Text(item.location!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _kInkMid))),
                    ]),
                  ],
                  if (merchant.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.storefront_rounded, size: 10, color: _kInkLight),
                      const SizedBox(width: 3),
                      Expanded(child: Text(merchant, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _kInkLight, fontWeight: FontWeight.w600))),
                    ]),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 11, 11),
                child: Row(children: [
                  Expanded(child: _CardButton(
                    label: 'Cart', icon: Icons.shopping_cart_outlined,
                    onPressed: isSold ? null : () => _addToCart(item),
                    filled: false,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _CardButton(
                    label: isSold ? 'Sold' : 'Buy',
                    icon: isSold ? Icons.block_rounded : Icons.bolt_rounded,
                    onPressed: isSold ? null : () => _openDetailsPage(item),
                    filled: true,
                  )),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DETAILS BOTTOM SHEET (redesigned)
  // ─────────────────────────────────────────────
  Future<void> _showDetailsBottomSheet(MarketplaceDetailModel item) async {
    if (!mounted) return;
    final Future<_SellerInfo> sellerFuture = _loadSellerForItem(item);
    final List<String> mediaSources = [];
    if (item.image.trim().isNotEmpty) mediaSources.add(item.image.trim());
    if (item.gallery.isNotEmpty) mediaSources.addAll(item.gallery.map((e) => e.toString().trim()).where((u) => u.isNotEmpty));
    final pageController = PageController();
    Timer? autoTimer; int currentPage = 0; bool autoStarted = false;

    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        margin: const EdgeInsets.only(top: 60),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: FractionallySizedBox(
          heightFactor: 1.0,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              if (!autoStarted && mediaSources.length > 1) {
                autoStarted = true; autoTimer?.cancel();
                autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
                  if (!pageController.hasClients) return;
                  final next = (currentPage + 1) % mediaSources.length;
                  pageController.animateToPage(next, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut);
                  setModalState(() => currentPage = next);
                });
              }
              return ScrollConfiguration(
                behavior: const _NoBarsScrollBehavior(),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
                    child: FutureBuilder<_SellerInfo>(
                      future: sellerFuture,
                      builder: (ctx, snap) {
                        final seller = snap.data;
                        final closing = _closingFromHours(seller?.openingHours);
                        final status = seller?.status;
                        final rating = seller?.rating;
                        final businessDesc = seller?.description;
                        final logo = seller?.logoUrl;
                        final merchantName = (item.merchantName ?? '').trim();
                        final displayMerchantName = merchantName.isNotEmpty ? merchantName : ((seller?.businessName ?? item.sellerBusinessName ?? '').trim().isNotEmpty ? (seller?.businessName ?? item.sellerBusinessName)!.trim() : 'Merchant');

                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Drag handle
                          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 0), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),

                          // ── HERO MEDIA ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Stack(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: mediaSources.isEmpty
                                      ? _buildItemImageWidget(item)
                                      : PageView.builder(
                                          controller: pageController,
                                          itemCount: mediaSources.length,
                                          physics: mediaSources.length > 1 ? const PageScrollPhysics() : const NeverScrollableScrollPhysics(),
                                          onPageChanged: (i) => setModalState(() => currentPage = i),
                                          itemBuilder: (_, i) => _imageFromAnySource(mediaSources[i], fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                        ),
                                ),
                                if (mediaSources.length > 1)
                                  Positioned(right: 12, bottom: 12, child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.60), borderRadius: BorderRadius.circular(20)),
                                    child: Text('${currentPage + 1}/${mediaSources.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                  )),
                              ]),
                            ),
                          ),

                          // ── CONTENT ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              // Title row
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _kInk, height: 1.2)),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [_kAmber, _kAmberDark]),
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [BoxShadow(color: _kAmber.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                                    ),
                                    child: Text(_mwk(item.price), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                                  ),
                                ])),
                                const SizedBox(width: 12),
                                // Chat button
                                Column(children: [
                                  GestureDetector(
                                    onTap: () => _openChatWithMerchant(item),
                                    child: Container(
                                      width: 50, height: 50,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [_kAmber, _kAmberDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                        shape: BoxShape.circle,
                                        boxShadow: [BoxShadow(color: _kAmber.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
                                      ),
                                      child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('Chat', style: TextStyle(fontSize: 10, color: _kInkLight, fontWeight: FontWeight.w600)),
                                ]),
                              ]),
                              const SizedBox(height: 12),
                              if (item.location != null && item.location!.trim().isNotEmpty)
                                _InfoPill(icon: Icons.location_on_rounded, text: item.location!, color: Colors.red),
                              if (item.createdAt != null)
                                _InfoPill(icon: Icons.schedule_rounded, text: 'Posted by $displayMerchantName • ${_formatTimeAgo(item.createdAt!)}', color: _kAmber),
                              if ((item.description ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity, padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(color: _kCream, borderRadius: BorderRadius.circular(14)),
                                  child: Text(item.description!.trim(), style: const TextStyle(fontSize: 13.5, height: 1.55, color: _kInkMid)),
                                ),
                              ],
                              const SizedBox(height: 16),
                              // Share row
                              Row(children: [
                                Expanded(child: _OutlineActionButton(icon: Icons.link_rounded, label: 'Copy Link', onTap: () => _copyProductLinkFromSheet(item))),
                                const SizedBox(width: 10),
                                Expanded(child: _OutlineActionButton(icon: Icons.share_rounded, label: 'Share', onTap: () => _shareProductFromSheet(item))),
                              ]),
                              const SizedBox(height: 16),
                              // Seller Card
                              _SellerCard(
                                logo: logo, displayMerchantName: displayMerchantName,
                                rating: rating, status: status, closing: closing,
                                businessDesc: businessDesc,
                                circleAvatarBuilder: (raw, radius) => _circleAvatarFromAnySource(raw, radius: radius),
                              ),
                              const SizedBox(height: 12),
                              if ((item.merchantId ?? '').trim().isNotEmpty)
                                SizedBox(width: double.infinity, child: _OutlineActionButton(
                                  icon: Icons.store_mall_directory_outlined,
                                  label: 'More from $displayMerchantName',
                                  onTap: () {
                                    Navigator.pop(sheetCtx);
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => MerchantProductsPage(merchantId: item.merchantId!.trim(), merchantName: displayMerchantName)));
                                  },
                                )),
                              const SizedBox(height: 16),
                              // CTA
                              SizedBox(
                                width: double.infinity, height: 54,
                                child: GestureDetector(
                                  onTap: () { Navigator.pop(sheetCtx); _goToCheckoutFromBottomSheet(item); },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [_kAmber, _kAmberDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [BoxShadow(color: _kAmber.withOpacity(0.45), blurRadius: 16, offset: const Offset(0, 6))],
                                    ),
                                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 20),
                                      SizedBox(width: 10),
                                      Text('Continue to Checkout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                    ]),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ]),
                          ),
                        ]);
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ).whenComplete(() { autoTimer?.cancel(); pageController.dispose(); });
  }

  // ─────────────────────────────────────────────
  // AI QUESTION HANDLER
  // ─────────────────────────────────────────────
  Future<void> _onAskQuestionSubmitted() async {
    final q = _askQuestionCtrl.text.trim();
    if (q.isEmpty) return;
    _askQuestionCtrl.clear();
    if (!mounted) return;
    setState(() => _veroAiLoading = true);
    try {
      final items = await _future;
      final answer = _answerVeroAiQuestion(q, items);
      if (!mounted) return;
      _showVeroAiAnswerSheet(q, answer);
    } finally { if (mounted) setState(() => _veroAiLoading = false); }
  }

  String _answerVeroAiQuestion(String question, List<MarketplaceDetailModel> items) {
    final q = question.toLowerCase().trim();
    if (items.isEmpty) return 'There are no products to answer questions about. Try searching for something first.';
    if (_matches(q, ['cheapest', 'lowest', 'cheap', 'budget', 'affordable', 'least expensive'])) {
      final sorted = List<MarketplaceDetailModel>.from(items)..sort((a, b) => a.price.compareTo(b.price));
      final best = sorted.first;
      return 'The cheapest option is **${best.name}** at ${_mwk(best.price)}${best.location != null && best.location!.isNotEmpty ? ' from ${best.location}' : ''}.';
    }
    if (_matches(q, ['expensive', 'highest', 'most expensive', 'top price'])) { final sorted = List<MarketplaceDetailModel>.from(items)..sort((a, b) => b.price.compareTo(a.price)); final top = sorted.first; return 'The most expensive option is **${top.name}** at ${_mwk(top.price)}.'; }
    if (_matches(q, ['best value', 'best deal', 'value for money', 'recommend', 'which one'])) {
      final scored = items.map((i) { final rating = (i.sellerRating ?? 0).clamp(0.0, 5.0); final score = rating > 0 ? (rating / 5) * 100 - (i.price / 10000) : -i.price / 10000; return MapEntry(i, score); }).toList();
      scored.sort((a, b) => b.value.compareTo(a.value));
      final best = scored.first.key; final rating = best.sellerRating;
      return 'Based on price and seller rating, I recommend **${best.name}** at ${_mwk(best.price)}${rating != null && rating >= 4 ? ' (${_fmtRating(rating)}★ seller)' : ''}.';
    }
    if (_matches(q, ['price range', 'how much', 'cost', 'prices'])) { final prices = items.map((i) => i.price).toList(); final min = prices.reduce((a, b) => a < b ? a : b); final max = prices.reduce((a, b) => a > b ? a : b); return 'Prices range from ${_mwk(min)} to ${_mwk(max)} across ${items.length} products.'; }
    if (_matches(q, ['compare', 'comparison', 'difference'])) {
      if (items.length < 2) return 'There\'s only one product. Try searching for more to compare.';
      final top3 = items.take(3).toList(); final sb = StringBuffer('Here\'s a quick comparison of the top results:\n\n');
      for (int i = 0; i < top3.length; i++) { final it = top3[i]; sb.write('${i + 1}. **${it.name}** – ${_mwk(it.price)}'); if (it.sellerRating != null) sb.write(' (${_fmtRating(it.sellerRating!)}★)'); sb.writeln(); }
      return sb.toString().trimRight();
    }
    if (_matches(q, ['categories', 'category', 'types', 'what kind'])) { final cats = <String, int>{}; for (final i in items) { final c = i.category.isEmpty ? 'other' : i.category; cats[c] = (cats[c] ?? 0) + 1; } final list = cats.entries.map((e) => '${_titleCase(e.key)} (${e.value})').join(', '); return 'These products span ${cats.length} categories: $list.'; }
    if (_matches(q, ['how many', 'count', 'number of', 'total'])) return 'There are ${items.length} product${items.length == 1 ? '' : 's'} matching your search.';
    if (_matches(q, ['where', 'location', 'locations', 'from where'])) { final locs = <String>{}; for (final i in items) { if (i.location != null && i.location!.trim().isNotEmpty) locs.add(i.location!.trim()); } if (locs.isEmpty) return 'Location details aren\'t available for these products.'; return 'Sellers are from: ${locs.take(5).join(', ')}${locs.length > 5 ? ' and ${locs.length - 5} more' : ''}.'; }
    return 'Based on the ${items.length} products you\'re viewing, prices range from ${_mwk(items.map((i) => i.price).reduce((a, b) => a < b ? a : b))} to ${_mwk(items.map((i) => i.price).reduce((a, b) => a > b ? a : b))}. Ask "cheapest?", "best value?", "compare", or "price range" for more specific answers.';
  }

  bool _matches(String q, List<String> keywords) => keywords.any((k) => q.contains(k));

  void _showVeroAiAnswerSheet(String question, String answer) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, -4))]),
        child: DraggableScrollableSheet(
          initialChildSize: 0.5, minChildSize: 0.35, maxChildSize: 0.85, expand: false,
          builder: (_, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl, padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(gradient: const LinearGradient(colors: [_kBlue, Color(0xFF1565C0)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Vero AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _kInk)), Text('Marketplace Intelligence', style: TextStyle(fontSize: 11, color: _kInkLight))]),
              ]),
              const SizedBox(height: 16),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _kBlueBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF90CAF9))), child: Text('Q: $question', style: TextStyle(fontSize: 13, color: Colors.blue.shade800, fontWeight: FontWeight.w600))),
              const SizedBox(height: 14),
              SelectableText(answer.replaceAll('**', ''), style: const TextStyle(fontSize: 15, height: 1.65, color: _kInkMid)),
            ]),
          ),
        ),
      ),
    );
  }


  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.white, statusBarIconBrightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: _kCream,
        body: Column(children: [
          // ── BEAUTIFUL HEADER ──
          _MarketAppBar(showBlur: _showHeaderBlur),

          // ── SEARCH BAR ──
          _SearchSection(
            controller: _searchCtrl,
            aiSearchMode: _aiSearchMode,
            suggestionIndex: _suggestionIndex,
            activeSearchSuggestions: _activeSearchSuggestions,
            onPhotoTap: _showPhotoPickerSheet,
            onSubmit: _onSubmit,
            onClear: () { _searchCtrl.clear(); _onSubmit(''); },
          ),

          // ── FILTER CHIPS ──
          _FilterRow(
            aiSearchMode: _aiSearchMode,
            forYouMode: _forYouMode,
            comfortableView: _comfortableView,
            selectedCategory: _selectedCategory,
            photoMode: _photoMode,
            categories: _kCategories,
            onAiToggle: (ai) {
              setState(() { _aiSearchMode = ai; if (!ai) _aiSummary = ''; _future = _lastQuery.isNotEmpty ? _searchByName(_lastQuery) : _loadAll(category: _selectedCategory); });
            },
            onFeedToggle: () { setState(() { _forYouMode = !_forYouMode; _future = _lastQuery.trim().isNotEmpty ? _searchByName(_lastQuery) : _loadAll(category: _selectedCategory); }); },
            onViewToggle: () => setState(() => _comfortableView = !_comfortableView),
            onCategoryTap: _setCategory,
            titleCase: _titleCase,
          ),

          // ── VERO AI QUESTION BOX ──
          if (_aiSearchMode)
            _AiQuestionBox(controller: _askQuestionCtrl, loading: _veroAiLoading, onSubmit: _onAskQuestionSubmitted),

          // ── GRID ──
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: _kAmber,
                child: FutureBuilder<List<MarketplaceDetailModel>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return LayoutBuilder(builder: (context, constraints) {
                        final layout = _marketplaceSliverGridLayout(comfortable: _comfortableView, width: constraints.maxWidth);
                        return AppSkeletonShimmer(
                          child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(layout.gridPadH, 14, layout.gridPadH, 14),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: layout.crossAxisCount, crossAxisSpacing: layout.gridSpacing, mainAxisSpacing: layout.gridSpacing, childAspectRatio: layout.childAspectRatio),
                                delegate: SliverChildBuilderDelegate((_, __) => const _SkeletonCard(), childCount: layout.crossAxisCount * 5),
                              ),
                            ),
                          ]),
                        );
                      });
                    }
                    if (snapshot.hasError) {
                      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                        Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: _kInkLight)))),
                      ]);
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty && !_loading) {
                      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                        Center(child: Column(children: [
                          Container(width: 80, height: 80, decoration: BoxDecoration(color: _kAmberLight, shape: BoxShape.circle), child: const Icon(Icons.search_off_rounded, size: 40, color: _kAmber)),
                          const SizedBox(height: 16),
                          Text(_photoMode ? 'No products found for this photo.' : 'No products found.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kInkMid), textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          const Text('Try a different search or category', style: TextStyle(fontSize: 13, color: _kInkLight)),
                        ])),
                      ]);
                    }
                    return LayoutBuilder(builder: (context, constraints) {
                      final layout = _marketplaceSliverGridLayout(comfortable: _comfortableView, width: constraints.maxWidth);
                      return CustomScrollView(
                        controller: _scrollCtrl,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (_aiSummary.isNotEmpty)
                            SliverToBoxAdapter(child: _AiSummaryBanner(summary: _aiSummary)),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(layout.gridPadH, 6, layout.gridPadH, 14),
                            sliver: SliverGrid(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: layout.crossAxisCount, crossAxisSpacing: layout.gridSpacing, mainAxisSpacing: layout.gridSpacing, childAspectRatio: layout.childAspectRatio),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final item = items[i];
                                  return _buildMarketItem(item);
                                },
                                childCount: items.length,
                              ),
                            ),
                          ),
                        ],
                      );
                    });
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
} // end _MarketPageState

// ─────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────

class _MarketAppBar extends StatelessWidget {
  final bool showBlur;
  const _MarketAppBar({required this.showBlur});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: showBlur ? [BoxShadow(color: _kShadow, blurRadius: 12, offset: const Offset(0, 2))] : null,
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            const SizedBox(width: 16),
            // Back arrow if we can pop
            if (Navigator.of(context).canPop()) ...[
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: _kAmberLight, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded, color: _kAmber, size: 20),
                ),
              ),
              const SizedBox(width: 12),
            ],
            // Title
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kAmberLight, Colors.white]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.storefront_rounded, color: _kAmber, size: 18),
                SizedBox(width: 8),
                Text('Marketplace', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _kInk, letterSpacing: -0.3)),
              ]),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kAmberLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kAmber.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.local_fire_department_rounded, size: 14, color: _kAmber),
                SizedBox(width: 4),
                Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kAmberDark)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  final TextEditingController controller;
  final bool aiSearchMode;
  final int suggestionIndex;
  final List<String> activeSearchSuggestions;
  final VoidCallback onPhotoTap;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  const _SearchSection({
    required this.controller, required this.aiSearchMode,
    required this.suggestionIndex, required this.activeSearchSuggestions,
    required this.onPhotoTap, required this.onSubmit, required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Stack(children: [
        // Search field
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _kCream,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kAmber.withOpacity(0.3)),
            boxShadow: [BoxShadow(color: _kAmber.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded, color: _kAmber, size: 20),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kInk),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: aiSearchMode ? 'Search with AI...' : '',
                hintStyle: TextStyle(color: _kInkLight, fontSize: 14, fontWeight: FontWeight.w500),
                isDense: true, contentPadding: EdgeInsets.zero,
              ),
            )),
            if (controller.text.isNotEmpty)
              GestureDetector(onTap: onClear, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.close_rounded, color: _kInkLight, size: 18))),
            GestureDetector(
              onTap: onPhotoTap,
              child: Container(
                margin: const EdgeInsets.all(6),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kAmber, _kAmberDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: _kAmber.withOpacity(0.4), blurRadius: 8)],
                ),
                child: const Icon(Icons.camera_alt_rounded, size: 17, color: Colors.white),
              ),
            ),
          ]),
        ),
        // Sliding suggestion overlay
        if (!aiSearchMode && controller.text.trim().isEmpty && activeSearchSuggestions.isNotEmpty)
          Positioned(left: 48, right: 60, top: 0, bottom: 0,
            child: IgnorePointer(
              ignoring: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.8), end: Offset.zero).chain(CurveTween(curve: Curves.easeOut)).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: GestureDetector(
                    key: ValueKey<String>(activeSearchSuggestions[suggestionIndex % activeSearchSuggestions.length]),
                    onTap: () {
                      final s = activeSearchSuggestions[suggestionIndex % activeSearchSuggestions.length];
                      controller.text = s;
                      controller.selection = TextSelection.fromPosition(TextPosition(offset: s.length));
                      onSubmit(s);
                    },
                    child: Text(
                      activeSearchSuggestions[suggestionIndex % activeSearchSuggestions.length],
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _kInkLight),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final bool aiSearchMode, forYouMode, comfortableView, photoMode;
  final String? selectedCategory;
  final List<String> categories;
  final ValueChanged<bool> onAiToggle;
  final VoidCallback onFeedToggle, onViewToggle;
  final ValueChanged<String?> onCategoryTap;
  final String Function(String) titleCase;

  const _FilterRow({
    required this.aiSearchMode, required this.forYouMode, required this.comfortableView,
    required this.selectedCategory, required this.photoMode, required this.categories,
    required this.onAiToggle, required this.onFeedToggle, required this.onViewToggle,
    required this.onCategoryTap, required this.titleCase,
  });

  Widget _chip({required String label, required bool selected, required VoidCallback onTap, IconData? icon, Color? activeColor}) {
    final color = activeColor ?? _kAmber;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : _kCreamDark, width: selected ? 0 : 1),
          boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: selected ? Colors.white : _kInkLight), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : _kInkMid)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(children: [
        // Mode chips
        SizedBox(height: 40, child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          scrollDirection: Axis.horizontal,
          children: [
            _chip(label: 'All', selected: !aiSearchMode, onTap: () => onAiToggle(false), icon: Icons.grid_view_rounded),
            const SizedBox(width: 7),
            _chip(label: '✦ VeroAI', selected: aiSearchMode, onTap: () => onAiToggle(true), icon: Icons.auto_awesome_rounded, activeColor: _kBlue),
            const SizedBox(width: 7),
            _chip(label: forYouMode ? 'For You' : 'Newest', selected: true, onTap: onFeedToggle, icon: forYouMode ? Icons.person_pin_rounded : Icons.schedule_rounded),
            const SizedBox(width: 7),
            _chip(label: comfortableView ? 'Comfy' : 'Compact', selected: comfortableView, onTap: onViewToggle, icon: comfortableView ? Icons.view_agenda_rounded : Icons.grid_view_rounded),
          ],
        )),
        // Category chips
        SizedBox(height: 42, child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 3, 14, 8),
          scrollDirection: Axis.horizontal,
          children: [
            _chip(label: 'All Items', selected: selectedCategory == null && !photoMode, onTap: () => onCategoryTap(null)),
            ...categories.map((c) {
              final catColor = _kCategoryColors[c] ?? _kAmber;
              return Padding(
                padding: const EdgeInsets.only(left: 7),
                child: _chip(label: titleCase(c), selected: selectedCategory == c, onTap: () => onCategoryTap(c), icon: _kCategoryIcons[c], activeColor: catColor),
              );
            }),
          ],
        )),
        Container(height: 1, color: _kCreamDark),
      ]),
    );
  }
}

class _AiQuestionBox extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSubmit;

  const _AiQuestionBox({required this.controller, required this.loading, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        decoration: BoxDecoration(
          color: _kBlueBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF90CAF9)),
        ),
        child: Row(children: [
          const SizedBox(width: 12),
          const Icon(Icons.auto_awesome_rounded, size: 16, color: _kBlue),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            style: const TextStyle(fontSize: 13.5, color: _kInk),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Ask Vero AI about these results…', hintStyle: TextStyle(fontSize: 13.5, color: _kInkLight), isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12)),
          )),
          loading
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue)))
              : IconButton(icon: const Icon(Icons.send_rounded, color: _kBlue, size: 18), onPressed: onSubmit),
        ]),
      ),
    );
  }
}

class _AiSummaryBanner extends StatelessWidget {
  final String summary;
  const _AiSummaryBanner({required this.summary});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_kBlueBg, Colors.white.withOpacity(0.6)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _kBlue.withOpacity(0.12), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, size: 14, color: _kBlue)),
        const SizedBox(width: 10),
        Expanded(child: Text(summary, style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.blue.shade900))),
      ]),
    );
  }
}

// Beautiful animated product card entrance
class _AnimatedProductCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _AnimatedProductCard({
    required this.child,
    this.onTap,
  });
  @override
  State<_AnimatedProductCard> createState() => _AnimatedProductCardState();
}

class _AnimatedProductCardState extends State<_AnimatedProductCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic)),
    );
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack)),
    );
    Future.delayed(const Duration(milliseconds: 80), () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() {
              _pressed = true;
            }),
            onTapUp: (_) => setState(() {
              _pressed = false;
            }),
            onTapCancel: () => setState(() {
              _pressed = false;
            }),
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// Card button
class _CardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  const _CardButton({required this.label, required this.icon, required this.onPressed, required this.filled});

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: onPressed != null ? const LinearGradient(colors: [_kAmber, _kAmberDark], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            color: onPressed == null ? _kCreamDark : null,
            borderRadius: BorderRadius.circular(11),
            boxShadow: onPressed != null ? [BoxShadow(color: _kAmber.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))] : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: onPressed != null ? Colors.white : _kInkLight),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: onPressed != null ? Colors.white : _kInkLight), overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );
    }
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: onPressed != null ? _kAmber : _kCreamDark),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: onPressed != null ? _kAmber : _kInkLight),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onPressed != null ? _kAmber : _kInkLight), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

// Info pill for details sheet
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _InfoPill({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, color: _kInkMid, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// Outline action button for sheet
class _OutlineActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OutlineActionButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _kCreamDark),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: _kAmber),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kInkMid), overflow: TextOverflow.ellipsis)),
      ]),
    ),
  );
}

// Seller card for details sheet
class _SellerCard extends StatelessWidget {
  final String? logo;
  final String displayMerchantName;
  final double? rating;
  final String? status;
  final String? closing;
  final String? businessDesc;
  final Widget Function(String? raw, double radius) circleAvatarBuilder;

  const _SellerCard({
    required this.logo, required this.displayMerchantName, required this.rating,
    required this.status, required this.closing, required this.businessDesc,
    required this.circleAvatarBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kCreamDark),
        boxShadow: [BoxShadow(color: _kShadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          circleAvatarBuilder(logo, 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayMerchantName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _kInk), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (rating != null) ...[const SizedBox(height: 2), _ratingStars(rating)],
          ])),
          _statusChip(status),
        ]),
        const SizedBox(height: 12),
        if ((closing ?? '').isNotEmpty) _infoRow('Closes at', closing, icon: Icons.access_time_rounded),
        if ((businessDesc ?? '').isNotEmpty) ...[
          const Divider(height: 16, color: _kCreamDark),
          Text(businessDesc!, style: const TextStyle(fontSize: 13, color: _kInkMid, height: 1.5)),
        ],
      ]),
    );
  }
}

// Photo picker option
class _PhotoPickerOption extends StatelessWidget {
  final Color iconBg;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PhotoPickerOption({required this.iconBg, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCreamDark),
        ),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kInk)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: _kInkLight)),
          ]),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: _kInkLight),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AUTO SLIDE IMAGE CAROUSEL (unchanged logic)
// ─────────────────────────────────────────────
class _AutoSlideImageCarousel extends StatefulWidget {
  const _AutoSlideImageCarousel({
    super.key,
    required this.sources,
    required this.itemBuilder,
    this.interval = const Duration(seconds: 3),
    this.showIndicators = false,
    this.onTap,
  });
  final List<String> sources;
  final Widget Function(String source) itemBuilder;
  final Duration interval;
  final bool showIndicators;
  final VoidCallback? onTap;

  @override
  State<_AutoSlideImageCarousel> createState() => _AutoSlideImageCarouselState();
}

class _AutoSlideImageCarouselState extends State<_AutoSlideImageCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.sources.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted || !_controller.hasClients || widget.sources.length <= 1) return;
        final next = (_index + 1) % widget.sources.length;
        _controller.animateToPage(next, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      PageView.builder(
        controller: _controller,
        itemCount: widget.sources.length,
        physics: widget.sources.length > 1 ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.translucent,
          child: widget.itemBuilder(widget.sources[i]),
        ),
      ),
      if (widget.showIndicators && widget.sources.length > 1)
        Positioned(left: 0, right: 0, bottom: 8, child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.sources.length, (i) {
            final active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: active ? 14 : 6, height: 6,
              decoration: BoxDecoration(
                color: active ? _kAmber : Colors.white70,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.black26, width: 0.4),
              ),
            );
          }),
        )),
    ]);
  }
}