// lib/Pages/MerchantDashboards/marketplace_merchant_dashboard.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/services/merchant_service_helper.dart';
import 'package:vero360_app/Pages/marketPlace.dart';
import 'package:vero360_app/Pages/Home/Profilepage.dart';
import 'package:vero360_app/screens/chat_list_page.dart';
import 'package:vero360_app/Pages/cartpage.dart';
import 'package:vero360_app/services/cart_services.dart';
import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/MerchantDashboards/merchant_wallet.dart';
import 'package:vero360_app/Pages/homepage.dart';
import 'package:vero360_app/services/serviceprovider_service.dart';
import 'package:vero360_app/models/marketplace.model.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/toasthelper.dart';

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

class MarketplaceMerchantDashboard extends StatefulWidget {
  final String email;
  const MarketplaceMerchantDashboard({super.key, required this.email});

  @override
  State<MarketplaceMerchantDashboard> createState() => _MarketplaceMerchantDashboardState();
}

class _MarketplaceMerchantDashboardState extends State<MarketplaceMerchantDashboard>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  final CartService _cartService = CartService('https://heflexitservice.co.za', apiPrefix: 'vero');
  final ServiceproviderService _spService = ServiceproviderService();
  final _picker = ImagePicker();
  
  // Marketplace form controllers
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  
  // Tab controller for marketplace tabs
  late TabController _marketplaceTabs;
  
  // Marketplace state
  bool _isActive = true;
  bool _submitting = false;
  LocalMedia? _cover;
  final List<LocalMedia> _gallery = <LocalMedia>[];
  final List<LocalMedia> _videos = <LocalMedia>[];
  List<Map<String, dynamic>> _items = [];
  bool _loadingItems = true;
  bool _busyRow = false;
  
  static const List<String> _kCategories = <String>[
    'food',
    'drinks',
    'electronics',
    'clothes',
    'shoes',
    'other',
  ];
  String? _category = 'other';
  
  // Dashboard state
  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentSales = [];
  List<dynamic> _topItems = [];
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats
  int _totalItems = 0;
  int _activeItems = 0;
  int _soldItems = 0;
  double _totalEarnings = 0;
  double _rating = 0.0;
  String _status = 'pending';

  // Navigation State
  int _selectedIndex = 0;

  // Brand colors
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFE8CC);

  @override
  void initState() {
    super.initState();
    _marketplaceTabs = TabController(length: 3, vsync: this); // Changed to 3 tabs
    _loadMerchantData();
    _loadItems();
    _startPeriodicUpdates();
  }

  void _startPeriodicUpdates() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadMerchantData();
        _loadItems();
      }
    });
  }

  Future<void> _loadMerchantData() async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    
    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'marketplace');
        
        if (!dashboardData.containsKey('error')) {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentSales = dashboardData['recentOrders'] ?? [];
            _totalItems = dashboardData['totalItems'] ?? 0;
            _activeItems = dashboardData['activeItems'] ?? 0;
            _soldItems = dashboardData['soldItems'] ?? 0;
            _totalEarnings = dashboardData['totalRevenue'] ?? 0;
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
            _businessName = dashboardData['merchant']?['businessName'] ?? 'Marketplace Merchant';
          });
        }

        await _loadTopItems();
        await _loadWalletBalance();

      } catch (e) {
        print('Error loading marketplace data: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _initialLoadComplete = true;
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loadingItems = true);
    try {
      final sellerId = await _getNestUserId();

      Query<Map<String, dynamic>> query =
          _firestore.collection('marketplace_items');

      if (sellerId != null) {
        query = query.where('sellerUserId', isEqualTo: sellerId);
      }

      final snap = await query.get();

      _items =
          snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    } catch (e) {
      print('Error loading items: $e');
      _items = [];
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _loadTopItems() async {
    try {
      final snapshot = await _firestore
          .collection('marketplace_items')
          .where('sellerUserId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      if (mounted) {
        setState(() {
          _topItems = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading top items: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(_uid)
          .get();
      
      if (walletDoc.exists && mounted) {
        setState(() {
          _walletBalance = (walletDoc.data()?['balance'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      print('Error loading wallet: $e');
    }
  }

  // ---------------- Marketplace Methods ----------------
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
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

      final dynamic rawId = payload['sub'] ?? payload['id'] ?? payload['userId'];
      if (rawId == null) return null;
      return rawId.toString();
    } catch (_) {
      return null;
    }
  }

  // FIXED: Get merchant info from Firebase instead of ServiceproviderService
  Future<Map<String, dynamic>?> _getMerchantInfoFromFirebase() async {
    try {
      // First try marketplace_merchants collection
      final marketplaceDoc = await _firestore
          .collection('marketplace_merchants')
          .doc(_uid)
          .get();
      
      if (marketplaceDoc.exists) {
        final data = marketplaceDoc.data();
        return {
          'id': _uid,
          'businessName': data?['businessName'] ?? 'Marketplace Merchant',
          'serviceType': 'marketplace',
        };
      }
      
      // If not found, try users collection
      final userDoc = await _firestore
          .collection('users')
          .doc(_uid)
          .get();
      
      if (userDoc.exists) {
        final data = userDoc.data();
        return {
          'id': _uid,
          'businessName': data?['businessName'] ?? 'Marketplace Merchant',
          'serviceType': data?['merchantService'] ?? 'marketplace',
        };
      }
      
      // Last resort: use SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      return {
        'id': _uid,
        'businessName': prefs.getString('business_name') ?? 'Marketplace Merchant',
        'serviceType': 'marketplace',
      };
      
    } catch (e) {
      print('Error getting merchant info from Firebase: $e');
      return null;
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
      await _firestore.collection('marketplace_items').doc(id).delete();
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

  // Media pickers
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

  void _removeGalleryAt(int i) {
    _gallery.removeAt(i);
    setState(() {});
  }

  void _clearCover() {
    _cover = null;
    setState(() {});
  }

  // Base64 encoding
  Future<String> _encodeMediaAsBase64(LocalMedia media) async {
    try {
      return base64Encode(media.bytes);
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

  Future<void> _create() async {
    // Validate
    if (_cover == null) {
      ToastHelper.showCustomToast(
        context,
        'Please pick a cover photo',
        isSuccess: false,
        errorMessage: 'Photo required',
      );
      return;
    }

    if (_name.text.isEmpty || _price.text.isEmpty || _location.text.isEmpty) {
      ToastHelper.showCustomToast(
        context,
        'Please fill all required fields',
        isSuccess: false,
        errorMessage: 'Missing fields',
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final sellerId = await _getNestUserId();
      
      // FIXED: Use Firebase merchant info instead of ServiceproviderService
      final merchantInfo = await _getMerchantInfoFromFirebase();

      if (merchantInfo == null) {
        ToastHelper.showCustomToast(
          context,
          'Unable to identify merchant information. Please ensure your merchant profile is complete.',
          isSuccess: false,
          errorMessage: 'Missing merchant info',
        );
        return;
      }

      // Encode media
      final coverBase64 = await _encodeMediaAsBase64(_cover!);
      final galleryBase64 = await _encodeAll(_gallery);

      // Create data
      final data = {
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'image': coverBase64,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'location': _location.text.trim(),
        'isActive': _isActive,
        'category': _category ?? 'other',
        'gallery': galleryBase64,
        'videos': [],
        'createdAt': FieldValue.serverTimestamp(),
        'sellerUserId': sellerId ?? 'unknown',
        'merchantId': merchantInfo['id'] ?? _uid,
        'merchantName': merchantInfo['businessName'] ?? _businessName,
        'serviceType': 'marketplace',
      };

      await _firestore.collection('marketplace_items').add(data);

      ToastHelper.showCustomToast(
        context,
        'Item Posted Successfully!',
        isSuccess: true,
        errorMessage: 'Created',
      );

      // Reset form
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
      await _loadItems();
      await _loadMerchantData();
      _marketplaceTabs.animateTo(2); // Navigate to "My Items" tab

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

  // Location helpers
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ToastHelper.showCustomToast(
          context,
          'Location services are disabled.',
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
          'Location permissions are permanently denied.',
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
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
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

  // UI Helpers
  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  ButtonStyle _filledBtnStyle({double padV = 14}) => FilledButton.styleFrom(
    backgroundColor: _brandOrange,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    padding: EdgeInsets.symmetric(vertical: padV, horizontal: 14),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  );

  // Dashboard Widgets
  Widget _StatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null,
      body: _getCurrentPage(),
      bottomNavigationBar: _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    return AppBar(
      title: Text(_initialLoadComplete ? '$_businessName Dashboard' : 'Loading...'),
      backgroundColor: _brandOrange,
      actions: [
        IconButton(
          icon: const Icon(Icons.switch_account),
          tooltip: 'Switch to Customer View',
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => Bottomnavbar(email: widget.email)),
              (_) => false,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.account_balance_wallet),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MerchantWalletPage(
                  merchantId: _uid,
                  merchantName: _businessName,
                  serviceType: 'marketplace',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0: // Home
        return Vero360Homepage(email: widget.email);
      case 1: // Marketplace
        return MarketPage(cartService: _cartService);
      case 2: // Cart
        return CartPage(cartService: _cartService);
      case 3: // Messages
        return ChatListPage();
      case 4: // Dashboard
        return _buildDashboardContent();
      default:
        return Vero360Homepage(email: widget.email);
    }
  }

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Loading dashboard...'),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 3, // Changed to 3 tabs
      child: Column(
        children: [
          TabBar(
            controller: _marketplaceTabs,
            labelColor: _brandOrange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _brandOrange,
            tabs: const [
              Tab(text: 'Dashboard'),
              Tab(text: 'Add Item'), // Changed from 'Manage Items'
              Tab(text: 'My Items'), // New tab
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _marketplaceTabs,
              children: [
                // Dashboard Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeSection(),
                      _buildStatsSection(),
                      _buildQuickActions(),
                      _buildWalletSummary(),
                      _buildRecentSales(),
                      _buildTopItems(),
                    ],
                  ),
                ),
                // Add Item Tab - FIXED: Now just the form, no items list
                _buildAddItemTab(),
                // My Items Tab - FIXED: Just the items grid
                _buildMyItemsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.store, size: 50, color: Colors.orange),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _businessName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Marketplace Merchant'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        label: Text(_status.toUpperCase()),
                        backgroundColor: _status == 'approved' 
                            ? Colors.green[100] 
                            : _status == 'pending'
                              ? Colors.orange[100]
                              : Colors.red[100],
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Row(
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}'),
                          ],
                        ),
                        backgroundColor: Colors.amber[100],
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

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Business Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _StatCard(
              title: 'Total Items',
              value: '$_totalItems',
              icon: Icons.inventory,
              color: _brandOrange,
            ),
            _StatCard(
              title: 'Active Items',
              value: '$_activeItems',
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            _StatCard(
              title: 'Sold Items',
              value: '$_soldItems',
              icon: Icons.shopping_bag,
              color: Colors.blue,
            ),
            _StatCard(
              title: 'Total Earnings',
              value: 'MWK ${_totalEarnings.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              color: Colors.green,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              avatar: const Icon(Icons.add, size: 20),
              label: const Text('Add Item'),
              onPressed: () {
                _marketplaceTabs.animateTo(1); // Navigate to Add Item tab
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.analytics, size: 20),
              label: const Text('Analytics'),
              onPressed: () {
                // Analytics
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.trending_up, size: 20),
              label: const Text('Performance'),
              onPressed: () {
                // Performance
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.settings, size: 20),
              label: const Text('Settings'),
              onPressed: () {
                // Settings
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.support_agent, size: 20),
              label: const Text('Support'),
              onPressed: () {
                // Support
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.inventory, size: 20),
              label: const Text('Inventory'),
              onPressed: () {
                _marketplaceTabs.animateTo(2); // Navigate to My Items tab
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWalletSummary() {
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wallet Balance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MWK ${_walletBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MerchantWalletPage(
                          merchantId: _uid,
                          merchantName: _businessName,
                          serviceType: 'marketplace',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('View Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Earnings from marketplace sales',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSales() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Sales',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // View all sales
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentSales.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No sales yet')),
            ),
          )
        else
          ..._recentSales.take(3).map((sale) {
            final saleMap = sale as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.shopping_bag, color: Colors.orange),
                title: Text('Sale #${saleMap['orderId']?.toString().substring(0, 8) ?? 'N/A'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer: ${saleMap['customerName'] ?? 'N/A'}'),
                    Text('Items: ${saleMap['itemCount'] ?? '0'}'),
                    Text('Total: MWK ${saleMap['totalAmount'] ?? '0'}'),
                  ],
                ),
                trailing: Chip(
                  label: Text(saleMap['status'] ?? 'pending'),
                  backgroundColor: _getSaleStatusColor(saleMap['status']),
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildTopItems() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Top Items',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_topItems.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No items yet')),
            ),
          )
        else
          ..._topItems.map((item) {
            final itemMap = item as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: _buildItemImage(itemMap['image']),
                title: Text(itemMap['name'] ?? 'Unknown Item'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Price: MWK ${itemMap['price'] ?? '0'}'),
                    Text('Category: ${itemMap['category'] ?? 'other'}'),
                  ],
                ),
                trailing: Chip(
                  label: Text(itemMap['isActive'] == true ? 'Active' : 'Inactive'),
                  backgroundColor: itemMap['isActive'] == true ? Colors.green[50] : Colors.red[50],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  // FIXED: New method for Add Item tab - just the form
  Widget _buildAddItemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add New Item',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Cover Image
                  const Text('Cover Image', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _cover == null
                        ? Container(
                            height: 150,
                            color: Colors.grey[100],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.image, size: 40, color: Colors.grey),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _pickCover(ImageSource.gallery),
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Select Image'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              Image.memory(
                                _cover!.bytes,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: _clearCover,
                                ),
                              ),
                            ],
                          ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Form Fields
                  TextField(
                    controller: _name,
                    decoration: _inputDecoration(label: 'Item Name'),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(label: 'Price (MWK)'),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _location,
                    decoration: _inputDecoration(label: 'Location').copyWith(
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.my_location),
                            onPressed: _getCurrentLocation,
                          ),
                          IconButton(
                            icon: const Icon(Icons.map),
                            onPressed: _openGoogleMap,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<String>(
                    value: _category,
                    items: _kCategories.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c[0].toUpperCase() + c.substring(1)),
                    )).toList(),
                    onChanged: (v) => setState(() => _category = v),
                    decoration: _inputDecoration(label: 'Category'),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _desc,
                    minLines: 3,
                    maxLines: 5,
                    decoration: _inputDecoration(label: 'Description (optional)'),
                  ),
                  const SizedBox(height: 12),
                  
                  // Gallery
                  const Text('Gallery Images (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildGalleryPreview(),
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const Text('Active'),
                      const Spacer(),
                      FilledButton.icon(
                        style: _filledBtnStyle(),
                        onPressed: _submitting ? null : _create,
                        icon: _submitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Post Item'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // FIXED: New method for My Items tab - just the items grid
  Widget _buildMyItemsTab() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Items',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  _marketplaceTabs.animateTo(1); // Go to Add Item tab
                },
                icon: const Icon(Icons.add),
                label: const Text('Add New Item'),
              ),
            ],
          ),
        ),
        
        // Items Grid
        Expanded(
          child: _loadingItems
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory, size: 60, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No items yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _marketplaceTabs.animateTo(1); // Go to Add Item tab
                            },
                            child: const Text('Add your first item'),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return _ItemCard(
                          item: item,
                          busy: _busyRow,
                          onDelete: () => _deleteItem(item),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildGalleryPreview() {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _gallery.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == _gallery.length) {
            return OutlinedButton.icon(
              onPressed: _pickGalleryMulti,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add'),
            );
          }
          final m = _gallery[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(m.bytes, width: 80, height: 80, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () => _removeGalleryAt(i),
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildItemImage(dynamic imageData) {
    if (imageData is! String || imageData.isEmpty) {
      return const CircleAvatar(
        backgroundColor: Colors.grey,
        child: Icon(Icons.image, color: Colors.white),
      );
    }
    
    try {
      if (imageData.startsWith('http')) {
        return CircleAvatar(
          backgroundColor: Colors.grey[200],
          backgroundImage: NetworkImage(imageData),
        );
      } else {
        final bytes = base64Decode(imageData);
        return CircleAvatar(
          backgroundColor: Colors.grey[200],
          backgroundImage: MemoryImage(bytes),
        );
      }
    } catch (_) {
      return const CircleAvatar(
        backgroundColor: Colors.grey,
        child: Icon(Icons.image, color: Colors.white),
      );
    }
  }

  Widget _buildMerchantNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 'Home', 0),
              _buildNavItem(Icons.store, 'Marketplace', 1),
              _buildNavItem(Icons.shopping_cart, 'Cart', 2),
              _buildNavItem(Icons.message, 'Messages', 3),
              _buildNavItem(Icons.dashboard, 'Dashboard', 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _brandOrange.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? _brandOrange : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? _brandOrange : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSaleStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green[100]!;
      case 'processing':
        return Colors.blue[100]!;
      case 'shipped':
        return Colors.orange[100]!;
      case 'pending':
        return Colors.yellow[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onDelete;
  
  const _ItemCard({
    required this.item,
    required this.busy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                child: _buildImage(item['image']),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'MWK ${(item['price'] ?? 0).toString()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['category'] ?? 'other',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item['location'] ?? '',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Actions
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    color: Colors.red,
                    onPressed: busy ? null : onDelete,
                  ),
                ),
              ],
            ),
          ),
          
          // Status badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (item['isActive'] == true) ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                (item['isActive'] == true) ? 'Active' : 'Inactive',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(dynamic imageData) {
    if (imageData is! String || imageData.isEmpty) {
      return Container(
        height: 120,
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.image, color: Colors.grey),
        ),
      );
    }
    
    try {
      if (imageData.startsWith('http')) {
        return Image.network(
          imageData,
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } else {
        final bytes = base64Decode(imageData);
        return Image.memory(
          bytes,
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      height: 120,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey),
      ),
    );
  }
}