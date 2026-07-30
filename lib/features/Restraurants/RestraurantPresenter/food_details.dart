// lib/features/Restraurants/RestraurantPresenter/food_details.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/GernalServices/address_service.dart';
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
  final _formKey      = GlobalKey<FormState>();
  final _descCtrl     = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  late  PageController _pageCtrl;
  late  TabController  _tabCtrl;

  int  _pageIdx           = 0;
  int  _qty               = 1;
  bool _payStarting       = false;
  bool _descExpanded      = false;

  double? _deliveryLat, _deliveryLng;
  bool _pinning = false;
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

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _tabCtrl  = TabController(length: 2, vsync: this);
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
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Prefill from prefs / address cache without blocking the food hero UI.
  Future<void> _hydrateDefaultsFast() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final name = sp.getString('user_full_name') ?? sp.getString('name');
      final phone = sp.getString('user_phone') ?? sp.getString('phone');
      final email = sp.getString('email');
      if (mounted) {
        setState(() {
          if (name?.trim().isNotEmpty == true) _nameCtrl.text = name!;
          if (phone?.trim().isNotEmpty == true) _phoneCtrl.text = phone!;
          if (email?.trim().isNotEmpty == true) _emailCtrl.text = email!;
        });
      }

      final cached = await _addressService.getCachedDefaultAddress();
      if (cached != null && mounted) {
        final d = cached.description.trim();
        final c = cached.city.trim();
        final location = d.isNotEmpty && c.isNotEmpty
            ? '$d, $c'
            : d.isNotEmpty
                ? d
                : (c.isNotEmpty ? c : null);
        setState(() {
          if (location != null && location.isNotEmpty) {
            _locationCtrl.text = location;
          }
          if (cached.lat != null && cached.lng != null) {
            _deliveryLat = cached.lat;
            _deliveryLng = cached.lng;
          }
        });
      }

      unawaited(_refreshAddressFromNetwork());
      unawaited(_autoPinDelivery());
    } catch (_) {
      unawaited(_autoPinDelivery());
    }
  }

  Future<void> _refreshAddressFromNetwork() async {
    try {
      final addrs = await _addressService.getMyAddresses();
      if (!mounted || addrs.isEmpty) return;
      final def = addrs.firstWhere(
        (a) => a.isDefault == true,
        orElse: () => addrs.first,
      );
      final d = def.description.trim();
      final c = def.city.trim();
      final location = d.isNotEmpty && c.isNotEmpty
          ? '$d, $c'
          : d.isNotEmpty
              ? d
              : (c.isNotEmpty ? c : null);
      if (!mounted) return;
      setState(() {
        if (location != null &&
            location.isNotEmpty &&
            _locationCtrl.text.trim().isEmpty) {
          _locationCtrl.text = location;
        }
        if (_deliveryLat == null &&
            def.lat != null &&
            def.lng != null) {
          _deliveryLat = def.lat;
          _deliveryLng = def.lng;
        }
      });
    } catch (_) {}
  }

  /// Auto-pin coords so Buy works without tapping Pin first.
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
          if (_locationCtrl.text.trim().isEmpty) {
            unawaited(_fillAddressFromCoords(last.latitude, last.longitude));
          }
          return true;
        }
      } catch (_) {}

      if (await _gpsSilent()) return true;
      if (await _geocodeSilent()) return true;
      return false;
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
      if (line.isNotEmpty && _locationCtrl.text.trim().isEmpty) {
        setState(() => _locationCtrl.text = line);
      }
    } catch (_) {}
  }

  void _toast(String msg, bool ok) =>
      ToastHelper.showCustomToast(context, msg, isSuccess: ok, errorMessage: '');

  Future<void> _openMaps() async {
    final q = _locationCtrl.text.trim();
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q.isEmpty ? 'delivery address' : q)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _toast('Could not open Maps', false);
    }
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
      if (_locationCtrl.text.trim().isEmpty) {
        unawaited(_fillAddressFromCoords(pos.latitude, pos.longitude));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _gps() async {
    final ok = await _gpsSilent();
    if (!ok) {
      _toast('Could not get location. Check permissions.', false);
      return;
    }
    if (_locationCtrl.text.trim().isEmpty &&
        _deliveryLat != null &&
        _deliveryLng != null) {
      await _fillAddressFromCoords(_deliveryLat!, _deliveryLng!);
    }
    if (mounted) _toast('Location pinned', true);
  }

  Future<bool> _geocodeSilent() async {
    final addr = _locationCtrl.text.trim();
    if (addr.length < 4) return false;
    try {
      final list = await locationFromAddress(addr);
      if (list.isEmpty || !mounted) return false;
      setState(() {
        _deliveryLat = list.first.latitude;
        _deliveryLng = list.first.longitude;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _geocodeTyped() async {
    final addr = _locationCtrl.text.trim();
    if (addr.length < 4) {
      final ok = await _autoPinDelivery();
      if (ok) {
        _toast('Location pinned', true);
      } else {
        _toast('Allow location or enter an address', false);
      }
      return;
    }
    final ok = await _geocodeSilent();
    if (ok) {
      _toast('Location pinned', true);
      return;
    }
    if (await _gpsSilent()) {
      _toast('Location pinned via GPS', true);
    } else {
      _toast('Could not find that address', false);
    }
  }

  Future<void> _startCheckout() async {
    if (_payStarting) return;
    setState(() => _payStarting = true);

    final item = widget.foodItem;
    final mid = item.merchantId?.trim();
    if (mid == null || mid.isEmpty) {
      if (mounted) setState(() => _payStarting = false);
      _toast('This dish cannot be ordered online (missing seller).', false);
      return;
    }
    if (!_formKey.currentState!.validate()) {
      if (mounted) setState(() => _payStarting = false);
      _toast('Please complete all required fields', false);
      return;
    }
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final loc = _locationCtrl.text.trim();
    var email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      final d = phone.replaceAll(RegExp(r'\D'), '');
      email = d.isNotEmpty ? 'guest+$d@guest.vero360.app' : 'guest@vero360.app';
    }

    // One-tap Buy: pin automatically if needed (no manual Pin tap).
    if (_deliveryLat == null || _deliveryLng == null) {
      await _autoPinDelivery();
    }
    if ((_deliveryLat == null || _deliveryLng == null) && loc.length < 4) {
      if (mounted) setState(() => _payStarting = false);
      _toast('Add a delivery address or allow location.', false);
      return;
    }

    try {
      await InternetAddress.lookup('api.paychangu.com');
    } on SocketException {
      if (mounted) setState(() => _payStarting = false);
      _toast('No internet — check connection', false);
      return;
    }

    final amount = (item.price * _qty).round();
    if (amount < 1) {
      if (mounted) setState(() => _payStarting = false);
      _toast('Invalid price', false);
      return;
    }
    final txRef = 'vero-food-${DateTime.now().millisecondsSinceEpoch}';
    final parts = name.split(RegExp(r'\s+'));
    final fName = parts.isNotEmpty ? parts.first : 'Customer';
    final lName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    try {
      final res = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode({
              'tx_ref': txRef,
              'first_name': fName,
              'last_name': lName,
              'email': email,
              'phone_number': phone,
              'currency': 'MWK',
              'amount': amount.toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero360 Food',
                'description': '${item.FoodName} x$_qty • $loc',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 201) {
        setState(() => _payStarting = false);
        _toast('Payment start failed (${res.statusCode})', false);
        return;
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final status = (body['status'] ?? '').toString().toLowerCase();
      if (status != 'success') {
        setState(() => _payStarting = false);
        _toast(body['message']?.toString() ?? 'Payment failed', false);
        return;
      }
      final checkoutUrl = body['data']['checkout_url'] as String;
      final note = _descCtrl.text.trim();
      final imgRaw = item.FoodImage.trim().isNotEmpty
          ? item.FoodImage.trim()
          : (item.gallery.isNotEmpty ? item.gallery.first.trim() : '');
      final img =
          (imgRaw.startsWith('http://') || imgRaw.startsWith('https://'))
              ? imgRaw
              : null;
      if (!mounted) return;
      setState(() => _payStarting = false);
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => InAppPaymentPage(
          checkoutUrl: checkoutUrl,
          txRef: txRef,
          totalAmount: item.price * _qty,
          rootContext: context,
          foodCheckout: FoodCheckoutContext(
            merchantId: mid,
            customerName: name,
            customerPhone: phone,
            customerEmail: email,
            deliveryAddress: loc,
            deliveryLat: _deliveryLat,
            deliveryLng: _deliveryLng,
            foodName: item.FoodName,
            totalMwk: item.price * _qty,
            customerNote: note.isEmpty ? null : note,
            foodImageUrl: img,
            sqlListingId: item.id != 0 ? item.id.toString() : null,
            firestoreListingId: item.firestoreListingId,
          ),
        ),
      ));
    } on SocketException {
      if (mounted) setState(() => _payStarting = false);
      _toast('Network error', false);
    } catch (e) {
      if (mounted) setState(() => _payStarting = false);
      _toast('Could not start payment: $e', false);
    }
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

    // How tall the orange hero zone is
    const double heroHeight = 420.0;
    // How much the food image overflows into the white card
    const double overflow   = 48.0;

    return Scaffold(
      backgroundColor: _veroOrange,
      // No AppBar — we paint everything manually
      body: Stack(
        children: [

          // ── SCROLLABLE BODY ──────────────────────────────────────────────
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [

                  // ── ORANGE HERO AREA ──────────────────────────────────
                  SizedBox(
                    height: heroHeight,
                    width: double.infinity,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [

                        // Soft gradient fill
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF9A1F), Color(0xFFFF7A00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),

                        // Food image — edge-to-edge so it doesn't look shrunk
                        Positioned(
                          top: mq.padding.top + 8,
                          left: 0,
                          right: 0,
                          bottom: -overflow,
                          child: PageView.builder(
                            controller: _pageCtrl,
                            itemCount: heroImages.length,
                            onPageChanged: _onHeroPageChanged,
                            itemBuilder: (_, i) => SizedBox.expand(
                              child: _FoodHeroImage(
                                raw: heroImages[i],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                        // Soft fade into white card
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -overflow,
                          height: 72,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.92),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Page indicator dots
                        if (heroImages.length > 1)
                          Positioned(
                            bottom: 14, left: 0, right: 0,
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
                                  width: a ? 20 : 6,
                                  decoration: BoxDecoration(
                                    color: a
                                        ? Colors.white
                                        : Colors.white54,
                                    borderRadius:
                                        BorderRadius.circular(99),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── WHITE CARD ────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(36)),
                    ),
                    // top padding = overflow so food image has room
                    padding: EdgeInsets.fromLTRB(
                        22, overflow + 16, 22, 16),
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
                              'MWK ${item.price.toStringAsFixed(0)}',
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

                        const SizedBox(height: 18),

                        // Details / Reviews tabs
                        _SegmentedTabs(controller: _tabCtrl),
                        const SizedBox(height: 14),

                        // Tab content (fixed height)
                        SizedBox(
                          height: 95,
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
                              Center(
                                child: Text('No reviews yet.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade400)),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                        const Divider(height: 1, color: _divider),
                        const SizedBox(height: 20),

                        // Delivery section heading
                        const Text('Delivery details',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _ink)),
                        const SizedBox(height: 5),
                        Text(
                          'Enter your address (type, GPS or Maps) and we\'ll deliver to you.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              height: 1.4),
                        ),
                        const SizedBox(height: 16),

                        // ── Form ────────────────────────────────────────
                        _field(ctrl: _descCtrl,
                            label: 'Note to kitchen (optional)',
                            hint: 'e.g. No onions, extra sauce…',
                            maxLines: 2),
                        const SizedBox(height: 10),
                        _field(ctrl: _nameCtrl, label: 'Your name',
                            hint: 'Full name', required: true),
                        const SizedBox(height: 10),
                        _field(ctrl: _phoneCtrl, label: 'Phone',
                            hint: '+265 99 123 4567',
                            keyboard: TextInputType.phone,
                            required: true),
                        const SizedBox(height: 10),
                        _field(ctrl: _emailCtrl,
                            label: 'Email (for receipt)',
                            hint: 'you@email.com',
                            keyboard: TextInputType.emailAddress,
                            customValidator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              if (!t.contains('@'))
                                return 'Enter a valid email';
                              return null;
                            }),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                  ctrl: _locationCtrl,
                                  label: 'Delivery address',
                                  hint: 'Street, area, city…',
                                  maxLines: 3,
                                  required: true),
                            ),
                            const SizedBox(width: 10),
                            Column(children: [
                              const SizedBox(height: 22),
                              _iconBtn(Icons.map_rounded, 'Maps', _openMaps),
                              const SizedBox(height: 6),
                              _iconBtn(Icons.my_location_rounded, 'GPS',
                                  _gps),
                            ]),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _geocodeTyped,
                            icon: const Icon(Icons.pin_drop_outlined,
                                size: 16, color: _veroOrange),
                            label: const Text('Pin on map',
                                style: TextStyle(
                                    color: _veroOrange,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 30)),
                          ),
                        ),
                        if (_deliveryLat != null && _deliveryLng != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Colors.green.shade600, size: 14),
                              const SizedBox(width: 4),
                              Text('Coordinates saved',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),

                        // Space so content clears the fixed bottom bar
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
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

          // ── THREE-DOT MENU (top-right, over red) ────────────────────────
          Positioned(
            top: mq.padding.top + 18,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (_) => Container(
                  width: 4, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 2.5),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ),

          // ── BOTTOM BAR ────────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 12 + mq.padding.bottom),
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: _veroOrange,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: _veroOrange.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  children: [
                    // ── Qty stepper ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _stepBtn(
                          icon: Icons.remove_rounded,
                          onTap: () {
                            if (_qty > 1) setState(() => _qty--);
                          },
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            '$_qty',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ),
                        _stepBtn(
                          icon: Icons.add_rounded,
                          onTap: () => setState(() => _qty++),
                        ),
                      ]),
                    ),

                    // Thin divider
                    Container(
                        width: 1,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: Colors.white.withOpacity(0.30)),

                    // ── Buy ─────────────────────────────────────────────
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _payStarting ? null : () {
                            FocusScope.of(context).unfocus();
                            unawaited(_startCheckout());
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Center(
                            child: _payStarting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Buy',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: Material(
      color: _veroOrange.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: _veroOrange, size: 20),
        ),
      ),
    ),
  );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    TextInputType keyboard  = TextInputType.text,
    int maxLines            = 1,
    bool required           = false,
    String? Function(String?)? customValidator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12.5, color: _ink)),
          if (required)
            const Text(' *',
                style: TextStyle(color: _veroOrange, fontSize: 12)),
        ]),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: const TextStyle(
              fontSize: 14, color: _ink, fontWeight: FontWeight.w500),
          cursorColor: _veroOrange,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
                fontWeight: FontWeight.w400),
            filled: true, fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _divider, width: 1.2)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide(color: _veroOrange, width: 1.8)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Colors.red, width: 1.2)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Colors.red, width: 1.8)),
          ),
          validator: customValidator ??
              (required
                  ? (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return '$label is required';
                      return null;
                    }
                  : null),
        ),
      ],
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