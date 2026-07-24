import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_detail_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as marketplaceModel;
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_reviews_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

int? _stayListingApiId(Map<String, dynamic> d) {
  final direct = d['apiAccommodationId'];
  if (direct is int) return direct;
  if (direct is num) return direct.toInt();
  final id = d['id'];
  if (id is int && id > 0) return id;
  if (id is String) {
    final p = int.tryParse(id);
    if (p != null && p > 0) return p;
  }
  return null;
}

class _MerchantShopHeaderCache {
  final String? profileUrl;
  final String? email;
  final String? phone;
  final String? status;
  final double? rating;
  final int reviewCount;
  final int followerCount;
  final int? backendId;
  final List<MerchantReview> recentReviews;

  const _MerchantShopHeaderCache({
    required this.profileUrl,
    required this.email,
    required this.phone,
    required this.status,
    required this.rating,
    required this.reviewCount,
    required this.followerCount,
    required this.backendId,
    required this.recentReviews,
  });
}

class MerchantProductsPage extends StatefulWidget {
  final String merchantId;
  final String merchantName;

  const MerchantProductsPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
  });

  @override
  State<MerchantProductsPage> createState() => _MerchantProductsPageState();
}

class _MerchantProductsPageState extends State<MerchantProductsPage> {
  final _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late Future<List<MarketplaceDetailModel>> _future;
  late Future<List<_MerchantStayPreview>> _staysFuture;
  final CartService _cartService =
      CartService('unused', apiPrefix: ApiConfig.apiPrefix);

  /// null while detecting — show products immediately (common case).
  bool? _isAccommodationHost;

  double? _merchantRating;
  int _merchantReviewCount = 0;
  int? _merchantBackendId;
  List<MerchantReview> _recentReviews = const [];
  List<MerchantReview> _cachedReviews = const [];
  MerchantReviewSummary? _cachedReviewSummary;
  String? _merchantStatus;
  String? _merchantProfileUrl;
  String? _merchantEmail;
  String? _merchantPhone;
  bool _loadingHeader = true;
  bool _following = false;
  int _followerCount = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Brand color to match main marketplace UI
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _pageBg = Color(0xFFF4F6FA);
  static const Color _surfaceBorder = Color(0xFFE2E6EF);

  /// Instant re-open of the same shop.
  static final Map<String, List<MarketplaceDetailModel>> _itemsMemCache = {};
  static final Map<String, bool> _accommodationMemCache = {};
  static final Map<String, _MerchantShopHeaderCache> _headerMemCache = {};

  // Small cache for Firebase download URLs (gs:// or storage paths)
  final Map<String, Future<String?>> _dlUrlCache = {};

  bool _reviewsLoading = false;

  bool _isHttp(String s) => s.startsWith('http://') || s.startsWith('https://');
  bool _isGs(String s) => s.startsWith('gs://');

  /// Prefer local cache so first paint is not blocked on network.
  Future<QuerySnapshot<Map<String, dynamic>>> _queryFast(
    Query<Map<String, dynamic>> q,
  ) async {
    try {
      final cached = await q.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        unawaited(q.get(const GetOptions(source: Source.serverAndCache)));
        return cached;
      }
    } catch (_) {}
    return q.get(const GetOptions(source: Source.serverAndCache));
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _docFast(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        unawaited(ref.get(const GetOptions(source: Source.serverAndCache)));
        return cached;
      }
    } catch (_) {}
    return ref.get(const GetOptions(source: Source.serverAndCache));
  }

  bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.isEmpty) return false;
    return x.length >= 40 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  bool _isRelativePath(String s) =>
      s.isNotEmpty && !s.contains('://') && !_looksLikeBase64(s);

  Widget _profileImageFromAnySource(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.storefront_rounded, size: 56, color: Colors.grey),
      );
    }
    if (_looksLikeBase64(s)) {
      try {
        final base64Part = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Part);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 56),
        );
      } catch (_) {}
    }
    if (_isHttp(s)) {
      return Image.network(
        s,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, size: 56),
      );
    }
    return FutureBuilder<String?>(
      future: _toDownloadUrl(s),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null || u.isEmpty) {
          return const Icon(Icons.broken_image_outlined, size: 56);
        }
        return Image.network(
          u,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined, size: 56),
        );
      },
    );
  }

  void _showMerchantProfileViewer() {
    final raw = (_merchantProfileUrl ?? '').trim();
    if (raw.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.6,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: double.infinity,
                  child: _profileImageFromAnySource(raw),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _backendUrlForPath(String path) async {
    final base = await ApiConfig.readBase();
    final baseNorm = base.endsWith('/') ? base : '$base/';
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$baseNorm$p';
  }

  /// Same logic as main_marketPlace.dart: gs://, storage path, backend-relative fallback
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

  /// Same as main_marketPlace: base64, http(s), gs://, storage path, backend-relative
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
          return wrap(Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_rounded),
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

  /// Match main marketplace: imageBytes, main image, gallery fallback
  Widget buildItemImage(MarketplaceDetailModel item) {
    if (item.imageBytes != null) {
      return Image.memory(
        item.imageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    final mainImage = item.image.trim();
    final fallbackUrl = mainImage.isEmpty && item.gallery.isNotEmpty
        ? item.gallery.first.toString().trim()
        : null;
    return _imageFromAnySource(
      mainImage.isNotEmpty ? mainImage : (fallbackUrl ?? ''),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  /// Build image for a single source. Used by carousel.
  Widget buildImageForSource(String source) {
    return _imageFromAnySource(
      source.trim(),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  void initState() {
    super.initState();
    final id = widget.merchantId.trim();
    final memItems = _itemsMemCache[id];
    if (memItems != null) {
      _future = Future.value(memItems);
      // Refresh quietly in background.
      unawaited(_loadMerchantItems().then((fresh) {
        if (!mounted) return;
        setState(() => _future = Future.value(fresh));
      }));
    } else {
      _future = _loadMerchantItems();
    }

    final memAccom = _accommodationMemCache[id];
    if (memAccom != null) {
      _isAccommodationHost = memAccom;
    }

    final memHeader = _headerMemCache[id];
    if (memHeader != null) {
      _merchantProfileUrl = memHeader.profileUrl;
      _merchantEmail = memHeader.email;
      _merchantPhone = memHeader.phone;
      _merchantStatus = memHeader.status;
      _merchantRating = memHeader.rating;
      _merchantReviewCount = memHeader.reviewCount;
      _followerCount = memHeader.followerCount;
      _merchantBackendId = memHeader.backendId;
      _recentReviews = memHeader.recentReviews;
      _loadingHeader = false;
      final bid = memHeader.backendId;
      if (bid != null) {
        final warm = MerchantReviewService.peekCache(bid);
        if (warm != null) {
          _cachedReviewSummary = warm.summary;
          _cachedReviews = warm.reviews;
          _recentReviews = warm.reviews.take(3).toList();
          _merchantRating = warm.summary.average;
          _merchantReviewCount = warm.summary.count;
        }
      }
    }

    _staysFuture = _loadMerchantStays();
    unawaited(_resolveAccommodationMode());
    unawaited(_loadMerchantHeader());
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  void _persistHeaderCache() {
    _headerMemCache[widget.merchantId.trim()] = _MerchantShopHeaderCache(
      profileUrl: _merchantProfileUrl,
      email: _merchantEmail,
      phone: _merchantPhone,
      status: _merchantStatus,
      rating: _merchantRating,
      reviewCount: _merchantReviewCount,
      followerCount: _followerCount,
      backendId: _merchantBackendId,
      recentReviews: List<MerchantReview>.from(_recentReviews),
    );
  }

  int? _parseBackendIdFromMap(Map<String, dynamic> data) {
    for (final key in [
      'backendUserId',
      'userId',
      'merchantUserId',
      'ownerId',
      'sellerUserId',
      'sqlUserId',
    ]) {
      final raw = data[key];
      if (raw is int && raw > 0) return raw;
      if (raw is num && raw.toInt() > 0) return raw.toInt();
      final p = int.tryParse('${raw ?? ''}'.trim());
      if (p != null && p > 0) return p;
    }
    return null;
  }

  void _applyRatingFieldsFromMap(Map<String, dynamic> data) {
    final rating = data['rating'] ??
        data['averageRating'] ??
        data['avgRating'] ??
        data['merchantRating'];
    if (rating is num) _merchantRating = rating.toDouble();

    final count = data['reviewCount'] ??
        data['reviewsCount'] ??
        data['ratingCount'] ??
        data['totalReviews'];
    if (count is num) _merchantReviewCount = count.toInt();
  }

  Future<void> _resolveAccommodationMode() async {
    final v = await _detectAccommodationMerchant();
    _accommodationMemCache[widget.merchantId.trim()] = v;
    if (!mounted) return;
    if (_isAccommodationHost != v) {
      setState(() => _isAccommodationHost = v);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// True for accommodation hosts: `accommodation_merchants` doc and/or `accommodation_rooms` rows.
  Future<bool> _detectAccommodationMerchant() async {
    final id = widget.merchantId.trim();
    if (id.isEmpty) return false;
    try {
      final results = await Future.wait([
        _docFast(_firestore.collection('accommodation_merchants').doc(id)),
        _queryFast(
          _firestore
              .collection('accommodation_rooms')
              .where('merchantId', isEqualTo: id)
              .limit(1),
        ),
      ]);
      final doc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      if (doc.exists) return true;
      final rooms = results[1] as QuerySnapshot<Map<String, dynamic>>;
      if (rooms.docs.isNotEmpty) return true;
    } catch (e) {
      debugPrint('detect accommodation: $e');
    }
    return false;
  }

  Future<List<MarketplaceDetailModel>> _loadMerchantItems() async {
    try {
      final String id = widget.merchantId.trim();
      final String name = widget.merchantName.trim();

      // 1) Try match by merchantId (cache-first)
      final idSnap = await _queryFast(
        _firestore
            .collection('marketplace_items')
            .where('merchantId', isEqualTo: id),
      );

      var docs = idSnap.docs;

      // 2) Fallback: older items may only have merchantName
      if (docs.isEmpty && name.isNotEmpty) {
        final nameSnap = await _queryFast(
          _firestore
              .collection('marketplace_items')
              .where('merchantName', isEqualTo: name),
        );
        docs = nameSnap.docs;
      }

      final all = docs
          .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
          .where((item) => item.isActive)
          .toList();

      all.sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      _itemsMemCache[id] = all;
      return all;
    } catch (e) {
      debugPrint('Error loading merchant items: $e');
      return _itemsMemCache[widget.merchantId.trim()] ?? [];
    }
  }

  Future<List<_MerchantStayPreview>> _loadMerchantStays() async {
    final id = widget.merchantId.trim();
    final merged = <_MerchantStayPreview>[];
    final apiIds = <int>{};

    // Resolve email from likely sources in parallel.
    var email = '';
    try {
      final snaps = await Future.wait([
        _docFast(_firestore.collection('users').doc(id)),
        _docFast(_firestore.collection('marketplace_merchants').doc(id)),
        _docFast(_firestore.collection('accommodation_merchants').doc(id)),
      ]);
      for (final snap in snaps) {
        final d = snap.data();
        if (d == null) continue;
        final e = (d['email'] ?? d['userEmail'] ?? '').toString().trim();
        if (e.isNotEmpty) {
          email = e;
          break;
        }
      }
    } catch (_) {}

    // Firestore rooms + optional API ownership in parallel.
    final roomsFuture = _queryFast(
      _firestore
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: id),
    );

    Future<List<_MerchantStayPreview>> apiFuture() async {
      if (email.isEmpty) return const [];
      try {
        final mine = await AccommodationService().fetchOwnedByEmail(email);
        final out = <_MerchantStayPreview>[];
        for (final a in mine) {
          apiIds.add(a.id);
          final preview = _MerchantStayPreview.fromAccommodation(a);
          if (!preview.isDummyListing) out.add(preview);
        }
        return out;
      } catch (e) {
        debugPrint('Merchant stays (API): $e');
        return const [];
      }
    }

    final results = await Future.wait([roomsFuture, apiFuture()]);
    final fromApi = results[1] as List<_MerchantStayPreview>;
    merged.addAll(fromApi);

    try {
      final fs = results[0] as QuerySnapshot<Map<String, dynamic>>;
      for (final doc in fs.docs) {
        final d = doc.data();
        final pid = _stayListingApiId(d);
        if (pid != null && apiIds.contains(pid)) continue;
        final preview = _MerchantStayPreview.fromFirestore(doc.id, d);
        if (!preview.isDummyListing) {
          merged.add(preview);
        }
      }
    } catch (e) {
      debugPrint('Merchant stays (Firestore): $e');
    }

    merged.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return merged;
  }

  void _showStayPreviewSheet(_MerchantStayPreview stay) {
    final sources = stay.imageSources;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: sources.length <= 1
                    ? _imageFromAnySource(
                        sources.isEmpty ? '' : sources.first,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : PageView.builder(
                        itemCount: sources.length,
                        itemBuilder: (_, i) => _imageFromAnySource(
                          sources[i],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              stay.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            if (stay.location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 20, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stay.location,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    stay.typeLabel.isEmpty ? 'Stay' : stay.typeLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: _brandOrange.withValues(alpha: 0.12),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    'MWK ${NumberFormat('#,##0').format(stay.price)}${stay.pricePeriod.uiSuffix}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.green.shade800,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: Colors.green.shade50,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (stay.description.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                stay.description.trim(),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AccommodationMainPage(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.explore_rounded),
              label: const Text(
                'Browse all stays',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
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

  Future<String?> _resolveImageUrl(MarketplaceDetailModel item) async {
    final raw = item.image.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    try {
      if (raw.startsWith('gs://')) {
        return FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      }
      return FirebaseStorage.instance.ref(raw).getDownloadURL();
    } catch (_) {
      return raw;
    }
  }

  CartModel _toCartModel(MarketplaceDetailModel item, String imageUrl) {
    final parsed = item.sqlItemId;
    final itemId = parsed ?? _fnv1a32('mp:${item.id}:${item.name}');
    final uid = _auth.currentUser?.uid ?? '';
    return CartModel(
      userId: uid,
      item: itemId,
      quantity: 1,
      name: item.name,
      image: imageUrl,
      price: item.price,
      description: item.description ?? '',
      comment: null,
      merchantId: widget.merchantId,
      merchantName: widget.merchantName,
      serviceType: 'marketplace',
    );
  }

  Future<void> _addToCart(MarketplaceDetailModel item) async {
    if (_auth.currentUser == null) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to add items to cart.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    try {
      final url = await _resolveImageUrl(item);
      final cartItem = _toCartModel(item, url ?? item.image);
      await _cartService.addToCart(cartItem);
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        '${item.name} added to cart',
        isSuccess: true,
        errorMessage: '',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not add to cart. Please try again.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _buyNow(MarketplaceDetailModel item) async {
    if (_auth.currentUser == null) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to buy.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    try {
      final url = await _resolveImageUrl(item);
      final cartItem = _toCartModel(item, url ?? item.image);
      await _cartService.addToCart(cartItem);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckoutFromCartPage(items: [cartItem]),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not proceed. Please try again.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _toggleFollow() async {
    final user = _auth.currentUser;
    if (user == null) {
      // Not logged in – you can later hook this to open login.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to follow this seller.')),
      );
      return;
    }

    final merchantId = widget.merchantId.trim();
    final followerRef = _firestore
        .collection('merchant_followers')
        .doc(merchantId)
        .collection('followers')
        .doc(user.uid);

    try {
      if (_following) {
        await followerRef.delete();
        setState(() => _following = false);
      } else {
        await followerRef.set({
          'uid': user.uid,
          'email': user.email,
          'followedAt': FieldValue.serverTimestamp(),
        });
        setState(() => _following = true);
      }
    } catch (e) {
      debugPrint('Toggle follow error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update follow status.')),
      );
    }
  }

  String get _merchantShopUrl =>
      'https://vero360.app/merchant/${widget.merchantId.trim()}';

  String get _shareMessage =>
      'Check out this merchant on Vero360 - ${widget.merchantName}\n$_merchantShopUrl';

  void _copyMerchantLink() {
    Clipboard.setData(ClipboardData(text: _merchantShopUrl));
    ToastHelper.showCustomToast(
      context,
      'Merchant link copied to clipboard',
      isSuccess: true,
      errorMessage: '',
    );
  }

  void _shareMerchantShop() {
    Share.share(_shareMessage);
  }

  Future<void> _showReportScreenshotPicker(
    BuildContext sheetCtx,
    void Function(XFile? file) onPicked,
  ) async {
    await showModalBottomSheet<void>(
      context: sheetCtx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          16 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add screenshot',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Optional — helps us review faster',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final img = await ImagePicker()
                      .pickImage(source: ImageSource.camera);
                  onPicked(img);
                } catch (_) {}
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF8A00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Take photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final img = await ImagePicker()
                      .pickImage(source: ImageSource.gallery);
                  onPicked(img);
                } catch (_) {}
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E88E5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Choose from gallery',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockMerchant() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.block_rounded,
                    size: 30, color: Colors.red.shade700),
              ),
              const SizedBox(height: 16),
              const Text(
                'Block merchant?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You will stop seeing this merchant in recommendations and listings. You can change this later in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Block',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Merchant blocked (coming soon to sync across devices).')),
    );
  }

  Future<void> _reportMerchant() async {
    final controller = TextEditingController();
    XFile? picked;

    final result = await showDialog<({String message, XFile? picked})?>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _brandOrange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: _brandOrange, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Report merchant',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _brandNavy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.merchantName.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: Icon(Icons.close_rounded,
                            color: Colors.grey.shade600),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText:
                          'Tell us what is wrong (fraud, fake products, abuse, etc.)',
                      filled: true,
                      fillColor: const Color(0xFFF6F7FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: _brandOrange, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Screenshot (optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: const Color(0xFFF6F7FB),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showReportScreenshotPicker(
                        dialogCtx,
                        (file) {
                          if (file != null) {
                            setLocal(() => picked = file);
                          }
                        },
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: picked == null
                            ? Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _brandOrange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: _brandOrange),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Add a screenshot',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Camera or gallery',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      color: Colors.grey.shade400),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: Image.file(
                                        File(picked!.path),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Screenshot attached',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Colors.green.shade800,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          picked!.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextButton.icon(
                                          onPressed: () =>
                                              setLocal(() => picked = null),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                Colors.red.shade700,
                                            padding: EdgeInsets.zero,
                                            minimumSize: Size.zero,
                                            tapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                          label: const Text(
                                            'Remove',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final msg = controller.text.trim();
                            if (msg.isEmpty && picked == null) {
                              final messenger =
                                  ScaffoldMessenger.maybeOf(dialogCtx);
                              if (messenger != null) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Please write a message or add a screenshot.',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.all(16),
                                  ),
                                );
                              } else {
                                ToastHelper.showCustomToast(
                                  dialogCtx,
                                  'Please write a message or add a screenshot.',
                                  isSuccess: false,
                                  errorMessage: '',
                                );
                              }
                              return;
                            }
                            Navigator.pop(
                              dialogCtx,
                              (message: msg, picked: picked),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _brandOrange,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Send report',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Let the route finish unmounting before disposing the controller the TextField used.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (result == null || !mounted) return;

    final user = _auth.currentUser;
    if (user == null) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to report a merchant.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    final message = result.message;
    final pickedFile = result.picked;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending report…')),
    );

    try {
      String? proofUrl;
      if (pickedFile != null) {
        final ext = pickedFile.name.toLowerCase().split('.').last;
        final safeExt = (ext.length <= 5) ? ext : 'png';
        final ref = FirebaseStorage.instance.ref().child(
              'reports/merchant/${widget.merchantId.trim()}/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.$safeExt',
            );
        final file = File(pickedFile.path);
        final task = await ref.putFile(file);
        proofUrl = await task.ref.getDownloadURL();
      }

      await _firestore.collection('merchant_reports').add({
        'merchantId': widget.merchantId.trim(),
        'merchantName': widget.merchantName.trim(),
        'reporterUid': user.uid,
        'reporterEmail': user.email,
        'message': message,
        'proofUrl': proofUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you. Your report was sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        'Could not send report. Please try again.',
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _loadMerchantHeader() async {
    // Keep cached profile visible; only show skeleton on cold open.
    if (_headerMemCache[widget.merchantId.trim()] == null && mounted) {
      setState(() => _loadingHeader = true);
    }

    try {
      final mid = widget.merchantId.trim();
      final user = _auth.currentUser;

      // Merchant + user profile in parallel (cache-first).
      final snaps = await Future.wait([
        _docFast(_firestore.collection('marketplace_merchants').doc(mid)),
        _docFast(_firestore.collection('users').doc(mid)),
      ]);
      final merchantDoc = snaps[0];
      final userDoc = snaps[1];

      String? profileUrl;
      String? email;
      String? phone;
      String? status;
      int? backendId = _merchantBackendId;
      int followerCount = _followerCount;
      num? storedFollowerCount;

      if (merchantDoc.exists) {
        final data = merchantDoc.data() ?? <String, dynamic>{};
        status = (data['status'] ?? data['verificationStatus'] ?? '')
            .toString()
            .trim();
        if (status.isEmpty) status = null;
        profileUrl = (data['profilePicture'] ?? data['profilepicture'] ?? '')
            .toString()
            .trim();
        if (profileUrl.isEmpty) profileUrl = null;
        email = (data['email'] ?? data['userEmail'] ?? '').toString().trim();
        if (email.isEmpty) email = null;
        phone = (data['phone'] ?? data['phoneNumber'] ?? '').toString().trim();
        if (phone.isEmpty) phone = null;
        backendId = _parseBackendIdFromMap(data) ?? backendId;
        storedFollowerCount = data['followerCount'] ?? data['followersCount'];
        if (storedFollowerCount is num) {
          followerCount = storedFollowerCount.toInt();
        }

        if (mounted) {
          setState(() {
            _applyRatingFieldsFromMap(data);
            if (status != null) _merchantStatus = status;
            if (profileUrl != null) _merchantProfileUrl = profileUrl;
            if (email != null) _merchantEmail = email;
            if (phone != null) _merchantPhone = phone;
            if (backendId != null) _merchantBackendId = backendId;
            _followerCount = followerCount;
            _loadingHeader = false;
          });
          _persistHeaderCache();
        }
      }

      // Fill gaps from users doc without blocking first paint.
      if (userDoc.exists) {
        final u = userDoc.data() ?? <String, dynamic>{};
        final uProfile = (u['profilepicture'] ??
                u['profilePicture'] ??
                u['photoUrl'] ??
                u['photoURL'] ??
                '')
            .toString()
            .trim();
        final uEmail = (u['email'] ?? '').toString().trim();
        final uPhone = (u['phone'] ?? u['phoneNumber'] ?? '').toString().trim();
        backendId ??= _parseBackendIdFromMap(u);
        if (mounted) {
          setState(() {
            if ((_merchantProfileUrl?.trim().isEmpty ?? true) &&
                uProfile.isNotEmpty) {
              _merchantProfileUrl = uProfile;
            }
            if ((_merchantEmail?.trim().isEmpty ?? true) && uEmail.isNotEmpty) {
              _merchantEmail = uEmail;
            }
            if ((_merchantPhone?.trim().isEmpty ?? true) && uPhone.isNotEmpty) {
              _merchantPhone = uPhone;
            }
            if (backendId != null) _merchantBackendId = backendId;
            _loadingHeader = false;
          });
          _persistHeaderCache();
        }
      } else if (mounted && !merchantDoc.exists) {
        setState(() => _loadingHeader = false);
      }

      // Follow state + count in background (must not delay profile).
      unawaited(_refreshFollowMeta(
        mid: mid,
        userId: user?.uid,
        knownCount: storedFollowerCount is num ? storedFollowerCount.toInt() : null,
      ));

      // Reviews / rating from API (uses backend id from doc when possible).
      unawaited(_loadMerchantReviewsQuiet(knownBackendId: backendId));
    } catch (e) {
      debugPrint('Error loading merchant header: $e');
      if (mounted) setState(() => _loadingHeader = false);
      unawaited(_loadMerchantReviewsQuiet());
    }
  }

  Future<void> _refreshFollowMeta({
    required String mid,
    String? userId,
    int? knownCount,
  }) async {
    try {
      final followFuture = (userId == null || userId.isEmpty)
          ? Future<bool>.value(_following)
          : _docFast(
              _firestore
                  .collection('merchant_followers')
                  .doc(mid)
                  .collection('followers')
                  .doc(userId),
            ).then((s) => s.exists);

      Future<int> countFuture() async {
        if (knownCount != null) return knownCount;
        try {
          final agg = await _firestore
              .collection('merchant_followers')
              .doc(mid)
              .collection('followers')
              .count()
              .get()
              .timeout(const Duration(seconds: 4));
          return agg.count ?? _followerCount;
        } catch (_) {
          return _followerCount;
        }
      }

      final pair = await Future.wait([
        followFuture.timeout(const Duration(seconds: 4),
            onTimeout: () => _following),
        countFuture(),
      ]);
      if (!mounted) return;
      setState(() {
        _following = pair[0] as bool;
        _followerCount = pair[1] as int;
      });
      _persistHeaderCache();
    } catch (_) {}
  }

  Future<void> _loadMerchantReviewsQuiet({int? knownBackendId}) async {
    final mid = widget.merchantId.trim();
    final cached = _headerMemCache[mid];
    if (cached != null &&
        cached.recentReviews.isNotEmpty &&
        (cached.rating != null || cached.reviewCount > 0)) {
      // Already showing cache; refresh quietly below.
    } else if (mounted) {
      setState(() => _reviewsLoading = true);
    }

    try {
      var backendId = knownBackendId ?? _merchantBackendId;
      if (backendId != null && backendId > 0) {
        final warm = MerchantReviewService.peekCache(backendId);
        if (warm != null) {
          if (mounted) {
            setState(() {
              _merchantBackendId = backendId;
              _merchantRating = warm.summary.average;
              _merchantReviewCount = warm.summary.count;
              _cachedReviewSummary = warm.summary;
              _cachedReviews = warm.reviews;
              _recentReviews = warm.reviews.take(3).toList();
              _reviewsLoading = false;
            });
            _persistHeaderCache();
          }
          unawaited(const MerchantReviewService()
              .loadFast(backendId, forceRefresh: true)
              .then((bundle) {
            if (!mounted) return;
            setState(() {
              _merchantRating = bundle.summary.average;
              _merchantReviewCount = bundle.summary.count;
              _cachedReviewSummary = bundle.summary;
              _cachedReviews = bundle.reviews;
              _recentReviews = bundle.reviews.take(3).toList();
            });
            _persistHeaderCache();
          }).catchError((_) {}));
          return;
        }
      }

      if (backendId == null || backendId <= 0) {
        backendId = await MerchantReviewIdResolver.resolveMerchantId(
          merchantRef: mid,
          preResolvedBackendId: _merchantBackendId,
        ).timeout(const Duration(seconds: 5));
      }
      final int resolvedBackendId = backendId;

      final bundle = await const MerchantReviewService()
          .loadFast(resolvedBackendId)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      setState(() {
        _merchantBackendId = resolvedBackendId;
        if (bundle.summary.average > 0) {
          _merchantRating = bundle.summary.average;
        }
        if (bundle.summary.count > 0) {
          _merchantReviewCount = bundle.summary.count;
        }
        _cachedReviewSummary = bundle.summary;
        _cachedReviews = bundle.reviews;
        _recentReviews = bundle.reviews.take(3).toList();
        _reviewsLoading = false;
      });
      _persistHeaderCache();
    } catch (e) {
      debugPrint('Error loading merchant reviews: $e');
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  Widget _buildModernSearchBar(String hintText) {
    final hasText = _searchController.text.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _surfaceBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1D26),
        ),
        cursorColor: _brandOrange,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: const Color(0xFFF6F7FB),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.search_rounded, color: _brandOrange, size: 26),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _brandOrange, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildStaysGridBody(
    BuildContext context,
    AsyncSnapshot<List<_MerchantStayPreview>> snap,
  ) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: AppSkeletonLatestArrivalsGrid(),
      );
    }
    if (snap.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load listings',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      );
    }
    final all = snap.data ?? const <_MerchantStayPreview>[];
    final filtered = _searchQuery.isEmpty
        ? all
        : all
            .where((s) {
              final q = _searchQuery;
              return s.name.toLowerCase().contains(q) ||
                  s.location.toLowerCase().contains(q) ||
                  s.description.toLowerCase().contains(q);
            })
            .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _searchQuery.isEmpty
                    ? Icons.hotel_class_outlined
                    : Icons.search_off_rounded,
                size: 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No listings yet'
                    : 'No matching results',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isEmpty
                    ? 'Check back later for new listings from this host.'
                    : 'Try a different search.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: ratio,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final st = filtered[index];
        return _MerchantStayCard(
          stay: st,
          onTap: () => _showStayPreviewSheet(st),
          buildCover: (raw) => _imageFromAnySource(
            raw,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      },
    );
  }

  void _openMerchantReviews() {
    final backendId = _merchantBackendId;
    final cached =
        backendId != null ? MerchantReviewService.peekCache(backendId) : null;
    final reviews = cached?.reviews ??
        (_cachedReviews.isNotEmpty ? _cachedReviews : _recentReviews);
    final summary = cached?.summary ??
        _cachedReviewSummary ??
        MerchantReviewSummary(
          average: _merchantRating ?? 0,
          count: _merchantReviewCount > 0
              ? _merchantReviewCount
              : reviews.length,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantReviewsPage(
          merchantId: widget.merchantId,
          merchantName: widget.merchantName,
          logoUrl: _merchantProfileUrl,
          rating: _merchantRating ?? summary.average,
          merchantBackendId: backendId,
          initialSummary: summary,
          initialReviews: reviews,
        ),
      ),
    );
  }

  Widget _buildRecentReviewsSection() {
    if (!_reviewsLoading && _recentReviews.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Customer reviews',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Color(0xFF1A1D26),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _openMerchantReviews,
                  child: const Text('See all'),
                ),
              ],
            ),
            if (_reviewsLoading && _recentReviews.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _brandOrange,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loading reviews…',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._recentReviews.map((review) {
                final comment = review.comment.trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              review.authorName.trim().isEmpty
                                  ? 'Customer'
                                  : review.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (i) {
                              return Icon(
                                i < review.rating
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 14,
                                color: Colors.amber,
                              );
                            }),
                          ),
                        ],
                      ),
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          comment,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storefront_rounded, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(
                builder: (context) {
                  final isAccommodation = _isAccommodationHost == true;
                  final baseName = widget.merchantName.trim().isEmpty
                      ? 'Merchant'
                      : widget.merchantName.trim();
                  final title =
                      isAccommodation ? baseName : '$baseName Store';
                  return Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      letterSpacing: -0.2,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_rounded),
            onPressed: _copyMerchantLink,
            tooltip: 'Copy merchant link',
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _shareMerchantShop,
            tooltip: 'Share merchant shop',
          ),
        ],
      ),
      body: Column(
        children: [
          _MerchantProfileCard(
            merchantId: widget.merchantId,
            name: widget.merchantName,
            email: _merchantEmail,
            phone: _merchantPhone,
            rating: _merchantRating,
            reviewCount: _merchantReviewCount,
            status: _merchantStatus,
            profileUrl: _merchantProfileUrl,
            loading: _loadingHeader,
            following: _following,
            followerCount: _followerCount,
            onToggleFollow: _toggleFollow,
            onBlock: _blockMerchant,
            onReport: _reportMerchant,
            onViewProfile: _showMerchantProfileViewer,
            onOpenReviews: _openMerchantReviews,
          ),
          _buildRecentReviewsSection(),
          Expanded(
            child: Builder(
              builder: (context) {
                // Don't block products on accommodation detect — show products
                // unless we already know this is a Stay host.
                final isAccommodationHost = _isAccommodationHost == true;
                if (isAccommodationHost) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: _buildModernSearchBar(
                          'Search ${widget.merchantName.trim().isEmpty ? 'this host' : widget.merchantName.trim()}…',
                        ),
                      ),
                      Expanded(
                        child: FutureBuilder<List<_MerchantStayPreview>>(
                          future: _staysFuture,
                          builder: (context, snap) =>
                              _buildStaysGridBody(context, snap),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Browse products',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildModernSearchBar(
                            'Search products from ${widget.merchantName}...',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: FutureBuilder<List<MarketplaceDetailModel>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
                              child: AppSkeletonLatestArrivalsGrid(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline_rounded,
                                        size: 48,
                                        color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Could not load products',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final allItems = snapshot.data ??
                              const <MarketplaceDetailModel>[];
                          final items = _searchQuery.isEmpty
                              ? allItems
                              : allItems
                                  .where((i) => i.name
                                      .toLowerCase()
                                      .contains(_searchQuery))
                                  .toList();
                          if (items.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _searchQuery.isEmpty
                                          ? Icons.inventory_2_outlined
                                          : Icons.search_off_rounded,
                                      size: 56,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'No products yet'
                                          : 'No matching products',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'Check back later for new listings from this store.'
                                          : 'Try a different search term.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
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
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: ratio,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final it = items[index];
                              return _MerchantProductCard(
                                item: it,
                                imageBuilder: (item) => _ProductImageCarousel(
                                  item: item,
                                  buildImageForSource: buildImageForSource,
                                ),
                                onAddToCart: () => _addToCart(it),
                                onBuyNow: () => _buyNow(it),
                                onOpen: () {
                                  if (!it.hasValidSqlItemId) return;

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DetailsPage(
                                        item: marketplaceModel
                                            .MarketplaceDetailModel(
                                          id: it.sqlItemId!,
                                          backendItemId: it.sqlItemId,
                                          name: it.name,
                                          image: it.image,
                                          price: it.price,
                                          description: it.description ?? '',
                                          location: it.location ?? '',
                                          comment: null,
                                          category: it.category,
                                          gallery: it.gallery,
                                          videos: it.videos,
                                          sellerBusinessName: null,
                                          sellerOpeningHours: null,
                                          sellerStatus: null,
                                          sellerBusinessDescription: null,
                                          sellerRating: null,
                                          sellerLogoUrl: null,
                                          serviceProviderId: null,
                                          sellerUserId: null,
                                          merchantId: widget.merchantId,
                                          merchantName: widget.merchantName,
                                          serviceType: 'marketplace',
                                          createdAt: it.createdAt,
                                        ),
                                        cartService: _cartService,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Merged API + Firestore accommodation row for a merchant shop (Stays tab).
class _MerchantStayPreview {
  _MerchantStayPreview({
    required this.stableId,
    required this.name,
    required this.location,
    required this.description,
    required this.price,
    AccommodationPricePeriod? pricePeriod,
    required this.coverUrl,
    required this.gallery,
    required this.typeLabel,
    this.apiAccommodationId,
  }) : _pricePeriod = pricePeriod;

  final String stableId;
  final String name;
  final String location;
  final String description;
  final int price;
  final AccommodationPricePeriod? _pricePeriod;

  AccommodationPricePeriod get pricePeriod =>
      _pricePeriod ?? AccommodationPricePeriod.night;
  final String coverUrl;
  final List<String> gallery;
  final String typeLabel;
  final int? apiAccommodationId;

  bool get isDummyListing {
    final n = name.trim().toLowerCase();
    final hasRealName = n.isNotEmpty && n != 'stay';
    final hasInfo = location.trim().isNotEmpty ||
        description.trim().isNotEmpty ||
        imageSources.isNotEmpty;
    final hasPrice = price > 0;
    return !hasRealName && !hasInfo && !hasPrice;
  }

  List<String> get imageSources {
    final out = <String>[];
    final seen = <String>{};
    final c = coverUrl.trim();
    if (c.isNotEmpty && seen.add(c)) out.add(c);
    for (final g in gallery) {
      final t = g.trim();
      if (t.isNotEmpty && seen.add(t)) out.add(t);
    }
    return out;
  }

  factory _MerchantStayPreview.fromAccommodation(Accommodation a) {
    return _MerchantStayPreview(
      stableId: 'api-${a.id}',
      name: a.name,
      location: a.location,
      description: a.description,
      price: a.price,
      pricePeriod: a.pricePeriod,
      coverUrl: (a.image ?? '').trim(),
      gallery: List<String>.from(a.gallery),
      typeLabel: a.accommodationType,
      apiAccommodationId: a.id,
    );
  }

  factory _MerchantStayPreview.fromFirestore(
    String docId,
    Map<String, dynamic> d,
  ) {
    final priceRaw = d['pricePerNight'] ?? d['price'] ?? 0;
    final price = priceRaw is num
        ? priceRaw.toInt()
        : int.tryParse(priceRaw.toString()) ?? 0;
    final cover = (d['imageUrl'] ?? d['image'] ?? '').toString().trim();
    final gal = <String>[];
    final g1 = d['galleryUrls'];
    if (g1 is List) {
      gal.addAll(
        g1.map((e) => e.toString()).where((s) => s.trim().isNotEmpty),
      );
    }
    final g2 = d['gallery'];
    if (g2 is List) {
      for (final e in g2) {
        final s = e.toString().trim();
        if (s.isNotEmpty) gal.add(s);
      }
    }
    return _MerchantStayPreview(
      stableId: docId,
      name: (d['name'] ?? '').toString(),
      location: (d['location'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      price: price,
      pricePeriod: accommodationPricePeriodFromDynamic(
        d['pricingPeriod'] ?? d['pricePeriod'],
      ),
      coverUrl: cover,
      gallery: gal,
      typeLabel:
          (d['accommodationType'] ?? d['type'] ?? '').toString().trim(),
      apiAccommodationId: _stayListingApiId(d),
    );
  }
}

class _MerchantStayCard extends StatelessWidget {
  const _MerchantStayCard({
    required this.stay,
    required this.onTap,
    required this.buildCover,
  });

  final _MerchantStayPreview stay;
  final VoidCallback onTap;
  final Widget Function(String raw) buildCover;

  static const Color _brandOrange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final sources = stay.imageSources;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: sources.isEmpty
                  ? ColoredBox(
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.hotel_class_outlined,
                        size: 40,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : sources.length == 1
                      ? buildCover(sources.first)
                      : PageView.builder(
                          itemCount: sources.length,
                          itemBuilder: (_, i) => buildCover(sources[i]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stay.name.trim().isEmpty ? 'Stay' : stay.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (stay.location.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      stay.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'MWK ${NumberFormat('#,##0').format(stay.price)}${stay.pricePeriod.uiSuffix}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brandOrange,
                        side: const BorderSide(color: _brandOrange),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'View stay',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
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
    );
  }
}

class _MerchantProductCard extends StatelessWidget {
  final MarketplaceDetailModel item;
  final VoidCallback onOpen;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;
  final Widget Function(MarketplaceDetailModel) imageBuilder;

  const _MerchantProductCard({
    required this.item,
    required this.onOpen,
    required this.onAddToCart,
    required this.onBuyNow,
    required this.imageBuilder,
  });

  static const Color _brandOrange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
                child: imageBuilder(item),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onOpen,
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MWK ${NumberFormat('#,###', 'en').format(item.price.truncate())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onAddToCart,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brandOrange,
                            side: const BorderSide(color: _brandOrange),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Add to Cart',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onBuyNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Buy Now',
                              style: TextStyle(fontSize: 11)),
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
    );
  }
}

class _MerchantProfileCard extends StatelessWidget {
  static const Color _kBrandOrange = Color(0xFFFF8A00);
  static const Color _kBrandNavy = Color(0xFF16284C);
  static const Color _kBorder = Color(0xFFE2E6EF);

  final String merchantId;
  final String name;
  final String? email;
  final String? phone;
  final double? rating;
  final int reviewCount;
  final String? status;
  final String? profileUrl;
  final bool loading;
  final bool following;
  final VoidCallback onToggleFollow;
  final int followerCount;
  final VoidCallback onBlock;
  final VoidCallback onReport;
  final VoidCallback onViewProfile;
  final VoidCallback onOpenReviews;

  const _MerchantProfileCard({
    required this.merchantId,
    required this.name,
    required this.email,
    required this.phone,
    required this.rating,
    required this.reviewCount,
    required this.status,
    required this.profileUrl,
    required this.loading,
    required this.following,
    required this.onToggleFollow,
    required this.followerCount,
    required this.onBlock,
    required this.onReport,
    required this.onViewProfile,
    required this.onOpenReviews,
  });

  ImageProvider? _profileImageProvider() {
    final raw = profileUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return CachedNetworkImageProvider(raw, maxWidth: 200, maxHeight: 200);
    }
    // Try base64 (same pattern as dashboard)
    try {
      final base64Part = raw.contains(',') ? raw.split(',').last : raw;
      final bytes = base64Decode(base64Part);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'verified':
      case 'approved':
        return Colors.green;
      case 'pending':
      case 'under_review':
        return Colors.orange;
      case 'suspended':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = status?.isNotEmpty == true ? status! : 'pending';
    final img = _profileImageProvider();
    final hasPhoto = img != null;
    final emailStr = email?.trim().isNotEmpty == true ? email! : null;
    final phoneStr = phone?.trim().isNotEmpty == true ? phone! : null;
    final followersLabel = followerCount <= 0
        ? 'No followers yet'
        : followerCount == 1
            ? '1 follower'
            : '$followerCount followers';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoryProfileRing(
                merchantId: merchantId,
                merchantName: name,
                merchantImageUrl: profileUrl,
                size: 74,
                imageProvider: img,
                placeholderIcon: Icons.storefront_rounded,
                onNoStoriesTap: hasPhoto ? onViewProfile : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1D26),
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (emailStr != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        emailStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      phoneStr ?? 'No phone number',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          onTap: onOpenReviews,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    size: 14, color: Colors.amber),
                                Text(
                                  ' ${rating?.toStringAsFixed(1) ?? '0.0'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                                if (reviewCount > 0) ...[
                                  Text(
                                    ' · $reviewCount',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(effectiveStatus)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                effectiveStatus.toLowerCase() == 'verified'
                                    ? Icons.verified_rounded
                                    : Icons.shield_outlined,
                                size: 14,
                                color: _statusColor(effectiveStatus),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                effectiveStatus,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(effectiveStatus),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_alt_outlined, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              followersLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade800),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: Colors.white,
                elevation: 10,
                offset: const Offset(0, 10),
                onSelected: (value) {
                  if (value == 'block') {
                    onBlock();
                  } else if (value == 'report') {
                    onReport();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'block',
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.block_rounded,
                              color: Colors.red.shade700, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Block',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'Hide this seller',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'report',
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _kBrandOrange.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.flag_rounded,
                              color: _kBrandOrange, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Report',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'Tell us what happened',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
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
              if (!loading)
                Tooltip(
                  message:
                      following ? 'Unfollow seller' : 'Follow seller',
                  child: Material(
                    color: following
                        ? Colors.red.shade50
                        : const Color(0xFFF6F7FB),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: onToggleFollow,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          following
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: following ? Colors.red : _kBrandNavy,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Photo carousel for a product (cover + gallery), auto-slides every 1 second like details/main.
class _ProductImageCarousel extends StatefulWidget {
  final MarketplaceDetailModel item;
  final Widget Function(String source) buildImageForSource;

  const _ProductImageCarousel({
    required this.item,
    required this.buildImageForSource,
  });

  @override
  State<_ProductImageCarousel> createState() => _ProductImageCarouselState();
}

class _ProductImageCarouselState extends State<_ProductImageCarousel> {
  late final PageController _pc;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController();
    final n = _mediaCount;
    if (n > 1) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_pc.hasClients) return;
        final next = (_page + 1) % n;
        _pc.animateToPage(
          next,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      });
    }
  }

  int get _mediaCount {
    int c = 0;
    if (widget.item.image.trim().isNotEmpty) c++;
    c += widget.item.gallery.where((u) => u.trim().isNotEmpty).length;
    return c;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final images = <String>[
      if (item.image.trim().isNotEmpty) item.image.trim(),
      ...item.gallery.map((e) => e.toString().trim()).where((s) => s.isNotEmpty),
    ];
    if (images.isEmpty) {
      return Container(
        color: const Color(0xFFEDEDED),
        child: const Center(
          child: Icon(Icons.image_not_supported_rounded, color: Colors.black38),
        ),
      );
    }
    if (images.length == 1) {
      if (item.imageBytes != null && item.image.trim().isNotEmpty && item.image.trim() == images.first) {
        return Image.memory(
          item.imageBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      return widget.buildImageForSource(images.first);
    }
    return PageView.builder(
      controller: _pc,
      itemCount: images.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (context, i) {
        final src = images[i];
        final useBytes = i == 0 && item.imageBytes != null && item.image.trim() == src;
        if (useBytes) {
          return Image.memory(
            item.imageBytes!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }
        return widget.buildImageForSource(src);
      },
    );
  }
}