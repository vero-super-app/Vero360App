// lib/features/Restraurants/RestraurantPresenter/food_details.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:vero360_app/GeneralPages/address.dart';
import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_share_link.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_review_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_time.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

// ── Brand colours (Vero) ──────────────────────────────────────────────────────
const Color _veroOrange = Color(0xFFFF8A00);
const Color _ink        = Color(0xFF1A1109);
const Color _divider    = Color(0xFFEEEEEE);

// ── Image helpers ─────────────────────────────────────────────────────────────
bool _isBase64(String s) {
  final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
  if (x.length < 40) return false;
  return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
}

class _FoodHeroImage extends StatefulWidget {
  const _FoodHeroImage({required this.raw, this.fit = BoxFit.cover});
  final String raw;
  final BoxFit fit;

  @override
  State<_FoodHeroImage> createState() => _FoodHeroImageState();
}

class _FoodHeroImageState extends State<_FoodHeroImage> {
  String? _httpUrl;
  Uint8List? _bytes;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _FoodHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw) _resolve();
  }

  Future<void> _resolve() async {
    final raw = widget.raw.trim();
    if (raw.isEmpty) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      if (mounted) {
        setState(() {
          _httpUrl = raw;
          _ready = true;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _precache(raw));
      return;
    }
    if (_isBase64(raw)) {
      try {
        final part = raw.contains(',') ? raw.split(',').last : raw;
        final bytes = base64Decode(part.replaceAll(RegExp(r'\s'), ''));
        if (mounted) {
          setState(() {
            _bytes = bytes;
            _ready = true;
          });
        }
        return;
      } catch (_) {}
    }
    try {
      final ref = lower.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(raw)
          : FirebaseStorage.instance.ref(raw);
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _httpUrl = url;
        _ready = true;
      });
      _precache(url);
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _precache(String url) {
    if (!mounted || url.isEmpty) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Keep hero sharp — avoid heavy downsampling that looks "compressed".
    final cachePx = (MediaQuery.sizeOf(context).width * dpr).round().clamp(640, 1600);
    unawaited(
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: cachePx, maxHeight: cachePx),
        context,
      ).catchError((_) {}),
    );
  }

  Widget _err() => const Center(
        child: Icon(Icons.restaurant_menu_rounded, size: 80, color: Colors.white54),
      );

  @override
  Widget build(BuildContext context) {
    if (!_ready && _httpUrl == null && _bytes == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
        ),
      );
    }
    final url = (_httpUrl ?? '').trim();
    if (url.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cachePx =
          (MediaQuery.sizeOf(context).width * dpr).round().clamp(640, 1600);
      return ResilientCachedNetworkImage(
        url: url,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
        showSpinner: false,
        placeholderColor: const Color(0xFFFFF4E8),
      );
    }
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _err(),
      );
    }
    return _err();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class FoodDetailsPage extends StatefulWidget {
  final FoodModel foodItem;
  const FoodDetailsPage({required this.foodItem, super.key});

  @override
  State<FoodDetailsPage> createState() => _FoodDetailsPageState();
}

class _FoodDetailsPageState extends State<FoodDetailsPage>
    with SingleTickerProviderStateMixin {
  final _descCtrl = TextEditingController();
  late PageController _pageCtrl;
  late TabController _tabCtrl;

  int _pageIdx = 0;
  int _qty = 1;
  bool _cartBusy = false;
  bool _descExpanded = false;
  int? _selectedVariantIndex;
  final Set<int> _selectedAddOnIndexes = {};

  double? _deliveryLat, _deliveryLng;
  bool _pinning = false;
  bool _addressLoading = true;
  bool _loggedIn = false;
  String _deliveryAddressLine = '';
  Timer? _heroAutoSlide;
  final _addressService = AddressService();

  List<String> get _heroImages {
    final item = widget.foodItem;
    final images = <String>[
      if (item.FoodImage.trim().isNotEmpty) item.FoodImage.trim(),
      ...item.gallery.map((e) => e.trim()).where((e) => e.isNotEmpty),
    ];
    final unique = <String>[];
    for (final u in images) {
      if (!unique.contains(u)) unique.add(u);
    }
    return unique.isNotEmpty ? unique : [''];
  }

  double get _unitPrice {
    final item = widget.foodItem;
    var total = item.price;
    final vi = _selectedVariantIndex;
    if (vi != null && vi >= 0 && vi < item.variants.length) {
      total += item.variants[vi].priceDeltaMwk;
    }
    for (final i in _selectedAddOnIndexes) {
      if (i >= 0 && i < item.addOns.length) {
        total += item.addOns[i].priceMwk;
      }
    }
    return total;
  }

  String? get _selectedVariantName {
    final item = widget.foodItem;
    final vi = _selectedVariantIndex;
    if (vi == null || vi < 0 || vi >= item.variants.length) return null;
    final n = item.variants[vi].name.trim();
    return n.isEmpty ? null : n;
  }

  List<String> get _selectedAddOnNames {
    final item = widget.foodItem;
    final names = <String>[];
    for (final i in _selectedAddOnIndexes) {
      if (i < 0 || i >= item.addOns.length) continue;
      final n = item.addOns[i].name.trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names;
  }

  String get _incomingLineConfigKey {
    final v = (_selectedVariantName ?? '').toLowerCase();
    final a = _selectedAddOnNames.map((e) => e.toLowerCase()).toList()..sort();
    if (v.isEmpty && a.isEmpty) return '';
    return '$v|${a.join(',')}';
  }

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _tabCtrl  = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    final item = widget.foodItem;
    if (item.variants.isNotEmpty) _selectedVariantIndex = 0;
    for (var i = 0; i < item.addOns.length; i++) {
      if (item.addOns[i].isDefault) _selectedAddOnIndexes.add(i);
    }
    _hydrateDefaultsFast();
    _startHeroAutoSlide();
  }

  void _startHeroAutoSlide() {
    _heroAutoSlide?.cancel();
    final count = _heroImages.length;
    if (count <= 1) return;
    _heroAutoSlide = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_pageIdx + 1) % count;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onHeroPageChanged(int i) {
    setState(() => _pageIdx = i);
    // Restart timer so manual swipes don't fight the auto-slide.
    _startHeroAutoSlide();
  }

  @override
  void dispose() {
    _heroAutoSlide?.cancel();
    _pageCtrl.dispose();
    _tabCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _foodShareUrl() {
    final item = widget.foodItem;
    return foodShareUrl(
      id: foodProductShareId(
        sqlId: item.id > 0 ? item.id : null,
        firestoreListingId: item.firestoreListingId,
      ),
      name: item.FoodName,
      restaurant: item.RestrauntName,
      price: NumberFormat('#,##0').format(_unitPrice.round()),
      location: item.listingLocation,
      description: item.description,
      image: foodShareImageUrl(item.FoodImage, item.gallery),
    );
  }

  Future<void> _shareFood() async {
    final item = widget.foodItem;
    final url = _foodShareUrl();
    final buf = StringBuffer('Try ${item.FoodName} on Vero360');
    if (item.RestrauntName.trim().isNotEmpty) {
      buf.write(' — ${item.RestrauntName.trim()}');
    }
    buf.write('\nMWK ${NumberFormat('#,##0').format(_unitPrice.round())}');
    buf.write('\n$url');
    await Share.share(buf.toString());
  }

  Future<void> _copyFoodLink() async {
    await Clipboard.setData(ClipboardData(text: _foodShareUrl()));
    _toast('Link copied', true);
  }

  void _applyAddress(Address? addr) {
    if (addr == null) {
      setState(() => _deliveryAddressLine = '');
      return;
    }
    final d = addr.description.trim();
    final c = addr.city.trim();
    final line = d.isNotEmpty && c.isNotEmpty
        ? '$d, $c'
        : d.isNotEmpty
            ? d
            : (c.isNotEmpty ? c : addr.formattedAddress.trim());
    setState(() {
      _deliveryAddressLine = line;
      if (addr.lat != null && addr.lng != null) {
        _deliveryLat = addr.lat;
        _deliveryLng = addr.lng;
      }
    });
  }

  /// Prefill delivery from account address cache (checkout uses the same data).
  Future<void> _hydrateDefaultsFast() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (mounted) {
      setState(() {
        _loggedIn = uid != null && uid.isNotEmpty;
        _addressLoading = _loggedIn;
      });
    }
    if (!_loggedIn) {
      if (mounted) setState(() => _addressLoading = false);
      return;
    }

    try {
      final cached = await _addressService.getCachedDefaultAddress();
      if (cached != null && mounted) _applyAddress(cached);

      unawaited(_refreshAddressFromNetwork());
      unawaited(_autoPinDelivery());
    } catch (_) {
      unawaited(_autoPinDelivery());
    } finally {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  Future<void> _openAddressManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressPage()),
    );
    if (!mounted) return;
    setState(() => _addressLoading = true);
    await _refreshAddressFromNetwork(forceRefresh: true);
    if (mounted) setState(() => _addressLoading = false);
  }

  Future<void> _refreshAddressFromNetwork({bool forceRefresh = false}) async {
    try {
      final addrs = await _addressService.getMyAddresses(
        forceRefresh: forceRefresh,
      );
      if (!mounted || addrs.isEmpty) return;
      final def = addrs.firstWhere(
        (a) => a.isDefault == true,
        orElse: () => addrs.first,
      );
      _applyAddress(def);
    } catch (_) {}
  }

  /// Auto-pin coords when no saved address exists yet.
  Future<bool> _autoPinDelivery() async {
    if (_deliveryLat != null && _deliveryLng != null) return true;
    if (_pinning) return false;
    _pinning = true;
    try {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() {
            _deliveryLat = last.latitude;
            _deliveryLng = last.longitude;
          });
          if (_deliveryAddressLine.trim().isEmpty) {
            unawaited(_fillAddressFromCoords(last.latitude, last.longitude));
          }
          return true;
        }
      } catch (_) {}

      return await _gpsSilent();
    } finally {
      _pinning = false;
    }
  }

  Future<void> _fillAddressFromCoords(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (!mounted || marks.isEmpty) return;
      final p = marks.first;
      final line = [
        p.street,
        p.subLocality,
        p.locality,
        p.administrativeArea,
        p.country,
      ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
      if (line.isNotEmpty && _deliveryAddressLine.trim().isEmpty) {
        setState(() => _deliveryAddressLine = line);
      }
    } catch (_) {}
  }

  Future<bool> _gpsSilent() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return false;
      setState(() {
        _deliveryLat = pos.latitude;
        _deliveryLng = pos.longitude;
      });
      if (_deliveryAddressLine.trim().isEmpty) {
        unawaited(_fillAddressFromCoords(pos.latitude, pos.longitude));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String _kitchenKeyForFood(FoodModel item) {
    final rid = item.restaurantId?.trim();
    if (rid != null && rid.isNotEmpty) return 'r:$rid';
    final mid = item.merchantId?.trim();
    if (mid != null && mid.isNotEmpty) return 'm:$mid';
    return 'n:${item.RestrauntName.trim().toLowerCase()}';
  }

  Future<bool> _confirmReplaceCart(String otherName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new order?'),
        content: Text(
          'Your cart has items from $otherName. Clear cart and add this item instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Clear cart',
              style: TextStyle(color: _veroOrange),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addFoodToCart({required bool goToCheckout}) async {
    if (_cartBusy) return;
    final item = widget.foodItem;
    final mid = item.merchantId?.trim();
    if (mid == null || mid.isEmpty) {
      _toast('This dish cannot be ordered online (missing seller).', false);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _toast('Please sign in to add items to cart.', false);
      return;
    }

    setState(() => _cartBusy = true);
    try {
      final cart = CartServiceProvider.getInstance();
      var existing = cart.cachedItems;
      if (existing.isEmpty) {
        existing = await cart.loadLocalCart();
      }

      final incomingKey = _kitchenKeyForFood(item);
      CartModel? conflict;
      for (final e in existing.where((c) => c.isFood)) {
        if (e.kitchenKey != incomingKey) {
          conflict = e;
          break;
        }
      }
      if (conflict != null) {
        final proceed = await _confirmReplaceCart(
          conflict.merchantName.trim().isEmpty
              ? 'another restaurant'
              : conflict.merchantName.trim(),
        );
        if (!proceed) return;
        await cart.clearCart();
        existing = const [];
      }

      final numericId = item.id != 0
          ? item.id
          : (item.firestoreListingId ?? item.FoodName).hashCode.abs() %
              2000000000;
      var already = 0;
      final configKey = _incomingLineConfigKey;
      for (final c in existing) {
        if (c.item == numericId &&
            c.merchantId == mid &&
            c.lineConfigKey == configKey) {
          already += c.quantity;
        }
      }
      final qty = (already + _qty).clamp(1, 99999);

      final note = _descCtrl.text.trim();
      final img = item.FoodImage.trim().isNotEmpty
          ? item.FoodImage.trim()
          : (item.gallery.isNotEmpty ? item.gallery.first.trim() : '');
      final addOns = _selectedAddOnNames;

      final cartItem = CartModel(
        userId: uid,
        item: numericId,
        quantity: qty,
        image: img,
        name: item.FoodName,
        price: _unitPrice,
        description: item.description ?? '',
        comment: note.isEmpty ? null : note,
        merchantId: mid,
        merchantName: item.RestrauntName.trim().isEmpty
            ? 'Local kitchen'
            : item.RestrauntName.trim(),
        serviceType: 'food',
        restaurantId: item.restaurantId?.trim().isEmpty == true
            ? null
            : item.restaurantId?.trim(),
        variant: _selectedVariantName,
        notes: note.isEmpty ? null : note,
        addOns: addOns,
      );

      await cart.addToCart(cartItem);
      if (!mounted) return;

      if (goToCheckout) {
        final items = cart.cachedItems.isNotEmpty
            ? cart.cachedItems
            : <CartModel>[cartItem];
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CheckoutFromCartPage(items: items),
          ),
        );
      } else {
        _toast('${item.FoodName} added to cart', true);
      }
    } catch (e) {
      if (mounted) {
        _toast('Could not add to cart. Please sign in and try again.', false);
      }
    } finally {
      if (mounted) setState(() => _cartBusy = false);
    }
  }

  void _toast(String msg, bool ok) =>
      ToastHelper.showCustomToast(context, msg, isSuccess: ok, errorMessage: '');

  Widget _buildDeliverToCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Deliver to',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              if (_loggedIn)
                TextButton.icon(
                  onPressed: _addressLoading ? null : _openAddressManager,
                  style: TextButton.styleFrom(
                    foregroundColor: _veroOrange,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                  label: Text(
                    _deliveryAddressLine.trim().isEmpty ? 'Set' : 'Change',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_loggedIn)
            Text(
              'Sign in to order. Your name, email, and phone are taken from your account at checkout.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            )
          else if (_addressLoading)
            const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_deliveryAddressLine.trim().isEmpty)
            Text(
              'No delivery address yet. Tap Set to add one in your profile.',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded,
                    color: _veroOrange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _deliveryAddressLine,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          if (_loggedIn) ...[
            const SizedBox(height: 8),
            Text(
              'Name, email, and phone are filled from your account at checkout.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final item   = widget.foodItem;
    final heroImages = _heroImages;
    final cat    = ((item.category ?? 'Meals').trim().isEmpty)
        ? 'Meals' : item.category!.trim();
    final desc   = item.description?.trim() ?? '';
    final mq     = MediaQuery.of(context);

    // How tall the orange dome is
    final double heroHeight = 300.0 + mq.padding.top;
    const double imageSize = 220.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [

          // ── SCROLLABLE BODY ──────────────────────────────────────────────
          SingleChildScrollView(
            child: Column(
                children: [

                  // ── ORANGE DOME + CIRCULAR FOOD ───────────────────────
                  SizedBox(
                    height: heroHeight + 48,
                    width: double.infinity,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: heroHeight,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF9A1F), Color(0xFFFF7A00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(200),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8,
                          child: Center(
                            child: Container(
                              width: imageSize,
                              height: imageSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: PageView.builder(
                                  controller: _pageCtrl,
                                  itemCount: heroImages.length,
                                  onPageChanged: _onHeroPageChanged,
                                  itemBuilder: (_, i) => _FoodHeroImage(
                                    raw: heroImages[i],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (heroImages.length > 1)
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(heroImages.length, (i) {
                                final a = i == _pageIdx;
                                return AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 3),
                                  height: 6,
                                  width: a ? 16 : 6,
                                  decoration: BoxDecoration(
                                    color: a
                                        ? _veroOrange
                                        : Colors.grey.shade300,
                                    borderRadius:
                                        BorderRadius.circular(99),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── WHITE BODY ────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Name + Price row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(item.FoodName,
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: _ink,
                                      letterSpacing: -0.4)),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'MWK ${_unitPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: _veroOrange),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Category
                        Text(cat,
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500)),

                        if (item.variants.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text('Size',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _ink)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(item.variants.length, (i) {
                              final v = item.variants[i];
                              final sel = _selectedVariantIndex == i;
                              final delta = v.priceDeltaMwk;
                              final deltaLabel = delta == 0
                                  ? v.name
                                  : '${v.name} (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)})';
                              return ChoiceChip(
                                label: Text(deltaLabel),
                                selected: sel,
                                onSelected: (_) =>
                                    setState(() => _selectedVariantIndex = i),
                                selectedColor: _veroOrange,
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.white : _ink,
                                ),
                                backgroundColor: Colors.grey.shade100,
                                checkmarkColor: Colors.white,
                              );
                            }),
                          ),
                        ],
                        if (item.addOns.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text('Add-ons',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _ink)),
                          const SizedBox(height: 4),
                          ...List.generate(item.addOns.length, (i) {
                            final a = item.addOns[i];
                            final sel = _selectedAddOnIndexes.contains(i);
                            return CheckboxListTile(
                              value: sel,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: _veroOrange,
                              title: Text(
                                a.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                              secondary: Text(
                                a.priceMwk == 0
                                    ? 'Free'
                                    : '+ MWK ${a.priceMwk.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedAddOnIndexes.add(i);
                                  } else {
                                    _selectedAddOnIndexes.remove(i);
                                  }
                                });
                              },
                            );
                          }),
                        ],

                        const SizedBox(height: 18),

                        // Details / Reviews tabs
                        _SegmentedTabs(controller: _tabCtrl),
                        const SizedBox(height: 14),

                        // Tab content (description stays compact; reviews list needs room)
                        SizedBox(
                          height: _tabCtrl.index == 1 ? 220 : 95,
                          child: TabBarView(
                            controller: _tabCtrl,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            children: [
                              // — Details tab —
                              desc.isEmpty
                                  ? Text('No description available.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500))
                                  : RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                            height: 1.6),
                                        children: [
                                          TextSpan(
                                            text: _descExpanded
                                                ? desc
                                                : (desc.length > 130
                                                    ? '${desc.substring(0, 130)}.. '
                                                    : desc),
                                          ),
                                          if (desc.length > 130 &&
                                              !_descExpanded)
                                            WidgetSpan(
                                              child: GestureDetector(
                                                onTap: () => setState(
                                                    () => _descExpanded =
                                                        true),
                                                child: const Text(
                                                  'See more.',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _veroOrange),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                              // — Reviews tab —
                              _KitchenReviewsPane(
                                restaurantId: item.restaurantId,
                                merchantId: item.merchantId,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                        const Divider(height: 1, color: _divider),
                        const SizedBox(height: 20),

                        const Text(
                          'Note to kitchen',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _field(
                          ctrl: _descCtrl,
                          label: 'Optional',
                          hint: 'e.g. No onions, extra sauce…',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        _buildDeliverToCard(),

                        // Space so content clears the fixed bottom bar
                        const SizedBox(height: 140),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── BACK BUTTON (top-left, over red) ────────────────────────────
          Positioned(
            top: mq.padding.top + 14,
            left: 16,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              shadowColor: Colors.black26,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: _ink),
                ),
              ),
            ),
          ),

          // ── THREE-DOT MENU ──────────────────────────────────────────────
          Positioned(
            top: mq.padding.top + 10,
            right: 48,
            child: Material(
              color: Colors.white.withValues(alpha: 0.22),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                onPressed: () => unawaited(_shareFood()),
              ),
            ),
          ),

          Positioned(
            top: mq.padding.top + 10,
            right: 8,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (v) {
                if (v == 'buy') {
                  FocusScope.of(context).unfocus();
                  unawaited(_addFoodToCart(goToCheckout: true));
                } else if (v == 'share') {
                  unawaited(_shareFood());
                } else if (v == 'copy') {
                  unawaited(_copyFoodLink());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'share',
                  child: Text('Share link'),
                ),
                PopupMenuItem(
                  value: 'copy',
                  child: Text('Copy link'),
                ),
                PopupMenuItem(
                  value: 'buy',
                  child: Text('Buy now'),
                ),
              ],
            ),
          ),

          // ── BOTTOM BAR ────────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  20, 10, 20, 14 + mq.padding.bottom),
              child: Row(
                children: [
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _stepBtn(
                          icon: Icons.remove_rounded,
                          onTap: () {
                            if (_qty > 1) setState(() => _qty--);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '$_qty',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                        ),
                        _stepBtn(
                          icon: Icons.add_rounded,
                          onTap: () => setState(() => _qty++),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _cartBusy
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                unawaited(
                                    _addFoodToCart(goToCheckout: false));
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _veroOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _cartBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Add to cart',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tiny helpers ───────────────────────────────────────────────────────────
  Widget _stepBtn({required IconData icon, required VoidCallback onTap}) =>
      Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 18, color: _veroOrange),
          ),
        ),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: _ink,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: const TextStyle(
            fontSize: 14,
            color: _ink,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: _veroOrange,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _divider, width: 1.2),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: _veroOrange, width: 1.8),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Kitchen reviews (food_reviews) ────────────────────────────────────────────
class _KitchenReviewsPane extends StatelessWidget {
  const _KitchenReviewsPane({this.restaurantId, this.merchantId});

  final String? restaurantId;
  final String? merchantId;

  @override
  Widget build(BuildContext context) {
    final stream = FoodReviewService().reviewsStreamForKitchen(
      restaurantId: restaurantId,
      merchantId: merchantId,
    );
    if (stream == null) {
      return Text(
        'No reviews yet.',
        style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _veroOrange,
              ),
            ),
          );
        }
        final docs = [...(snap.data?.docs ?? const [])];
        docs.sort((a, b) {
          DateTime at = DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bt = DateTime.fromMillisecondsSinceEpoch(0);
          final ad = a.data()['createdAt'];
          final bd = b.data()['createdAt'];
          if (ad is Timestamp) at = ad.toDate();
          if (bd is Timestamp) bt = bd.toDate();
          return bt.compareTo(at);
        });
        if (docs.isEmpty) {
          return Text(
            'No reviews yet.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = docs[i].data();
            final name =
                (m['customerName']?.toString() ?? 'Anonymous').trim();
            final comment = (m['comment']?.toString() ?? '').trim();
            final rating = m['rating'] is num
                ? (m['rating'] as num).round()
                : int.tryParse('${m['rating']}') ?? 0;
            DateTime? when;
            final raw = m['createdAt'];
            if (raw is Timestamp) when = raw.toDate();
            if (raw is DateTime) when = raw;
            final ago = when == null
                ? ''
                : MarketplaceTime.formatTimeAgo(when, verbose: true);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Anonymous' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _ink,
                        ),
                      ),
                    ),
                    ...List.generate(5, (s) {
                      return Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: s < rating
                            ? const Color(0xFFFFC107)
                            : Colors.grey.shade300,
                      );
                    }),
                  ],
                ),
                if (comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      comment,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                if (ago.isNotEmpty)
                  Text(
                    ago,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Segmented tab bar ─────────────────────────────────────────────────────────
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tab('Details', 0, controller.index),
            const SizedBox(width: 10),
            _tab('Reviews', 1, controller.index),
          ],
        );
      },
    );
  }

  Widget _tab(String label, int i, int selected) {
    final active = i == selected;
    return GestureDetector(
      onTap: () => controller.animateTo(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _veroOrange : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: active ? _veroOrange : const Color(0xFFDDDDDD)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.grey.shade500),
        ),
      ),
    );
  }
}