// lib/Pages/MerchantDashboards/accommodation_merchant_dashboard.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'package:vero360_app/config/api_config.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/Home/homepage.dart';
import 'package:vero360_app/settings/Settings.dart';
// Add login screen import
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// Local media for Add Property (cover + gallery) – like marketplace LocalMedia.
class _PropertyMedia {
  final Uint8List bytes;
  final String filename;
  final String? mime;
  const _PropertyMedia({
    required this.bytes,
    required this.filename,
    this.mime,
  });
}

class AccommodationMerchantDashboard extends StatefulWidget {
  final String email;
  const AccommodationMerchantDashboard({super.key, required this.email});

  @override
  State<AccommodationMerchantDashboard> createState() => _AccommodationMerchantDashboardState();
}

class _AccommodationMerchantDashboardState extends State<AccommodationMerchantDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  // ✅ Use CartService singleton from provider
  final CartService _cartService = CartServiceProvider.getInstance();

  // Brand (match Marketplace merchant)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  // Wallet lock (PIN) – like marketplace
  DateTime? _walletUnlockedUntil;
  static const Duration _walletUnlockDuration = Duration(minutes: 5);

  bool get _walletUnlockedNow {
    final until = _walletUnlockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentBookings = [];

  // Profile (editable)
  String _merchantEmail = 'No Email';
  String _merchantPhone = 'No Phone';
  String _merchantProfileUrl = '';
  bool _profileUploading = false;
  final _picker = ImagePicker();

  // Services offered (conferences, bar, pool, etc.)
  List<String> _servicesOffered = [];
  List<dynamic> _rooms = [];
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats
  int _totalBookings = 0;
  int _activeBookings = 0;
  int _completedBookings = 0;
  double _totalRevenue = 0;
  double _rating = 0.0;
  String _status = 'pending';
  int _availableRooms = 0;

  // Navigation State
  int _selectedIndex = 0;

  // Tabs for dashboard content
  TabController? _accommodationTabs;

  @override
  void initState() {
    super.initState();
    _accommodationTabs = TabController(length: 3, vsync: this);
    _loadMerchantData();
    // No periodic refresh – data updates only on pull-to-refresh
  }

  @override
  void dispose() {
    _accommodationTabs?.dispose();
    super.dispose();
  }

  // ---------------- Logout Functionality ----------------
  Future<void> _logout() async {
    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Sign out from Firebase
      await _auth.signOut();

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Or clear specific keys if you want to keep some data

      // Show success message
      ToastHelper.showCustomToast(
        context,
        'Logged out successfully',
        isSuccess: true,
        errorMessage: 'Logged out',
      );

      // Navigate to login screen and remove all routes
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      
      // Show error message
      ToastHelper.showCustomToast(
        context,
        'Logout failed: $e',
        isSuccess: false,
        errorMessage: 'Logout failed',
      );
    }
  }

  Future<void> _loadMerchantData({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) setState(() => _isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    _businessName = prefs.getString('business_name') ?? 'Accommodation Provider';
    
    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'accommodation');
        
        if (!dashboardData.containsKey('error')) {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentBookings = dashboardData['recentOrders'] ?? [];
            _totalBookings = dashboardData['totalOrders'] ?? 0;
            _completedBookings = dashboardData['completedOrders'] ?? 0;
            _totalRevenue = dashboardData['totalRevenue'] ?? 0;
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
          });
        }

        await _loadRooms();
        await _loadWalletBalance();
        await _loadProfileFromAuthAndFirestore();
        await _loadServicesOffered();
        await _loadReviews();
        await _calculateActiveBookings();
        await _calculateAvailableRooms();

      } catch (e) {
        print('Error loading accommodation data: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        if (showLoading) _isLoading = false;
        _initialLoadComplete = true;
      });
    }
  }

  Future<void> _loadRooms() async {
    try {
      final snapshot = await _firestore
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: _uid)
          .get();
      
      if (mounted) {
        setState(() {
          _rooms = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading rooms: $e');
    }
  }

  Future<void> _loadProfileFromAuthAndFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      String email = (user.email ?? '').trim();
      String phone = (user.phoneNumber ?? '').trim();
      String photo = (user.photoURL ?? '').trim();
      if (email.isEmpty) email = 'No Email';
      if (phone.isEmpty) phone = 'No Phone';

      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null && mounted) {
        final p = (data['phone'] ?? '').toString().trim();
        final e = (data['email'] ?? '').toString().trim();
        final pic = (data['profilePicture'] ?? data['profilepicture'] ?? '')
            .toString()
            .trim();
        if (p.isNotEmpty) phone = p;
        if (e.isNotEmpty) email = e;
        if (pic.isNotEmpty) photo = pic;
      }
      if (mounted) {
        setState(() {
          _merchantEmail = email;
          _merchantPhone = phone;
          _merchantProfileUrl = photo;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadServicesOffered() async {
    if (_uid.isEmpty) return;
    try {
      final doc = await _firestore
          .collection('accommodation_merchants')
          .doc(_uid)
          .get();
      final data = doc.data();
      if (data != null && data['servicesOffered'] != null && mounted) {
        final list = data['servicesOffered'] as List<dynamic>?;
        setState(() => _servicesOffered = list?.map((e) => e.toString()).toList() ?? []);
      }
    } catch (_) {}
  }

  Future<void> _saveServicesOffered() async {
    if (_uid.isEmpty) return;
    try {
      await _firestore
          .collection('accommodation_merchants')
          .doc(_uid)
          .set({
        'servicesOffered': _servicesOffered,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ToastHelper.showCustomToast(context, 'Services saved', isSuccess: true, errorMessage: '');
    } catch (_) {
      if (mounted) ToastHelper.showCustomToast(context, 'Failed to save', isSuccess: false, errorMessage: '');
    }
  }

 Future<String> _uploadAccommodationImage(
    Uint8List bytes, {
    required String filename,
    String? mime,
  }) async {
    final ext = filename.contains('.') ? filename.split('.').last : 'jpg';
    final safeExt = ext.isEmpty || ext.length > 4 ? 'jpg' : ext;
    final path = 'accommodation_photos/$_uid/${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final ref = FirebaseStorage.instance.ref().child(path);
    final mimeType = mime ?? lookupMimeType(filename, headerBytes: bytes) ?? 'image/jpeg';
    await ref.putData(bytes, SettableMetadata(contentType: mimeType));
    return await ref.getDownloadURL();
  }

  void _showAddPropertySheet() {
    const accommodationTypes = ['hotel', 'lodge', 'bnb', 'house', 'hostel', 'apartment'];
    const maxGalleryPhotos = 5;
    String selectedType = accommodationTypes.first;
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();
    bool submitting = false;
    _PropertyMedia? cover;
    List<_PropertyMedia> gallery = [];

    Future<void> pickCover(ImageSource src) async {
      final x = await _picker.pickImage(source: src, imageQuality: 90, maxWidth: 2048);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final mime = lookupMimeType(x.name, headerBytes: bytes);
      cover = _PropertyMedia(bytes: bytes, filename: x.name, mime: mime);
    }

    Future<void> pickMorePhotos() async {
      if (gallery.length >= maxGalleryPhotos) return;
      final files = await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2048);
      if (files.isEmpty) return;
      final remaining = maxGalleryPhotos - gallery.length;
      for (final x in files.take(remaining)) {
        final bytes = await x.readAsBytes();
        gallery.add(_PropertyMedia(
          bytes: bytes,
          filename: x.name,
          mime: lookupMimeType(x.name, headerBytes: bytes),
        ));
      }
    }

    Future<void> pickOneFromCamera() async {
      if (gallery.length >= maxGalleryPhotos) return;
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 2048);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      gallery.add(_PropertyMedia(
        bytes: bytes,
        filename: x.name,
        mime: lookupMimeType(x.name, headerBytes: bytes),
      ));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Add Accomodation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Cover Image – like marketplace Add Item
                  const Text('Cover Image *', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: cover == null
                        ? Container(
                            height: 160,
                            color: const Color(0xFFF3F4F7),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.image, size: 40, color: Colors.black26),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(backgroundColor: _brandOrange),
                                        onPressed: () async {
                                          await pickCover(ImageSource.gallery);
                                          if (ctx.mounted) setLocal(() {});
                                        },
                                        icon: const Icon(Icons.photo_library),
                                        label: const Text('Gallery'),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(backgroundColor: _brandNavy),
                                        onPressed: () async {
                                          await pickCover(ImageSource.camera);
                                          if (ctx.mounted) setLocal(() {});
                                        },
                                        icon: const Icon(Icons.camera_alt),
                                        label: const Text('Camera'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              Image.memory(
                                cover!.bytes,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: InkWell(
                                  onTap: () {
                                    cover = null;
                                    setLocal(() {});
                                  },
                                  child: const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.black54,
                                    child: Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  // More Photos – like marketplace
                  Row(
                    children: [
                      const Expanded(
                        child: Text('More Photos (optional)', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                      Text('${gallery.length}/$maxGalleryPhotos', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: gallery.length >= maxGalleryPhotos ? null : () async {
                            await pickMorePhotos();
                            if (ctx.mounted) setLocal(() {});
                          },
                          icon: const Icon(Icons.collections_outlined),
                         label: Text(gallery.isEmpty ? 'Gallery' : 'Add More', style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: gallery.length >= maxGalleryPhotos ? null : () async {
                            await pickOneFromCamera();
                            if (ctx.mounted) setLocal(() {});
                          },
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      if (gallery.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            gallery.clear();
                            setLocal(() {});
                          },
                          child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),
                  if (gallery.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: gallery.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (_, i) {
                        final m = gallery[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(m.bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: InkWell(
                                onTap: () {
                                  gallery.removeAt(i);
                                  setLocal(() {});
                                },
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
                  ],
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Accommodation Type *'),
                    value: selectedType,
                    items: accommodationTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1))))
                        .toList(),
                    onChanged: (v) => setLocal(() => selectedType = v ?? accommodationTypes.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Accomodation Name *', hintText: 'e.g. Sunset Lodge'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(labelText: 'Location / Address *', hintText: 'e.g. Lilongwe, Area 47'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description', hintText: 'Describe your Accomodation', alignLabelWithHint: true),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price per Night (MWK) *', hintText: 'e.g. mwk 40,000'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: submitting ? null : () async {
                      if (cover == null) {
                        ToastHelper.showCustomToast(context, 'Please pick a cover photo', isSuccess: false, errorMessage: '');
                        return;
                      }
                      final name = nameController.text.trim();
                      final location = locationController.text.trim();
                      final price = double.tryParse(priceController.text.trim());
                      if (name.isEmpty || location.isEmpty) {
                        ToastHelper.showCustomToast(context, 'Name and Location are required', isSuccess: false, errorMessage: '');
                        return;
                      }
                      if (price == null || price <= 0) {
                        ToastHelper.showCustomToast(context, 'Enter a valid price per night', isSuccess: false, errorMessage: '');
                        return;
                      }
                      setLocal(() => submitting = true);
                      try {
                        final coverUrl = await _uploadAccommodationImage(
                          cover!.bytes,
                          filename: cover!.filename,
                          mime: cover!.mime,
                        );
                        final galleryUrls = <String>[];
                        for (var i = 0; i < gallery.length; i++) {
                          final m = gallery[i];
                          final url = await _uploadAccommodationImage(m.bytes, filename: m.filename, mime: m.mime);
                          galleryUrls.add(url);
                        }
                        await _firestore.collection('accommodation_rooms').add({
                          'name': name,
                          'location': location,
                          'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                          'pricePerNight': price,
                          'price': price,
                          'accommodationType': selectedType,
                          'type': selectedType,
                          'merchantId': _uid,
                          'isAvailable': true,
                          'capacity': 1,
                          'imageUrl': coverUrl,
                          'image': coverUrl,
                          'galleryUrls': galleryUrls,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _loadRooms();
                        _accommodationTabs?.animateTo(1);
                        ToastHelper.showCustomToast(context, 'Accomodation added successfully', isSuccess: true, errorMessage: '');
                      } catch (e) {
                        if (ctx.mounted) setLocal(() => submitting = false);
                        final String msg = e is FirebaseException
                            ? (e.message ?? '').contains('404') || (e.message ?? '').contains('Not Found')
                                ? 'Photo upload failed. Enable Firebase Storage in Console (Build → Storage → Get started).'
                                : 'Upload failed: ${e.message}'
                            : 'Failed to add property';
                        if (ctx.mounted) ToastHelper.showCustomToast(context, msg, isSuccess: false, errorMessage: '');
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: _brandOrange, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: submitting
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add Accomodation'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  Future<void> _loadReviews() async {
    try {
      final snapshot = await _firestore
          .collection('accommodation_reviews')
          .where('merchantId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      if (mounted) {
        setState(() {
          _reviews = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading reviews: $e');
    }
  }

  Future<void> _calculateActiveBookings() async {
    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('accommodationId', isEqualTo: _uid)
          .where('status', whereIn: ['confirmed', 'checked_in'])
          .get();
      
      if (mounted) {
        setState(() {
          _activeBookings = snapshot.size;
        });
      }
    } catch (e) {
      print('Error calculating active bookings: $e');
    }
  }

  Future<void> _calculateAvailableRooms() async {
    try {
      final availableRooms = _rooms.where((room) {
        final roomMap = room as Map<String, dynamic>;
        return roomMap['isAvailable'] == true;
      }).length;
      
      if (mounted) {
        setState(() {
          _availableRooms = availableRooms;
        });
      }
    } catch (e) {
      print('Error calculating available rooms: $e');
    }
  }

  Future<void> _updateBookingStatus(String bookingId, String status) async {
    try {
      await _firestore
          .collection('bookings')
          .doc(bookingId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      _loadMerchantData(showLoading: false);
    } catch (e) {
      print('Error updating booking: $e');
    }
  }

  // ----------------- Wallet PIN helpers -----------------
  Random _safeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _randomSalt([int len = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = _safeRandom();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin::$salt');
    return sha256.convert(bytes).toString();
  }

  Future<bool> _ensureAppPinExists() async {
    final sp = await SharedPreferences.getInstance();
    final existingHash = sp.getString('app_pin_hash');
    final existingSalt = sp.getString('app_pin_salt');

    if (existingHash != null &&
        existingHash.trim().isNotEmpty &&
        existingSalt != null &&
        existingSalt.trim().isNotEmpty) {
      return true;
    }

    final pin = await _showSetPinDialog();
    if (pin == null) return false;

    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);

    await sp.setString('app_pin_salt', salt);
    await sp.setString('app_pin_hash', hash);

    if (!mounted) return true;
    ToastHelper.showCustomToast(
      context,
      'App password set',
      isSuccess: true,
      errorMessage: '',
    );
    return true;
  }

  Future<bool> _unlockWalletWithPin() async {
    if (_walletUnlockedNow) return true;

    final okSetup = await _ensureAppPinExists();
    if (!okSetup) return false;

    final sp = await SharedPreferences.getInstance();
    final salt = (sp.getString('app_pin_salt') ?? '').trim();
    final hash = (sp.getString('app_pin_hash') ?? '').trim();
    if (salt.isEmpty || hash.isEmpty) return false;

    final entered = await _showEnterPinDialog();
    if (entered == null) return false;

    final enteredHash = _hashPin(entered, salt);
    final ok = enteredHash == hash;

    if (!ok) {
      if (!mounted) return false;
      ToastHelper.showCustomToast(
        context,
        'Wrong password',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _walletUnlockedUntil = DateTime.now().add(_walletUnlockDuration);
    });
    return true;
  }

  Future<String?> _showEnterPinDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Enter Your Password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'PIN (4–6 digits)',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length < 4) return;
              Navigator.pop(context, pin);
            },
            child: const Text(
              'Unlock',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSetPinDialog() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Set Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create a PIN to protect your wallet.'),
              const SizedBox(height: 10),
              TextField(
                controller: p1,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'New PIN (4–6 digits)',
                  counterText: '',
                ),
              ),
              TextField(
                controller: p2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: 'Confirm PIN',
                  counterText: '',
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(
                  err!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final a = p1.text.trim();
                final b = p2.text.trim();
                if (a.length < 4) {
                  setLocal(() => err = 'PIN must be at least 4 digits.');
                  return;
                }
                if (a != b) {
                  setLocal(() => err = 'PINs do not match.');
                  return;
                }
                Navigator.pop(context, a);
              },
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null,
      body: _getCurrentPage(),
      bottomNavigationBar: _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    return AppBar(
      title: Text(
        _initialLoadComplete ? 'Accommodation Dashboard' : 'Loading...',
      ),
      backgroundColor: _brandOrange,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(onBackToHomeTab: () {}),
              ),
            );
          },
        ),
      ],
    );
  }

   Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0: // Home (First position)
        return Vero360Homepage(email: widget.email);
      case 1: // Marketplace (Second position)
        return MarketPage(cartService: _cartService);
      case 2: // Cart (Third position)
        return CartPage(cartService: _cartService);
      case 3: // Messages (Fourth position)
        return ChatListPage();
      case 4: // Dashboard (Fifth/last position)
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
            Text('Loading accommodation dashboard...'),
          ],
        ),
      );
    }

    // Mirror MarketplaceMerchantDashboard: tabs for dashboard / rooms / bookings
    if (_accommodationTabs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _accommodationTabs!,
            labelColor: _brandOrange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _brandOrange,
            tabs: const [
              Tab(text: 'Dashboard'),
             // Tab(text: 'Rooms'),
              Tab(text: 'Bookings'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _accommodationTabs!,
            children: [
              // Dashboard tab
              RefreshIndicator(
                onRefresh: () async => _loadMerchantData(showLoading: false),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeSection(),
                      const SizedBox(height: 12),
                      _buildStatsSection(),
                      const SizedBox(height: 12),
                      _buildQuickActions(),
                      const SizedBox(height: 12),
                      _buildWalletSummary(),
                      const SizedBox(height: 12),
                      _buildRecentBookings(),
                    ],
                  ),
                ),
              ),
              // Rooms tab (dedicated list of rooms)
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _buildRoomsSection(),
              ),
              // Bookings tab (full booking list + reviews summary)
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecentBookings(),
                    const SizedBox(height: 16),
                    _buildRecentReviews(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------- Profile image helpers -----------------
  ImageProvider? _profileImageProvider() {
    final s = _merchantProfileUrl.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http')) return NetworkImage(s);
    try {
      final bytes = base64Decode(s);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfile(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfile(ImageSource.gallery);
              },
            ),
            if (_merchantProfileUrl.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                title: const Text('Remove current photo'),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _viewProfilePhoto() {
    final img = _profileImageProvider();
    if (img == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Image(image: img, fit: BoxFit.cover),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Future<String?> _getBearerTokenForApi({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && forceRefresh) {
      try {
        final idToken = await user.getIdToken(true);
        final t = idToken?.trim();
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt');
    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }
    if (user == null) return null;
    try {
      final idToken = await user.getIdToken(forceRefresh);
      final t = idToken?.trim();
      if (t == null || t.isEmpty) return null;
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<String> _uploadProfileViaBackend(XFile file) async {
    String bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
    if (bearer.isEmpty) throw Exception('Not authenticated');
    final uri = ApiConfig.endpoint('/users/me/profile-picture');
    final bytes = await file.readAsBytes();
    final mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    final contentType = parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
    Future<http.StreamedResponse> sendRequest(String token) async {
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'profile.jpg',
          contentType: contentType,
        ));
      return req.send();
    }
    var sent = await sendRequest(bearer);
    var resp = await http.Response.fromStream(sent);
    if (resp.statusCode == 401) {
      bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
      if (bearer.isEmpty) throw Exception('Session expired. Please sign in again.');
      sent = await sendRequest(bearer);
      resp = await http.Response.fromStream(sent);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 404) throw Exception('Profile picture endpoint not found');
      if (resp.statusCode == 401) throw Exception('Session expired. Please sign in again.');
      throw Exception('Upload failed (${resp.statusCode}) ${resp.body}');
    }
    final body = jsonDecode(resp.body);
    final data = (body is Map && body['data'] is Map)
        ? body['data'] as Map
        : (body is Map ? Map<String, dynamic>.from(body as Map) : <String, dynamic>{});
    final url = (data['profilepicture'] ?? data['profilePicture'] ?? data['url'])?.toString();
    if (url == null || url.isEmpty) throw Exception('No URL in response');
    return url;
  }

  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {
    final rawExt = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final ext = rawExt.isEmpty || rawExt.length > 4 ? 'jpg' : rawExt;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'profile_photos/${uid}_$timestamp.$ext';
    final ref = FirebaseStorage.instance.ref().child(path);
    final bytes = await file.readAsBytes();
    final mime = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    await ref.putData(bytes, SettableMetadata(contentType: mime));
    return await ref.getDownloadURL();
  }

  Future<void> _pickAndUploadProfile(ImageSource src) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final file = await _picker.pickImage(
      source: src,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;
    try {
      setState(() => _profileUploading = true);
      String url;
      try {
        url = await _uploadProfileViaBackend(file);
      } catch (backendErr) {
        debugPrint('Backend profile upload failed: $backendErr');
        try {
          url = await _uploadProfileToFirebaseStorage(user.uid, file);
        } on FirebaseException catch (e) {
          if ((e.code == 'object-not-found' || e.code == 'unknown') && (e.message?.contains('404') == true)) {
            url = await _uploadProfileViaBackend(file);
          } else {
            rethrow;
          }
        }
      }
      await user.updatePhotoURL(url);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);
      if (!mounted) return;
      setState(() => _merchantProfileUrl = url);
      ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
    } on FirebaseException catch (e) {
      debugPrint('Profile upload error: ${e.code} ${e.message}');
      if (!mounted) return;
      try {
        final url = await _uploadProfileViaBackend(file);
        if (url.isNotEmpty) {
          final u = _auth.currentUser;
          if (u != null) {
            await u.updatePhotoURL(url);
            await u.reload();
            await _firestore.collection('users').doc(u.uid).set({
              'profilePicture': url,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('profilepicture', url);
            if (mounted) setState(() => _merchantProfileUrl = url);
            ToastHelper.showCustomToast(context, 'Profile picture updated', isSuccess: true, errorMessage: '');
            return;
          }
        }
      } catch (fallbackErr) {
        debugPrint('Backend fallback failed: $fallbackErr');
      }
      if (e.code == 'object-not-found' || (e.message ?? '').contains('404')) {
        ToastHelper.showCustomToast(context, 'Upload failed. Check network and that the server is running.', isSuccess: false, errorMessage: '');
      } else {
        ToastHelper.showCustomToast(context, 'Failed to upload photo. Please try again.', isSuccess: false, errorMessage: '');
      }
    } catch (e) {
      debugPrint('Profile upload error: $e');
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to upload photo. Please try again.', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      setState(() => _profileUploading = true);
      await user.updatePhotoURL(null);
      await user.reload();
      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');
      if (!mounted) return;
      setState(() => _merchantProfileUrl = '');
      ToastHelper.showCustomToast(context, 'Profile picture removed', isSuccess: true, errorMessage: '');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showCustomToast(context, 'Failed to remove photo', isSuccess: false, errorMessage: '');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  Future<void> _showEditEmailDialog() async {
    final controller = TextEditingController(text: _merchantEmail == 'No Email' ? '' : _merchantEmail);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Email'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Email'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      try {
        await _firestore.collection('users').doc(_uid).set({
          'email': result,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        setState(() => _merchantEmail = result);
        ToastHelper.showCustomToast(context, 'Email updated', isSuccess: true, errorMessage: '');
      } catch (_) {
        ToastHelper.showCustomToast(context, 'Failed to update email', isSuccess: false, errorMessage: '');
      }
    }
  }

  Future<void> _showEditPhoneDialog() async {
    final controller = TextEditingController(text: _merchantPhone == 'No Phone' ? '' : _merchantPhone);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Phone'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Phone number'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      try {
        await _firestore.collection('users').doc(_uid).set({
          'phone': result,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        setState(() => _merchantPhone = result.isEmpty ? 'No Phone' : result);
        ToastHelper.showCustomToast(context, 'Phone updated', isSuccess: true, errorMessage: '');
      } catch (_) {
        ToastHelper.showCustomToast(context, 'Failed to update phone', isSuccess: false, errorMessage: '');
      }
    }
  }

  Widget _buildWelcomeSection() {
    final st = _status.trim().toLowerCase();
    final statusText = st.isEmpty ? 'PENDING' : st.toUpperCase();

    Color statusBg;
    Color statusFg;
    if (st == 'approved' || st == 'active') {
      statusBg = const Color(0xFFE7F6EC);
      statusFg = Colors.green.shade700;
    } else if (st == 'pending' || st == 'under_review' || st == 'submitted') {
      statusBg = const Color(0xFFFFF3E5);
      statusFg = const Color(0xFFB86E00);
    } else {
      statusBg = const Color(0xFFFFEDEE);
      statusFg = Colors.red.shade700;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_brandNavy, _brandNavy.withOpacity(0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _profileImageProvider() != null ? _viewProfilePhoto : null,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    backgroundImage: _profileImageProvider(),
                    child: _profileImageProvider() == null
                        ? const Icon(Icons.hotel_rounded, color: Colors.white, size: 26)
                        : null,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: _showPhotoSheet,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _brandOrange,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _profileUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _businessName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  GestureDetector(
                    onTap: _showEditEmailDialog,
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined, size: 14, color: Colors.white.withOpacity(0.85)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _merchantEmail,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.edit, size: 12, color: Colors.white.withOpacity(0.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: _showEditPhoneDialog,
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined, size: 14, color: Colors.white.withOpacity(0.85)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _merchantPhone,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.edit, size: 12, color: Colors.white.withOpacity(0.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(color: statusFg, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
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

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
       const Text(
          'Business Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 74,
          ),
          itemBuilder: (_, i) {
            switch (i) {
              case 0:
                return _compactStatTile(
                  title: 'Total Bookings',
                  value: '$_totalBookings',
                  icon: Icons.book_online,
                  color: _brandOrange,
                );
              case 1:
                return _compactStatTile(
                  title: 'Total Revenue',
                  value: 'MWK ${_totalRevenue.toStringAsFixed(2)}',
                  icon: Icons.attach_money,
                  color: Colors.green,
                );
              case 2:
                return _compactStatTile(
                  title: 'Active Guests',
                  value: '$_activeBookings',
                  icon: Icons.people,
                  color: _brandNavy,
                );
              default:
                return _compactStatTile(
                  title: 'Available Rooms',
                  value: '$_availableRooms/${_rooms.length}',
                  icon: Icons.bed,
                  color: Colors.orange,
                );
            }
          },
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
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 74,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            _QuickActionTile(
             title: 'Add Property',
              icon: Icons.add_business_outlined,
              color: _brandOrange,
              onTap: _showAddPropertySheet,
            ),
            _QuickActionTile(
              title: 'Rooms',
              icon: Icons.meeting_room_outlined,
              color: _brandNavy,
              onTap: () => _accommodationTabs?.animateTo(1),
            ),
            _QuickActionTile(
              title: 'Bookings',
              icon: Icons.book_online_outlined,
              color: Colors.green,
              onTap: () => _accommodationTabs?.animateTo(2),
            ),
       
           
            
            _QuickActionTile(
              title: 'Promotions',
              icon: Icons.campaign_outlined,
              color: Colors.orange,
              onTap: () {
                // Promotions for rooms
              },
            ),
        
          ],
        ),
      ],
    );
  }

  Widget _buildWalletSummary() {
    final unlocked = _walletUnlockedNow;
    final balanceStr = unlocked
        ? 'MWK ${_walletBalance.toStringAsFixed(2)}'
        : 'MWK ••••';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (unlocked ? Colors.green : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              unlocked
                  ? Icons.account_balance_wallet_rounded
                  : Icons.lock_rounded,
              color: unlocked ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wallet Balance',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  balanceStr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: unlocked ? Colors.green : Colors.black54,
                  ),
                ),
                if (!unlocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Locked — tap Open to unlock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final ok = await _unlockWalletWithPin();
              if (!ok || !mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: _businessName,
                    serviceType: 'accommodation',
                  ),
                ),
              );
            },
            child: const Text(
              'Open',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentBookings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Bookings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // View all bookings
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentBookings.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No bookings yet')),
            ),
          )
        else
          ..._recentBookings.take(3).map((booking) {
            final bookingMap = booking as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.hotel, color: _brandOrange),
                title: Text('Booking #${bookingMap['bookingId']?.toString().substring(0, 8) ?? 'N/A'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Guest: ${bookingMap['guestName'] ?? 'N/A'}'),
                    Text('Room: ${bookingMap['roomType'] ?? 'N/A'}'),
                    Text('Dates: ${bookingMap['checkIn'] ?? ''} - ${bookingMap['checkOut'] ?? ''}'),
                    Text('Amount: MWK ${bookingMap['totalAmount'] ?? '0'}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(bookingMap['status'] ?? 'pending'),
                      backgroundColor: _getBookingStatusColor(bookingMap['status']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        _showBookingActions(bookingMap);
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Rooms',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Add room
              },
              child: const Text('Add Room'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_rooms.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No rooms added yet')),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: _rooms.length,
            itemBuilder: (context, index) {
              final room = _rooms[index] as Map<String, dynamic>;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        room['type'] == 'suite' ? Icons.king_bed : Icons.bed,
                        size: 40,
                        color: _brandOrange,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        room['name'] ?? 'Room ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${room['type'] ?? 'Standard'} Room',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MWK ${(room['price'] ?? 0).toStringAsFixed(2)}/night',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              room['isAvailable'] == true ? 'Available' : 'Booked',
                              style: TextStyle(
                                color: room['isAvailable'] == true 
                                    ? Colors.green 
                                    : Colors.red,
                              ),
                            ),
                            backgroundColor: room['isAvailable'] == true 
                                ? Colors.green[50] 
                                : Colors.red[50],
                          ),
                          const Spacer(),
                          Text(
                            '${room['capacity'] ?? 1} guests',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildRecentReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Recent Reviews',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No reviews yet')),
            ),
          )
        else
          ..._reviews.map((review) {
            final reviewMap = review as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    reviewMap['guestName']?.toString().substring(0, 1) ?? 'G',
                  ),
                ),
                title: Row(
                  children: [
                    Text(reviewMap['guestName'] ?? 'Anonymous'),
                    const Spacer(),
                    ...List.generate(5, (index) {
                      return Icon(
                        Icons.star,
                        size: 16,
                        color: index < (reviewMap['rating'] ?? 0) 
                            ? Colors.amber 
                            : Colors.grey[300],
                      );
                    }),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reviewMap['comment'] ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      'Booking: #${reviewMap['bookingId']?.toString().substring(0, 8) ?? 'N/A'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

 Widget _buildMerchantNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_rounded, 'Home', 0),
              _buildNavItem(Icons.storefront_rounded, 'Marketplace', 1),
              _buildNavItem(Icons.shopping_cart_rounded, 'Cart', 2),
              _buildNavItem(Icons.message_rounded, 'Messages', 3),
              _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _brandOrange.withOpacity(0.12) : Colors.transparent,
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
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBookingStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'checked_out':
        return Colors.green[100]!;
      case 'checked_in':
        return Colors.blue[100]!;
      case 'confirmed':
        return Colors.orange[100]!;
      case 'pending':
        return Colors.yellow[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  void _showBookingActions(Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(context);
                  // View booking details
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Confirm Booking'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'confirmed');
                },
              ),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Check In'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'checked_in');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Check Out'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'checked_out');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel Booking'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------- Quick action tile (reuse marketplace style) -----------------
class _QuickActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _QuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}