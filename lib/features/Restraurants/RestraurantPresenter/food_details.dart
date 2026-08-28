// lib/features/Restraurants/RestraurantPresenter/food_details.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vero360_app/GeneralModels/address_model.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GeneralPages/address.dart';
import 'package:vero360_app/features/Cart/CartModel/cart_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_share_link.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_checkout_page.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_engagement_service.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_review_service.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_time.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/courier_city.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/map_location_picker_screen.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
import 'package:vero360_app/GernalServices/blocked_merchant_service.dart';
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
  bool _buyNowBusy = false;
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
  List<FoodModel> _moreFromKitchen = [];
  bool _moreKitchenLoading = true;

  /// Merchant stock cap; legacy dishes without quantity stay effectively uncapped.
  int get _maxQty => widget.foodItem.maxOrderQuantity;

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
    final max = item.maxOrderQuantity;
    if (max < 1) {
      _qty = 1;
    } else if (_qty > max) {
      _qty = max;
    }
    _hydrateDefaultsFast();
    _startHeroAutoSlide();
    unawaited(_loadMoreFromKitchen());
    unawaited(FoodEngagementService.recordView(widget.foodItem));
    unawaited(FoodEngagementService.recordClick(widget.foodItem));
  }

  Future<void> _loadMoreFromKitchen() async {
    final item = widget.foodItem;
    try {
      final list = await FoodService().fetchFromSameKitchen(
        restaurantId: item.restaurantId,
        merchantId: item.merchantId,
        kitchenName: item.RestrauntName,
        exclude: item,
        limit: 24,
      );
      if (!mounted) return;
      setState(() {
        _moreFromKitchen = list;
        _moreKitchenLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _moreKitchenLoading = false);
    }
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
    unawaited(_persistDropoffPin());
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

  Future<void> _openMapPicker() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          selectAsDropoff: false,
          initialLatitude: _deliveryLat,
          initialLongitude: _deliveryLng,
        ),
      ),
    );
    if (!mounted || place == null) return;
    setState(() {
      _deliveryLat = place.latitude;
      _deliveryLng = place.longitude;
      if (place.address.trim().isNotEmpty) {
        _deliveryAddressLine = place.address.trim();
      }
    });
    await _persistDropoffPin();
    _toast('Exact pin saved', true);
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
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12),
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

  Future<void> _persistDropoffPin() async {
    final lat = _deliveryLat;
    final lng = _deliveryLng;
    if (lat == null || lng == null) return;
    final addr = _deliveryAddressLine.trim();
    final city = CourierCityHelper.resolve(addr);
    final cityName = city == null ? '' : CourierCityHelper.displayName(city);
    AddressService.seedLocalDefaultPin(
      description: addr.isEmpty
          ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'
          : addr,
      city: cityName,
      lat: lat,
      lng: lng,
    );
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('food_dropoff_lat', lat);
      await sp.setDouble('food_dropoff_lng', lng);
      if (addr.isNotEmpty) await sp.setString('food_dropoff_address', addr);
    } catch (_) {}
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

  Future<void> _addFoodToCart() async {
    if (_cartBusy || _buyNowBusy) return;
    if (_maxQty < 1) {
      _toast('This dish is out of stock.', false);
      return;
    }
    if (_deliveryLat == null || _deliveryLng == null) {
      final pinned = await _autoPinDelivery();
      if (!pinned || _deliveryLat == null || _deliveryLng == null) {
        _toast('Pin your exact location so the courier can find you.', false);
        return;
      }
    }
    await _persistDropoffPin();
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
      if (already >= _maxQty) {
        _toast('Only $_maxQty available for this dish.', false);
        return;
      }
      final qty = (already + _qty).clamp(1, _maxQty);

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
        location: item.listingLocation,
      );

      await cart.addToCart(cartItem);
      if (!mounted) return;
      _toast('${item.FoodName} added to cart', true);
    } catch (e) {
      if (mounted) {
        _toast('Could not add to cart. Please sign in and try again.', false);
      }
    } finally {
      if (mounted) {
        setState(() => _cartBusy = false);
      }
    }
  }

  /// Checkout this dish only — does not write to the cart.
  Future<void> _buyFoodNow() async {
    if (_cartBusy || _buyNowBusy) return;
    if (_maxQty < 1) {
      _toast('This dish is out of stock.', false);
      return;
    }
    if (_deliveryLat == null || _deliveryLng == null) {
      final pinned = await _autoPinDelivery();
      if (!pinned || _deliveryLat == null || _deliveryLng == null) {
        _toast('Pin your exact location so the courier can find you.', false);
        return;
      }
    }
    await _persistDropoffPin();
    final item = widget.foodItem;
    final mid = item.merchantId?.trim();
    if (mid == null || mid.isEmpty) {
      _toast('This dish cannot be ordered online (missing seller).', false);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _toast('Please sign in to buy.', false);
      return;
    }

    setState(() => _buyNowBusy = true);
    try {
      final numericId = item.id != 0
          ? item.id
          : (item.firestoreListingId ?? item.FoodName).hashCode.abs() %
              2000000000;
      final qty = _qty.clamp(1, _maxQty);
      final note = _descCtrl.text.trim();
      final img = item.FoodImage.trim().isNotEmpty
          ? item.FoodImage.trim()
          : (item.gallery.isNotEmpty ? item.gallery.first.trim() : '');

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
        addOns: _selectedAddOnNames,
        location: item.listingLocation,
      );

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FoodCheckoutPage(items: [cartItem]),
        ),
      );
    } catch (e) {
      if (mounted) {
        _toast('Could not start checkout. Please try again.', false);
      }
    } finally {
      if (mounted) {
        setState(() => _buyNowBusy = false);
      }
    }
  }

  void _toast(String msg, bool ok) =>
      ToastHelper.showCustomToast(context, msg, isSuccess: ok, errorMessage: '');

  String _coverFor(FoodModel item) {
    final primary = item.FoodImage.trim();
    if (primary.isNotEmpty) return primary;
    for (final g in item.gallery) {
      if (g.trim().isNotEmpty) return g.trim();
    }
    return '';
  }

  void _openKitchenExplore() {
    final kitchen = widget.foodItem.RestrauntName.trim().isEmpty
        ? 'this restaurant'
        : widget.foodItem.RestrauntName.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _KitchenExplorePage(
          kitchenName: kitchen,
          items: _moreFromKitchen,
          merchantId: (widget.foodItem.merchantId ?? '').trim(),
          restaurantId: (widget.foodItem.restaurantId ?? '').trim(),
        ),
      ),
    );
  }

  Widget _buildMoreFromKitchen() {
    final kitchen = widget.foodItem.RestrauntName.trim().isEmpty
        ? 'this restaurant'
        : widget.foodItem.RestrauntName.trim();
    final preview = _moreFromKitchen.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Explore more from $kitchen',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'More dishes from this restaurant',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 12),
        if (_moreKitchenLoading)
          const SizedBox(
            height: 80,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _veroOrange,
                ),
              ),
            ),
          )
        else if (preview.isNotEmpty)
          SizedBox(
            height: 168,
            child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final f = preview[i];
              final img = _coverFor(f);
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FoodDetailsPage(foodItem: f),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 132,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 100,
                          width: 132,
                          child: img.isEmpty
                              ? Container(
                                  color: const Color(0xFFFFF4E8),
                                  child: const Icon(
                                    Icons.restaurant_menu_rounded,
                                    color: _veroOrange,
                                  ),
                                )
                              : ResilientCachedNetworkImage(
                                  url: img,
                                  height: 100,
                                  width: 132,
                                  memCacheWidth: 264,
                                  showSpinner: false,
                                  placeholderColor: const Color(0xFFFFF4E8),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        f.FoodName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: _ink,
                        ),
                      ),
                      Text(
                        'MWK ${NumberFormat('#,##0').format(f.price.round())}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: _veroOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _openKitchenExplore,
            style: OutlinedButton.styleFrom(
              foregroundColor: _veroOrange,
              side: const BorderSide(color: _veroOrange, width: 1.4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Explore more from $kitchen',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

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
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _openMapPicker,
              icon: const Icon(Icons.pin_drop_outlined, size: 16),
              label: const Text(
                'Pin exact location on map',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: _veroOrange,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (_deliveryLat != null && _deliveryLng != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: GoogleMap(
                    key: ValueKey(
                      'pin-${_deliveryLat!.toStringAsFixed(5)}-${_deliveryLng!.toStringAsFixed(5)}',
                    ),
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_deliveryLat!, _deliveryLng!),
                      zoom: 17.5,
                    ),
                    mapType: MapType.normal,
                    liteModeEnabled: true,
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    markers: {
                      Marker(
                        markerId: const MarkerId('food_dropoff'),
                        position: LatLng(_deliveryLat!, _deliveryLng!),
                      ),
                    },
                    onTap: (_) => _openMapPicker(),
                  ),
                ),
              ),
            ],
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
                              'MWK ${NumberFormat('#,##0').format(_unitPrice.round())}',
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
                                  : '${v.name} (${delta > 0 ? '+' : ''}${NumberFormat('#,##0').format(delta.round())})';
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
                                    : '+ MWK ${NumberFormat('#,##0').format(a.priceMwk.round())}',
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
                        _buildMoreFromKitchen(),

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

          Positioned(
            top: mq.padding.top + 10,
            right: 12,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              shadowColor: Colors.black26,
              child: IconButton(
                tooltip: 'Share food',
                icon: const Icon(Icons.share_rounded, color: _ink),
                onPressed: () => unawaited(_shareFood()),
              ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                          onTap: () {
                            if (_qty >= _maxQty) {
                              _toast(
                                _maxQty < 1
                                    ? 'This dish is out of stock.'
                                    : 'Only $_maxQty available.',
                                false,
                              );
                              return;
                            }
                            setState(() => _qty++);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _barActionButton(
                      label: 'Add to cart',
                      color: _veroOrange,
                      busy: _cartBusy,
                      onPressed: (_cartBusy || _buyNowBusy || _maxQty < 1)
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              unawaited(_addFoodToCart());
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _barActionButton(
                      label: 'Buy',
                      color: const Color(0xFFE53935),
                      busy: _buyNowBusy,
                      onPressed: (_cartBusy || _buyNowBusy || _maxQty < 1)
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              unawaited(_buyFoodNow());
                            },
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
  Widget _barActionButton({
    required String label,
    required Color color,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
      ),
    );
  }

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

class _KitchenExplorePage extends StatefulWidget {
  const _KitchenExplorePage({
    required this.kitchenName,
    required this.items,
    this.merchantId = '',
    this.restaurantId = '',
  });

  final String kitchenName;
  final List<FoodModel> items;
  final String merchantId;
  final String restaurantId;

  @override
  State<_KitchenExplorePage> createState() => _KitchenExplorePageState();
}

class _KitchenExplorePageState extends State<_KitchenExplorePage> {
  static const int _kMaxReportPhotos = 4;
  final ImagePicker _picker = ImagePicker();

  String _name = '';
  String _profileUrl = '';
  String _description = '';
  String _openingHours = '';
  List<int> _openingDays = const [];
  String _location = '';
  int _reviewCount = 0;
  double _rating = 0;
  bool _loadingProfile = true;
  bool _following = false;
  int _followerCount = 0;
  bool _followBusy = false;
  List<FoodModel> _menuItems = [];
  bool _loadingMenu = true;

  String get _merchantId {
    final mid = widget.merchantId.trim();
    if (mid.isNotEmpty) return mid;
    for (final f in widget.items) {
      final m = (f.merchantId ?? '').trim();
      if (m.isNotEmpty) return m;
    }
    return '';
  }

  String get _restaurantId {
    final rid = widget.restaurantId.trim();
    if (rid.isNotEmpty) return rid;
    for (final f in widget.items) {
      final r = (f.restaurantId ?? '').trim();
      if (r.isNotEmpty) return r;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _name = widget.kitchenName;
    _menuItems = List<FoodModel>.from(widget.items);
    for (final f in widget.items) {
      final loc = (f.listingLocation ?? '').trim();
      if (loc.isNotEmpty) {
        _location = loc;
        break;
      }
    }
    unawaited(_loadProfile());
    unawaited(_loadFullMenu());
  }

  Future<void> _loadFullMenu() async {
    try {
      final list = await FoodService().fetchKitchenListings(
        restaurantId: _restaurantId,
        merchantId: _merchantId,
        kitchenName: widget.kitchenName,
      );
      if (!mounted) return;
      setState(() {
        _menuItems = list.isNotEmpty ? list : List<FoodModel>.from(widget.items);
        _loadingMenu = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _menuItems = List<FoodModel>.from(widget.items);
          _loadingMenu = false;
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    final mid = _merchantId;
    if (mid.isEmpty) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }
    try {
      final db = FirebaseFirestore.instance;
      final docs = await Future.wait([
        db.collection('food_merchants').doc(mid).get(),
        db.collection('users').doc(mid).get(),
      ]);
      final merchant = docs[0];
      final user = docs[1];

      if (merchant.exists) {
        final m = merchant.data() ?? {};
        final n = (m['businessName'] ?? m['name'] ?? '').toString().trim();
        if (n.isNotEmpty) _name = n;
        final pic = (m['profileImage'] ??
                m['logo'] ??
                m['logoUrl'] ??
                m['image'] ??
                '')
            .toString()
            .trim();
        if (pic.isNotEmpty) _profileUrl = pic;
        final desc = (m['description'] ?? m['businessDescription'] ?? '')
            .toString()
            .trim();
        if (desc.isNotEmpty) _description = desc;
        final hours = MarketplaceShopHours.normalize(
              (m['openingHours'] ?? m['shopHours'] ?? '').toString(),
            ) ??
            '';
        if (hours.isNotEmpty) _openingHours = hours;
        final days = MarketplaceShopHours.parseDays(m['openingDays']);
        if (days.isNotEmpty) _openingDays = days;
        final loc = (m['businessLocation'] ??
                m['address'] ??
                m['location'] ??
                m['listingLocation'] ??
                '')
            .toString()
            .trim();
        if (loc.isNotEmpty) _location = loc;
        final fc = m['followerCount'] ?? m['followersCount'];
        if (fc is num) _followerCount = fc.toInt();
        final rc = m['reviewCount'] ?? m['reviewsCount'];
        if (rc is num) _reviewCount = rc.toInt();
        final rt = m['rating'] ?? m['avgRating'];
        if (rt is num) _rating = rt.toDouble();
      }

      final u = user.data() ?? {};
      if (_name.isEmpty || _name == 'this restaurant') {
        final n = (u['businessName'] ?? u['fullname'] ?? '').toString().trim();
        if (n.isNotEmpty) _name = n;
      }
      if (_profileUrl.isEmpty) {
        _profileUrl = (u['profilepicture'] ??
                u['profilePicture'] ??
                u['photoURL'] ??
                '')
            .toString()
            .trim();
      }
      if (_description.isEmpty) {
        _description =
            (u['businessDescription'] ?? u['description'] ?? '')
                .toString()
                .trim();
      }
      if (_openingHours.isEmpty) {
        _openingHours = MarketplaceShopHours.normalize(
              (u['openingHours'] ?? u['shopHours'] ?? '').toString(),
            ) ??
            '';
      }
      if (_openingDays.isEmpty) {
        _openingDays = MarketplaceShopHours.parseDays(u['openingDays']);
      }
      if (_location.isEmpty) {
        _location = (u['businessLocation'] ??
                u['address'] ??
                u['location'] ??
                u['listingLocation'] ??
                '')
            .toString()
            .trim();
      }
    } catch (e) {
      debugPrint('Kitchen profile load: $e');
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }

    // Reviews + follow should not block first paint.
    unawaited(_loadReviewsAndFollow(mid));
  }

  Future<void> _loadReviewsAndFollow(String mid) async {
    final db = FirebaseFirestore.instance;
    try {
      final reviews = await db
          .collection('food_reviews')
          .where('merchantId', isEqualTo: mid)
          .limit(40)
          .get();
      double sum = 0;
      int n = 0;
      for (final d in reviews.docs) {
        final raw = d.data()['rating'] ?? d.data()['stars'];
        final v = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
        if (v == null || v <= 0) continue;
        sum += v;
        n += 1;
      }
      int count = n;
      try {
        final agg = await db
            .collection('food_reviews')
            .where('merchantId', isEqualTo: mid)
            .count()
            .get();
        count = agg.count ?? n;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _reviewCount = count;
          _rating = n > 0 ? sum / n : _rating;
        });
      }
    } catch (_) {}

    final me = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    try {
      final followFuture = (me.isEmpty)
          ? Future<bool>.value(false)
          : db
              .collection('merchant_followers')
              .doc(mid)
              .collection('followers')
              .doc(me)
              .get()
              .then((s) => s.exists);

      Future<int> countFuture() async {
        try {
          final agg = await db
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
    } catch (_) {}
  }

  String _cover(FoodModel item) {
    final primary = item.FoodImage.trim();
    if (primary.isNotEmpty) return primary;
    for (final g in item.gallery) {
      if (g.trim().isNotEmpty) return g.trim();
    }
    return '';
  }

  void _viewProfilePhoto() {
    final url = _profileUrl.trim();
    if (url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(_name),
          ),
          body: Center(
            child: InteractiveViewer(
              child: ResilientCachedNetworkImage(
                url: url,
                fit: BoxFit.contain,
                showSpinner: true,
                placeholderColor: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _shareRestaurant() {
    final mid = _merchantId;
    final url = foodRestaurantShareUrl(
      merchantId: mid.isNotEmpty ? mid : 'kitchen',
      name: _name,
      image: _profileUrl,
    );
    Share.share('Check out $_name on Vero360 Food\n$url');
  }

  Future<void> _toggleFollow() async {
    final mid = _merchantId;
    final me = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (mid.isEmpty) {
      _toast('Restaurant profile is not ready yet.', false);
      return;
    }
    if (me.isEmpty) {
      _toast('Please log in to follow this restaurant.', false);
      return;
    }
    if (_followBusy) return;
    setState(() => _followBusy = true);
    final db = FirebaseFirestore.instance;
    final followerRef = db
        .collection('merchant_followers')
        .doc(mid)
        .collection('followers')
        .doc(me);
    try {
      if (_following) {
        await followerRef.delete();
        await db
            .collection('users')
            .doc(me)
            .collection('followed_merchants')
            .doc(mid)
            .delete();
        if (!mounted) return;
        setState(() {
          _following = false;
          if (_followerCount > 0) _followerCount -= 1;
        });
      } else {
        await followerRef.set({
          'uid': me,
          'followedAt': FieldValue.serverTimestamp(),
        });
        await db
            .collection('users')
            .doc(me)
            .collection('followed_merchants')
            .doc(mid)
            .set({
          'merchantId': mid,
          'followedAt': FieldValue.serverTimestamp(),
          'type': 'food',
        });
        if (!mounted) return;
        setState(() {
          _following = true;
          _followerCount += 1;
        });
      }
    } catch (e) {
      debugPrint('Follow restaurant: $e');
      if (mounted) _toast('Could not update follow status.', false);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _blockRestaurant() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Please log in to block a restaurant.', false);
      return;
    }
    final mid = _merchantId;
    if (mid.isEmpty) {
      _toast('Cannot block this restaurant yet.', false);
      return;
    }
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
                'Block restaurant?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You will stop seeing this restaurant in Food. You can unblock later in Settings.',
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
      merchantId: mid,
      displayName: _name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_name blocked. Unblock anytime in Settings.'),
        action: SnackBarAction(
          label: 'Unblock',
          onPressed: () async {
            await BlockedMerchantService.unblockMerchant(mid);
          },
        ),
      ),
    );
    Navigator.of(context).pop();
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
    if (bytes.isEmpty) throw StateError('Photo ${index + 1} is empty.');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeMerchant = _safeStorageSegment(merchantId);
    final safeUid = _safeStorageSegment(reporterUid);
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
            await ref.putFile(File(file.path), meta);
          }
          final url = await ref.getDownloadURL();
          if (url.trim().isEmpty) {
            throw StateError('Empty download URL for photo ${index + 1}');
          }
          return url;
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Could not upload photo ${index + 1}');
  }

  Future<void> _showReportScreenshotPicker(
    BuildContext sheetCtx, {
    required int remainingSlots,
    required void Function(List<XFile> files) onPicked,
  }) async {
    if (remainingSlots <= 0) return;
    await showModalBottomSheet<void>(
      context: sheetCtx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add screenshots',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final file = await _picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 85,
                  );
                  if (file != null) onPicked([file]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final files = await _picker.pickMultiImage(imageQuality: 85);
                  if (files.isNotEmpty) {
                    onPicked(files.take(remainingSlots).toList());
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reportRestaurant() async {
    final mid = _merchantId;
    final user = FirebaseAuth.instance.currentUser;
    if (mid.isEmpty) {
      _toast('Cannot report this restaurant yet.', false);
      return;
    }
    if (user == null) {
      _toast('Please log in to report a restaurant.', false);
      return;
    }

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
                          color: _veroOrange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: _veroOrange, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Report restaurant',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              _name,
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText:
                          'Tell us what is wrong (fraud, unsafe food, abuse, etc.)',
                      filled: true,
                      fillColor: const Color(0xFFF6F7FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Screenshots (optional, up to $_kMaxReportPhotos)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (picked.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < picked.length; i++)
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(picked[i].path),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: GestureDetector(
                                  onTap: () => setLocal(() => picked.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  if (picked.length < _kMaxReportPhotos) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        unawaited(_showReportScreenshotPicker(
                          dialogCtx,
                          remainingSlots: _kMaxReportPhotos - picked.length,
                          onPicked: (files) {
                            setLocal(() {
                              for (final f in files) {
                                if (picked.length >= _kMaxReportPhotos) break;
                                picked.add(f);
                              }
                            });
                          },
                        ));
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        picked.isEmpty
                            ? 'Add screenshots'
                            : 'Add more photos · ${picked.length}/$_kMaxReportPhotos',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Cancel',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _veroOrange,
                          ),
                          onPressed: () {
                            final msg = controller.text.trim();
                            if (msg.isEmpty && picked.isEmpty) {
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please write a message or add a screenshot.',
                                  ),
                                ),
                              );
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Sending report…'),
        duration: Duration(seconds: 60),
      ),
    );

    try {
      final proofUrls = <String>[];
      for (var i = 0; i < result.picked.length; i++) {
        if (mounted) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Uploading photo ${i + 1} of ${result.picked.length}…',
              ),
              duration: const Duration(seconds: 60),
            ),
          );
        }
        proofUrls.add(await _uploadReportProof(
          file: result.picked[i],
          merchantId: mid,
          reporterUid: user.uid,
          index: i,
        ));
      }

      await FirebaseFirestore.instance.collection('merchant_reports').add({
        'merchantId': mid,
        'merchantName': _name,
        'reporterUid': user.uid,
        'reporterEmail': user.email,
        'message': result.message,
        'proofUrl': proofUrls.isNotEmpty ? proofUrls.first : null,
        'proofUrls': proofUrls,
        'photoCount': proofUrls.length,
        'type': 'food_restaurant',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });

      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Report sent',
              style: TextStyle(fontWeight: FontWeight.w900)),
          content: Text(
            proofUrls.isEmpty
                ? 'Your report was sent successfully. Our team will review it.'
                : 'Your report was sent successfully.\n\n${proofUrls.length} photo${proofUrls.length == 1 ? '' : 's'} received.',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _veroOrange),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Report restaurant: $e');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      _toast('Could not submit report. Try again.', false);
    }
  }

  void _toast(String msg, bool ok) =>
      ToastHelper.showCustomToast(context, msg, isSuccess: ok, errorMessage: '');

  @override
  Widget build(BuildContext context) {
    final openNow = MarketplaceShopHours.isOpenNow(_openingHours, _openingDays);
    final hasHours = _openingHours.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      appBar: AppBar(
        title: Text(
          _name.isEmpty ? 'Restaurant' : _name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _veroOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Share restaurant',
            icon: const Icon(Icons.share_rounded),
            onPressed: _shareRestaurant,
          ),
              PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'block') unawaited(_blockRestaurant());
              if (v == 'report') unawaited(_reportRestaurant());
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    const Text('Block restaurant',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, color: _veroOrange),
                    SizedBox(width: 12),
                    Text('Report restaurant',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2E6EF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
                    children: [
                      if (_loadingProfile)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            color: _veroOrange,
                            backgroundColor: Color(0xFFFFE8CC),
                          ),
                        ),
                      GestureDetector(
                        onTap: _profileUrl.trim().isEmpty
                            ? null
                            : _viewProfilePhoto,
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: const Color(0xFFFFF3E5),
                          backgroundImage: _profileUrl.trim().isNotEmpty
                              ? NetworkImage(_profileUrl.trim())
                              : null,
                          child: _profileUrl.trim().isEmpty
                              ? const Icon(
                                  Icons.restaurant_rounded,
                                  size: 40,
                                  color: _veroOrange,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _veroOrange,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (_reviewCount > 0)
                            '$_reviewCount review${_reviewCount == 1 ? '' : 's'} · ${_rating.toStringAsFixed(1)} ★'
                          else
                            'No reviews yet',
                          _followerCount <= 0
                              ? 'No followers yet'
                              : '$_followerCount follower${_followerCount == 1 ? '' : 's'}',
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_location.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_rounded,
                                size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _location.trim(),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (hasHours) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: openNow
                                ? const Color(0xFFE7F6EC)
                                : const Color(0xFFFFEDEE),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            openNow
                                ? 'OPEN · $_openingHours'
                                : 'CLOSED · $_openingHours',
                            style: TextStyle(
                              color: openNow
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (_description.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _description.trim(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _followBusy ? null : _toggleFollow,
                          style: FilledButton.styleFrom(
                            backgroundColor: _following
                                ? const Color(0xFF16284C)
                                : _veroOrange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            _following
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _following ? 'Following' : 'Follow',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          Text(
            _loadingMenu
                ? 'Loading menu…'
                : 'Menu · ${_menuItems.length} dish${_menuItems.length == 1 ? '' : 'es'}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingMenu)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _veroOrange,
                  ),
                ),
              ),
            )
          else if (_menuItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No dishes from this restaurant yet.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ...List.generate(_menuItems.length, (i) {
              final f = _menuItems[i];
              final img = _cover(f);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => FoodDetailsPage(foodItem: f),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _divider),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 72,
                              height: 72,
                              child: img.isEmpty
                                  ? Container(
                                      color: const Color(0xFFFFF4E8),
                                      child: const Icon(
                                        Icons.restaurant_menu_rounded,
                                        color: _veroOrange,
                                      ),
                                    )
                                  : ResilientCachedNetworkImage(
                                      url: img,
                                      width: 72,
                                      height: 72,
                                      memCacheWidth: 160,
                                      showSpinner: false,
                                      placeholderColor:
                                          const Color(0xFFFFF4E8),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.FoodName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'MWK ${NumberFormat('#,##0').format(f.price.round())}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _veroOrange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
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