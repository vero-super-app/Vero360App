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

import 'package:vero360_app/GernalServices/blocked_merchant_service.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_detail_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as marketplaceModel;
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_reviews_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_id_resolver.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_seller_loader.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace_cart_social_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/vero_ride_driver_profile_page.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_share_link.dart';

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
  final String? displayName;
  final String? profileUrl;
  final String? email;
  final String? phone;
  final String? status;
  final String? openingHours;
  final List<int> openingDays;
  final String? businessDescription;
  final double? rating;
  final int reviewCount;
  final int followerCount;
  final int? backendId;
  final List<MerchantReview> recentReviews;

  const _MerchantShopHeaderCache({
    this.displayName,
    required this.profileUrl,
    required this.email,
    required this.phone,
    required this.status,
    required this.openingHours,
    this.openingDays = const [],
    required this.businessDescription,
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

  /// Drop shop mem caches on logout / account switch.
  static void clearSessionCaches() {
    _MerchantProductsPageState.clearSessionCaches();
  }

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
  /// Driver accounts must not show a merchant shop.
  bool _redirectingToDriver = false;
  /// True when the signed-in viewer has blocked this merchant.
  bool _blockedByViewer = false;

  double? _merchantRating;
  int _merchantReviewCount = 0;
  int? _merchantBackendId;
  List<MerchantReview> _recentReviews = const [];
  List<MerchantReview> _cachedReviews = const [];
  MerchantReviewSummary? _cachedReviewSummary;
  String? _merchantStatus;
  String? _merchantOpeningHours;
  List<int> _merchantOpeningDays = const [];
  String? _merchantProfileUrl;
  /// Resolved https URL when profile is gs:// or a storage path.
  String? _resolvedProfileHttpUrl;
  String? _merchantBusinessDescription;
  String? _merchantEmail;
  String? _merchantPhone;
  /// Live name from merchant/users docs (overrides constructor when set).
  String _resolvedMerchantName = '';
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
  static final Map<String, Set<String>> _identityMemCache = {};
  static final Map<String, Future<Set<String>>> _identityInflight = {};

  static void clearSessionCaches() {
    _itemsMemCache.clear();
    _accommodationMemCache.clear();
    _headerMemCache.clear();
    _identityMemCache.clear();
    _identityInflight.clear();
  }

  // Small cache for Firebase download URLs (gs:// or storage paths)
  final Map<String, Future<String?>> _dlUrlCache = {};

  bool _reviewsLoading = false;

  bool _isHttp(String s) => s.startsWith('http://') || s.startsWith('https://');
  bool _isGs(String s) => s.startsWith('gs://');

  String get _shopDisplayName {
    final resolved = _resolvedMerchantName.trim();
    if (resolved.isNotEmpty) return resolved;
    final passed = widget.merchantName.trim();
    return passed.isEmpty ? 'Merchant' : passed;
  }

  String? _nameFromMerchantMap(Map<String, dynamic> data) {
    for (final key in const [
      'businessName',
      'merchantName',
      'displayName',
      'fullName',
      'name',
    ]) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

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

  bool _looksLikeFirebaseUid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(value);
  }

  void _addIdentityValue(Set<String> keys, dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'undefined') {
      return;
    }
    keys.add(s);
  }

  void _addIdentityFromMap(Set<String> keys, Map<String, dynamic>? data) {
    if (data == null) return;
    for (final key in [
      'firebaseUid',
      'firebase_uid',
      'uid',
      'merchantId',
      'sellerUserId',
      'backendUserId',
      'userId',
      'ownerId',
      'hostId',
      'id',
    ]) {
      _addIdentityValue(keys, data[key]);
    }
  }

  Future<Set<String>> _resolveMerchantIdentityKeys() async {
    final mid = widget.merchantId.trim();
    final cached = _identityMemCache[mid];
    if (cached != null && cached.isNotEmpty) return cached;
    final inflight = _identityInflight[mid];
    if (inflight != null) return inflight;

    final future = _resolveMerchantIdentityKeysUncached(mid);
    _identityInflight[mid] = future;
    try {
      final keys = await future;
      _identityMemCache[mid] = keys;
      return keys;
    } finally {
      _identityInflight.remove(mid);
    }
  }

  Future<Set<String>> _resolveMerchantIdentityKeysUncached(String mid) async {
    final keys = <String>{};
    _addIdentityValue(keys, mid);
    if (_merchantBackendId != null) {
      _addIdentityValue(keys, _merchantBackendId);
    }

    void absorbDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!snap.exists) return;
      keys.add(snap.id);
      _addIdentityFromMap(keys, snap.data());
    }

    try {
      final snaps = await Future.wait([
        _docFast(_firestore.collection('users').doc(mid)),
        _docFast(_firestore.collection('marketplace_merchants').doc(mid)),
      ]);
      for (final s in snaps) {
        absorbDoc(s);
      }
    } catch (_) {}

    // Firebase UID shops already have the listing key — skip slow numeric bridges.
    if (!_looksLikeFirebaseUid(mid)) {
      final numeric = int.tryParse(mid) ?? _merchantBackendId;
      if (numeric != null && numeric > 0) {
        try {
          final merchantF =
              MerchantSellerLoader.lookupMerchantDocByBackendId(numeric);
          final userIdF = _firestore
              .collection('users')
              .where('userId', isEqualTo: numeric)
              .limit(1)
              .get();
          final backendIdF = _firestore
              .collection('users')
              .where('backendUserId', isEqualTo: numeric)
              .limit(1)
              .get();
          final merchant = await merchantF;
          if (merchant != null) {
            keys.add(merchant.docId);
            _addIdentityFromMap(keys, merchant.data);
          }
          for (final snap in await Future.wait([userIdF, backendIdF])) {
            if (snap.docs.isEmpty) continue;
            keys.add(snap.docs.first.id);
            _addIdentityFromMap(keys, snap.docs.first.data());
            break;
          }
        } catch (_) {}
      }
    }

    if (keys.length <= 8) return keys;
    final preferred = <String>{};
    if (mid.isNotEmpty) preferred.add(mid);
    preferred.addAll(keys.where(_looksLikeFirebaseUid).take(4));
    preferred.addAll(keys.where((k) => int.tryParse(k) != null).take(2));
    for (final k in keys) {
      if (preferred.length >= 8) break;
      preferred.add(k);
    }
    return preferred;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryDocsByOwner({
    required String collection,
    required Set<String> keys,
    required List<String> fields,
    String? merchantName,
  }) async {
    final col = _firestore.collection(collection);
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    final seen = <String>{};

    void enqueue(String field, dynamic value) {
      final sig = '$field=$value';
      if (!seen.add(sig)) return;
      futures.add(
        _queryFast(col.where(field, isEqualTo: value).limit(40)),
      );
    }

    for (final key in keys) {
      if (_looksLikeFirebaseUid(key)) {
        if (fields.contains('merchantId')) enqueue('merchantId', key);
        if (fields.contains('firebaseUid')) enqueue('firebaseUid', key);
        continue;
      }
      final n = int.tryParse(key);
      if (n != null && n > 0) {
        if (fields.contains('sellerUserId')) {
          enqueue('sellerUserId', key);
          enqueue('sellerUserId', n);
        }
        if (fields.contains('merchantId')) enqueue('merchantId', key);
        enqueue('merchantBackendId', n);
        continue;
      }
      for (final field in fields) {
        enqueue(field, key);
      }
    }
    final name = (merchantName ?? '').trim();
    if (futures.isEmpty &&
        name.isNotEmpty &&
        name.toLowerCase() != 'merchant') {
      enqueue('merchantName', name);
    }

    if (futures.isEmpty) return const [];
    final snaps = await Future.wait(futures);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        byId[doc.id] = doc;
      }
    }
    if (byId.isEmpty &&
        name.isNotEmpty &&
        name.toLowerCase() != 'merchant' &&
        !seen.contains('merchantName=$name')) {
      try {
        final nameSnap = await _queryFast(
          col.where('merchantName', isEqualTo: name).limit(40),
        );
        for (final doc in nameSnap.docs) {
          byId[doc.id] = doc;
        }
      } catch (_) {}
    }
    return byId.values.toList();
  }

  bool _looksLikeBase64(String s) {
    final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
    if (x.isEmpty) return false;
    return x.length >= 40 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
  }

  bool _isRelativePath(String s) =>
      s.isNotEmpty && !s.contains('://') && !_looksLikeBase64(s);

  Widget _profileImageFromAnySource(String raw, {BoxFit fit = BoxFit.contain}) {
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
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined, size: 56),
        );
      } catch (_) {}
    }
    if (_isHttp(s)) {
      // Disk + memory cache — same URL as the avatar ring, so open is instant.
      return CachedNetworkImage(
        imageUrl: s,
        fit: fit,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
          ),
        ),
        errorWidget: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, size: 56, color: Colors.white70),
      );
    }
    // Resolve gs:// / relative once; prefer cached http if already resolved.
    final cached = _resolvedProfileHttpUrl;
    if (cached != null && cached.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: cached,
        fit: fit,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
          ),
        ),
        errorWidget: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, size: 56, color: Colors.white70),
      );
    }
    return FutureBuilder<String?>(
      future: _toDownloadUrl(s),
      builder: (context, snap) {
        final u = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
            ),
          );
        }
        if (u == null || u.isEmpty) {
          return const Icon(Icons.broken_image_outlined, size: 56, color: Colors.white70);
        }
        _resolvedProfileHttpUrl = u;
        return CachedNetworkImage(
          imageUrl: u,
          fit: fit,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined, size: 56, color: Colors.white70),
        );
      },
    );
  }

  /// Warm full-size photo into image cache so tap-to-view is instant.
  void _precacheMerchantProfilePhoto() {
    if (!mounted) return;
    final raw = (_merchantProfileUrl ?? '').trim();
    if (raw.isEmpty) return;

    Future<void> warm(String url) async {
      if (!_isHttp(url) || !mounted) return;
      try {
        await precacheImage(CachedNetworkImageProvider(url), context);
      } catch (_) {}
    }

    if (_isHttp(raw)) {
      unawaited(warm(raw));
      return;
    }
    unawaited(() async {
      final u = await _toDownloadUrl(raw);
      if (u == null || u.isEmpty || !mounted) return;
      _resolvedProfileHttpUrl = u;
      await warm(u);
    }());
  }

  void _showMerchantProfileViewer() {
    final raw = (_merchantProfileUrl ?? '').trim();
    if (raw.isEmpty) return;

    // Open dialog immediately — image comes from cache when available.
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Center(
                child: InteractiveViewer(
                  minScale: 0.6,
                  maxScale: 4.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(ctx).width - 24,
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _profileImageFromAnySource(raw, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    unawaited(_maybeRedirectDriverProfile());
    unawaited(_refreshBlockedByViewer());
    final id = widget.merchantId.trim();
    final memItems = _itemsMemCache[id];
    if (memItems != null) {
      _future = Future.value(memItems);
      // Refresh quietly in background.
      unawaited(_loadMerchantItems().then((fresh) {
        if (!mounted || _redirectingToDriver) return;
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
      _resolvedMerchantName = (memHeader.displayName ?? '').trim();
      _merchantProfileUrl = memHeader.profileUrl;
      _merchantEmail = memHeader.email;
      _merchantPhone = memHeader.phone;
      _merchantStatus = memHeader.status;
      _merchantOpeningHours = memHeader.openingHours;
      _merchantOpeningDays = memHeader.openingDays;
      _merchantBusinessDescription = memHeader.businessDescription;
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
      // Warm full-size photo into image cache so tap-to-view is instant.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _precacheMerchantProfilePhoto();
      });
    } else {
      // Instant OPEN/CLOSED from shared hours cache while header loads.
      final hours = MerchantSellerLoader.peekOpeningHours(id);
      if (hours != null && hours.isNotEmpty) {
        _merchantOpeningHours = hours;
        _loadingHeader = false;
      }
      final days = MerchantSellerLoader.peekOpeningDays(id);
      if (days != null && days.isNotEmpty) {
        _merchantOpeningDays = days;
      }
    }

    _staysFuture = memAccom == true
        ? _loadMerchantStays()
        : Future<List<_MerchantStayPreview>>.value(const []);
    unawaited(_resolveAccommodationMode());
    unawaited(_prefetchOpeningHoursFast(id));
    unawaited(_loadMerchantHeader());
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  /// Drivers must see Vero Ride profile (ratings + taxi), not a merchant shop.
  Future<void> _maybeRedirectDriverProfile() async {
    final id = widget.merchantId.trim();
    if (id.isEmpty) return;
    final isDriver = await VeroRideDriverProfilePage.isDriverAccount(id);
    if (!mounted || !isDriver) return;
    setState(() => _redirectingToDriver = true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => VeroRideDriverProfilePage(
          firebaseUid: id,
          displayName: _shopDisplayName,
        ),
      ),
    );
  }

  Future<void> _prefetchOpeningHoursFast(String merchantId) async {
    final hours = await MerchantSellerLoader.prefetchOpeningHours(merchantId);
    if (!mounted || hours == null || hours.isEmpty) return;
    if (_merchantOpeningHours == hours) return;
    setState(() => _merchantOpeningHours = hours);
  }

  void _persistHeaderCache() {
    _headerMemCache[widget.merchantId.trim()] = _MerchantShopHeaderCache(
      displayName: _resolvedMerchantName.trim().isEmpty
          ? null
          : _resolvedMerchantName.trim(),
      profileUrl: _merchantProfileUrl,
      email: _merchantEmail,
      phone: _merchantPhone,
      status: _merchantStatus,
      openingHours: _merchantOpeningHours,
      openingDays: List<int>.from(_merchantOpeningDays),
      businessDescription: _merchantBusinessDescription,
      rating: _merchantRating,
      reviewCount: _merchantReviewCount,
      followerCount: _followerCount,
      backendId: _merchantBackendId,
      recentReviews: List<MerchantReview>.from(_recentReviews),
    );
  }

  List<int> _parseOpeningDays(dynamic raw) {
    final out = <int>{};
    if (raw is List) {
      for (final e in raw) {
        final n = e is int ? e : int.tryParse('$e');
        if (n != null && n >= 1 && n <= 7) out.add(n);
      }
    }
    return out.toList()..sort();
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
    if (_isAccommodationHost == v) return;
    setState(() {
      _isAccommodationHost = v;
      if (v) _staysFuture = _loadMerchantStays();
    });
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
      final doc = await _docFast(
        _firestore.collection('accommodation_merchants').doc(id),
      );
      if (doc.exists && looksLikeRealMerchantShopDoc(doc.data())) return true;
      final rooms = await _queryFast(
        _firestore
            .collection('accommodation_rooms')
            .where('merchantId', isEqualTo: id)
            .limit(1),
      );
      if (rooms.docs.isNotEmpty) return true;
      if (_looksLikeFirebaseUid(id)) return false;

      final keys = await _resolveMerchantIdentityKeys();
      for (final key in keys.where(_looksLikeFirebaseUid).take(2)) {
        if (key == id) continue;
        final extraDoc = await _docFast(
          _firestore.collection('accommodation_merchants').doc(key),
        );
        if (extraDoc.exists && looksLikeRealMerchantShopDoc(extraDoc.data())) {
          return true;
        }
        final extraRooms = await _queryFast(
          _firestore
              .collection('accommodation_rooms')
              .where('merchantId', isEqualTo: key)
              .limit(1),
        );
        if (extraRooms.docs.isNotEmpty) return true;
      }
    } catch (e) {
      debugPrint('detect accommodation: $e');
    }
    return false;
  }

  List<MarketplaceDetailModel> _parseMerchantItemDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required Set<String> keys,
  }) {
    final viewerUid = (_auth.currentUser?.uid ?? '').trim();
    final viewingOwnShop = viewerUid.isNotEmpty && keys.contains(viewerUid);
    final all = <MarketplaceDetailModel>[];
    for (final doc in docs) {
      final review =
          (doc.data()['reviewStatus'] ?? '').toString().trim().toLowerCase();
      if (review == 'rejected') continue;
      final item = MarketplaceDetailModel.fromFirestore(doc);
      if (viewingOwnShop || item.isActive) {
        all.add(item);
      }
    }
    all.sort((a, b) {
      final da = a.createdAt;
      final db = b.createdAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return all;
  }

  Future<List<MarketplaceDetailModel>> _loadMerchantItems() async {
    try {
      final String id = widget.merchantId.trim();
      final primaryKeys = <String>{id};
      if (_merchantBackendId != null) {
        primaryKeys.add('${_merchantBackendId}');
      }

      // Fast first paint: query the id this shop was opened with.
      final primaryDocs = await _queryDocsByOwner(
        collection: 'marketplace_items',
        keys: primaryKeys,
        fields: _looksLikeFirebaseUid(id)
            ? const ['merchantId']
            : const ['merchantId', 'sellerUserId'],
      );
      var all = _parseMerchantItemDocs(primaryDocs, keys: primaryKeys);
      _itemsMemCache[id] = all;

      if (all.isNotEmpty) {
        unawaited(_expandMerchantItems(id, all));
        return all;
      }

      final keys = await _resolveMerchantIdentityKeys();
      final docs = await _queryDocsByOwner(
        collection: 'marketplace_items',
        keys: keys,
        fields: const [
          'merchantId',
          'sellerUserId',
          'firebaseUid',
          'ownerId',
        ],
        merchantName: _shopDisplayName,
      );
      all = _parseMerchantItemDocs(docs, keys: keys);
      _itemsMemCache[id] = all;
      return all;
    } catch (e) {
      debugPrint('Error loading merchant items: $e');
      return _itemsMemCache[widget.merchantId.trim()] ?? [];
    }
  }

  Future<void> _expandMerchantItems(
    String id,
    List<MarketplaceDetailModel> already,
  ) async {
    try {
      final keys = await _resolveMerchantIdentityKeys();
      if (keys.length <= 1) return;
      final docs = await _queryDocsByOwner(
        collection: 'marketplace_items',
        keys: keys,
        fields: const [
          'merchantId',
          'sellerUserId',
          'firebaseUid',
          'ownerId',
        ],
        merchantName: _shopDisplayName,
      );
      final merged = _parseMerchantItemDocs(docs, keys: keys);
      if (merged.length <= already.length) return;
      _itemsMemCache[id] = merged;
      if (!mounted || _redirectingToDriver) return;
      setState(() => _future = Future.value(merged));
    } catch (e) {
      debugPrint('expand merchant items: $e');
    }
  }

  Future<List<_MerchantStayPreview>> _loadMerchantStays() async {
    final id = widget.merchantId.trim();
    final merged = <_MerchantStayPreview>[];
    final apiIds = <int>{};
    final keys = await _resolveMerchantIdentityKeys();

    var email = '';
    try {
      final docReads = <Future<DocumentSnapshot<Map<String, dynamic>>>>[
        _docFast(_firestore.collection('users').doc(id)),
        _docFast(_firestore.collection('marketplace_merchants').doc(id)),
        _docFast(_firestore.collection('accommodation_merchants').doc(id)),
      ];
      for (final key in keys.take(6)) {
        if (key == id) continue;
        docReads.add(_docFast(_firestore.collection('users').doc(key)));
      }
      final snaps = await Future.wait(docReads);
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

    final roomsFuture = _queryDocsByOwner(
      collection: 'accommodation_rooms',
      keys: keys,
      fields: const [
        'merchantId',
        'firebaseUid',
      ],
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
      final fs =
          results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      for (final doc in fs) {
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
      merchantName: _shopDisplayName,
      serviceType: 'marketplace',
      availableStock: item.stockQuantity,
      location: item.location,
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
    if (item.isOutOfStock) {
      ToastHelper.showCustomToast(
        context,
        'This item is out of stock',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    try {
      final url = await _resolveImageUrl(item);
      final cartItem = _toCartModel(item, url ?? item.image);
      await _cartService.addToCart(cartItem);
      final uid = _auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        unawaited(
          MarketplaceCartSocialService.recordAdd(
            itemDocId: item.id,
            uid: uid,
          ),
        );
      }
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
    if (item.isOutOfStock) {
      ToastHelper.showCustomToast(
        context,
        'This item is out of stock',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    try {
      final url = await _resolveImageUrl(item);
      final cartItem = _toCartModel(item, url ?? item.image);
      await _cartService.addToCart(cartItem);
      final uid = _auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        unawaited(
          MarketplaceCartSocialService.recordAdd(
            itemDocId: item.id,
            uid: uid,
          ),
        );
      }
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
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('followed_merchants')
            .doc(merchantId)
            .delete();
        setState(() => _following = false);
      } else {
        await followerRef.set({
          'uid': user.uid,
          'email': user.email,
          'followedAt': FieldValue.serverTimestamp(),
        });
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('followed_merchants')
            .doc(merchantId)
            .set({
          'merchantId': merchantId,
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

  String get _merchantShopUrl => marketplaceShopShareUrl(
        merchantId: widget.merchantId.trim(),
        name: _shopDisplayName,
        image: _merchantProfileUrl,
      );

  String get _shareMessage =>
      'Check out this shop on Vero360 — $_shopDisplayName\n$_merchantShopUrl';

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

  static const int _kMaxReportPhotos = 4;

  Future<void> _showReportScreenshotPicker(
    BuildContext sheetCtx, {
    required int remainingSlots,
    required void Function(List<XFile> files) onPicked,
  }) async {
    if (remainingSlots <= 0) return;
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
              'Add screenshots',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Up to $_kMaxReportPhotos photos · $remainingSlots slot${remainingSlots == 1 ? '' : 's'} left',
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
                  final img = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    imageQuality: 85,
                    maxWidth: 1600,
                  );
                  if (img != null) onPicked([img]);
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
                  final imgs = await ImagePicker().pickMultiImage(
                    imageQuality: 85,
                    maxWidth: 1600,
                    limit: remainingSlots,
                  );
                  if (imgs.isNotEmpty) {
                    onPicked(imgs.take(remainingSlots).toList());
                  }
                } catch (_) {
                  try {
                    final img = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                      maxWidth: 1600,
                    );
                    if (img != null) onPicked([img]);
                  } catch (_) {}
                }
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

  String _safeStorageSegment(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'unknown';
    return t.replaceAll(RegExp(r'[^\w\-.]'), '_');
  }

  Future<String> _uploadReportProof({
    required XFile file,
    required String merchantId,
    required String reporterUid,
    required int index,
  }) async {
    final ext = file.name.toLowerCase().split('.').last;
    final safeExt =
        (ext.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) ? ext : 'jpg';
    final contentType = switch (safeExt) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Photo ${index + 1} is empty.');
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeMerchant = _safeStorageSegment(merchantId);
    final safeUid = _safeStorageSegment(reporterUid);

    // Primary path + fallback under profile_photos (already allowed by Storage rules).
    final paths = <String>[
      'reports/merchant/$safeMerchant/$safeUid/${ts}_$index.$safeExt',
      'profile_photos/${reporterUid}_report_${safeMerchant}_${ts}_$index.$safeExt',
    ];

    Object? lastError;
    for (final path in paths) {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final ref = FirebaseStorage.instance.ref().child(path);
          final meta = SettableMetadata(
            contentType: contentType,
            customMetadata: {
              'purpose': 'merchant_report',
              'merchantId': merchantId,
              'index': '$index',
            },
          );
          try {
            await ref.putData(bytes, meta);
          } catch (_) {
            // Some devices fail putData; putFile is more reliable on Android.
            await ref.putFile(File(file.path), meta);
          }
          final url = await ref.getDownloadURL();
          if (url.trim().isEmpty) {
            throw StateError('Empty download URL for photo ${index + 1}');
          }
          return url;
        } catch (e) {
          lastError = e;
          debugPrint(
            '[ReportMerchant] upload path=$path attempt=${attempt + 1}: $e',
          );
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Could not upload photo ${index + 1}');
  }

  Future<void> _refreshBlockedByViewer() async {
    final blocked = await BlockedMerchantService.isBlocked(widget.merchantId);
    if (!mounted) return;
    if (_blockedByViewer != blocked) {
      setState(() => _blockedByViewer = blocked);
    }
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
    await BlockedMerchantService.blockMerchant(
      merchantId: widget.merchantId,
      displayName: _shopDisplayName,
    );
    if (!mounted) return;
    setState(() => _blockedByViewer = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_shopDisplayName} blocked. Unblock anytime in Settings.'),
        action: SnackBarAction(
          label: 'Unblock',
          onPressed: _unblockMerchant,
        ),
      ),
    );
  }

  Future<void> _unblockMerchant() async {
    await BlockedMerchantService.unblockMerchant(widget.merchantId);
    if (!mounted) return;
    setState(() => _blockedByViewer = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_shopDisplayName} unblocked')),
    );
  }

  Future<void> _reportMerchant() async {
    final controller = TextEditingController();
    final picked = <XFile>[];

    final result = await showDialog<({String message, List<XFile> picked})?>(
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
                              _shopDisplayName,
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
                    'Screenshots (optional, up to $_kMaxReportPhotos)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (picked.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < picked.length; i++)
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: Image.file(
                                    File(picked[i].path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: Material(
                                  color: Colors.red.shade600,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () =>
                                        setLocal(() => picked.removeAt(i)),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.close,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (picked.length < _kMaxReportPhotos)
                    Material(
                      color: const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showReportScreenshotPicker(
                          dialogCtx,
                          remainingSlots: _kMaxReportPhotos - picked.length,
                          onPicked: (files) {
                            if (files.isEmpty) return;
                            setLocal(() {
                              for (final f in files) {
                                if (picked.length >= _kMaxReportPhotos) break;
                                picked.add(f);
                              }
                            });
                          },
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      picked.isEmpty
                                          ? 'Add screenshots'
                                          : 'Add more photos',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Camera or gallery · ${picked.length}/$_kMaxReportPhotos',
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
                            if (msg.isEmpty && picked.isEmpty) {
                              final messenger =
                                  ScaffoldMessenger.maybeOf(dialogCtx);
                              if (messenger != null) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please write a message or add a screenshot.',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.all(16),
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
                              (
                                message: msg,
                                picked: List<XFile>.from(picked),
                              ),
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
    final pickedFiles = result.picked;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Sending report…'),
        duration: Duration(seconds: 60),
      ),
    );

    try {
      final mid = widget.merchantId.trim();
      final proofUrls = <String>[];

      // Upload every attached photo (retries + fallback path). Fail if any missing.
      for (var i = 0; i < pickedFiles.length; i++) {
        if (mounted) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Uploading photo ${i + 1} of ${pickedFiles.length}…',
              ),
              duration: const Duration(seconds: 60),
            ),
          );
        }
        final url = await _uploadReportProof(
          file: pickedFiles[i],
          merchantId: mid,
          reporterUid: user.uid,
          index: i,
        );
        proofUrls.add(url);
      }

      if (pickedFiles.isNotEmpty && proofUrls.length != pickedFiles.length) {
        throw StateError(
          'Only ${proofUrls.length} of ${pickedFiles.length} photos uploaded.',
        );
      }

      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Saving report…'),
            duration: Duration(seconds: 30),
          ),
        );
      }

      await _firestore.collection('merchant_reports').add({
        'merchantId': mid,
        'merchantName': _shopDisplayName,
        'reporterUid': user.uid,
        'reporterEmail': user.email,
        'message': message,
        'proofUrl': proofUrls.isNotEmpty ? proofUrls.first : null,
        'proofUrls': proofUrls,
        'photoCount': proofUrls.length,
        'photoCountRequested': pickedFiles.length,
        'photoUploadFailures': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      final received = proofUrls.length;
      final String body;
      if (received == 0) {
        body = 'Your report was sent successfully. Our team will review it.';
      } else if (received == 1) {
        body = 'Your report was sent successfully.\n\n1 photo received.';
      } else {
        body =
            'Your report was sent successfully.\n\nAll $received photos received.';
      }

      // Dialog is hard to miss (SnackBar/toast can be hidden under nav bars).
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade700,
                size: 28,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Report sent',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            body,
            style: TextStyle(
              height: 1.45,
              fontSize: 15,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: _brandOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      debugPrint('[ReportMerchant] send failed: $e');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Report not sent',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Text(
            pickedFiles.isEmpty
                ? 'Could not send your report. Please try again later.'
                : 'Could not upload all ${pickedFiles.length} photos.\n\n'
                    'Your report was not sent. Please check your connection and try again.',
            style: TextStyle(height: 1.4, color: Colors.grey.shade800),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: _brandOrange),
              child: const Text('OK'),
            ),
          ],
        ),
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
      String? openingHours;
      int? backendId = _merchantBackendId;
      int followerCount = _followerCount;
      num? storedFollowerCount;

      if (merchantDoc.exists) {
        final data = merchantDoc.data() ?? <String, dynamic>{};
        status = (data['status'] ?? data['verificationStatus'] ?? '')
            .toString()
            .trim();
        if (status.isEmpty) status = null;
        openingHours = (data['openingHours'] ?? '').toString().trim();
        if (openingHours.isEmpty) openingHours = null;
        final openingDays = _parseOpeningDays(data['openingDays']);
        profileUrl = (data['profilePicture'] ?? data['profilepicture'] ?? '')
            .toString()
            .trim();
        if (profileUrl.isEmpty) profileUrl = null;
        email = (data['email'] ?? data['userEmail'] ?? '').toString().trim();
        if (email.isEmpty) email = null;
        phone = (data['phone'] ?? data['phoneNumber'] ?? '').toString().trim();
        if (phone.isEmpty) phone = null;
        final bizDesc = (data['businessDescription'] ?? data['description'] ?? data['about'] ?? '')
            .toString()
            .trim();
        final liveName = _nameFromMerchantMap(data);
        backendId = _parseBackendIdFromMap(data) ?? backendId;
        storedFollowerCount = data['followerCount'] ?? data['followersCount'];
        if (storedFollowerCount is num) {
          followerCount = storedFollowerCount.toInt();
        }

        if (mounted) {
          setState(() {
            _applyRatingFieldsFromMap(data);
            if (liveName != null) _resolvedMerchantName = liveName;
            if (status != null) _merchantStatus = status;
            if (openingHours != null) {
              _merchantOpeningHours = openingHours;
              MerchantSellerLoader.cacheOpeningHours(mid, openingHours);
            }
            if (openingDays.isNotEmpty) {
              _merchantOpeningDays = openingDays;
              MerchantSellerLoader.cacheOpeningDays(mid, openingDays);
            }
            if (profileUrl != null) _merchantProfileUrl = profileUrl;
            if (email != null) _merchantEmail = email;
            if (phone != null) _merchantPhone = phone;
            if (bizDesc.isNotEmpty) _merchantBusinessDescription = bizDesc;
            if (backendId != null) _merchantBackendId = backendId;
            _followerCount = followerCount;
            _loadingHeader = false;
          });
          _persistHeaderCache();
          _precacheMerchantProfilePhoto();
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
        final uDesc = (u['businessDescription'] ?? u['description'] ?? u['bio'] ?? '')
            .toString()
            .trim();
        final uHours = (u['openingHours'] ?? '').toString().trim();
        final uDays = _parseOpeningDays(u['openingDays']);
        final uName = _nameFromMerchantMap(u);
        backendId ??= _parseBackendIdFromMap(u);
        if (mounted) {
          setState(() {
            if (_resolvedMerchantName.trim().isEmpty && uName != null) {
              _resolvedMerchantName = uName;
            }
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
            if ((_merchantBusinessDescription?.trim().isEmpty ?? true) &&
                uDesc.isNotEmpty) {
              _merchantBusinessDescription = uDesc;
            }
            if ((_merchantOpeningHours?.trim().isEmpty ?? true) &&
                uHours.isNotEmpty) {
              _merchantOpeningHours = uHours;
              MerchantSellerLoader.cacheOpeningHours(mid, uHours);
            }
            if (_merchantOpeningDays.isEmpty && uDays.isNotEmpty) {
              _merchantOpeningDays = uDays;
              MerchantSellerLoader.cacheOpeningDays(mid, uDays);
            }
            if (backendId != null) _merchantBackendId = backendId;
            _loadingHeader = false;
          });
          _persistHeaderCache();
          _precacheMerchantProfilePhoto();
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
          merchantName: _shopDisplayName,
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

  Widget _buildProductsBrowseColumn(BuildContext context) {
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
                            'Search products from $_shopDisplayName...',
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
                                          merchantName: _shopDisplayName,
                                          serviceType: 'marketplace',
                                          createdAt: it.createdAt,
                                          stockQuantity: it.stockQuantity,
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
  }

  @override
  Widget build(BuildContext context) {
    if (_redirectingToDriver) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: AppSkeletonListPlaceholder(items: 8),
      );
    }
    if (_blockedByViewer) {
      return Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          title: const Text('Shop'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block_rounded, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 20),
                Text(
                  'You blocked ${_shopDisplayName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _brandNavy,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Their shop, products, stories, and promotions are hidden from your app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _unblockMerchant,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Unblock merchant'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
                  final baseName = _shopDisplayName;
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
            name: _shopDisplayName,
            rating: _merchantRating,
            reviewCount: _merchantReviewCount,
            openingHours: _merchantOpeningHours,
            openingDays: _merchantOpeningDays,
            profileUrl: _merchantProfileUrl,
            businessDescription: _merchantBusinessDescription,
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
                  return FutureBuilder<List<_MerchantStayPreview>>(
                    future: _staysFuture,
                    builder: (context, staySnap) {
                      if (staySnap.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: AppSkeletonLatestArrivalsGrid(),
                        );
                      }
                      final stays =
                          staySnap.data ?? const <_MerchantStayPreview>[];
                      if (stays.isNotEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: _buildModernSearchBar(
                                'Search ${_shopDisplayName == 'Merchant' ? 'this host' : _shopDisplayName}…',
                              ),
                            ),
                            Expanded(
                              child: _buildStaysGridBody(context, staySnap),
                            ),
                          ],
                        );
                      }
                      // Host profile with no stay rooms — show marketplace listings.
                      return _buildProductsBrowseColumn(context);
                    },
                  );
                }
                return _buildProductsBrowseColumn(context);
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
  final double? rating;
  final int reviewCount;
  final String? openingHours;
  final List<int> openingDays;
  final String? profileUrl;
  final String? businessDescription;
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
    required this.rating,
    required this.reviewCount,
    required this.openingHours,
    this.openingDays = const [],
    required this.profileUrl,
    required this.businessDescription,
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
      // Same URL as the full viewer → shared disk/memory cache (instant open).
      return CachedNetworkImageProvider(raw);
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

  TimeOfDay? _parseTime(String raw) {
    final t = raw.trim().split(':');
    if (t.length != 2) return null;
    final h = int.tryParse(t[0]);
    final m = int.tryParse(t[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  bool _isShopOpenNow() {
    final s = (openingHours ?? '').trim();
    if (s.isEmpty) return false;
    if (openingDays.isNotEmpty &&
        !openingDays.contains(DateTime.now().weekday)) {
      return false;
    }
    final parts = s.replaceAll('–', '-').replaceAll('—', '-').split('-');
    if (parts.length != 2) return false;
    final open = _parseTime(parts[0]);
    final close = _parseTime(parts[1]);
    if (open == null || close == null) return false;
    final now = TimeOfDay.now();
    final nowM = now.hour * 60 + now.minute;
    final openM = open.hour * 60 + open.minute;
    final closeM = close.hour * 60 + close.minute;
    if (openM == closeM) return false;
    if (openM < closeM) {
      return nowM >= openM && nowM < closeM;
    }
    return nowM >= openM || nowM < closeM;
  }

  @override
  Widget build(BuildContext context) {
    final shopOpen = _isShopOpenNow();
    final statusColor =
        shopOpen ? Colors.green.shade700 : Colors.red.shade700;
    final statusLabel = shopOpen ? 'OPEN' : 'CLOSED';
    final img = _profileImageProvider();
    final hasPhoto = (profileUrl?.trim().isNotEmpty ?? false);
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
              Tooltip(
                message: hasPhoto
                    ? 'Tap to view photo · Long-press for stories'
                    : 'Profile photo',
                child: StoryProfileRing(
                  merchantId: merchantId,
                  merchantName: name,
                  merchantImageUrl: profileUrl,
                  size: 74,
                  imageProvider: img,
                  placeholderIcon: Icons.storefront_rounded,
                  onNoStoriesTap: hasPhoto ? onViewProfile : null,
                  onAvatarTap: hasPhoto ? onViewProfile : null,
                ),
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
                    if ((businessDescription ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        businessDescription!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
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
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                              letterSpacing: 0.2,
                            ),
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