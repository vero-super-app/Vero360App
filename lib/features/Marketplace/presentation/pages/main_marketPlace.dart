// lib/Pages/marketPlace.dart
// ─────────────────────────────────────────────
// Upgraded UI – Modern 2025 design
//   • Skeleton shimmer loading cards
//   • Responsive grid (2 col / 3 col wide)
//   • Preserved colors: #FF8A00 orange, #1E88E5 blue AI
//   • No layout shrinking on small screens
//   • All original functionality intact
// ─────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

// ─────────────────────────────────────────────
// CONSTANTS & THEME
// ─────────────────────────────────────────────
const _kOrange = Color(0xFFFF8A00);
const _kOrangeLight = Color(0xFFFFF4E6);
const _kOrangeSoft = Color(0xFFFFE8CC);
const _kBlue = Color(0xFF1E88E5);
const _kBlueBg = Color(0xFFE3F2FD);
const _kSurface = Colors.white;
const _kBg = Color(0xFFF5F6FA);
const _kTextPrimary = Color(0xFF1A1A2E);
const _kTextSecondary = Color(0xFF6B7280);
const _kShadow = Color(0x14000000);

// ─────────────────────────────────────────────
// SKELETON SHIMMER WIDGET
// ─────────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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
            Color(0xFFEBEBF5),
            Color(0xFFF8F8FF),
            Color(0xFFEBEBF5),
          ],
          stops: [
            (_anim.value - 0.5).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 0.5).clamp(0.0, 1.0),
          ],
        ).createShader(bounds),
        child: child!,
      ),
      child: widget.child,
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E5EA),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton card that matches the real product card layout
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: _kShadow, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Expanded(
              flex: 5,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFE2E5EA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
            ),
            // Info area
            Expanded(
              flex: 4,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF4E6),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SkeletonBox(width: double.infinity, height: 13),
                    const SizedBox(height: 6),
                    const _SkeletonBox(width: 80, height: 11),
                    const SizedBox(height: 6),
                    const _SkeletonBox(width: 60, height: 11),
                    const SizedBox(height: 10),
                    // Buttons row
                    Row(
                      children: const [
                        Expanded(
                          child: _SkeletonBox(
                              width: double.infinity, height: 34, radius: 10),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _SkeletonBox(
                              width: double.infinity, height: 34, radius: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SCROLL BEHAVIOR (no scrollbars/glow)
// ─────────────────────────────────────────────
class _NoBarsScrollBehavior extends MaterialScrollBehavior {
  const _NoBarsScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

// ─────────────────────────────────────────────
// LOCAL MARKETPLACE MODEL
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
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.image,
    this.sqlItemId,
    this.imageBytes,
    this.description,
    this.location,
    this.isActive = true,
    this.createdAt,
    this.gallery = const [],
    this.sellerBusinessName,
    this.sellerOpeningHours,
    this.sellerStatus,
    this.sellerBusinessDescription,
    this.sellerRating,
    this.sellerLogoUrl,
    this.serviceProviderId,
    this.sellerUserId,
    this.merchantId,
    this.merchantName,
    this.serviceType = 'marketplace',
  });

  bool get hasValidSqlItemId => sqlItemId != null && sqlItemId! > 0;

  bool get hasValidMerchantInfo =>
      merchantId != null &&
      merchantId!.isNotEmpty &&
      merchantId != 'unknown' &&
      merchantName != null &&
      merchantName!.isNotEmpty &&
      merchantName != 'Unknown Merchant';

  factory MarketplaceDetailModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawImage = (data['image'] ??
            data['imageUrl'] ??
            data['photo'] ??
            data['picture'] ??
            '')
        .toString()
        .trim();

    bool looksLikeBase64(String s) {
      final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
      if (x.length < 150) return false;
      return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
    }

    Uint8List? bytes;
    if (rawImage.isNotEmpty && looksLikeBase64(rawImage)) {
      try {
        final base64Part =
            rawImage.contains(',') ? rawImage.split(',').last : rawImage;
        bytes = base64Decode(base64Part);
      } catch (_) {
        bytes = null;
      }
    }

    DateTime? created;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) {
      created = createdRaw.toDate();
    } else if (createdRaw is DateTime) {
      created = createdRaw;
    }

    double price = 0;
    final p = data['price'];
    if (p is num) {
      price = p.toDouble();
    } else if (p != null) {
      price = double.tryParse(p.toString()) ?? 0;
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().replaceAll(RegExp(r'[^\d]'), ''));
    }

    final rawSql =
        data['sqlItemId'] ?? data['backendId'] ?? data['itemId'] ?? data['id'];
    final sqlId = parseInt(rawSql);
    final cat = (data['category'] ?? '').toString().toLowerCase();

    List<String> parseGalleryField(dynamic field) {
      if (field is List) {
        return field
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (field is String) {
        final raw = field.trim();
        if (raw.isEmpty) return const [];
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } catch (_) {}
        return raw
            .split(',')
            .map((e) => e.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return const [];
    }

    // `gallery` (Post_On_Marketplace) vs `galleryUrls` (merchant dashboard upload flow)
    final fromGallery = parseGalleryField(data['gallery']);
    final fromGalleryUrls = parseGalleryField(data['galleryUrls']);
    final seen = <String>{};
    final gallery = <String>[];
    for (final s in [...fromGallery, ...fromGalleryUrls]) {
      final t = s.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      gallery.add(t);
    }

    double? sellerRating;
    final r = data['sellerRating'];
    if (r is num) {
      sellerRating = r.toDouble();
    } else if (r != null) {
      sellerRating = double.tryParse(r.toString());
    }

    return MarketplaceDetailModel(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      category: cat,
      price: price,
      image: rawImage,
      imageBytes: bytes,
      description: data['description']?.toString(),
      location: data['location']?.toString(),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      createdAt: created,
      sqlItemId: sqlId,
      gallery: gallery,
      sellerBusinessName: data['sellerBusinessName']?.toString(),
      sellerOpeningHours: data['sellerOpeningHours']?.toString(),
      sellerStatus: data['sellerStatus']?.toString(),
      sellerBusinessDescription: data['sellerBusinessDescription']?.toString(),
      sellerRating: sellerRating,
      sellerLogoUrl: data['sellerLogoUrl']?.toString(),
      serviceProviderId: data['serviceProviderId']?.toString(),
      sellerUserId: data['sellerUserId']?.toString(),
      merchantId: data['merchantId']?.toString(),
      merchantName: data['merchantName']?.toString(),
      serviceType: data['serviceType']?.toString() ?? 'marketplace',
    );
  }
}

// ─────────────────────────────────────────────
// SELLER INFO
// ─────────────────────────────────────────────
class _SellerInfo {
  String? businessName, openingHours, status, description, logoUrl;
  double? rating;
  String? serviceProviderId;

  _SellerInfo({
    this.businessName,
    this.openingHours,
    this.status,
    this.description,
    this.rating,
    this.logoUrl,
    this.serviceProviderId,
  });
}

Future<_SellerInfo> _loadSellerForItem(MarketplaceDetailModel i) async {
  final info = _SellerInfo(
    businessName: i.sellerBusinessName,
    openingHours: i.sellerOpeningHours,
    status: i.sellerStatus,
    description: i.sellerBusinessDescription,
    rating: i.sellerRating,
    logoUrl: i.sellerLogoUrl,
    serviceProviderId: i.serviceProviderId,
  );
  final missing = info.businessName == null ||
      info.openingHours == null ||
      info.status == null ||
      info.description == null ||
      info.rating == null ||
      info.logoUrl == null;
  final spId = info.serviceProviderId?.trim();
  if (missing && spId != null && spId.isNotEmpty) {
    try {
      final ServiceProvider? sp =
          await ServiceProviderServicess.fetchByNumber(spId);
      if (sp != null) {
        info.businessName ??= sp.businessName;
        info.openingHours ??= sp.openingHours;
        info.status ??= sp.status;
        info.description ??= sp.businessDescription;
        info.logoUrl ??= sp.logoUrl;
        final r = sp.rating;
        if (info.rating == null && r != null) {
          info.rating = (r is num) ? r.toDouble() : double.tryParse('$r');
        }
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

Widget _ratingStars(double? rating) {
  final rr = ((rating ?? 0).clamp(0, 5)).toDouble();
  final filled = rr.floor();
  final hasHalf = (rr - filled) >= 0.5 && filled < 5;
  final empty = 5 - filled - (hasHalf ? 1 : 0);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    for (int i = 0; i < filled; i++)
      const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
    if (hasHalf)
      const Icon(Icons.star_half_rounded, size: 15, color: Colors.amber),
    for (int i = 0; i < empty; i++)
      const Icon(Icons.star_outline_rounded, size: 15, color: Colors.amber),
    const SizedBox(width: 4),
    Text(_fmtRating(rr),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
  ]);
}

Widget _infoRow(String label, String? value, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[
        Icon(icon, size: 15, color: _kTextSecondary),
        const SizedBox(width: 8),
      ],
      SizedBox(
        width: 110,
        child: Text(label,
            style: const TextStyle(color: _kTextSecondary, fontSize: 12)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          (value ?? '').isNotEmpty ? value! : '—',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    ]),
  );
}

Widget _statusChip(String? status) {
  final s = (status ?? '').toLowerCase().trim();
  Color bg = const Color(0xFFF3F4F6);
  Color fg = _kTextSecondary;
  if (s == 'open') {
    bg = const Color(0xFFDCFCE7);
    fg = const Color(0xFF16A34A);
  } else if (s == 'closed') {
    bg = const Color(0xFFFEE2E2);
    fg = const Color(0xFFDC2626);
  } else if (s == 'busy') {
    bg = const Color(0xFFFEF3C7);
    fg = const Color(0xFFD97706);
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      (status ?? '—').toUpperCase(),
      style: TextStyle(
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: 10,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// Network image that on load error retries with the other scheme (http <-> https).
/// --------------------
/// Market Page
/// --------------------
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

  late final NumberFormat _mwkFmt =
      NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
  String _mwk(num v) => _mwkFmt.format(v);

  Widget _smallBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }


  static const List<String> _kCategories = <String>[
    'food',
    'drinks',
    'electronics',
    'clothes',
    'shoes',
    'other'
  ];
  String? _selectedCategory;

  Timer? _debounce;
  Timer? _suggestionTimer;
  String _lastQuery = '';
  bool _loading = false;
  bool _photoMode = false;
  bool _comfortableView = false;
  bool _forYouMode = true;
  int _suggestionIndex = 0;
  static const List<String> _searchSuggestions = <String>[
    'iphone 13 near me',
    'nike shoes size 42',
    'ps5 controller',
    'laptop under 500k',
    'kitchen blender',
    'office chair',
  ];

  // Search suggestion carousel (interactive + auto-slides)
  List<String> _activeSearchSuggestions = const <String>[];

  /// AI Search mode: when true, shows AI summary, product highlights, and smarter search
bool _aiSearchMode=false;


  late Future<List<MarketplaceDetailModel>> _future;

  /// Merchant UIDs the signed-in user follows (`merchant_followers/{id}/followers/{uid}`).
  /// Cached briefly to avoid extra reads on every scroll refresh.
  Set<String> _followedMerchantIdsCache = {};
  DateTime _followedMerchantIdsFetchedAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kFollowedMerchantsCacheTtl = Duration(minutes: 2);

  /// AI summary text (generated from results). Empty when not in AI mode or no query.
  String _aiSummary = '';

  final Map<String, Future<String?>> _dlUrlCache = {};
  static const String _prefsPersonalizationPrefix = 'marketplace_personalization_v1_';

  List<String> _keywordsFromText(String text) {
    final clean = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .trim();
    if (clean.isEmpty) return const [];
    const stop = {
      'the', 'and', 'for', 'with', 'this', 'that', 'from', 'you', 'your', 'item',
      'items', 'new', 'used', 'very', 'good', 'best', 'all', 'are', 'was', 'were',
      'has', 'have', 'had', 'not', 'but', 'can', 'will', 'its', 'our', 'their',
    };
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stop.contains(w))
        .toList();
    return words;
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
      if (raw == null || raw.isEmpty) {
        return {
          'cat': <String, num>{},
          'merchant': <String, num>{},
          'kw': <String, num>{},
          'last': <String, int>{},
        };
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return {
          'cat': Map<String, num>.from(decoded['cat'] ?? const {}),
          'merchant': Map<String, num>.from(decoded['merchant'] ?? const {}),
          'kw': Map<String, num>.from(decoded['kw'] ?? const {}),
          'last': Map<String, int>.from(decoded['last'] ?? const {}),
        };
      }
    } catch (_) {}
    return {
      'cat': <String, num>{},
      'merchant': <String, num>{},
      'kw': <String, num>{},
      'last': <String, int>{},
    };
  }

  DateTime _lastSuggestionRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _writePersonalizationProfile(Map<String, dynamic> profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final k = await _personalizationStorageKey();
      await prefs.setString(k, jsonEncode(profile));
    } catch (_) {}
  }

  Future<void> _trackInteraction(
    MarketplaceDetailModel item, {
    double weight = 1.0,
  }) async {
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
    for (final w in keywords.take(8)) {
      kw[w] = (kw[w] ?? 0) + (weight * 0.45);
    }

    last[item.id] = DateTime.now().millisecondsSinceEpoch;
    if (last.length > 120) {
      final sorted = last.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      for (final e in sorted.take(last.length - 120)) {
        last.remove(e.key);
      }
    }

    profile['cat'] = cat;
    profile['merchant'] = merchant;
    profile['kw'] = kw;
    profile['last'] = last;
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
    for (final w in words.take(8)) {
      kw[w] = (kw[w] ?? 0) + 0.35;
    }
    profile['kw'] = kw;
    await _writePersonalizationProfile(profile);
  }

  /// Resolves merchant IDs the current user follows (same paths as [MerchantProductsPage] follow).
  Future<Set<String>> _fetchFollowedMerchantIds() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return {};
    try {
      final qs = await _firestore
          .collectionGroup('followers')
          .where(FieldPath.documentId, isEqualTo: uid)
          .limit(300)
          .get();
      final out = <String>{};
      for (final doc in qs.docs) {
        final merchantRef = doc.reference.parent.parent;
        if (merchantRef == null) continue;
        final id = merchantRef.id.trim();
        if (id.isNotEmpty) out.add(id);
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('followed merchants query: $e');
      }
      return {};
    }
  }

  Future<Set<String>> _getFollowedMerchantIdsCached() async {
    final now = DateTime.now();
    if (_followedMerchantIdsFetchedAt.millisecondsSinceEpoch > 0 &&
        now.difference(_followedMerchantIdsFetchedAt) < _kFollowedMerchantsCacheTtl) {
      return _followedMerchantIdsCache;
    }
    final fresh = await _fetchFollowedMerchantIds();
    _followedMerchantIdsCache = fresh;
    _followedMerchantIdsFetchedAt = now;
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
        for (final e in entries.take(take)) {
          final text = toText(e.key);
          if (text.isNotEmpty) suggestions.add(text);
        }
      }

      addSorted(kwMap, 4, (k) => k);
      addSorted(catMap, 2, (k) => '${k} near me');
      addSorted(merchantMap, 2, (k) => k);

      final seen = <String>{};
      final out = <String>[];
      for (final s in suggestions) {
        final t = s.trim();
        if (t.isEmpty || seen.contains(t)) continue;
        seen.add(t);
        out.add(t);
      }

      if (out.isEmpty) {
        out.addAll(_searchSuggestions);
      }

      // Keep it small + fast to render
      final finalOut = out.take(6).toList();
      if (!mounted) return;
      setState(() {
        _activeSearchSuggestions = finalOut;
        _suggestionIndex = 0;
      });
    } catch (_) {}
  }

  Future<List<MarketplaceDetailModel>> _rankByPersonalization(
    List<MarketplaceDetailModel> items,
  ) async {
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
      if (sid.isNotEmpty && followedMerchants.contains(sid)) return true;
      return false;
    }

    double score(MarketplaceDetailModel i) {
      var s = 0.0;
      final c = i.category.trim().toLowerCase();
      if (c.isNotEmpty) s += (cat[c] ?? 0).toDouble() * 1.3;

      final m = (i.merchantName ?? i.sellerBusinessName ?? '').trim().toLowerCase();
      if (m.isNotEmpty) s += (merchant[m] ?? 0).toDouble() * 1.1;

      final words = _keywordsFromText('${i.name} ${i.description ?? ''} ${i.location ?? ''}');
      for (final w in words.take(10)) {
        s += (kw[w] ?? 0).toDouble() * 0.45;
      }

      final t = last[i.id];
      if (t != null) {
        final days = DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(t))
                .inHours /
            24.0;
        s += (days <= 7 ? 2.2 : 1.2 / (1 + days / 7));
      }

      // Strong boost for merchants you follow (same Firestore follow as merchant shop page).
      if (_itemIsFromFollowedSeller(i)) {
        s += 22.0;
      }
      return s;
    }

    final ranked = List<MarketplaceDetailModel>.from(items);
    ranked.sort((a, b) {
      final sb = score(b);
      final sa = score(a);
      final byScore = sb.compareTo(sa);
      if (byScore != 0) return byScore;
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return ranked;
  }

  void _setSuggestionsFromItems(List<MarketplaceDetailModel> items) {
    if (!mounted) return;
    if (items.isEmpty) return;

    final seen = <String>{};
    final out = <String>[];
    for (final it in items) {
      final n = it.name.trim();
      if (n.isEmpty) continue;
      final k = n.toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);
      out.add(n);
      if (out.length >= 6) break;
    }

    if (out.isEmpty) return;
    setState(() {
      _activeSearchSuggestions = out;
      _suggestionIndex = 0;
    });
  }

  Future<List<MarketplaceDetailModel>> _sortByNewest(List<MarketplaceDetailModel> items) async {
    final copy = List<MarketplaceDetailModel>.from(items);
    copy.sort((a, b) {
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return copy;
  }

  // ── Animation controllers ──
  late AnimationController _fabCtrl;
  late Animation<double> _fabAnim;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    _searchCtrl.addListener(_onSearchChanged);

    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fabAnim = CurvedAnimation(parent: _fabCtrl, curve: Curves.elasticOut);
    _fabCtrl.forward();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _askQuestionCtrl.dispose();
    _fabCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // IMAGE HELPERS
  // ─────────────────────────────────────────────
  bool _isHttp(String s) {
    final lower = s.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  bool _isGs(String s) => s.startsWith('gs://');
  bool _isRelativePath(String s) =>
      s.isNotEmpty && !s.contains('://') && !_looksLikeBase64(s);

  bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.isEmpty) return false;
    return x.length >= 40 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  Future<String> _backendUrlForPath(String path) async {
    final base = await ApiConfig.readBase();
    final baseNorm = base.endsWith('/') ? base : '$base/';
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$baseNorm$p';
  }

  Future<String?> _toDownloadUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (_isHttp(s)) return s;
    if (s.startsWith('/')) {
      try {
        final url = await _backendUrlForPath(s);
        if (url.isNotEmpty) return url;
      } catch (_) {}
      return null;
    }
    if (_dlUrlCache.containsKey(s)) {
      try {
        return await _dlUrlCache[s]!;
      } catch (_) {
        _dlUrlCache.remove(s);
      }
    }
    Future<String?> fut() async {
      try {
        if (_isGs(s)) {
          return await FirebaseStorage.instance.refFromURL(s).getDownloadURL();
        }
        return await FirebaseStorage.instance.ref(s).getDownloadURL();
      } catch (_) {
        if (_isRelativePath(s)) {
          try {
            return await _backendUrlForPath(s);
          } catch (_) {}
        }
        return null;
      }
    }

    _dlUrlCache[s] = fut();
    return _dlUrlCache[s]!;
  }

  Widget _imageFromAnySource(
    String raw, {
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    BorderRadius? radius,
  }) {
    final s = raw.trim();

    Widget wrap(Widget child) {
      if (radius == null) return child;
      return ClipRRect(borderRadius: radius, child: child);
    }

    if (s.isEmpty) {
      return wrap(Container(
        width: width,
        height: height,
        color: const Color(0xFFF3F4F6),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
      ));
    }

    if (_looksLikeBase64(s)) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        return wrap(Image.memory(bytes, fit: fit, width: width, height: height));
      } catch (_) {}
    }

    if (_isHttp(s)) {
      return wrap(ResilientCachedNetworkImage(
        url: s,
        fit: fit,
        width: width,
        height: height,
      ));
    }

    return FutureBuilder<String?>(
      future: _toDownloadUrl(s),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return wrap(_Shimmer(
            child: Container(
              width: width,
              height: height,
              color: const Color(0xFFE2E5EA),
            ),
          ));
        }
        return wrap(ResilientCachedNetworkImage(
          url: url,
          fit: fit,
          width: width,
          height: height,
        ));
      },
    );
  }

  Widget _circleAvatarFromAnySource(String? raw, {double radius = 18}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFF3F4F6),
        child: const Icon(Icons.storefront_rounded, color: _kTextSecondary, size: 16),
      );
    }
    if (_looksLikeBase64(s)) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        return CircleAvatar(radius: radius, backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }
    if (_isHttp(s)) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(s));
    }
    return FutureBuilder<String?>(
      future: _toDownloadUrl(s),
      builder: (_, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFFF3F4F6),
            child: const Icon(Icons.storefront_rounded, color: _kTextSecondary, size: 16),
          );
        }
        return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    _searchCtrl.addListener(_onSearchChanged);
    _startSuggestionTimer();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestionTimer?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _askQuestionCtrl.dispose();
    super.dispose();
  }

  void _startSuggestionTimer() {
    _suggestionTimer?.cancel();
    _suggestionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_aiSearchMode) return; // suggestions UI is hidden in AI mode anyway
      if (_searchCtrl.text.trim().isNotEmpty) return; // pause while user types

      final suggestions = _activeSearchSuggestions;
      if (suggestions.length <= 1) return;

      final current = _suggestionIndex % suggestions.length;
      int next;
      if (suggestions.length == 2) {
        next = 1 - current;
      } else {
        final rng = Random();
        next = current;
        while (next == current) {
          next = rng.nextInt(suggestions.length);
        }
      }

      setState(() {
        _suggestionIndex = next;
      });
    });
  }

  void _stopSuggestionTimer() {
    _suggestionTimer?.cancel();
    _suggestionTimer = null;
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading...'),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _getCurrentUserId() async {
    try {
      final FirebaseAuth auth = FirebaseAuth.instance;
      final User? user = auth.currentUser;
      if (user != null) return user.uid;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('uid');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getAuthToken() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 1) backend JWT tokens first
      final String? token =
          prefs.getString('token') ?? prefs.getString('jwt_token');
      if (token != null && token.isNotEmpty) return token;

      // 2) Firebase token
      final User? firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final String? firebaseToken = await firebaseUser.getIdToken();
        if (firebaseToken != null && firebaseToken.isNotEmpty) {
          await prefs.setString('firebase_token', firebaseToken);
          return firebaseToken;
        }
      }

      // 3) stored firebase token fallback
      final String? storedFirebaseToken = prefs.getString('firebase_token');
      if (storedFirebaseToken != null && storedFirebaseToken.isNotEmpty) {
        return storedFirebaseToken;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
  // Removed misplaced await Share.shareXFiles block which was syntactically incorrect here.
  // If sharing functionality is needed, place it inside a function or event handler.


  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'Just now';

    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      final unit = m == 1 ? 'min' : 'mins';
      return '$m $unit ago';
    }

    if (diff.inHours < 24) {
      final h = diff.inHours;
      final unit = h == 1 ? 'hr' : 'hrs';
      return '$h $unit ago';
    }

    if (diff.inDays < 7) {
      final d = diff.inDays;
      final unit = d == 1 ? 'day' : 'days';
      return '$d $unit ago';
    }

    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) {
      final unit = weeks == 1 ? 'week' : 'weeks';
      return '$weeks $unit ago';
    }

    final months = (diff.inDays / 30).floor();
    if (months < 12) {
      final unit = months == 1 ? 'month' : 'months';
      return '$months $unit ago';
    }

    final years = (diff.inDays / 365).floor();
    final unit = years == 1 ? 'year' : 'years';
    return '$years $unit ago';
  }

  int _stablePositiveIdFromString(String s) {
    int hash = 0;
    for (final code in s.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    if (hash == 0) hash = 1;
    return hash;
  }

  Future<List<MarketplaceDetailModel>> _loadAll({String? category}) async {
    setState(() {
      _loading = true;
      _photoMode = false;
      _selectedCategory = category;
    });
    try {
      QuerySnapshot? snapshot;
      try {
        snapshot = await _firestore
            .collection('marketplace_items')
            .orderBy('createdAt', descending: true)
            .get(const GetOptions(source: Source.cache));
        if (snapshot.docs.isNotEmpty) {
          final all = snapshot.docs
              .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
              .where((item) => item.isActive)
              .toList();

          if (category == null || category.isEmpty) {
            final result = _forYouMode
                ? await _rankByPersonalization(all)
                : await _sortByNewest(all);
            _setSuggestionsFromItems(result);
            return result;
          }

          final c = category.toLowerCase();
          final filtered = all.where((item) => item.category.toLowerCase() == c).toList();
          final result = _forYouMode
              ? await _rankByPersonalization(filtered)
              : await _sortByNewest(filtered);
          _setSuggestionsFromItems(result);
          return result;
        }
      } catch (_) {}
      try {
        snapshot = await _firestore
            .collection('marketplace_items')
            .orderBy('createdAt', descending: true)
            .get(const GetOptions(source: Source.server));
        final all = snapshot.docs
            .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
            .where((item) => item.isActive)
            .toList();

        if (category == null || category.isEmpty) {
          final result = _forYouMode
              ? await _rankByPersonalization(all)
              : await _sortByNewest(all);
          _setSuggestionsFromItems(result);
          return result;
        }

        final c = category.toLowerCase();
        final filtered = all.where((item) => item.category.toLowerCase() == c).toList();
        final result = _forYouMode
            ? await _rankByPersonalization(filtered)
            : await _sortByNewest(filtered);
        _setSuggestionsFromItems(result);
        return result;
      } catch (serverError) {
        final errorStr = serverError.toString().toLowerCase();
        final isNetworkError = errorStr.contains('unavailable') ||
            errorStr.contains('network') ||
            errorStr.contains('offline');
        if (isNetworkError && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('You are offline. Showing cached items if available.'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return [];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<MarketplaceDetailModel>> _searchByName(String raw) async {
    final q = raw.trim();
    unawaited(_trackSearchInterest(q));
    if (q.isEmpty || q.length < 2) {
      _aiSummary = '';
      return _loadAll(category: _selectedCategory);
    }
    setState(() {
      _loading = true;
      _photoMode = false;
    });
    try {
      final all = await _loadAll(category: _selectedCategory);
      final lower = q.toLowerCase();
      final words =
          lower.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
      List<MarketplaceDetailModel> matches;
      if (_aiSearchMode && words.length > 1) {
        matches = all.where((item) {
          final searchable =
              '${item.name} ${item.description ?? ''} ${item.category} ${item.location ?? ''}'
                  .toLowerCase();
          return words.every((w) => searchable.contains(w));
        }).toList();
      } else {
        matches = all.where((item) {
          final searchable =
              '${item.name} ${item.description ?? ''} ${item.category} ${item.location ?? ''}'
                  .toLowerCase();
          return searchable.contains(lower);
        }).toList();
      }
      if (_aiSearchMode && matches.isNotEmpty) {
        _aiSummary = _buildAiSummary(q, matches);
      } else {
        _aiSummary = '';
      }
      final result = _forYouMode
          ? await _rankByPersonalization(matches)
          : await _sortByNewest(matches);
      _setSuggestionsFromItems(result);
      return result;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _buildAiSummary(String query, List<MarketplaceDetailModel> items) {
    final catCounts = <String, int>{};
    for (final i in items) {
      final c = i.category.isEmpty ? 'other' : i.category;
      catCounts[c] = (catCounts[c] ?? 0) + 1;
    }
    final topCats = catCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final catsText =
        topCats.take(3).map((e) => _titleCase(e.key)).join(', ');
    final priceMin =
        items.map((i) => i.price).reduce((a, b) => a < b ? a : b);
    final priceMax =
        items.map((i) => i.price).reduce((a, b) => a > b ? a : b);
    return 'Found ${items.length} results for "$query" across ${topCats.length} categories${topCats.isNotEmpty ? ' ($catsText)' : ''}. Prices: MWK ${priceMin.toStringAsFixed(0)} – MWK ${priceMax.toStringAsFixed(0)}.';
  }

  String _getAiHighlight(MarketplaceDetailModel item) {
    final sb = StringBuffer();
    final rating = item.sellerRating ?? 0;
    if (rating >= 4.5) {
      sb.write('Top-rated seller');
    } else if (rating >= 4) {
      sb.write('Reliable seller');
    }
    if (sb.isNotEmpty && item.price > 0) sb.write(' · ');
    sb.write(_mwk(item.price));
    if ((item.description ?? '').toLowerCase().contains('new') ||
        (item.description ?? '').toLowerCase().contains('brand')) {
      if (sb.isNotEmpty) sb.write(' · ');
      sb.write('Like new');
    }
    return sb.toString().trim().isEmpty ? _mwk(item.price) : sb.toString();
  }

  core.MarketplaceDetailModel _toCoreDetailModel(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId
        ? item.sqlItemId!
        : _stablePositiveIdFromString(item.id);
    return core.MarketplaceDetailModel(
      id: id,
      name: item.name,
      category: item.category,
      price: item.price,
      image: item.image,
      description: item.description ?? '',
      location: item.location ?? '',
      comment: null,
      gallery: item.gallery,
      videos: const [],
      sellerBusinessName: item.sellerBusinessName,
      sellerOpeningHours: item.sellerOpeningHours,
      sellerStatus: item.sellerStatus,
      sellerBusinessDescription: item.sellerBusinessDescription,
      sellerRating: item.sellerRating,
      sellerLogoUrl: item.sellerLogoUrl,
      serviceProviderId: item.serviceProviderId,
      sellerUserId: item.sellerUserId,
      merchantId: item.merchantId,
      merchantName: item.merchantName,
      serviceType: item.serviceType ?? 'marketplace',
      createdAt: item.createdAt,
    );
  }

  void _openDetailsPage(MarketplaceDetailModel item) {
    unawaited(_trackInteraction(item, weight: 1.2));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsPage(
          item: _toCoreDetailModel(item),
          cartService: widget.cartService,
        ),
      ),
    );
  }

  MarketplaceDetailModel _fromCoreMarketplace(core.MarketplaceDetailModel c) {
    return MarketplaceDetailModel(
      id: c.id.toString(),
      sqlItemId: c.id,
      name: c.name,
      category: (c.category ?? '').toLowerCase(),
      price: c.price,
      image: c.image,
      imageBytes: null,
      description: c.description.isEmpty ? null : c.description,
      location: c.location.isEmpty ? null : c.location,
      isActive: true,
      createdAt: null,
      gallery: c.gallery,
      sellerBusinessName: c.sellerBusinessName,
      sellerOpeningHours: c.sellerOpeningHours,
      sellerStatus: c.sellerStatus,
      sellerBusinessDescription: c.sellerBusinessDescription,
      sellerRating: c.sellerRating,
      sellerLogoUrl: c.sellerLogoUrl,
      serviceProviderId: c.serviceProviderId,
      sellerUserId: c.sellerUserId,
      merchantId: c.merchantId,
      merchantName: c.merchantName,
      serviceType: c.serviceType ?? 'marketplace',
    );
  }

  Future<List<MarketplaceDetailModel>> _searchByPhoto(
      dynamic imageSource) async {
    setState(() {
      _loading = true;
      _photoMode = true;
      _selectedCategory = null;
      _aiSummary = '';
    });
    try {
      final Uint8List bytes;
      final String filename;
      if (imageSource is XFile) {
        bytes = await imageSource.readAsBytes();
        final path = imageSource.path.toLowerCase();
        filename = path.endsWith('.png')
            ? 'photo.png'
            : path.endsWith('.webp')
                ? 'photo.webp'
                : 'photo.jpg';
      } else if (imageSource is File) {
        bytes = await imageSource.readAsBytes();
        final path = imageSource.path.toLowerCase();
        filename = path.endsWith('.png')
            ? 'photo.png'
            : path.endsWith('.webp')
                ? 'photo.webp'
                : 'photo.jpg';
      } else {
        throw StateError('Invalid image source');
      }
      final service = MarketplaceService();
      final firebaseResults =
          await service.searchByPhotoBytes(bytes, filename: filename);
      final converted = firebaseResults.map(_fromCoreMarketplace).toList();
      if (mounted && converted.isNotEmpty) {
        _setSuggestionsFromItems(converted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Found ${converted.length} product${converted.length == 1 ? '' : 's'} from your photo search.',
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else if (mounted && converted.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'No visually similar products found. Showing all items.'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return _loadAll(category: null);
      }
      return converted;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Photo search error: $e\n$st');
      if (mounted) {
        final msg = e
            .toString()
            .replaceAll(RegExp(r'^Exception:?\s*'), '')
            .split('\n')
            .first;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNetwork
                  ? 'Cannot reach Firebase now.'
                  : 'Photo search failed: ${msg.length > 60 ? '${msg.substring(0, 60)}...' : msg}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return _loadAll(category: null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────
  // AUTH HELPERS
  // ─────────────────────────────────────────────
  Future<String?> _getCurrentUserId() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) return user.uid;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('uid');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isUserLoggedIn() async {
    final token = await AuthHandler.getTokenForApi();
    return token != null && token.isNotEmpty;
  }

  Future<bool> _requireLoginForCart() async {
    final isLoggedIn = await _isUserLoggedIn();
    if (!isLoggedIn && mounted) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to add items to cart.',
        isSuccess: false,
        errorMessage: '',
      );
    }
    return isLoggedIn;
  }

  Future<bool> _requireLoginForChat() async {
    final isLoggedIn = await _isUserLoggedIn();
    if (!isLoggedIn && mounted) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to chat with merchant.',
        isSuccess: false,
        errorMessage: '',
      );
    }
    return isLoggedIn;
  }

  // ─────────────────────────────────────────────
  // SHARING
  // ─────────────────────────────────────────────
  void _shareProductFromSheet(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId
        ? item.sqlItemId!
        : _stablePositiveIdFromString(item.id);
    final merchantName =
        item.merchantName ?? item.sellerBusinessName ?? 'A merchant';
    final productUrl = 'https://vero360.app/marketplace/$id';
    final priceStr =
        NumberFormat('#,###', 'en').format(item.price.truncate());
    Share.share(
      '$merchantName is selling this on Vero360 - Check out ${item.name} - MWK $priceStr\n$productUrl',
    );
  }

  void _copyProductLinkFromSheet(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId
        ? item.sqlItemId!
        : _stablePositiveIdFromString(item.id);
    Clipboard.setData(
        ClipboardData(text: 'https://vero360.app/marketplace/$id'));
    if (!mounted) return;
    ToastHelper.showCustomToast(
      context,
      'Product link copied',
      isSuccess: true,
      errorMessage: 'OK',
    );
  }

  // ─────────────────────────────────────────────
  // CART / CHECKOUT
  // ─────────────────────────────────────────────
  void _showQuickLoading(BuildContext context,
      {String text = 'Adding to cart...'}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: _kOrange),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(text,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}



Future<void> _addToCart(MarketplaceDetailModel item, {String? note}) async {
  final isLoggedIn = await _requireLoginForCart();
  if (!isLoggedIn) return;

  if (!item.hasValidMerchantInfo) {
    ToastHelper.showCustomToast(
      context,
      'This item cannot be added to cart: Missing merchant information.',
      isSuccess: false,
      errorMessage: 'Invalid merchant info',
    );
    return;
  }

  _showQuickLoading(context); // ✅ show loading immediately

  try {
    final userId = await _getCurrentUserId() ?? 'unknown';

    final int numericItemId = item.hasValidSqlItemId
        ? item.sqlItemId!
        : _stablePositiveIdFromString(item.id);

    final cartItem = CartModel(
      userId: userId,
      item: numericItemId,
      quantity: 1,
      image: item.image,
      name: item.name,
      price: item.price,
      description: item.description ?? '',
      merchantId: item.merchantId ?? 'unknown',
      merchantName: item.merchantName ?? 'Unknown Merchant',
      serviceType: item.serviceType ?? 'marketplace',
      comment: note,
    );

    await widget.cartService.addToCart(cartItem); // Firestore first = fast
    unawaited(_trackInteraction(item, weight: 3.0));

    if (mounted) Navigator.of(context).pop(); // ✅ close loading

    ToastHelper.showCustomToast(
      context,
      '${item.name} added to cart',
      isSuccess: true,
      errorMessage: 'OK',
    );
  } catch (e) {
    if (mounted) Navigator.of(context).pop(); // close loading

    ToastHelper.showCustomToast(
      context,
      'Failed to add item: $e',
      isSuccess: false,
      errorMessage: 'Add to cart failed',
    );
  }

  Future<void> _addToCart(MarketplaceDetailModel item, {String? note}) async {
    final isLoggedIn = await _requireLoginForCart();
    if (!isLoggedIn) return;
    if (!item.hasValidMerchantInfo) {
      ToastHelper.showCustomToast(
        context,
        'This item cannot be added to cart: Missing merchant information.',
        isSuccess: false,
        errorMessage: 'Invalid merchant info',
      );
      return;
    }
    _showQuickLoading(context);
    try {
      final userId = await _getCurrentUserId() ?? 'unknown';
      final int numericItemId = item.hasValidSqlItemId
          ? item.sqlItemId!
          : _stablePositiveIdFromString(item.id);
      final cartItem = CartModel(
        userId: userId,
        item: numericItemId,
        quantity: 1,
        image: item.image,
        name: item.name,
        price: item.price,
        description: item.description ?? '',
        merchantId: item.merchantId ?? 'unknown',
        merchantName: item.merchantName ?? 'Unknown Merchant',
        serviceType: item.serviceType ?? 'marketplace',
        comment: note,
      );
      await widget.cartService.addToCart(cartItem);
      if (mounted) Navigator.of(context).pop();
      ToastHelper.showCustomToast(
        context,
        '${item.name} added to cart',
        isSuccess: true,
        errorMessage: 'OK',
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ToastHelper.showCustomToast(
        context,
        'Failed to add item: $e',
        isSuccess: false,
        errorMessage: 'Add to cart failed',
      );
    }
  }

  Future<void> _openChatWithMerchant(MarketplaceDetailModel item) async {
    if (!await _requireLoginForChat()) return;
    final peerAppId =
        (item.serviceProviderId ?? item.sellerUserId ?? '').trim();
    if (peerAppId.isEmpty) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Seller chat unavailable',
        isSuccess: false,
        errorMessage: 'Seller id missing',
      );
      return;
    }
    final merchantName = (item.merchantName ?? '').trim();
    final sellerName = merchantName.isNotEmpty
        ? merchantName
        : ((item.sellerBusinessName ?? 'Seller').trim());
    final rawAvatar = (item.sellerLogoUrl ?? '').trim();
    final sellerAvatar = (await _toDownloadUrl(rawAvatar)) ?? rawAvatar;
    await ChatService.ensureFirebaseAuth();
    final me = await ChatService.myAppUserId();
    await ChatService.ensureThread(
      myAppId: me,
      peerAppId: peerAppId,
      peerName: sellerName,
      peerAvatar: sellerAvatar,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagePage(
          peerAppId: peerAppId,
          peerName: sellerName,
          peerAvatarUrl: sellerAvatar,
          peerId: '',
        ),
      ),
    );
  }

  Future<void> _goToCheckoutFromBottomSheet(MarketplaceDetailModel item) async {
    if (!mounted) return;
    final core.MarketplaceDetailModel checkoutItem = core.MarketplaceDetailModel(
      id: item.hasValidSqlItemId
          ? item.sqlItemId!
          : _stablePositiveIdFromString(item.id),
      name: item.name,
      category: item.category,
      price: item.price,
      image: item.image,
      description: item.description ?? '',
      location: item.location ?? '',
      gallery: item.gallery,
      sellerBusinessName: item.sellerBusinessName,
      sellerOpeningHours: item.sellerOpeningHours,
      sellerStatus: item.sellerStatus,
      sellerBusinessDescription: item.sellerBusinessDescription,
      sellerRating: item.sellerRating,
      sellerLogoUrl: item.sellerLogoUrl,
      serviceProviderId: item.serviceProviderId,
      sellerUserId: item.sellerUserId,
      merchantId: item.merchantId,
      merchantName: item.merchantName,
      serviceType: item.serviceType,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutPage(item: checkoutItem)),
    );
  }

  // ─────────────────────────────────────────────
  // SEARCH CALLBACKS
  // ─────────────────────────────────────────────
  void _onSearchChanged() {
    _debounce?.cancel();

    // If the user starts typing, immediately hide/stop suggestions.
    final typingNow = _searchCtrl.text.trim().isNotEmpty;
    if (typingNow) {
      _stopSuggestionTimer();
      setState(() {}); // trigger rebuild so the suggestion widget disappears right away
    } else {
      // Restart suggestions when the input is empty again (non-AI mode).
      if (!_aiSearchMode && _suggestionTimer == null) {
        _startSuggestionTimer();
      }
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      final txt = _searchCtrl.text;
      if (txt == _lastQuery) return;
      _lastQuery = txt;
      setState(() => _future = _searchByName(txt));
    });
  }

  void _onSubmit(String value) {
    _debounce?.cancel();
    setState(() => _future = _searchByName(value));
  }

  void _setCategory(String? cat) {
    unawaited(_trackCategoryInterest(cat));
    _searchCtrl.clear();
    _lastQuery = '';
    _aiSummary = '';
    setState(() => _future = _loadAll(category: cat));
  }

  Future<void> _showPhotoPickerSheet() async {
    if (kIsWeb) {
      await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1280);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Photo search works best in mobile builds.')),
      );
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Builder(
          builder: (sheetContext) {
            const brandOrange = Color(0xFFFF8A00);
            const brandBlue = Color(0xFF1E88E5);

            Widget sheetAction({
              required Color iconBg,
              required IconData icon,
              required String title,
              required VoidCallback onTap,
            }) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: iconBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF222222),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Search by Photo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF222222),
                    ),
                  ),
                  const SizedBox(height: 6),
                  sheetAction(
                    iconBg: brandOrange,
                    icon: Icons.camera_alt,
                    title: 'Use Camera',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final XFile? picked = await _picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 85,
                        maxWidth: 1280,
                      );
                      if (picked != null) {
                        final future = _searchByPhoto(picked);
                        if (!mounted) return;
                        setState(() => _future = future);
                      }
                    },
                  ),
                  sheetAction(
                    iconBg: brandBlue,
                    icon: Icons.photo_library,
                    title: 'Choose from Gallery',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final XFile? picked = await _picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
                        maxWidth: 1280,
                      );
                      if (picked != null) {
                        final future = _searchByPhoto(picked);
                        if (!mounted) return;
                        setState(() => _future = future);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    _searchCtrl.clear();
    _lastQuery = '';
    _aiSummary = '';
    _followedMerchantIdsFetchedAt =
        DateTime.fromMillisecondsSinceEpoch(0); // pick up new follows after visiting a shop
    setState(() => _future = _loadAll(category: _selectedCategory));
    await _future;
  }

  // ✅ Grid image widget (supports base64 + http + firebase + gallery fallback)
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

  /// ✅ FULL Details Bottom Sheet
  /// - Removes the left/right "bars" (no arrow overlays)
  /// - Auto-slides photos every 3 seconds
  /// - Still swipeable
  /// - No scrollbars / no glow
  Future<void> _showDetailsBottomSheet(MarketplaceDetailModel item) async {
    if (!mounted) return;

    final Future<_SellerInfo> sellerFuture = _loadSellerForItem(item);

    final List<String> mediaSources = [];
    if (item.image.trim().isNotEmpty) mediaSources.add(item.image.trim());
    if (item.gallery.isNotEmpty) {
      mediaSources.addAll(
        item.gallery.map((e) => e.toString().trim()).where((u) => u.isNotEmpty),
      );
    }

    final pageController = PageController();
    Timer? autoTimer;
    int currentPage = 0;
    bool autoStarted = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              // ✅ start auto-slide ONCE
              if (!autoStarted && mediaSources.length > 1) {
                autoStarted = true;
                autoTimer?.cancel();
                autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
                  if (!pageController.hasClients) return;
                  final next = (currentPage + 1) % mediaSources.length;
                  pageController.animateToPage(
                    next,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOut,
                  );
                  setModalState(() => currentPage = next);
                });
              }

              return ScrollConfiguration(
                behavior: const _NoBarsScrollBehavior(),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    ),
                    child: FutureBuilder<_SellerInfo>(
                      future: sellerFuture,
                      builder: (ctx, snap) {
                        final seller = snap.data;

                        final openingHours = seller?.openingHours;
                        final closing = _closingFromHours(openingHours);
                        final status = seller?.status;
                        final rating = seller?.rating;
                        final businessDesc = seller?.description;
                        final logo = seller?.logoUrl;

                        final merchantName = (item.merchantName ?? '').trim();
                        final displayMerchantName = merchantName.isNotEmpty
                            ? merchantName
                            : ((seller?.businessName ?? item.sellerBusinessName ?? '')
                                    .trim()
                                    .isNotEmpty
                                ? (seller?.businessName ?? item.sellerBusinessName)!.trim()
                                : 'Merchant');

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            // ✅ Media Area (NO BARS)
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: mediaSources.isEmpty
                                        ? _buildItemImageWidget(item)
                                        : PageView.builder(
                                            controller: pageController,
                                            itemCount: mediaSources.length,
                                            physics: mediaSources.length > 1
                                                ? const PageScrollPhysics()
                                                : const NeverScrollableScrollPhysics(),
                                            onPageChanged: (i) => setModalState(() => currentPage = i),
                                            itemBuilder: (_, i) {
                                              return _imageFromAnySource(
                                                mediaSources[i],
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                              );
                                            },
                                          ),
                                  ),
                                  if (mediaSources.length > 1)
                                    Positioned(
                                      right: 10,
                                      bottom: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.55),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${currentPage + 1}/${mediaSources.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Title + Price + Chat
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE8CC),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFFFF8A00)),
                                        ),
                                        child: Text(
                                          _mwk(item.price),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (item.location != null &&
                                          item.location!.trim().isNotEmpty)
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.location_on,
                                                size: 16, color: Colors.redAccent),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                item.location!,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (item.createdAt != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          "Posted by $displayMerchantName • ${_formatTimeAgo(item.createdAt!)}",
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF8A00),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  onPressed: () => _openChatWithMerchant(item),
                                  icon: const Icon(Icons.message_rounded),
                                  label: const Text('Chat'),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            if ((item.description ?? '').trim().isNotEmpty)
                              Text(
                                item.description!.trim(),
                                style: const TextStyle(fontSize: 14, height: 1.3),
                              ),

                            const SizedBox(height: 12),

                            // Share / Copy link actions
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.link),
                                    label: const Text('Copy link'),
                                    onPressed: () => _copyProductLinkFromSheet(item),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.share),
                                    label: const Text('Share'),
                                    onPressed: () => _shareProductFromSheet(item),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Seller Card
                            Card(
                              elevation: 4,
                              shadowColor: Colors.black12,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        if ((logo ?? '').trim().isNotEmpty)
                                          _circleAvatarFromAnySource(logo, radius: 18),
                                        if ((logo ?? '').trim().isNotEmpty) const SizedBox(width: 10),
                                        const Icon(Icons.storefront_rounded,
                                            size: 20, color: Colors.black87),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            displayMerchantName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _ratingStars(rating),
                                        const SizedBox(width: 8),
                                        _statusChip(status),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _infoRow('Business name', displayMerchantName,
                                        icon: Icons.badge_rounded),
                                    _infoRow('Closing hours', closing,
                                        icon: Icons.access_time_rounded),
                                    _infoRow(
                                      'Status',
                                      (status ?? '').isEmpty ? '—' : status!.toUpperCase(),
                                      icon: Icons.info_outline_rounded,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text('Business description',
                                        style: TextStyle(color: Colors.black54)),
                                    const SizedBox(height: 4),
                                    Text(
                                      (businessDesc ?? '').isNotEmpty ? businessDesc! : '—',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // View more from this merchant
                            if ((item.merchantId ?? '').trim().isNotEmpty) ...[
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.store_mall_directory_outlined,
                                  ),
                                  label: Text(
                                    'View more from $displayMerchantName',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(sheetCtx);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MerchantProductsPage(
                                          merchantId: item.merchantId!.trim(),
                                          merchantName: displayMerchantName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            const SizedBox(height: 4),

                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF8A00),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  _goToCheckoutFromBottomSheet(item);
                                },
                                icon: const Icon(Icons.shopping_bag_outlined),
                                label: const Text("Continue to checkout"),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      autoTimer?.cancel();
      pageController.dispose();
    });
  }

  Widget _buildSearchModeChip(String title, bool isAiMode) {
    final selected = _aiSearchMode == isAiMode;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _aiSearchMode = isAiMode;
          if (!isAiMode) _aiSummary = '';
          _future = _lastQuery.isNotEmpty
              ? _searchByName(_lastQuery)
              : _loadAll(category: _selectedCategory);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E88E5) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedModeChip() {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        _forYouMode = !_forYouMode;
        _future = _lastQuery.trim().isNotEmpty
            ? _searchByName(_lastQuery)
            : _loadAll(category: _selectedCategory);
      }),
      child: Chip(
        avatar: Icon(
          _forYouMode ? Icons.auto_awesome_rounded : Icons.schedule_rounded,
          size: 14,
          color: _forYouMode ? Colors.white : Colors.black87,
        ),
        label: Text(
          _forYouMode ? 'For You' : 'Newest',
          style: TextStyle(
            color: _forYouMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        backgroundColor: _forYouMode ? const Color(0xFFFF8A00) : Colors.grey[300],
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildCategoryChip(
    String title, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Chip(
        label: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        backgroundColor: isSelected ? Colors.orange : Colors.grey[300],
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildViewModeChip() {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _comfortableView = !_comfortableView),
      child: Chip(
        avatar: Icon(
          _comfortableView ? Icons.view_agenda_rounded : Icons.grid_view_rounded,
          size: 14,
          color: _comfortableView ? Colors.white : Colors.black87,
        ),
        label: Text(
          _comfortableView ? 'Comfortable' : 'Compact',
          style: TextStyle(
            color: _comfortableView ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        backgroundColor: _comfortableView ? const Color(0xFFFF8A00) : Colors.grey[300],
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildMarketItem(MarketplaceDetailModel item) {
    final screenW = MediaQuery.of(context).size.width;
    final isCompactPhone = screenW < 380;
    final cat = item.category.trim();
    final merchant = (item.merchantName ?? '').trim();
    final showCat = cat.isNotEmpty;
    final showMerchant = merchant.isNotEmpty && !isCompactPhone;
    final isSold = !item.isActive;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isCompactPhone ? 14 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: isCompactPhone ? 10 : 14,
            offset: Offset(0, isCompactPhone ? 4 : 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(isCompactPhone ? 14 : 16),
                    ),
                    child: ColorFiltered(
                      colorFilter: isSold
                          ? const ColorFilter.mode(Colors.black45, BlendMode.darken)
                          : const ColorFilter.mode(Colors.transparent, BlendMode.srcOver),
                      child: _buildItemImageWidget(item),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.06),
                            Colors.black.withOpacity(0.24),
                          ],
                          stops: const [0.5, 0.78, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showCat || showMerchant || isSold)
                  Positioned(
                    left: isCompactPhone ? 6 : 8,
                    right: isCompactPhone ? 6 : 8,
                    top: isCompactPhone ? 6 : 8,
                    child: Row(
                      children: [
                        if (showCat)
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _smallBadge(_titleCase(cat)),
                            ),
                          ),
                        if ((showCat && showMerchant) || (showCat && isSold) || (showMerchant && isSold))
                          SizedBox(width: isCompactPhone ? 6 : 8),
                        if (showMerchant)
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _smallBadge(merchant),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (isSold)
                  Positioned(
                    right: -30,
                    top: 12,
                    child: Transform.rotate(
                      angle: -0.7, // diagonal ribbon
                      child: Container(
                        width: 120,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.redAccent, Colors.deepOrange],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'SOLD',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Product info area (light orange/peach)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E6),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(isCompactPhone ? 14 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompactPhone ? 9 : 12,
                    isCompactPhone ? 8 : 10,
                    isCompactPhone ? 9 : 12,
                    isCompactPhone ? 4 : 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompactPhone ? 14 : 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.15,
                        ),
                      ),
                      if (_aiSearchMode && _lastQuery.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 12, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _getAiHighlight(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: isCompactPhone ? 2 : 3),
                      Text(
                        _mwk(item.price),
                        style: TextStyle(
                          fontSize: isCompactPhone ? 13 : 14.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFF8A00),
                        ),
                      ),
                      SizedBox(height: isCompactPhone ? 2 : 3),
                      if (item.location != null && item.location!.trim().isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on, size: isCompactPhone ? 11 : 12, color: Colors.grey.shade600),
                            SizedBox(width: isCompactPhone ? 3 : 4),
                            Expanded(
                              child: Text(
                                item.location!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: isCompactPhone ? 10 : 11, color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      if (item.createdAt != null)
                        Text(
                          _formatTimeAgo(item.createdAt!),
                          style: TextStyle(fontSize: isCompactPhone ? 10 : 11, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompactPhone ? 9 : 12,
                    0,
                    isCompactPhone ? 9 : 12,
                    isCompactPhone ? 9 : 11,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSold ? null : () => _addToCart(item),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF8A00),
                            side: const BorderSide(color: Color(0xFFFF8A00)),
                            padding: EdgeInsets.symmetric(vertical: isCompactPhone ? 9 : 10.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text("Add to Cart", style: TextStyle(fontSize: isCompactPhone ? 12 : 13)),
                        ),
                      ),
                      SizedBox(width: isCompactPhone ? 8 : 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSold ? null : () => _openDetailsPage(item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8A00),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(vertical: isCompactPhone ? 9 : 10.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            isSold ? 'Sold Out' : 'Buy Now',
                            style: TextStyle(fontSize: isCompactPhone ? 12 : 13),
                          ),
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
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : (s[0].toUpperCase() + s.substring(1));

  final TextEditingController _askQuestionCtrl = TextEditingController();
  bool _veroAiLoading = false;

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
    } finally {
      if (mounted) setState(() => _veroAiLoading = false);
    }
  }

  String _answerVeroAiQuestion(
      String question, List<MarketplaceDetailModel> items) {
    final q = question.toLowerCase().trim();
    if (items.isEmpty) {
      return 'There are no products to answer questions about. Try searching for something first.';
    }
    if (_matches(q, ['cheapest', 'lowest', 'cheap', 'budget', 'affordable', 'least expensive'])) {
      final sorted = List<MarketplaceDetailModel>.from(items)
        ..sort((a, b) => a.price.compareTo(b.price));
      final best = sorted.first;
      return 'The cheapest option is **${best.name}** at ${_mwk(best.price)}${best.location != null && best.location!.isNotEmpty ? ' from ${best.location}' : ''}.';
    }
    if (_matches(q, ['expensive', 'highest', 'most expensive', 'top price'])) {
      final sorted = List<MarketplaceDetailModel>.from(items)
        ..sort((a, b) => b.price.compareTo(a.price));
      final top = sorted.first;
      return 'The most expensive option is **${top.name}** at ${_mwk(top.price)}.';
    }
    if (_matches(q, ['best value', 'best deal', 'value for money', 'recommend', 'which one'])) {
      final scored = items.map((i) {
        final rating = (i.sellerRating ?? 0).clamp(0.0, 5.0);
        final score = rating > 0
            ? (rating / 5) * 100 - (i.price / 10000)
            : -i.price / 10000;
        return MapEntry(i, score);
      }).toList();
      scored.sort((a, b) => b.value.compareTo(a.value));
      final best = scored.first.key;
      final rating = best.sellerRating;
      return 'Based on price and seller rating, I recommend **${best.name}** at ${_mwk(best.price)}'
          '${rating != null && rating >= 4 ? ' (${_fmtRating(rating)}★ seller)' : ''}.';
    }
    if (_matches(q, ['price range', 'how much', 'cost', 'prices'])) {
      final prices = items.map((i) => i.price).toList();
      final min = prices.reduce((a, b) => a < b ? a : b);
      final max = prices.reduce((a, b) => a > b ? a : b);
      return 'Prices range from ${_mwk(min)} to ${_mwk(max)} across ${items.length} products.';
    }
    if (_matches(q, ['compare', 'comparison', 'difference'])) {
      if (items.length < 2) {
        return 'There\'s only one product. Try searching for more to compare.';
      }
      final top3 = items.take(3).toList();
      final sb = StringBuffer('Here\'s a quick comparison of the top results:\n\n');
      for (int i = 0; i < top3.length; i++) {
        final it = top3[i];
        sb.write('${i + 1}. **${it.name}** – ${_mwk(it.price)}');
        if (it.sellerRating != null)
          sb.write(' (${_fmtRating(it.sellerRating!)}★)');
        sb.writeln();
      }
      return sb.toString().trimRight();
    }
    if (_matches(q, ['categories', 'category', 'types', 'what kind'])) {
      final cats = <String, int>{};
      for (final i in items) {
        final c = i.category.isEmpty ? 'other' : i.category;
        cats[c] = (cats[c] ?? 0) + 1;
      }
      final list =
          cats.entries.map((e) => '${_titleCase(e.key)} (${e.value})').join(', ');
      return 'These products span ${cats.length} categories: $list.';
    }
    if (_matches(q, ['how many', 'count', 'number of', 'total'])) {
      return 'There are ${items.length} product${items.length == 1 ? '' : 's'} matching your search.';
    }
    if (_matches(q, ['where', 'location', 'locations', 'from where'])) {
      final locs = <String>{};
      for (final i in items) {
        if (i.location != null && i.location!.trim().isNotEmpty) {
          locs.add(i.location!.trim());
        }
      }
      if (locs.isEmpty) return 'Location details aren\'t available for these products.';
      return 'Sellers are from: ${locs.take(5).join(', ')}${locs.length > 5 ? ' and ${locs.length - 5} more' : ''}.';
    }
    return 'Based on the ${items.length} products you\'re viewing, prices range from '
        '${_mwk(items.map((i) => i.price).reduce((a, b) => a < b ? a : b))} to '
        '${_mwk(items.map((i) => i.price).reduce((a, b) => a > b ? a : b))}. '
        'Ask "cheapest?", "best value?", "compare", or "price range" for more specific answers.';
  }

  bool _matches(String q, List<String> keywords) =>
      keywords.any((k) => q.contains(k));

  void _showVeroAiAnswerSheet(String question, String answer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, -4)),
          ],
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('Vero AI',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: _kBlueBg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('Q: $question',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 14),
                SelectableText(answer.replaceAll('**', ''),
                    style: const TextStyle(fontSize: 15, height: 1.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.storefront_rounded,
              color: Color(0xFFFF8A00),
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              "Market Place",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Stack(
              children: [
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _onSubmit,
                  decoration: InputDecoration(
                    hintText: _aiSearchMode
                        ? "Search with Vero AI... (e.g. canon camera, phones)"
                        : '',
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.black54),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSubmit('');
                            },
                          ),
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: InkWell(
                            onTap: _showPhotoPickerSheet,
                            borderRadius: BorderRadius.circular(19),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF8A00),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFFF8A00), width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  ),
                ),

                // In-input sliding suggestions (only when search is empty & not in AI mode)
                if (!_aiSearchMode && _searchCtrl.text.trim().isEmpty)
                  Positioned(
                    left: 44,
                    right: 54,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 46,
                        child: Builder(
                          builder: (_) {
                            final suggestions = _activeSearchSuggestions;
                            if (suggestions.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final safeIndex = _suggestionIndex % suggestions.length;
                            final s = suggestions[safeIndex];

                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 380),
                              transitionBuilder: (child, anim) {
                                final beginOffset = const Offset(0, 0.9);
                                final tween = Tween<Offset>(begin: beginOffset, end: Offset.zero)
                                    .chain(CurveTween(curve: Curves.easeOut));
                                return SlideTransition(
                                  position: anim.drive(tween),
                                  child: child,
                                );
                              },
                              child: InkWell(
                                key: ValueKey<String>(s),
                                onTap: () {
                                  _debounce?.cancel();
                                  _searchCtrl.text = s;
                                  _searchCtrl.selection = TextSelection.fromPosition(
                                    TextPosition(offset: s.length),
                                  );
                                  _onSubmit(s);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                _buildSearchModeChip('All', false),
                const SizedBox(width: 6),
                _buildSearchModeChip('◆ VeroAI Search', true),
                const SizedBox(width: 6),
                _buildFeedModeChip(),
                const SizedBox(width: 6),
                _buildViewModeChip(),
              ],
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 36,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryChip(
                  "All Products",
                  isSelected: _selectedCategory == null && !_photoMode,
                  onTap: () => _setCategory(null),
                ),
                const SizedBox(width: 4),
                for (final c in _kCategories) ...[
                  _buildCategoryChip(
                    _titleCase(c),
                    isSelected: _selectedCategory == c,
                    onTap: () => _setCategory(c),
                  ),
                  child: FutureBuilder<_SellerInfo>(
                    future: sellerFuture,
                    builder: (ctx, snap) {
                      final seller = snap.data;
                      final closing =
                          _closingFromHours(seller?.openingHours);
                      final status = seller?.status;
                      final rating = seller?.rating;
                      final businessDesc = seller?.description;
                      final logo = seller?.logoUrl;
                      final merchantName =
                          (item.merchantName ?? '').trim();
                      final displayMerchantName =
                          merchantName.isNotEmpty
                              ? merchantName
                              : ((seller?.businessName ??
                                          item.sellerBusinessName ??
                                          '')
                                      .trim()
                                      .isNotEmpty
                                  ? (seller?.businessName ??
                                      item.sellerBusinessName)!.trim()
                                  : 'Merchant');

                      return Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius:
                                      BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;
                      final isWide = maxW >= 700;
                      final isNarrowPhone = maxW < 380;
                      final crossAxisCount = _comfortableView
                          ? (isWide ? 2 : 1)
                          : (isWide ? 3 : (isNarrowPhone ? 1 : 2));
                      final childAspectRatio = _comfortableView
                          ? (isWide ? 1.05 : 1.35)
                          : (isWide ? 0.70 : (isNarrowPhone ? 1.45 : 0.72));
                      final gridSpacing = isNarrowPhone ? 10.0 : 12.0;
                      final gridPadH = isNarrowPhone ? 10.0 : 12.0;

                      return CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (_aiSummary.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Container(
                                margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        size: 20, color: Colors.blue.shade700),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _aiSummary,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.4,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                              ),
                              if (mediaSources.length > 1)
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: Colors.black
                                            .withOpacity(0.55),
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: Text(
                                        '${currentPage + 1}/${mediaSources.length}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12)),
                                  ),
                                ),
                            ]),
                          ),
                          const SizedBox(height: 18),
                          // Title + Price + Chat
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: _kTextPrimary)),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _kOrangeSoft,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: _kOrange, width: 1),
                                      ),
                                      child: Text(_mwk(item.price),
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: _kOrange)),
                                    ),
                                    if (item.location != null &&
                                        item.location!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        const Icon(
                                            Icons.location_on_rounded,
                                            size: 14,
                                            color: Colors.redAccent),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(item.location!,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: _kTextSecondary)),
                                        ),
                                      ]),
                                    ],
                                    if (item.createdAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Posted by $displayMerchantName · ${_formatTimeAgo(item.createdAt!)}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: _kTextSecondary),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(gridPadH, 0, gridPadH, 12),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: gridSpacing,
                                mainAxisSpacing: gridSpacing,
                                childAspectRatio: childAspectRatio,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final item = items[i];
                                  return Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      splashColor: const Color(0x22FF8A00),
                                      highlightColor: const Color(0x11FF8A00),
                                      onTap: (!item.isActive) ? null : () => _openDetailsPage(item),
                                      child: _buildMarketItem(item),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _kOrange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16)),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15),
                              ),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _goToCheckoutFromBottomSheet(item);
                              },
                              icon: const Icon(
                                  Icons.shopping_bag_outlined),
                              label: const Text('Continue to checkout'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          }),
        );
      },
    ).whenComplete(() {
      autoTimer?.cancel();
      pageController.dispose();
    });
  }

  // ─────────────────────────────────────────────
  // UTILITIES
  // ─────────────────────────────────────────────
  String _titleCase(String s) =>
      s.isEmpty ? s : (s[0].toUpperCase() + s.substring(1));

  int _stablePositiveIdFromString(String s) {
    int hash = 0;
    for (final code in s.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    if (hash == 0) hash = 1;
    return hash;
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    if (diff.inHours < 24) return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '$weeks week${weeks == 1 ? '' : 's'} ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '$months month${months == 1 ? '' : 's'} ago';
    final years = (diff.inDays / 365).floor();
    return '$years year${years == 1 ? '' : 's'} ago';
  }

  // ─────────────────────────────────────────────
  // ITEM IMAGE WIDGET
  // ─────────────────────────────────────────────
  Widget _buildItemImageWidget(MarketplaceDetailModel item) {
    if (item.imageBytes != null) {
      return Image.memory(item.imageBytes!,
          fit: BoxFit.cover, width: double.infinity);
    }
    final mainImage = item.image.trim();
    final fallbackUrl =
        mainImage.isEmpty && item.gallery.isNotEmpty
            ? item.gallery.first.toString().trim()
            : null;
    return _imageFromAnySource(
      mainImage.isNotEmpty ? mainImage : (fallbackUrl ?? ''),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  // ─────────────────────────────────────────────
  // PRODUCT CARD
  // ─────────────────────────────────────────────
  Widget _buildMarketItem(MarketplaceDetailModel item) {
    final cat = item.category.trim();
    final merchant = (item.merchantName ?? '').trim();
    final isSold = !item.isActive;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: _kShadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Image area ──
          Expanded(
            flex: 54,
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: ColorFiltered(
                  colorFilter: isSold
                      ? const ColorFilter.mode(
                          Colors.black38, BlendMode.darken)
                      : const ColorFilter.mode(
                          Colors.transparent, BlendMode.srcOver),
                  child: _buildItemImageWidget(item),
                ),
              ),
              // Category badge
              if (cat.isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  child: _badge(_titleCase(cat)),
                ),
              // Merchant badge
              if (merchant.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _badge(merchant),
                ),
              // SOLD ribbon
              if (isSold)
                Positioned(
                  right: -28,
                  top: 14,
                  child: Transform.rotate(
                    angle: -0.7,
                    child: Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.redAccent, Colors.deepOrange],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 4,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Center(
                        child: Text('SOLD',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          // ── Info area ──
          Expanded(
            flex: 46,
            child: Container(
              decoration: const BoxDecoration(
                color: _kOrangeLight,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kTextPrimary)),
                  const SizedBox(height: 3),
                  // AI highlight
                  if (_aiSearchMode && _lastQuery.isNotEmpty) ...[
                    Row(children: [
                      const Icon(Icons.auto_awesome,
                          size: 11, color: _kOrange),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(_getAiHighlight(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10,
                                color: _kOrange,
                                fontWeight: FontWeight.w500)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                  ],
                  // Price
                  Text(_mwk(item.price),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kOrange)),
                  const SizedBox(height: 3),
                  // Location
                  if (item.location != null &&
                      item.location!.trim().isNotEmpty)
                    Row(children: [
                      Icon(Icons.location_on_rounded,
                          size: 11, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(item.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600)),
                      ),
                    ]),
                  // Time
                  if (item.createdAt != null)
                    Text(_formatTimeAgo(item.createdAt!),
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500)),
                  const Spacer(),
                  // Buttons
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: isSold ? null : () => _addToCart(item),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kOrange,
                            side: const BorderSide(color: _kOrange, width: 1.2),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Add',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed:
                              isSold ? null : () => _openDetailsPage(item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                              isSold ? 'Sold Out' : 'Buy',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoSlideImageCarousel extends StatefulWidget {
  const _AutoSlideImageCarousel({
    super.key,
    required this.sources,
    required this.itemBuilder,
    this.interval = const Duration(seconds: 3),
    this.showIndicators = false,
  });

  final List<String> sources;
  final Widget Function(String source) itemBuilder;
  final Duration interval;
  final bool showIndicators;

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
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.sources.length,
          physics: widget.sources.length > 1
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => widget.itemBuilder(widget.sources[i]),
        ),
        if (widget.showIndicators && widget.sources.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.sources.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: active ? 14 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFFF8A00) : Colors.white70,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.black26, width: 0.4),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}