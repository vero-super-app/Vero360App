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
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accomodation_mainpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

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
  late Future<bool> _isAccommodationMerchantFuture;
  final CartService _cartService =
      CartService('unused', apiPrefix: ApiConfig.apiPrefix);

  double? _merchantRating;
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

  // Small cache for Firebase download URLs (gs:// or storage paths)
  final Map<String, Future<String?>> _dlUrlCache = {};

  bool _isHttp(String s) => s.startsWith('http://') || s.startsWith('https://');
  bool _isGs(String s) => s.startsWith('gs://');

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
    _future = _loadMerchantItems();
    _staysFuture = _loadMerchantStays();
    _isAccommodationMerchantFuture = _detectAccommodationMerchant();
    _loadMerchantHeader();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
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
      final doc =
          await _firestore.collection('accommodation_merchants').doc(id).get();
      if (doc.exists) return true;
    } catch (e) {
      debugPrint('detect accommodation_merchants: $e');
    }
    try {
      final rooms = await _firestore
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: id)
          .limit(1)
          .get();
      if (rooms.docs.isNotEmpty) return true;
    } catch (e) {
      debugPrint('detect accommodation_rooms: $e');
    }
    return false;
  }

  Future<List<MarketplaceDetailModel>> _loadMerchantItems() async {
    try {
      // Same collection used elsewhere: 'marketplace_items'
      final String id = widget.merchantId.trim();
      final String name = widget.merchantName.trim();

      // 1) Try match by merchantId (new items) – no orderBy here to avoid composite index requirement
      final idSnap = await _firestore
          .collection('marketplace_items')
          .where('merchantId', isEqualTo: id)
          .get();

      var docs = idSnap.docs;

      // 2) Fallback: some older items may only have merchantName or numeric merchantId
      if (docs.isEmpty && name.isNotEmpty) {
        final nameSnap = await _firestore
            .collection('marketplace_items')
            .where('merchantName', isEqualTo: name)
            .get();
        docs = nameSnap.docs;
      }

      final all = docs
          .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
          .where((item) => item.isActive)
          .toList();

      // Sort in-memory by createdAt desc so newest items appear first
      all.sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      return all;
    } catch (e) {
      debugPrint('Error loading merchant items: $e');
      return [];
    }
  }

  Future<List<_MerchantStayPreview>> _loadMerchantStays() async {
    final id = widget.merchantId.trim();
    final merged = <_MerchantStayPreview>[];
    final apiIds = <int>{};

    var email = '';
    try {
      final uSnap = await _firestore.collection('users').doc(id).get();
      email = (uSnap.data()?['email'] ?? '').toString().trim();
    } catch (_) {}

    if (email.isEmpty) {
      try {
        final m = await _firestore
            .collection('marketplace_merchants')
            .doc(id)
            .get();
        final md = m.data();
        email = (md?['email'] ?? md?['userEmail'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (email.isEmpty) {
      try {
        final a = await _firestore
            .collection('accommodation_merchants')
            .doc(id)
            .get();
        email = (a.data()?['email'] ?? '').toString().trim();
      } catch (_) {}
    }

    if (email.isNotEmpty) {
      try {
        final mine =
            await AccommodationService().fetchOwnedByEmail(email);
        for (final a in mine) {
          apiIds.add(a.id);
          merged.add(_MerchantStayPreview.fromAccommodation(a));
        }
      } catch (e) {
        debugPrint('Merchant stays (API): $e');
      }
    }

    try {
      final fs = await _firestore
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: id)
          .get();
      for (final doc in fs.docs) {
        final d = doc.data();
        final pid = _stayListingApiId(d);
        if (pid != null && apiIds.contains(pid)) continue;
        merged.add(_MerchantStayPreview.fromFirestore(doc.id, d));
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
    setState(() => _loadingHeader = true);
    try {
      final user = _auth.currentUser;

      final doc = await _firestore
          .collection('marketplace_merchants')
          .doc(widget.merchantId.trim())
          .get();
      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        final rating = data['rating'];
        final status = (data['status'] ?? data['verificationStatus'] ?? '')
            .toString()
            .trim();
        final profileUrl =
            (data['profilePicture'] ?? data['profilepicture'] ?? '')
                .toString()
                .trim();
        final email =
            (data['email'] ?? data['userEmail'] ?? '').toString().trim();
        final phone = (data['phone'] ?? data['phoneNumber'] ?? '')
            .toString()
            .trim();
        bool following = _following;
        int followerCount = _followerCount;
        if (user != null) {
          final followSnap = await _firestore
              .collection('merchant_followers')
              .doc(widget.merchantId.trim())
              .collection('followers')
              .doc(user.uid)
              .get();
          following = followSnap.exists;
        }
        try {
          final followersSnap = await _firestore
              .collection('merchant_followers')
              .doc(widget.merchantId.trim())
              .collection('followers')
              .get();
          followerCount = followersSnap.size;
        } catch (_) {}
        setState(() {
          if (rating is num) _merchantRating = rating.toDouble();
          if (status.isNotEmpty) _merchantStatus = status;
          if (profileUrl.isNotEmpty) _merchantProfileUrl = profileUrl;
          if (email.isNotEmpty) _merchantEmail = email;
          if (phone.isNotEmpty) _merchantPhone = phone;
          _following = following;
          _followerCount = followerCount;
        });
      }

      // Fallback source to match dashboard profile data.
      final needsProfileFallback =
          (_merchantProfileUrl?.trim().isEmpty ?? true) ||
          (_merchantEmail?.trim().isEmpty ?? true) ||
          (_merchantPhone?.trim().isEmpty ?? true);
      if (needsProfileFallback) {
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.merchantId.trim())
            .get();
        if (userDoc.exists) {
          final u = userDoc.data() ?? <String, dynamic>{};
          final profileUrl = (u['profilepicture'] ??
                  u['profilePicture'] ??
                  u['photoUrl'] ??
                  u['photoURL'] ??
                  '')
              .toString()
              .trim();
          final email = (u['email'] ?? '').toString().trim();
          final phone = (u['phone'] ?? u['phoneNumber'] ?? '')
              .toString()
              .trim();
          if (mounted) {
            setState(() {
              if (profileUrl.isNotEmpty) _merchantProfileUrl = profileUrl;
              if (email.isNotEmpty) _merchantEmail = email;
              if (phone.isNotEmpty) _merchantPhone = phone;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading merchant header: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingHeader = false);
      }
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
              child: Text(
                '${widget.merchantName.trim().isEmpty ? 'Merchant' : widget.merchantName.trim()} Store',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: -0.2,
                ),
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
            name: widget.merchantName,
            email: _merchantEmail,
            phone: _merchantPhone,
            rating: _merchantRating,
            status: _merchantStatus,
            profileUrl: _merchantProfileUrl,
            loading: _loadingHeader,
            following: _following,
            followerCount: _followerCount,
            onToggleFollow: _toggleFollow,
            onBlock: _blockMerchant,
            onReport: _reportMerchant,
            onViewProfile: _showMerchantProfileViewer,
          ),
          Expanded(
            child: FutureBuilder<bool>(
              future: _isAccommodationMerchantFuture,
              builder: (context, modeSnap) {
                if (modeSnap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: _brandOrange,
                    ),
                  );
                }
                final isAccommodationHost = modeSnap.data ?? false;
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
          if (snapshot.connectionState == ConnectionState.waiting) {
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
                        size: 48, color: Colors.grey.shade400),
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

              final allItems =
                  snapshot.data ?? const <MarketplaceDetailModel>[];
          final items = _searchQuery.isEmpty
              ? allItems
              : allItems
                  .where((i) =>
                      i.name.toLowerCase().contains(_searchQuery))
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
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                  // If the Firestore item has a valid backend/sql id, open the full details page.
                  if (!it.hasValidSqlItemId) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailsPage(
                        item: marketplaceModel.MarketplaceDetailModel(
                          id: it.sqlItemId!,
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
      name: (d['name'] ?? 'Stay').toString(),
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
                    stay.name,
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

  final String name;
  final String? email;
  final String? phone;
  final double? rating;
  final String? status;
  final String? profileUrl;
  final bool loading;
  final bool following;
  final VoidCallback onToggleFollow;
  final int followerCount;
  final VoidCallback onBlock;
  final VoidCallback onReport;
  final VoidCallback onViewProfile;

  const _MerchantProfileCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.rating,
    required this.status,
    required this.profileUrl,
    required this.loading,
    required this.following,
    required this.onToggleFollow,
    required this.followerCount,
    required this.onBlock,
    required this.onReport,
    required this.onViewProfile,
  });

  ImageProvider? _profileImageProvider() {
    final raw = profileUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return NetworkImage(raw);
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
              InkWell(
                onTap: hasPhoto ? onViewProfile : null,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _kBrandOrange,
                        _kBrandNavy.withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.grey.shade100,
                      backgroundImage: img,
                      child: hasPhoto
                          ? null
                          : const Icon(Icons.storefront_rounded,
                              color: Colors.grey, size: 32),
                    ),
                  ),
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
                        Container(
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
                            ],
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