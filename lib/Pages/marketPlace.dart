// lib/Pages/marketPlace.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/Pages/checkout_page.dart';
import 'package:vero360_app/models/marketplace.model.dart'
    as core; // 👈 alias to avoid name clash

import 'package:vero360_app/models/cart_model.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/toasthelper.dart';

// 🔹 Chat + seller info
import 'package:vero360_app/Pages/Home/Messages.dart';
import 'package:vero360_app/services/chat_service.dart';
import 'package:vero360_app/services/serviceprovider_service.dart';
import 'package:vero360_app/models/serviceprovider_model.dart';

/// --------------------
/// Local marketplace model (Firestore) - UPDATED WITH MERCHANT FIELDS
/// --------------------
class MarketplaceDetailModel {
  final String id; // Firestore document id
  final int? sqlItemId; // Optional numeric backend id for Nest/SQL

  final String name;
  final String category;
  final double price;

  /// raw string from Firestore (base64 or URL)
  final String image;

  /// decoded image if base64
  final Uint8List? imageBytes;

  final String? description;
  final String? location;
  final bool isActive;
  final DateTime? createdAt;
  // NEW: Merchant fields for wallet integration
  final String? merchantId;
  final String? merchantName;
  final String? serviceType;

  // 🔹 Optional gallery & seller metadata (for richer UI + chat)
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
  });

  /// True only if there is a valid numeric backend id
  bool get hasValidSqlItemId => sqlItemId != null && sqlItemId! > 0;

  /// NEW: Check if this item has valid merchant info for wallet payments
  bool get hasValidMerchantInfo => 
      merchantId != null && 
      merchantId!.isNotEmpty && 
      merchantId != 'unknown' &&
      merchantName != null &&
      merchantName!.isNotEmpty &&
      merchantName != 'Unknown Merchant';

  factory MarketplaceDetailModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    // --- image: base64 → bytes (if applicable) ---
    final rawImage = (data['image'] ?? '').toString();
    Uint8List? bytes;
    if (rawImage.isNotEmpty) {
      try {
        bytes = base64Decode(rawImage);
      } catch (_) {
        bytes = null; // if it's actually a URL, decoding will fail
      }
    }

    // --- createdAt: Timestamp → DateTime ---
    DateTime? created;
    final createdRaw = data['createdAt'];
    if (createdRaw is Timestamp) {
      created = createdRaw.toDate();
    } else if (createdRaw is DateTime) {
      created = createdRaw;
    }

    // --- price: number ---
    double price = 0;
    final p = data['price'];
    if (p is num) {
      price = p.toDouble();
    } else if (p != null) {
      price = double.tryParse(p.toString()) ?? 0;
    }

    // --- helper to parse any int-like field ---
    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(
        v.toString().replaceAll(RegExp(r'[^\d]'), ''),
      );
    }

    // Try multiple keys in case your docs use different names
    final rawSql =
        data['sqlItemId'] ?? data['backendId'] ?? data['itemId'] ?? data['id'];
    final sqlId = _parseInt(rawSql);

    final cat = (data['category'] ?? '').toString().toLowerCase();

    // --- optional gallery (urls) ---
    List<String> gallery = const [];
    final galleryRaw = data['gallery'];
    if (galleryRaw is List) {
      gallery = galleryRaw.map((e) => e.toString()).toList();
    }

    // --- seller info (optional) ---
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
      sellerBusinessDescription:
          data['sellerBusinessDescription']?.toString(),
      sellerRating: sellerRating,
      sellerLogoUrl: data['sellerLogoUrl']?.toString(),
      serviceProviderId: data['serviceProviderId']?.toString(),
      sellerUserId: data['sellerUserId']?.toString(),
    );
  }
}

/// --------------------
/// Seller info helper
/// --------------------
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
    if (hasHalf)
      const Icon(Icons.star_half, size: 16, color: Colors.amber),
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
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54),
          ),
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

  static const List<String> _kCategories = <String>[
    'food',
    'drinks',
    'electronics',
    'clothes',
    'shoes',
    'other'
  ];
  String? _selectedCategory; // null = all

  Timer? _debounce;
  String _lastQuery = '';
  bool _loading = false;
  bool _photoMode = false;

  late Future<List<MarketplaceDetailModel>> _future;

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
    super.dispose();
  }

  // ---------- Helper: time ago ----------
String _formatTimeAgo(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);

  if (diff.inSeconds < 60) return 'Just now';

  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    final unit = m == 1 ? 'min' : 'mins';
    return '$m $unit ago'; // 1 min ago / 2 mins ago
  }

  if (diff.inHours < 24) {
    final h = diff.inHours;
    final unit = h == 1 ? 'hr' : 'hrs';
    return '$h $unit ago'; // 1 hr ago / 3 hrs ago
  }

  if (diff.inDays < 7) {
    final d = diff.inDays;
    final unit = d == 1 ? 'day' : 'days';
    return '$d $unit ago'; // 1 day ago / 4 days ago
  }

  final weeks = (diff.inDays / 7).floor();
  if (weeks < 4) {
    final unit = weeks == 1 ? 'week' : 'weeks';
    return '$weeks $unit ago'; // 1 week ago / 3 weeks ago
  }

  final months = (diff.inDays / 30).floor();
  if (months < 12) {
    final unit = months == 1 ? 'month' : 'months';
    return '$months $unit ago'; // 1 month ago / 6 months ago
  }

  final years = (diff.inDays / 365).floor();
  final unit = years == 1 ? 'year' : 'years';
  return '$years $unit ago'; // 1 year ago / 2 years ago
}

  // Stable positive int from a string (Firestore doc id)
  int _stablePositiveIdFromString(String s) {
    int hash = 0;
    for (final code in s.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff; // keep it positive
    }
    if (hash == 0) hash = 1; // ensure > 0
    return hash;
  }

  // ---------- Data loaders (Firestore) ----------
  Future<List<MarketplaceDetailModel>> _loadAll({String? category}) async {
    setState(() {
      _loading = true;
      _photoMode = false;
      _selectedCategory = category;
    });

    try {
      final snapshot = await _firestore
          .collection('marketplace_items')
          .orderBy('createdAt', descending: true)
          .get();

      final all = snapshot.docs
          .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
          .where((item) => item.isActive)
          .toList();

      if (category == null || category.isEmpty) {
        return all;
      }

      final c = category.toLowerCase();
      return all.where((item) => item.category.toLowerCase() == c).toList();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<MarketplaceDetailModel>> _searchByName(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || q.length < 2) {
      return _loadAll(category: _selectedCategory);
    }

    setState(() {
      _loading = true;
      _photoMode = false;
    });

    try {
      final all = await _loadAll(category: _selectedCategory);
      final lower = q.toLowerCase();
      return all
          .where((item) => item.name.toLowerCase().contains(lower))
          .toList();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  // ---------- Auth helpers ----------
  Future<String?> _readAuthToken() async {
    final sp = await SharedPreferences.getInstance();
    for (final k in const ['token', 'jwt_token', 'jwt']) {
      final v = sp.getString(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<bool> _isLoggedIn() async => (await _readAuthToken()) != null;

  Future<bool> _requireLoginForChat() async {
    final t = await _readAuthToken();
    final ok = t != null && t.isNotEmpty;
    if (!ok && mounted) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to chat with merchant.',
        isSuccess: false,
        errorMessage: 'Not logged in',
      );
    }
    return ok;
  }

  // ---------- Cart ----------
  Future<void> _addToCart(MarketplaceDetailModel item, {String? note}) async {
    final token = await _readAuthToken();
    if (token == null || token.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to add items to cart.',
        isSuccess: false,
        errorMessage: 'Not logged in',
      );
      return;
    }

    // NEW: Check if item has valid merchant info for wallet payments
    if (!item.hasValidMerchantInfo) {
      ToastHelper.showCustomToast(
        context,
        'This item cannot be added to cart: Missing merchant information.',
        isSuccess: false,
        errorMessage: 'Invalid merchant info',
      );
      return;
    }

    _showLoadingDialog();

    try {
      final userId = await _getCurrentUserId() ?? 'unknown';
      
      // Prefer numeric id from backend if available, otherwise derive from doc.id
      final int numericItemId = item.hasValidSqlItemId
          ? item.sqlItemId!
          : _stablePositiveIdFromString(item.id);

      // UPDATED: Create CartModel with merchant information
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
      );

      await widget.cartService.addToCart(cartItem);

      ToastHelper.showCustomToast(
        context,
        '${item.name} added to cart!\nFunds will go to ${item.merchantName}',
        isSuccess: true,
        errorMessage: 'OK',
      );
    } on TimeoutException {
      ToastHelper.showCustomToast(
        context,
        'Server is taking too long. Please try again.',
        isSuccess: false,
        errorMessage: 'Timeout',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Failed to add item: $e',
        isSuccess: false,
        errorMessage: 'Add to cart failed',
      );
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  // ---------- Chat ----------
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

    final sellerName = item.sellerBusinessName ?? 'Seller';
    final sellerAvatar = item.sellerLogoUrl ?? '';

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

  // ---------- Checkout from bottom sheet ----------
  Future<void> _goToCheckoutFromBottomSheet(
      MarketplaceDetailModel item) async {
  
    if (!mounted) return;

    // 🔹 Convert local Firestore item -> core model item
    final core.MarketplaceDetailModel checkoutItem =
        core.MarketplaceDetailModel(
      // ⚠️ Make sure these match your core model constructor
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
      //createdAt: item.createdAt,
      // If your core model also has `isActive`, `videos`, etc.,
      // you can pass them here as well.
    );

    // 🔹 Now push to CheckoutPage with the *core* model
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPage(item: checkoutItem),
      ),
    );
  }

  // ---------- Search handlers ----------
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
            content: Text('Photo search works best in mobile builds.')),
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
    setState(() => _future = _loadAll(category: _selectedCategory));
    await _future;
  }

  // ---------- Details bottom sheet (RICH VERSION) ----------
  Future<void> _showDetailsBottomSheet(MarketplaceDetailModel item) async {
    if (!mounted) return;

    // Load seller info once
    final Future<_SellerInfo> sellerFuture = _loadSellerForItem(item);

    // Build media list: we support 1 main image + optional gallery URLs
    final List<String> mediaUrls = [];
    if (item.image.isNotEmpty && item.image.startsWith('http')) {
      mediaUrls.add(item.image);
    }
    if (item.gallery.isNotEmpty) {
      mediaUrls.addAll(item.gallery.where((u) => u.trim().isNotEmpty));
    }

    final pageController = PageController();
    int currentPage = 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return SingleChildScrollView(
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
                      final businessName = seller?.businessName;
                      final openingHours = seller?.openingHours;
                      final closing = _closingFromHours(openingHours);
                      final status = seller?.status;
                      final rating = seller?.rating;
                      final businessDesc = seller?.description;
                      final logo = seller?.logoUrl;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Drag handle
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

                          // ----- MEDIA AREA -----
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: mediaUrls.isEmpty
                                      ? _buildItemImageWidget(item)
                                      : PageView.builder(
                                          controller: pageController,
                                          itemCount: mediaUrls.length,
                                          physics: mediaUrls.length > 1
                                              ? const BouncingScrollPhysics()
                                              : const NeverScrollableScrollPhysics(),
                                          onPageChanged: (i) =>
                                              setModalState(
                                                  () => currentPage = i),
                                          itemBuilder: (_, i) {
                                            return Image.network(
                                              mediaUrls[i],
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                color: Colors.grey.shade200,
                                                child: const Center(
                                                  child: Icon(Icons
                                                      .image_not_supported_rounded),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                if (mediaUrls.length > 1) ...[
                                  Positioned(
                                    left: 4,
                                    top: 0,
                                    bottom: 0,
                                    child: Material(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(24),
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(24),
                                        onTap: () {
                                          final prev = (currentPage -
                                                      1 +
                                                      mediaUrls.length) %
                                                  mediaUrls.length;
                                          pageController.animateToPage(
                                            prev,
                                            duration: const Duration(
                                                milliseconds: 300),
                                            curve: Curves.easeOut,
                                          );
                                        },
                                        child: const SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: Icon(Icons.chevron_left,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 0,
                                    bottom: 0,
                                    child: Material(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(24),
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(24),
                                        onTap: () {
                                          final next =
                                              (currentPage + 1) %
                                                  mediaUrls.length;
                                          pageController.animateToPage(
                                            next,
                                            duration: const Duration(
                                                milliseconds: 300),
                                            curve: Curves.easeOut,
                                          );
                                        },
                                        child: const SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: Icon(Icons.chevron_right,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    left: 0,
                                    right: 0,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children:
                                          List.generate(mediaUrls.length, (i) {
                                        final active = i == currentPage;
                                        return AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          width: active ? 18 : 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? Colors.orange
                                                : Colors.white70,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: Colors.black26),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ----- TITLE + PRICE + CHAT -----
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFE8CC),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: const Color(0xFFFF8A00)),
                                      ),
                                      child: Text(
                                        "MWK ${item.price.toStringAsFixed(0)}",
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.location_on,
                                              size: 16,
                                              color: Colors.redAccent),
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
                                        "Posted ${_formatTimeAgo(item.createdAt!)}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
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
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                onPressed: () =>
                                    _openChatWithMerchant(item),
                                icon: const Icon(Icons.message_rounded),
                                label: const Text('Chat'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if ((item.description ?? '').trim().isNotEmpty)
                            Text(
                              item.description!.trim(),
                              style: const TextStyle(
                                  fontSize: 14, height: 1.3),
                            ),

                          const SizedBox(height: 16),

                          // ----- SELLER CARD -----
                          Card(
                            elevation: 4,
                            shadowColor: Colors.black12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 14, 16, 14),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (logo != null && logo.isNotEmpty)
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundImage:
                                              NetworkImage(logo),
                                        ),
                                      if (logo != null && logo.isNotEmpty)
                                        const SizedBox(width: 10),
                                      const Icon(
                                          Icons.storefront_rounded,
                                          size: 20,
                                          color: Colors.black87),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          businessName ?? 'Posted by —',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _ratingStars(rating),
                                      const SizedBox(width: 8),
                                      _statusChip(status),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _infoRow('Business name', businessName,
                                      icon: Icons.badge_rounded),
                                  _infoRow('Closing hours', closing,
                                      icon: Icons.access_time_rounded),
                                  _infoRow(
                                    'Status',
                                    (status ?? '').isEmpty
                                        ? '—'
                                        : status!.toUpperCase(),
                                    icon:
                                        Icons.info_outline_rounded,
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Business description',
                                    style: TextStyle(
                                        color: Colors.black54),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (businessDesc ?? '').isNotEmpty
                                        ? businessDesc!
                                        : '—',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ----- ACTION BUTTON -----
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFFFF8A00),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _goToCheckoutFromBottomSheet(item);
                              },
                              icon: const Icon(
                                  Icons.shopping_bag_outlined),
                              label: const Text("Continue to checkout"),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      pageController.dispose();
    });
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          "Market Place",
          style:
              TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmit,
              decoration: InputDecoration(
                hintText: "Search items...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSubmit('');
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _showPhotoPickerSheet,
                      tooltip: 'Search by Photo',
                    ),
                  ],
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
              ),
            ),
          ),

          // Category chips
          SizedBox(
            height: 44,
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8),
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryChip(
                  "All Products",
                  isSelected:
                      _selectedCategory == null && !_photoMode,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: const [
                  Icon(Icons.image_search, size: 16),
                  SizedBox(width: 6),
                  Text("Showing results from photo search"),
                ],
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<
                  List<MarketplaceDetailModel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (_loading &&
                      snapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            "Failed to load items",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  }

                  final items = snapshot.data ??
                      const <MarketplaceDetailModel>[];
                  if (items.isEmpty) {
                    return ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _photoMode
                                ? "No visually similar items found"
                                : "No items available",
                            style: const TextStyle(
                                color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide =
                            constraints.maxWidth >= 700;
                        final crossAxisCount =
                            isWide ? 3 : 2;
                        final childAspectRatio =
                            isWide ? 0.70 : 0.68;

                        return GridView.builder(
                          itemCount: items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            return GestureDetector(
                              onTap: () =>
                                  _showDetailsBottomSheet(item),
                              child: _buildMarketItem(item),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Widgets ----------
  Widget _buildCategoryChip(String title,
      {required bool isSelected,
      required VoidCallback onTap}) {
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
        backgroundColor:
            isSelected ? Colors.orange : Colors.grey[300],
        padding:
            const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }

  Widget _buildItemImageWidget(MarketplaceDetailModel item) {
    if (item.imageBytes != null) {
      return Image.memory(
        item.imageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    }

    if (item.image.isNotEmpty &&
        item.image.startsWith('http')) {
      return Image.network(
        item.image,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[300],
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey[200],
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
                strokeWidth: 2),
          );
        },
      );
    }

    return Container(
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(Icons.image, size: 32),
    );
  }

  Widget _buildMarketItem(MarketplaceDetailModel item) {
    final cat = (item.category).trim();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          // Photo
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(
                            top: Radius.circular(15)),
                    child: _buildItemImageWidget(item),
                  ),
                ),
                if (cat.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Chip(
                      label: Text(_titleCase(cat)),
                      backgroundColor: Colors.black.withValues(alpha: 0.75),
                      labelStyle: const TextStyle(color: Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                // NEW: Merchant badge on image
                if (item.merchantName != null && item.merchantName!.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.merchantName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Texts
          Padding(
            padding: const EdgeInsets.fromLTRB(
                10, 10, 10, 6),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "MWK ${item.price.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                if (item.location != null &&
                    item.location!.trim().isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                          Icons.location_on,
                          size: 12,
                          color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                if (item.createdAt != null)
                  Text(
                    _formatTimeAgo(
                        item.createdAt!),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
              ],
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(
                10, 0, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _addToCart(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.green,
                      foregroundColor:
                          Colors.white,
                      padding: const EdgeInsets
                          .symmetric(
                              vertical: 10),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                                10),
                      ),
                    ),
                    child:
                        const Text("AddCart"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _showDetailsBottomSheet(
                            item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.red,
                      foregroundColor:
                          Colors.white,
                      padding: const EdgeInsets
                          .symmetric(
                              vertical: 10),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                                10),
                      ),
                    ),
                    child:
                        const Text("BuyNow"),
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
}