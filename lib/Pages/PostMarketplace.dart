// lib/Pages/PostMarketplace.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/Pages/myshop.dart';
import 'package:vero360_app/models/marketplace.model.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/services/serviceprovider_service.dart';

import '../toasthelper.dart';
import 'marketplace_edit_page.dart';

class LocalMedia {
  final Uint8List bytes;
  final String filename;
  final String? mime;
  final bool isVideo;
  const LocalMedia({
    required this.bytes,
    required this.filename,
    this.mime,
    this.isVideo = false,
  });
}

class MarketplaceCrudPage extends StatefulWidget {
  const MarketplaceCrudPage({super.key});

  @override
  State<MarketplaceCrudPage> createState() => _MarketplaceCrudPageState();
}

class _MarketplaceCrudPageState extends State<MarketplaceCrudPage>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  late final TabController _tabs;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();

  bool _isActive = true;
  bool _submitting = false;

  static const List<String> _kCategories = <String>[
    'food',
    'drinks',
    'electronics',
    'clothes',
    'shoes',
    'other',
  ];
  String? _category = 'other';

  // media (create tab)
  LocalMedia? _cover;
  final List<LocalMedia> _gallery = <LocalMedia>[];
  final List<LocalMedia> _videos = <LocalMedia>[];

  // manage tab
  List<Map<String, dynamic>> _items = [];
  bool _loadingItems = true;
  bool _busyRow = false; // disables per-card buttons when true

  // shop check
  bool _checkingShop = true;
  bool _hasShop = false;
  Map<String, dynamic>? _myShop; // NEW: Store shop details

  // Firestore only (no Firebase Auth, no Storage)
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // NestJS service provider client
  final _spService = ServiceproviderService();

  // --- Brand look to match Airport/Vero Courier ---
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFE8CC);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    await _checkShop();
    await _loadItems();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _price.dispose();
    _location.dispose();
    _desc.dispose();
    super.dispose();
  }

  // ---------------- NESTJS AUTH (JWT) ----------------

  /// Try to read JWT from SharedPreferences, decode payload and return userId as string.
  /// We do NOT block if this fails – posting still works.
  Future<String?> _getNestUserId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final token = sp.getString('jwt') ?? sp.getString('token');
      if (token == null || token.isEmpty) return null;

      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payloadJson = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payload =
          jsonDecode(payloadJson) as Map<String, dynamic>;

      final dynamic rawId =
          payload['sub'] ?? payload['id'] ?? payload['userId'];
      if (rawId == null) return null;
      return rawId.toString();
    } catch (_) {
      return null;
    }
  }

  // ---------------- shop check ----------------
  Future<void> _checkShop() async {
    setState(() => _checkingShop = true);
    try {
      // Use getMerchantInfo() instead of fetchMine() to get Map directly
      final sp = await _spService.getMerchantInfo();
      // if this works, backend already knows you're logged in
      if (sp != null) {
        _hasShop = true;
        _myShop = sp;
        
        // Debug: Print merchant info
        print('Merchant Info Loaded:');
        print('  Merchant ID: ${_myShop?['id']}');
        print('  Business Name: ${_myShop?['businessName']}');
        print('  Service Type: marketplace');
      } else {
        _hasShop = false;
        _myShop = null;
      }
    } catch (e) {
      _hasShop = false;
      _myShop = null;
      print('Error fetching shop: $e');
    } finally {
      if (mounted) setState(() => _checkingShop = false);
    }
  }

  // ---------------- data ----------------
  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);
    try {
      final sellerId = await _getNestUserId();

      Query<Map<String, dynamic>> query =
          _db.collection('marketplace_items');

      // If we can identify user → show only their items.
      // If not → show all items (no auth blocking).
      if (sellerId != null) {
        query = query.where('sellerUserId', isEqualTo: sellerId);
      }

      final snap = await query.get();

      _items =
          snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Load failed: $e',
        isSuccess: false,
        errorMessage: 'Load failed',
      );
      _items = [];
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item'),
        content: Text('Delete "${item['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyRow = true);
    try {
      final id = item['id'] as String;
      await _db.collection('marketplace_items').doc(id).delete();
      // All media is inside Firestore as base64; nothing in Storage to delete.
      _items.removeWhere((e) => e['id'] == id);
      setState(() {});
      ToastHelper.showCustomToast(
        context,
        'Deleted • ${item['name']}',
        isSuccess: true,
        errorMessage: 'Deleted',
      );
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Delete failed: $e',
        isSuccess: false,
        errorMessage: 'Delete failed',
      );
    } finally {
      if (mounted) setState(() => _busyRow = false);
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    final marketplaceItem = _createMarketplaceDetailModel(item);

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceEditPage(item: marketplaceItem),
      ),
    );
    if (changed == true) {
      await _loadItems();
    }
  }

  // Helper to create MarketplaceDetailModel from Map
  MarketplaceDetailModel _createMarketplaceDetailModel(
      Map<String, dynamic> item) {
    return MarketplaceDetailModel(
      // Firestore doc id is string, model expects int → just use 0 here
      id: 0,
      name: item['name'] as String? ?? '',
      image: item['image'] as String? ?? '',
      price: (item['price'] as num?)?.toDouble() ?? 0.0,
      description: item['description'] as String? ?? '',
      location: item['location'] as String? ?? '',
      category: (item['category'] as String?) ?? 'other',
      gallery: (item['gallery'] as List<dynamic>?)?.cast<String>() ??
          const [],
      videos: (item['videos'] as List<dynamic>?)?.cast<String>() ??
          const [],
      sellerUserId: item['sellerUserId'] as String?,
      merchantId: item['merchantId'] as String?, // NEW
      merchantName: item['merchantName'] as String?, // NEW
      serviceType: item['serviceType'] as String?, // NEW
      // isActive / createdAt are NOT part of the constructor in this model
    );
  }

  // ---------------- pickers (bytes) ----------------
  Future<void> _pickCover(ImageSource src) async {
    final x = await _picker.pickImage(
      source: src,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _cover = LocalMedia(
        bytes: bytes,
        filename: x.name,
        mime: lookupMimeType(x.name, headerBytes: bytes),
      );
    });
  }

  Future<void> _pickGalleryMulti() async {
    final xs = await _picker.pickMultiImage(
      imageQuality: 90,
      maxWidth: 2048,
    );
    for (final x in xs) {
      final bytes = await x.readAsBytes();
      _gallery.add(
        LocalMedia(
          bytes: bytes,
          filename: x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes),
        ),
      );
    }
    setState(() {});
  }

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    _videos.add(
      LocalMedia(
        bytes: bytes,
        filename: x.name,
        mime: lookupMimeType(x.name, headerBytes: bytes),
        isVideo: true,
      ),
    );
    setState(() {});
  }

  void _removeGalleryAt(int i) {
    _gallery.removeAt(i);
    setState(() {});
  }

  void _removeVideoAt(int i) {
    _videos.removeAt(i);
    setState(() {});
  }

  void _clearCover() {
    _cover = null;
    setState(() {});
  }

  // ---------------- BASE64 "COMPRESSION" (NO STORAGE) ----------------
  Future<Uint8List> _compressImage(Uint8List imageBytes) async {
    try {
      // Minimal compression stub – you can plug in flutter_image_compress
      // here if you like. For now we just return the bytes as-is.
      return imageBytes;
    } catch (_) {
      return imageBytes;
    }
  }

  /// Compress (for images) and return base64 string.
  Future<String> _encodeMediaAsBase64(LocalMedia media) async {
    try {
      Uint8List bytesToEncode = media.bytes;

      if (!media.isVideo) {
        bytesToEncode = await _compressImage(bytesToEncode);
      }

      return base64Encode(bytesToEncode);
    } catch (e) {
      throw ApiException(message: 'Encode failed: $e');
    }
  }

  Future<List<String>> _encodeAll(List<LocalMedia> items) async {
    final out = <String>[];
    for (final m in items) {
      out.add(await _encodeMediaAsBase64(m));
    }
    return out;
  }

  // ---------------- create ----------------
  Future<void> _create() async {
    // Must have shop guard (but no extra auth check here)
    if (!_hasShop) {
      ToastHelper.showCustomToast(
        context,
        'You need to open a shop before posting on Marketplace.',
        isSuccess: false,
        errorMessage: 'No shop',
      );
      return;
    }

    if (!_form.currentState!.validate()) return;
    if (_cover == null) {
      ToastHelper.showCustomToast(
        context,
        'Please pick a cover photo',
        isSuccess: false,
        errorMessage: 'Photo required',
      );
      return;
    }

    // NEW: Validate merchant info
    if (_myShop == null || _myShop!['id'] == null || _myShop!['businessName'] == null) {
      ToastHelper.showCustomToast(
        context,
        'Unable to identify merchant information. Please check your shop profile.',
        isSuccess: false,
        errorMessage: 'Missing merchant info',
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // 1️⃣ Try to get NestJS user id, but DO NOT block if null
      final sellerId = await _getNestUserId();

      // 2️⃣ Encode all media to base64
      String coverBase64;
      List<String> galleryBase64 = [];
      List<String> videoBase64 = [];

      try {
        coverBase64 = await _encodeMediaAsBase64(_cover!);
        galleryBase64 = await _encodeAll(_gallery);
        videoBase64 = await _encodeAll(_videos);
      } catch (e) {
        ToastHelper.showCustomToast(
          context,
          'Image encoding failed: $e',
          isSuccess: false,
          errorMessage: 'Upload failed',
        );
        return;
      }

      // 3️⃣ Get merchant information from shop
      final merchantId = _myShop!['id'].toString();
      final merchantName = _myShop!['businessName'].toString();
      final serviceType = 'marketplace'; // Fixed for marketplace items

      print('Creating item with merchant info:');
      print('  Merchant ID: $merchantId');
      print('  Merchant Name: $merchantName');
      print('  Service Type: $serviceType');

      // 4️⃣ Create marketplace item in Firestore WITH MERCHANT INFO
      final data = {
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'image': coverBase64, // base64 string
        'description':
            _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'location': _location.text.trim(),
        'isActive': _isActive,
        'category': _category ?? 'other',
        'gallery': galleryBase64, // base64 strings
        'videos': videoBase64, // base64 strings (careful: large)
        'createdAt': FieldValue.serverTimestamp(),
        // if sellerId is null we still allow posting
        'sellerUserId': sellerId ?? 'unknown',
        // NEW: Merchant information for wallet payments
        'merchantId': merchantId,
        'merchantName': merchantName,
        'serviceType': serviceType,
      };

      final docRef = await _db.collection('marketplace_items').add(data);
      
      print('Item created with ID: ${docRef.id}');
      print('Full data: $data');

      ToastHelper.showCustomToast(
        context,
        'Item Posted Successfully!\nFunds will go to your merchant wallet.',
        isSuccess: true,
        errorMessage: 'Created',
      );

      // Reset form and media
      _form.currentState!.reset();
      _name.clear();
      _price.clear();
      _location.clear();
      _desc.clear();
      _cover = null;
      _gallery.clear();
      _videos.clear();
      _isActive = true;
      _category = 'other';

      setState(() {});

      // Reload items and switch to manage tab
      await _loadItems();
      _tabs.animateTo(1);
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Create failed: $e',
        isSuccess: false,
        errorMessage: 'Create failed',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------- location helpers ----------------
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ToastHelper.showCustomToast(
          context,
          'Location services are disabled. Please enable them.',
          isSuccess: false,
          errorMessage: 'Location disabled',
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ToastHelper.showCustomToast(
            context,
            'Location permissions are denied.',
            isSuccess: false,
            errorMessage: 'Permission denied',
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ToastHelper.showCustomToast(
          context,
          'Location permissions are permanently denied. Please enable in settings.',
          isSuccess: false,
          errorMessage: 'Permission denied',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) {
        ToastHelper.showCustomToast(
          context,
          'Could not fetch address.',
          isSuccess: false,
          errorMessage: 'Address fetch failed',
        );
        return;
      }
      final place = placemarks[0];
      final address = [
        place.name,
        place.street,
        place.locality,
        place.administrativeArea,
        place.country,
      ].where((e) => e != null && e.isNotEmpty).join(', ');
      setState(() {
        _location.text = address;
      });
    } catch (e) {
      ToastHelper.showCustomToast(
        context,
        'Failed to get location: $e',
        isSuccess: false,
        errorMessage: 'Location failed',
      );
    }
  }

  Future<void> _openGoogleMap() async {
    if (_location.text.trim().isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Enter a location first.',
        isSuccess: false,
        errorMessage: 'No location',
      );
      return;
    }
    final query = Uri.encodeComponent(_location.text.trim());
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showCustomToast(
        context,
        'Could not open Google Maps.',
        isSuccess: false,
        errorMessage: 'Map failed',
      );
    }
  }

  // ---------------- time ago ----------------
  String _timeAgo(DateTime? date) {
    if (date == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}m ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}min ago';
    } else {
      return '${diff.inSeconds}s ago';
    }
  }

  // ---------------- UI helpers (brand look) ----------------
  InputDecoration _inputDecoration({
    String? label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  ButtonStyle _filledBtnStyle({double padV = 14}) =>
      FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: EdgeInsets.symmetric(vertical: padV, horizontal: 14),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final canCreate = !_submitting && _cover != null && _hasShop && _myShop != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Add Item'),
            Tab(text: 'Manage My Items'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildAddTab(canCreate),
            _buildManageTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTab(bool canCreate) {
    // While checking shop, show loader
    if (_checkingShop) {
      return const Center(child: CircularProgressIndicator());
    }

    // No shop -> show message and CTA to open a shop
    if (!_hasShop) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 8,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _brandOrange.withOpacity(0.35),
                    ),
                  ),
                  child: const Text(
                    'To post on Marketplace you must first open your shop. '
                    'Create your shop profile with a logo and opening hours, then come back here.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 20),
                const Icon(
                  Icons.storefront_outlined,
                  size: 80,
                  color: Colors.black38,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServiceProviderCrudPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.store),
                  label: const Text('Open My Shop'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // NEW: Show merchant info banner
    final merchantInfo = _myShop != null 
        ? Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_circle, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Merchant: ${_myShop!['businessName']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                      Text(
                        'Service: Marketplace',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                        ),
                      ),
                      if (_myShop?['id'] != null)
                        Text(
                          'ID: ${_myShop!['id']}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
          )
        : Container();

    // Normal form when a shop exists
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Card(
        elevation: 8,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Merchant info banner
                merchantInfo,

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    border: Border.all(color: _brandOrange.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.info_outline,
                        color: Colors.black87,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Add clear photos, set the right category, location and price. '
                          'Images are automatically compressed and stored safely.\n'
                          'NOTE: Payments for this item will go to your merchant wallet.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  'Add Product',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // Cover image preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _cover == null
                      ? Container(
                          height: 220,
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: Icon(
                              Icons.image,
                              size: 64,
                              color: Colors.black38,
                            ),
                          ),
                        )
                      : Image.memory(
                          _cover!.bytes,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      style: _filledBtnStyle(padV: 12),
                      onPressed: () => _pickCover(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(
                          color: Colors.black,
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => _pickCover(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Camera'),
                    ),
                    const Spacer(),
                    if (_cover != null)
                      TextButton.icon(
                        onPressed: _clearCover,
                        icon: const Icon(Icons.close),
                        label: const Text('Clear'),
                      ),
                  ],
                ),

                const SizedBox(height: 16),
                const Text(
                  'More photos (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _mediaStripImages(),

                const SizedBox(height: 12),
                const Text(
                  'Videos (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _mediaStripVideos(),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _name,
                  decoration: _inputDecoration(label: 'Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _inputDecoration(label: 'Price (MWK)'),
                  validator: (v) {
                    final pv = double.tryParse(v?.trim() ?? '');
                    if (pv == null || pv <= 0) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _location,
                  decoration:
                      _inputDecoration(label: 'Location').copyWith(
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.my_location),
                            tooltip: 'Use current location',
                            onPressed: _getCurrentLocation,
                          ),
                          IconButton(
                            icon: const Icon(Icons.map),
                            tooltip: 'View on Google Maps',
                            onPressed: _openGoogleMap,
                          ),
                        ],
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Location is required'
                          : null,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: _category,
                  items: _kCategories
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(_titleCase(c)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _category = v),
                  decoration: _inputDecoration(label: 'Category'),
                  validator: (v) =>
                      (v == null || v.isEmpty)
                          ? 'Please select a category'
                          : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _desc,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _inputDecoration(
                    label: 'Description (optional)',
                  ),
                ),
                const SizedBox(height: 8),

                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Active'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),

                // NEW: Payment info note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet, 
                          size: 20, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Payments for this item will be credited to your merchant wallet automatically.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: canCreate ? _create : null,
                  icon: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Post on Marketplace'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaStripImages() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _gallery.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == _gallery.length) {
            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: const BorderSide(
                  color: Colors.black,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _pickGalleryMulti,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add'),
            );
          }
          final m = _gallery[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  m.bytes,
                  width: 128,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  onTap: () => _removeGalleryAt(i),
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black54,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _mediaStripVideos() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _videos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == _videos.length) {
            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: const BorderSide(
                  color: Colors.black,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text('Add video'),
            );
          }
          return Stack(
            children: [
              Container(
                width: 160,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.play_arrow_rounded),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  onTap: () => _removeVideoAt(i),
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black54,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildManageTab() {
    if (_loadingItems) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadItems,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'No items yet. Add your first product!',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadItems,
      child: LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount = 2;
          if (constraints.maxWidth >= 1200) {
            crossAxisCount = 4;
          } else if (constraints.maxWidth >= 700) {
            crossAxisCount = 3;
          }

          final aspect =
              (constraints.maxWidth >= 700) ? 0.90 : 0.88;

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            gridDelegate:
                SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: aspect,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final it = _items[i];
              return _ManageCard(
                item: it,
                busy: _busyRow,
                onEdit: () => _editItem(it),
                onDelete: () => _deleteItem(it),
              );
            },
          );
        },
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : (s[0].toUpperCase() + s.substring(1));
}

/* ---------- Manage card ---------- */

class _ManageCard extends StatelessWidget {
  const _ManageCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.busy,
  });

  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const brandOrange = Color(0xFFFF8A00);
    const brandSoft = Color(0xFFFFE8CC);

    final price =
        (item['price'] as num?)?.toDouble() ?? 0;

    return Card(
      elevation: 6,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildImage(),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundIcon(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: busy ? null : onEdit,
                    ),
                    const SizedBox(width: 6),
                    _roundIcon(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      color: Colors.red,
                      onTap: busy ? null : onDelete,
                    ),
                  ],
                ),
              ),
              // NEW: Merchant badge
              if (item['merchantName'] != null)
                Positioned(
                  left: 6,
                  bottom: 6,
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
                      item['merchantName'].toString(),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              10,
              12,
              2,
            ),
            child: Text(
              item['name'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              0,
              12,
              10,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: brandSoft,
                    borderRadius:
                        BorderRadius.circular(20),
                    border: Border.all(
                      color: brandOrange,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'MWK ${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _timeAgo(
                    (item['createdAt'] as Timestamp?)
                        ?.toDate(),
                  ),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // NEW: Merchant info footer
          if (item['merchantId'] != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(
                    color: Colors.grey[200]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 12,
                    color: Colors.green[700],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Merchant Item',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final dynamic raw = item['image'];

    Widget placeholder() {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.black38,
          ),
        ),
      );
    }

    if (raw is! String || raw.isEmpty) {
      return placeholder();
    }

    // If it's a URL
    if (raw.startsWith('http')) {
      return Image.network(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
      );
    }

    // Otherwise, try to treat as base64
    try {
      final bytes = base64Decode(raw);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
      );
    } catch (_) {
      return placeholder();
    }
  }

  Widget _roundIcon({
    required IconData icon,
    String? tooltip,
    Color? color,
    VoidCallback? onTap,
  }) {
    final btn = Material(
      color: Colors.white.withValues(alpha: 0.90),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: color ?? Colors.black87,
          ),
        ),
      ),
    );
    return tooltip == null
        ? btn
        : Tooltip(message: tooltip, child: btn);
  }

  String _timeAgo(DateTime? date) {
    if (date == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}m ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}min ago';
    } else {
      return '${diff.inSeconds}s ago';
    }
  }
}