// lib/Pages/marketPlace.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart' as core;

import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/utils/toasthelper.dart';

import 'package:vero360_app/Home/Messages.dart';
import 'package:vero360_app/GernalServices/chat_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/serviceprovider_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/serviceprovider_model.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';

/// ✅ Removes scrollbars + glow everywhere inside bottom-sheet
class _NoBarsScrollBehavior extends MaterialScrollBehavior {
  const _NoBarsScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

/// --------------------
/// Local marketplace model (Firestore)
/// --------------------
class MarketplaceDetailModel {
  final String id;
  final int? sqlItemId;

  final String name;
  final String category;
  final double price;

  /// Can be:
  /// - base64 string (old)
  /// - http(s) url
  /// - gs://... firebase storage url
  /// - firebase storage path like "marketplace_items/abc.jpg"
  final String image;

  /// Only used when `image` is base64 and decodes successfully
  final Uint8List? imageBytes;

  final String? description;
  final String? location;
  final bool isActive;
  final DateTime? createdAt;

  // Merchant fields
  final String? merchantId;
  final String? merchantName;
  final String? serviceType;

  // gallery can contain http / gs:// / firebase paths
  final List<String> gallery;

  // Seller/business meta
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

    final rawImage = (data['image'] ?? '').toString().trim();

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

    List<String> gallery = const [];
    final galleryRaw = data['gallery'];
    if (galleryRaw is List) {
      gallery = galleryRaw.map((e) => e.toString()).toList();
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
      description:
          data['description'] == null ? null : data['description'].toString(),
      location: data['location'] == null ? null : data['location'].toString(),
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
      const Icon(Icons.star, size: 16, color: Colors.amber),
    if (hasHalf) const Icon(Icons.star_half, size: 16, color: Colors.amber),
    for (int i = 0; i < empty; i++)
      const Icon(Icons.star_border, size: 16, color: Colors.amber),
    const SizedBox(width: 6),
    Text(_fmtRating(rr), style: const TextStyle(fontWeight: FontWeight.w600)),
  ]);
}

Widget _infoRow(String label, String? value, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            (value ?? '').isNotEmpty ? value! : '—',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Widget _statusChip(String? status) {
  final s = (status ?? '').toLowerCase().trim();
  Color bg = Colors.grey.shade200;
  Color fg = Colors.black87;

  if (s == 'open') {
    bg = Colors.green.shade50;
    fg = Colors.green.shade700;
  } else if (s == 'closed') {
    bg = Colors.red.shade50;
    fg = Colors.red.shade700;
  } else if (s == 'busy') {
    bg = Colors.orange.shade50;
    fg = Colors.orange.shade800;
  }

  return Chip(
    label: Text((status ?? '—').toUpperCase()),
    backgroundColor: bg,
    labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w700),
    visualDensity: VisualDensity.compact,
  );
}

/// --------------------
/// Market Page
/// --------------------
class MarketPage extends StatefulWidget {
  final CartService cartService;
  const MarketPage({required this.cartService, Key? key}) : super(key: key);

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ MWK formatter (commas, no decimals)
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
  String _lastQuery = '';
  bool _loading = false;
  bool _photoMode = false;

  /// AI Search mode: when true, shows AI summary, product highlights, and smarter search
  bool _aiSearchMode = true;

  late Future<List<MarketplaceDetailModel>> _future;

  /// AI summary text (generated from results). Empty when not in AI mode or no query.
  String _aiSummary = '';

  // ✅ Cache firebase download URLs to avoid repeated calls
  final Map<String, Future<String>> _dlUrlCache = {};

  bool _isHttp(String s) => s.startsWith('http://') || s.startsWith('https://');
  bool _isGs(String s) => s.startsWith('gs://');

  bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.isEmpty) return false;
    // Allow shorter encoded images as well; URLs/storage paths contain characters
    // like ':' and '/' so they will fail this charset check.
    return x.length >= 40 &&
        RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  Future<String?> _toFirebaseDownloadUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (_isHttp(s)) return s;

    if (_dlUrlCache.containsKey(s)) return _dlUrlCache[s]!.then((v) => v);

    Future<String> fut() async {
      if (_isGs(s)) {
        return FirebaseStorage.instance.refFromURL(s).getDownloadURL();
      }
      return FirebaseStorage.instance.ref(s).getDownloadURL();
    }

    _dlUrlCache[s] = fut();
    try {
      return await _dlUrlCache[s]!;
    } catch (_) {
      return null;
    }
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
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_rounded),
      ));
    }

    // base64
    if (_looksLikeBase64(s)) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        return wrap(Image.memory(bytes, fit: fit, width: width, height: height));
      } catch (_) {}
    }

    // http(s)
    if (_isHttp(s)) {
      return wrap(Image.network(
        s,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        ),
        loadingBuilder: (c, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
      ));
    }

    // firebase gs:// or storage path
    return FutureBuilder<String?>(
      future: _toFirebaseDownloadUrl(s),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return wrap(Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_rounded),
          ));
        }
        return wrap(Image.network(
          url,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, __, ___) => Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_rounded),
          ),
        ));
      },
    );
  }

  Widget _circleAvatarFromAnySource(String? raw, {double radius = 18}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade200,
        child: const Icon(Icons.storefront_rounded, color: Colors.black54),
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
      future: _toFirebaseDownloadUrl(s),
      builder: (_, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey.shade200,
            child: const Icon(Icons.storefront_rounded, color: Colors.black54),
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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _askQuestionCtrl.dispose();
    super.dispose();
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

      // cache first
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

          if (category == null || category.isEmpty) return all;

          final c = category.toLowerCase();
          return all.where((item) => item.category.toLowerCase() == c).toList();
        }
      } catch (_) {}

      // server second
      try {
        snapshot = await _firestore
            .collection('marketplace_items')
            .orderBy('createdAt', descending: true)
            .get(const GetOptions(source: Source.server));

        final all = snapshot.docs
            .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
            .where((item) => item.isActive)
            .toList();

        if (category == null || category.isEmpty) return all;

        final c = category.toLowerCase();
        return all.where((item) => item.category.toLowerCase() == c).toList();
      } catch (serverError) {
        final errorStr = serverError.toString().toLowerCase();
        final isNetworkError = errorStr.contains('unavailable') ||
            errorStr.contains('network') ||
            errorStr.contains('offline');

        if (isNetworkError && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'You are offline. Showing cached items if available.'),
              backgroundColor: Colors.orange,
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

  /// Smarter search: matches name, description, category, location.
  /// In AI mode: also uses word splitting for better relevance.
  Future<List<MarketplaceDetailModel>> _searchByName(String raw) async {
    final q = raw.trim();
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
      final words = lower.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();

      List<MarketplaceDetailModel> matches;
      if (_aiSearchMode && words.length > 1) {
        matches = all.where((item) {
          final name = item.name.toLowerCase();
          final desc = (item.description ?? '').toLowerCase();
          final cat = item.category.toLowerCase();
          final loc = (item.location ?? '').toLowerCase();
          final searchable = '$name $desc $cat $loc';
          return words.every((w) => searchable.contains(w));
        }).toList();
      } else {
        matches = all.where((item) {
          final name = item.name.toLowerCase();
          final desc = (item.description ?? '').toLowerCase();
          final cat = item.category.toLowerCase();
          final loc = (item.location ?? '').toLowerCase();
          final searchable = '$name $desc $cat $loc';
          return searchable.contains(lower);
        }).toList();
      }

      if (_aiSearchMode && matches.isNotEmpty) {
        _aiSummary = _buildAiSummary(q, matches);
      } else {
        _aiSummary = '';
      }
      return matches;
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
    final catsText = topCats.take(3).map((e) => _titleCase(e.key)).join(', ');
    final priceMin = items.map((i) => i.price).reduce((a, b) => a < b ? a : b);
    final priceMax = items.map((i) => i.price).reduce((a, b) => a > b ? a : b);
    return 'Based on your search for "$query", I found ${items.length} relevant products across ${topCats.length} categories${topCats.isNotEmpty ? ' ($catsText)' : ''}. Prices range from MWK ${priceMin.toStringAsFixed(0)} to MWK ${priceMax.toStringAsFixed(0)}. Here are the best matches for you.';
  }

  /// AI highlight for a product (heuristic, ready to swap for real AI later).
  String _getAiHighlight(MarketplaceDetailModel item) {
    final sb = StringBuffer();
    final rating = item.sellerRating ?? 0;
    if (rating >= 4.5) sb.write('Top-rated seller');
    else if (rating >= 4) sb.write('Reliable seller');
    if (sb.isNotEmpty && item.price > 0) sb.write(' • ');
    sb.write(_mwk(item.price));
    if ((item.description ?? '').toLowerCase().contains('new') ||
        (item.description ?? '').toLowerCase().contains('brand')) {
      if (sb.isNotEmpty) sb.write(' • ');
      sb.write('Like new');
    }
    if ((item.description ?? '').toLowerCase().contains('free ship') ||
        (item.description ?? '').toLowerCase().contains('delivery')) {
      if (sb.isNotEmpty) sb.write(' • ');
      sb.write('Fast delivery');
    }
    return sb.toString().trim().isEmpty ? _mwk(item.price) : sb.toString();
  }

  Future<List<MarketplaceDetailModel>> _searchByPhoto(File file) async {
    setState(() {
      _loading = true;
      _photoMode = true;
      _selectedCategory = null;
    });
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Photo search not implemented yet. Showing all items.'),
          ),
        );
      }
      return _loadAll(category: null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Logged in = we have a token the cart/API can use (same source as CartService).
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
        errorMessage: 'Not logged in',
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
        errorMessage: 'Not logged in',
      );
    }
    return isLoggedIn;
  }

  void _shareProductFromSheet(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId
        ? item.sqlItemId!
        : _stablePositiveIdFromString(item.id);
    final productUrl = 'https://vero360.app/marketplace/$id';
    Share.share(
      'Check out ${item.name} on Vero360 - MWK ${item.price.toStringAsFixed(0)}\n$productUrl',
    );
  }

  void _copyProductLinkFromSheet(MarketplaceDetailModel item) {
    final id = item.hasValidSqlItemId
        ? item.sqlItemId!
        : _stablePositiveIdFromString(item.id);
    final productUrl = 'https://vero360.app/marketplace/$id';
    Clipboard.setData(ClipboardData(text: productUrl));
    if (!mounted) return;
    ToastHelper.showCustomToast(
      context,
      'Product link copied',
      isSuccess: true,
      errorMessage: 'OK',
    );
  }

void _showQuickLoading(BuildContext context, {String text = 'Adding to cart...'}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
}

  Future<void> _openChatWithMerchant(MarketplaceDetailModel item) async {
    if (!await _requireLoginForChat()) return;

    final peerAppId = (item.serviceProviderId ?? item.sellerUserId ?? '').trim();
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
    final sellerAvatar = (await _toFirebaseDownloadUrl(rawAvatar)) ?? rawAvatar;

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

  void _onSearchChanged() {
    _debounce?.cancel();
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
    _searchCtrl.clear();
    _lastQuery = '';
    _aiSummary = '';
    setState(() => _future = _loadAll(category: cat));
  }

  Future<void> _showPhotoPickerSheet() async {
    if (kIsWeb) {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (picked == null) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo search works best in mobile builds.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Use Camera'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? picked = await _picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 85,
                  maxWidth: 1280,
                );
                if (picked != null) {
                  final file = File(picked.path);
                  setState(() => _future = _searchByPhoto(file));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? picked = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                  maxWidth: 1280,
                );
                if (picked != null) {
                  final file = File(picked.path);
                  setState(() => _future = _searchByPhoto(file));
                }
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    _searchCtrl.clear();
    _lastQuery = '';
    _aiSummary = '';
    setState(() => _future = _loadAll(category: _selectedCategory));
    await _future;
  }

  // ✅ Grid image widget (supports base64 + http + firebase)
  Widget _buildItemImageWidget(MarketplaceDetailModel item) {
    if (item.imageBytes != null) {
      return Image.memory(item.imageBytes!, fit: BoxFit.cover, width: double.infinity);
    }
    return _imageFromAnySource(
      item.image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E88E5) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
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
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isSelected ? Colors.orange : Colors.grey[300],
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }

  Widget _buildMarketItem(MarketplaceDetailModel item) {
    final cat = item.category.trim();
    final merchant = (item.merchantName ?? '').trim();
    final showCat = cat.isNotEmpty;
    final showMerchant = merchant.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
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
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                    child: _buildItemImageWidget(item),
                  ),
                ),
                if (showCat || showMerchant)
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 8,
                    child: Row(
                      children: [
                        if (showCat)
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _smallBadge(_titleCase(cat)),
                            ),
                          ),
                        if (showCat && showMerchant) const SizedBox(width: 8),
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
              ],
            ),
          ),

          // Texts
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                if (_aiSearchMode && _lastQuery.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: Colors.blue.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _getAiHighlight(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _mwk(item.price),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                if (item.location != null && item.location!.trim().isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 12, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                if (item.createdAt != null)
                  Text(
                    _formatTimeAgo(item.createdAt!),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _addToCart(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("AddCart"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showDetailsBottomSheet(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("BuyNow"),
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

  void _onAskQuestionSubmitted() {
    final q = _askQuestionCtrl.text.trim();
    if (q.isEmpty) return;
    _askQuestionCtrl.clear();
    if (!mounted) return;
    ToastHelper.showCustomToast(
      context,
      'AI chat coming soon! Ask questions like "Compare these products" or "Best value?"',
      isSuccess: true,
      errorMessage: 'Vero AI',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          "Market Place",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmit,
              decoration: InputDecoration(
                hintText: _aiSearchMode
                    ? "Search with Vero AI... (e.g. canon camera, budget phone)"
                    : "Search items...",
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
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined),
                      onPressed: _showPhotoPickerSheet,
                      tooltip: 'Search by Photo',
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
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              children: [
                _buildSearchModeChip('All', false),
                const SizedBox(width: 8),
                _buildSearchModeChip('◆ VeroAI Search', true),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryChip(
                  "All Products",
                  isSelected: _selectedCategory == null && !_photoMode,
                  onTap: () => _setCategory(null),
                ),
                const SizedBox(width: 6),
                for (final c in _kCategories) ...[
                  _buildCategoryChip(
                    _titleCase(c),
                    isSelected: _selectedCategory == c,
                    onTap: () => _setCategory(c),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          if (_photoMode)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.image_search, size: 16),
                  SizedBox(width: 6),
                  Text("Showing results from photo search"),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<MarketplaceDetailModel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (_loading &&
                      snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text("Failed to load items",
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    );
                  }

                  final items = snapshot.data ?? const <MarketplaceDetailModel>[];
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _photoMode
                                ? "No visually similar items found"
                                : "No items available",
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 700;
                      final crossAxisCount = isWide ? 3 : 2;
                      final childAspectRatio = isWide ? 0.70 : 0.68;

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
                                  ],
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: childAspectRatio,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final item = items[i];
                                  return GestureDetector(
                                    onTap: () => _showDetailsBottomSheet(item),
                                    child: _buildMarketItem(item),
                                  );
                                },
                                childCount: items.length,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          if (_aiSearchMode)
            Container(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _askQuestionCtrl,
                      onSubmitted: (_) => _onAskQuestionSubmitted(),
                      decoration: InputDecoration(
                        hintText: 'Ask Vero AI a question about your search...',
                        hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _onAskQuestionSubmitted,
                    icon: const Icon(Icons.send_rounded, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
