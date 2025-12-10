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

import 'package:vero360_app/models/cart_model.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/toasthelper.dart';

/// --------------------
/// Local marketplace model (Firestore)
/// --------------------
class MarketplaceDetailModel {
  final String id;              // Firestore document id
  final int? sqlItemId;         // Optional numeric backend id for Nest/SQL
  final String name;
  final String category;
  final double price;
  final String image;           // raw string from Firestore (base64 or URL)
  final Uint8List? imageBytes;  // decoded image if base64
  final String? description;
  final String? location;
  final bool isActive;
  final DateTime? createdAt;

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
  });

  /// True only if there is a valid numeric backend id
  bool get hasValidSqlItemId => sqlItemId != null && sqlItemId! > 0;

  factory MarketplaceDetailModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    // --- image: base64 → bytes ---
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
    );
  }
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
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hrs ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return '$weeks weeks ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '$months months ago';
    final years = (diff.inDays / 365).floor();
    return '$years years ago';
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

    _showLoadingDialog();

    try {
      // Prefer numeric id from backend if available, otherwise derive from doc.id
      final int numericItemId = item.hasValidSqlItemId
          ? item.sqlItemId!
          : _stablePositiveIdFromString(item.id);

      final cartItem = CartModel(
        userId: '0',
        item: numericItemId, // always positive
        quantity: 1,
        name: item.name,
        image: item.image,
        price: item.price,
        description: item.description ?? '',
        comment: note ?? '',
      );

      await widget.cartService.addToCart(cartItem);

      ToastHelper.showCustomToast(
        context,
        '${item.name} added to cart!',
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

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Adding to cart...",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  // ---------- Details bottom sheet ----------
  Future<void> _showDetailsBottomSheet(MarketplaceDetailModel item) async {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
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
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildItemImageWidget(item),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "MWK ${item.price.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
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
                      "Posted ${_formatTimeAgo(item.createdAt!)}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (item.description != null &&
                      item.description!.trim().isNotEmpty)
                    Text(
                      item.description!,
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _addToCart(item);
                          },
                          icon: const Icon(Icons.shopping_cart),
                          label: const Text("Add to Cart"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Buy Now"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- UI ----------
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
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),

          // Category chips
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
                          child: Text(
                            "Failed to load items",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  }

                  final items =
                      snapshot.data ?? const <MarketplaceDetailModel>[];
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

                  return Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 700;
                        final crossAxisCount = isWide ? 3 : 2;
                        final childAspectRatio = isWide ? 0.70 : 0.68;

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
                              onTap: () => _showDetailsBottomSheet(item),
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
      {required bool isSelected, required VoidCallback onTap}) {
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

  Widget _buildItemImageWidget(MarketplaceDetailModel item) {
    if (item.imageBytes != null) {
      return Image.memory(
        item.imageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    }

    if (item.image.isNotEmpty && item.image.startsWith('http')) {
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
            child: const CircularProgressIndicator(strokeWidth: 2),
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
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(15)),
                    child: _buildItemImageWidget(item),
                  ),
                ),
                if (cat.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Chip(
                      label: Text(_titleCase(cat)),
                      backgroundColor: Colors.black.withOpacity(0.75),
                      labelStyle: const TextStyle(color: Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
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
                const SizedBox(height: 4),
                Text(
                  "MWK ${item.price.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                if (item.location != null &&
                    item.location!.trim().isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 12, color: Colors.redAccent),
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
                    _formatTimeAgo(item.createdAt!),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
}

