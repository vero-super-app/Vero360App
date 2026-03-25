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
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';

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
      return wrap(_ResilientNetworkImage(
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
        return wrap(_ResilientNetworkImage(
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

  Future<void> _blockMerchant() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block merchant'),
        content: const Text(
          'You will stop seeing this merchant in recommendations and listings. You can undo this later in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Block',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Merchant blocked (coming soon to sync across devices).')),
    );
  }

  Future<void> _reportMerchant() async {
    final controller = TextEditingController();
    XFile? picked;

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report merchant'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText:
                        'Tell us what is wrong (fraud, fake products, abuse, etc.)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final img = await ImagePicker()
                          .pickImage(source: ImageSource.gallery);
                      if (img != null) {
                        setLocal(() => picked = img);
                      }
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    picked == null
                        ? 'Add screenshot (optional)'
                        : 'Screenshot selected',
                  ),
                ),
                if (picked != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    picked!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Send report',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (sent != true || !mounted) return;

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

    final message = controller.text.trim();
    if (message.isEmpty && picked == null) {
      ToastHelper.showCustomToast(
        context,
        'Please write a report message or attach a screenshot.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending report…')),
    );

    try {
      String? proofUrl;
      if (picked != null) {
        final ext = picked!.name.toLowerCase().split('.').last;
        final safeExt = (ext.length <= 5) ? ext : 'png';
        final ref = FirebaseStorage.instance.ref().child(
              'reports/merchant/${widget.merchantId.trim()}/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.$safeExt',
            );
        final file = File(picked!.path);
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
    } catch (e) {
      debugPrint('Error loading merchant header: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingHeader = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        title: Text('${widget.merchantName} Store'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: _copyMerchantLink,
            tooltip: 'Copy merchant link',
          ),
          IconButton(
            icon: const Icon(Icons.share),
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
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products from ${widget.merchantName}...',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<MarketplaceDetailModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load products\n${snapshot.error}',
                textAlign: TextAlign.center,
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
              child: Text(
                _searchQuery.isEmpty
                    ? 'No products from this merchant yet.'
                    : 'No products match "$_searchQuery".',
                textAlign: TextAlign.center,
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
            padding: const EdgeInsets.all(12),
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
          )),
        ],
      ),
    );
  }
}

/// Network image that on load error retries with the other scheme (http <-> https).
class _ResilientNetworkImage extends StatefulWidget {
  const _ResilientNetworkImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<_ResilientNetworkImage> createState() => _ResilientNetworkImageState();
}

class _ResilientNetworkImageState extends State<_ResilientNetworkImage> {
  String get _currentUrl => _tryAlternate ? _alternateUrl : widget.url;
  late String _alternateUrl;
  bool _tryAlternate = false;

  @override
  void initState() {
    super.initState();
    _alternateUrl = _flipScheme(widget.url);
  }

  static String _flipScheme(String url) {
    final u = url.trim().toLowerCase();
    if (u.startsWith('https://')) return 'http://${url.substring(8)}';
    if (u.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }

  Widget _buildImage(String url) {
    return Image.network(
      url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        if (!_tryAlternate && _flipScheme(url) != url) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _tryAlternate = true);
          });
          return Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        );
      },
      loadingBuilder: (c, child, progress) {
        if (progress == null) return child;
        return Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey.shade100,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildImage(_currentUrl);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 0.6,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: img,
                child: hasPhoto
                    ? null
                    : const Icon(Icons.storefront_rounded,
                        color: Colors.grey, size: 32),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
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
                                .withOpacity(0.15),
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
                icon: const Icon(Icons.more_vert),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'block') {
                    onBlock();
                  } else if (value == 'report') {
                    onReport();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('block'),
                  ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report'),
                  ),
                ],
              ),
              if (!loading)
                IconButton(
                  onPressed: onToggleFollow,
                  icon: Icon(
                    following
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: following ? Colors.red : Colors.grey.shade700,
                  ),
                  tooltip: following ? 'Unfollow seller' : 'Follow seller',
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