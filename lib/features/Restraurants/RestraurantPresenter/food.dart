// lib/Pages/Home/food_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/GernalServices/location_service.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_details.dart';
import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_categories.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/Home/notifications_page.dart';
import 'package:vero360_app/utils/user_facing_error.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

class FoodPage extends StatefulWidget {
  const FoodPage({
    super.key,
    this.kitchenRestaurantId,
    this.kitchenMerchantId,
    this.kitchenName,
  });

  final String? kitchenRestaurantId;
  final String? kitchenMerchantId;
  final String? kitchenName;

  bool get _kitchenFilter =>
      (kitchenRestaurantId?.trim().isNotEmpty ?? false) ||
      (kitchenMerchantId?.trim().isNotEmpty ?? false) ||
      (kitchenName?.trim().isNotEmpty ?? false);

  @override
  _FoodPageState createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  // ── Brand palette ─────────────────────────────────────────────────────────
  static const Color _veroOrange   = Color(0xFFFF8A00);
  static const Color _ink          = Color(0xFF1A1109);
  static const Color _pageBg       = Color(0xFFFFFFFF);
  static const Color _divider      = Color(0xFFEEEEEE);

  // ── Services / controllers ─────────────────────────────────────────────────
  final FoodService            foodService      = FoodService();
  final LocationService        _locationService = LocationService();
  final TextEditingController  _searchCtrl      = TextEditingController();
  final ImagePicker            _picker          = ImagePicker();

  Timer?   _debounce;
  bool     _loading        = false;
  bool     _photoMode      = false;

  Position? _userPosition;
  String?   _locationLabel;
  bool      _locationLoading = false;

  double _radiusKm        = 25;
  String _categoryFilter  = 'All';

  String _navEmail = '';
  bool _isMerchant = false;
  String _profileUrl = '';

  late Future<List<FoodModel>> _future;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    // Must init before first build — never leave `late _future` unset.
    _future = _loadAll();
    unawaited(_bootstrap());
  }

  /// Warm last-known location, then reload so nearby dishes rank first.
  Future<void> _bootstrap() async {
    if (!kIsWeb) {
      final quick = await _locationService.getQuickPosition();
      if (mounted && quick != null) {
        setState(() {
          _userPosition = quick;
          // Don't spin forever — we already have a usable position.
          _locationLoading = false;
        });
        final next = _loadAll();
        setState(() {
          _future = next;
        });
        unawaited(_resolveLocationLabel(quick).then((l) {
          if (mounted && l != null) setState(() => _locationLabel = l);
        }));
      } else if (mounted) {
        setState(() => _locationLoading = true);
      }
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNavPrefs();
      if (!kIsWeb) unawaited(_refineLocationAndReload());
    });
  }

  Future<void> _refineLocationAndReload() async {
    if (!mounted) return;
    // Keep banner usable: only show spinner if we have no position yet.
    if (_userPosition == null) {
      setState(() => _locationLoading = true);
    }
    try {
      final pos = await _locationService
          .getCurrentLocation(timeLimit: const Duration(seconds: 4))
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (!mounted) return;
      if (pos == null) {
        setState(() => _locationLoading = false);
        return;
      }

      final prev = _userPosition;
      final movedKm = prev == null
          ? null
          : FoodService.distanceKm(
              prev.latitude,
              prev.longitude,
              pos.latitude,
              pos.longitude,
            );
      final movedFar = prev == null || (movedKm != null && movedKm > 0.35);

      unawaited(_resolveLocationLabel(pos).then((l) {
        if (mounted && l != null) setState(() => _locationLabel = l);
      }));

      setState(() {
        _userPosition = pos;
        _locationLoading = false;
      });

      if (movedFar && mounted) {
        final next = _loadAll();
        setState(() {
          _future = next;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  Future<String?> _resolveLocationLabel(Position pos) async {
    try {
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return null;
      final pl = marks.first;
      final parts = <String>[
        if ((pl.locality ?? '').trim().isNotEmpty) pl.locality!.trim(),
        if ((pl.subAdministrativeArea ?? '').trim().isNotEmpty)
          pl.subAdministrativeArea!.trim(),
      ];
      if (parts.isNotEmpty) return parts.join(', ');
      final country = (pl.country ?? '').trim();
      return country.isNotEmpty ? country : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadNavPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final role =
        (p.getString('user_role') ?? p.getString('role') ?? '').toLowerCase();
    setState(() {
      _navEmail = p.getString('email') ?? '';
      _isMerchant = role == 'merchant';
      _profileUrl = (p.getString('profilepicture') ??
              p.getString('profilePicture') ??
              p.getString('photoUrl') ??
              '')
          .trim();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FoodModel> _filterKitchen(List<FoodModel> items) {
    if (!widget._kitchenFilter) return items;
    return items
        .where((f) => FoodService.isSameKitchen(
              f,
              restaurantId: widget.kitchenRestaurantId,
              merchantId: widget.kitchenMerchantId,
              kitchenName: widget.kitchenName,
            ))
        .toList();
  }

  // ── Data helpers ───────────────────────────────────────────────────────────
  List<FoodModel> _sortByDistanceIfPossible(List<FoodModel> items) {
    final p = _userPosition;
    if (p == null) return items;
    return FoodService.sortByDistanceToUser(items, p.latitude, p.longitude);
  }

  Future<List<FoodModel>> _loadAll() async {
    setState(() { _loading = true; _photoMode = false; });
    try {
      final items = await foodService.fetchFoodItems(
        latitude:  _userPosition?.latitude,
        longitude: _userPosition?.longitude,
        radiusKm:  _radiusKm,
      );
      final sorted = _sortByDistanceIfPossible(_filterKitchen(items));
      _precacheFoodImages(sorted);
      return sorted;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<FoodModel>> _searchByQuery(String raw) async {
    final q = raw.trim();
    if (q.length < 2) return _loadAll();
    setState(() { _loading = true; _photoMode = false; });
    try {
      final items = await foodService.searchFoodByNameOrRestaurant(
        q,
        latitude:  _userPosition?.latitude,
        longitude: _userPosition?.longitude,
        radiusKm:  _radiusKm,
      );
      final sorted = _sortByDistanceIfPossible(_filterKitchen(items));
      _precacheFoodImages(sorted);
      return sorted;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<FoodModel>> _searchByPhoto(File file) async {
    setState(() { _loading = true; _photoMode = true; });
    try {
      final items = await foodService.searchFoodByPhoto(file);
      final sorted = _sortByDistanceIfPossible(_filterKitchen(items));
      _precacheFoodImages(sorted);
      return sorted;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _initLocation() async {
    if (kIsWeb) return;
    await _refineLocationAndReload();
  }

  void _precacheFoodImages(List<FoodModel> items) {
    if (!mounted) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Thumb-sized decode — much faster than full-res food photos.
    final cachePx = (120 * dpr).round().clamp(96, 240);
    // Near-you dishes first (already sorted); warm the first row hard.
    for (final item in items.take(16)) {
      final url = _foodCoverUrl(item);
      if (url == null) continue;
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(
            url,
            maxWidth: cachePx,
            maxHeight: cachePx,
          ),
          context,
        ).catchError((_) {}),
      );
    }
  }

  static String? _foodCoverUrl(FoodModel item) {
    final raw = item.FoodImage.trim().isNotEmpty
        ? item.FoodImage.trim()
        : (item.gallery.isNotEmpty ? item.gallery.first.trim() : '');
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return raw;
    return null;
  }

  // ── Search handlers ────────────────────────────────────────────────────────
  void _onSearchChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final next = _searchByQuery(_searchCtrl.text);
      setState(() {
        _future = next;
      });
    });
  }

  void _onSubmit(String value) {
    _debounce?.cancel();
    final next = _searchByQuery(value);
    setState(() {
      _future = next;
    });
  }

  Future<void> _pickAndSearchPhoto(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1280);
    if (picked == null) return;
    if (!mounted) return;
    final next = _searchByPhoto(File(picked.path));
    setState(() {
      _future = next;
    });
  }

  Future<void> _showPhotoPickerSheet() async {
    if (kIsWeb) {
      final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1280);
      if (picked == null || !mounted) return;
      final next = _searchByPhoto(File(picked.path));
      setState(() {
        _future = next;
      });
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, 20 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44, height: 5,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Search by photo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1D26))),
            const SizedBox(height: 6),
            Text('Find dishes that look like your picture',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600,
                    height: 1.4)),
            const SizedBox(height: 22),
            _sheetOption(
              ctx: ctx,
              icon: Icons.camera_alt_outlined,
              color: _veroOrange,
              label: 'Use camera',
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSearchPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
            _sheetOption(
              ctx: ctx,
              icon: Icons.photo_library_outlined,
              color: const Color(0xFF1E88E5),
              label: 'Choose from gallery',
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSearchPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption({
    required BuildContext ctx,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15))),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    _searchCtrl.clear();
    final next = _loadAll();
    setState(() {
      _future = next;
    });
    await _future;
  }

  bool _matchesCategoryChip(FoodModel f) {
    if (_categoryFilter == 'All') return true;
    final c = ((f.category ?? 'Meals').trim().isEmpty
        ? 'meals'
        : f.category!.trim().toLowerCase());
    final want = _categoryFilter.toLowerCase();
    return c == want || c.contains(want);
  }

  Future<void> _showDiscoverySheet() async {
    var radius = _radiusKm;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, 20 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44, height: 5,
                  decoration: BoxDecoration(color: Colors.black12,
                      borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Nearby radius',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20,
                      color: _ink)),
              const SizedBox(height: 6),
              Text('Listings with GPS are ranked within this distance.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600,
                      height: 1.4)),
              const SizedBox(height: 8),
              Slider(
                value: radius.clamp(5.0, 60.0),
                min: 5, max: 60, divisions: 11,
                label: '${radius.round()} km',
                activeColor: _veroOrange,
                onChanged: (v) => setModal(() => radius = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  final next = _loadAll();
                  setState(() {
                    _radiusKm = radius;
                    _future = next;
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _veroOrange, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Apply',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Location banner ────────────────────────────────────────────────────────
  Widget _buildLocationBanner() {
    if (_locationLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Row(children: [
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _veroOrange),
          ),
          const SizedBox(width: 10),
          Text('Getting your location…',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
        ]),
      );
    }

    if (_userPosition != null) {
      final label = (_locationLabel ?? '').trim();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _veroOrange.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _veroOrange.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.my_location_rounded, color: _veroOrange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.isNotEmpty
                      ? 'Near $label · prioritising nearby food'
                      : 'Using GPS · prioritising food near you',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: _veroOrange.withOpacity(0.9)),
                ),
              ),
              GestureDetector(
                onTap: _initLocation,
                child: Icon(Icons.refresh_rounded,
                    color: _veroOrange.withOpacity(0.7), size: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: GestureDetector(
        onTap: _initLocation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _divider),
          ),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined,
                  color: Colors.grey.shade500, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Location off — tap to find food near you',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
              ),
              Text('Enable',
                  style: TextStyle(fontWeight: FontWeight.w800,
                      color: _veroOrange, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search row ─────────────────────────────────────────────────────────────
  Widget _buildSearchRow() {
    return Row(
      children: [
        Expanded(child: _buildSearchField()),
        const SizedBox(width: 12),
        _FilterButton(onTap: _showDiscoverySheet, color: _veroOrange),
      ],
    );
  }

  Widget _buildSearchField() {
    final hasText = _searchCtrl.text.isNotEmpty;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06),
              blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: _onSubmit,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
            color: Color(0xFF1A1D26)),
        cursorColor: _veroOrange,
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: Colors.grey.shade400,
              fontWeight: FontWeight.w400, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded,
              color: _veroOrange, size: 22),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (hasText)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: Colors.grey.shade500, size: 18),
                  onPressed: () { _searchCtrl.clear(); _onSubmit(''); },
                ),
              _CameraButton(onTap: _showPhotoPickerSheet, color: _veroOrange),
            ]),
          ),
          filled: true, fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _divider, width: 1)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _veroOrange, width: 1.5)),
        ),
      ),
    );
  }

  // ── Category chips ─────────────────────────────────────────────────────────
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: kFoodBrowseChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final label = kFoodBrowseChips[i];
          final sel = _categoryFilter == label;
          return GestureDetector(
            onTap: () => setState(() => _categoryFilter = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? _veroOrange : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: sel ? _veroOrange : _divider),
                boxShadow: sel
                    ? [BoxShadow(color: _veroOrange.withOpacity(0.30),
                        blurRadius: 12, offset: const Offset(0, 4))]
                    : [BoxShadow(color: Colors.black.withOpacity(0.04),
                        blurRadius: 6, offset: const Offset(0, 2))],
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: sel ? Colors.white : _ink)),
            ),
          );
        },
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      bottomNavigationBar: VeroMainNavigationBar(
        selectedIndex: null,
        isDark: Theme.of(context).brightness == Brightness.dark,
        isMerchant: _isMerchant,
        onTap: (i) => openVeroMainShell(
          context,
          email: _navEmail,
          tabIndex: i,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: _veroOrange,
                    height: 1.05,
                    letterSpacing: -0.6,
                  ),
                ),
                Text(
                  widget._kitchenFilter
                      ? (widget.kitchenName?.trim().isNotEmpty == true
                          ? 'More from ${widget.kitchenName!.trim()}'
                          : 'More from this kitchen')
                      : 'your favourite Food',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _ink.withValues(alpha: 0.85),
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 18),
                _buildSearchRow(),
              ],
            ),
          ),

          // Location banner (mobile only)
          if (!kIsWeb) _buildLocationBanner(),
          if (!kIsWeb) const SizedBox(height: 10),

          // Photo-mode banner
          if (_photoMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _veroOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _veroOrange.withOpacity(0.22)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.image_search_rounded,
                        size: 18, color: _veroOrange),
                    const SizedBox(width: 8),
                    Text('Showing results similar to your photo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: _ink.withOpacity(0.85))),
                  ],
                ),
              ),
            ),

          // Category chips
          _buildCategoryChips(),
          const SizedBox(height: 4),

          // Content
          Expanded(
            child: RefreshIndicator(
              color: _veroOrange,
              onRefresh: _refresh,
              child: FutureBuilder<List<FoodModel>>(
                future: _future,
                builder: (context, snapshot) {
                  // Loading skeleton
                  if (_loading &&
                      snapshot.connectionState == ConnectionState.waiting) {
                    return _buildSkeletonGrid();
                  }
                  // Error
                  if (snapshot.hasError) {
                    return _buildError(UserFacingError.from(snapshot.error));
                  }
                  final items = snapshot.data ?? const <FoodModel>[];
                  if (items.isEmpty) return _buildEmpty();

                  final filtered = items.where(_matchesCategoryChip).toList();
                  if (filtered.isEmpty) return _buildEmptyCategory();

                  final p = _userPosition;
                  final nearYou = p != null
                      ? FoodService.filterWithinRadius(
                          filtered,
                          latitude: p.latitude,
                          longitude: p.longitude,
                          radiusKm: _radiusKm,
                        )
                      : const <FoodModel>[];
                  // Prefer local kitchens; fall back to full list if none geo-tagged nearby.
                  final localFirst = nearYou.isNotEmpty
                      ? nearYou
                      : (p != null
                          ? FoodService.sortByDistanceToUser(
                              List<FoodModel>.from(filtered),
                              p.latitude,
                              p.longitude,
                            )
                          : filtered);
                  final nearRow = localFirst.take(12).toList();
                  final popular = localFirst.take(12).toList();

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 28),
                    children: [
                      _SectionHeader(
                        title: nearYou.isNotEmpty
                            ? 'Near you'
                            : 'Popular Food',
                        accent: _veroOrange,
                        ink: _ink,
                        onSeeAll: () {},
                      ),
                      if (nearYou.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            _locationLabel != null
                                ? 'Kitchens around $_locationLabel'
                                : 'Prioritized by your current location',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 248,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: nearRow.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (_, i) => _FoodCard(
                            item: nearRow[i],
                            userLat: p?.latitude, userLng: p?.longitude,
                            accent: _veroOrange, ink: _ink,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) =>
                                    FoodDetailsPage(foodItem: nearRow[i]))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionHeader(
                        title: nearYou.isNotEmpty ? 'More nearby' : 'Nearest',
                        accent: _veroOrange,
                        ink: _ink,
                        onSeeAll: () {},
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 248,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: popular.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (_, i) => _FoodCard(
                            item: popular[i],
                            userLat: p?.latitude, userLng: p?.longitude,
                            accent: _veroOrange, ink: _ink,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) =>
                                    FoodDetailsPage(foodItem: popular[i]))),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTopBar() {
    final canPop = Navigator.of(context).canPop();
    final url = _profileUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: _ink,
            ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
            child: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFFFE8CC),
              backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
              child: url.isEmpty
                  ? const Icon(Icons.person_rounded, color: _veroOrange)
                  : null,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
            },
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: _veroOrange,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  // ── State helpers ──────────────────────────────────────────────────────────
  Widget _buildSkeletonGrid() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        AppSkeletonShimmer(
          child: LayoutBuilder(builder: (ctx, c) {
            final cross = c.maxWidth >= 700 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross, crossAxisSpacing: 14,
                mainAxisSpacing: 14, childAspectRatio: 0.70),
              itemCount: cross * 4,
              itemBuilder: (_, __) => const AppSkeletonProductCardCore(),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildError(String err) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.error_outline_rounded, size: 52, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Center(child: Text('Could not load food',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17,
                color: Colors.grey.shade700))),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(err, textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: _refresh,
            style: FilledButton.styleFrom(
              backgroundColor: _veroOrange,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.restaurant_outlined, size: 60, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Center(child: Text('No food found in your area',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17,
                color: Colors.grey.shade700))),
        const SizedBox(height: 8),
        Center(child: Text('Try another search or browse all.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14))),
      ],
    );
  }

  Widget _buildEmptyCategory() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.restaurant_outlined, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Center(child: Text('Nothing in this category',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16,
                color: Colors.grey.shade700))),
        Center(child: TextButton(
          onPressed: () => setState(() => _categoryFilter = 'All'),
          child: const Text('Show all'),
        )),
      ],
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

bool _foodImageLooksLikeBase64(String s) {
  final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
  if (x.length < 40) return false;
  return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(x);
}

String _foodListingLocationLine(FoodModel item) {
  final loc = item.listingLocation?.trim();
  if (loc != null && loc.isNotEmpty) {
    return loc.length > 40 ? '${loc.substring(0, 38)}…' : loc;
  }
  if (item.latitude != null && item.longitude != null) {
    return '${item.latitude!.toStringAsFixed(2)}°, ${item.longitude!.toStringAsFixed(2)}°';
  }
  return 'Location on request';
}

String _foodEtaLabel(FoodModel item, double? userLat, double? userLng) {
  double? d;
  int? deliveryMins;
  if (userLat != null &&
      userLng != null &&
      item.latitude != null &&
      item.longitude != null) {
    d = FoodService.distanceKm(
        userLat, userLng, item.latitude!, item.longitude!);
    if (d != null) {
      deliveryMins = (d * 2.8).round().clamp(1, 45);
    }
  }

  final prep = item.effectivePrepTimeMinutes;
  if (prep != null) {
    final total = prep + (deliveryMins ?? 0);
    return '~$total min';
  }

  // No item/restaurant prep — keep the old distance-based estimate.
  if (d != null) {
    final mins = (18 + d * 2.8).round().clamp(18, 55);
    return '~$mins min';
  }
  return '25–40 min';
}

Widget _foodMetaRow(IconData icon, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );

class _FoodImageTile extends StatefulWidget {
  const _FoodImageTile({
    required this.raw,
    this.height = 116,
    this.fit = BoxFit.cover,
  });
  final String raw;
  final double height;
  final BoxFit fit;

  @override
  State<_FoodImageTile> createState() => _FoodImageTileState();
}

class _FoodImageTileState extends State<_FoodImageTile> {
  String? _resolvedHttp;
  Uint8List? _bytes;
  bool _resolvingStorage = false;

  @override
  void initState() {
    super.initState();
    _kickStorageResolveIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _FoodImageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw) {
      _resolvedHttp = null;
      _bytes = null;
      _resolvingStorage = false;
      _kickStorageResolveIfNeeded();
    }
  }

  void _kickStorageResolveIfNeeded() {
    final raw = widget.raw.trim();
    if (raw.isEmpty) return;
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return;
    if (_foodImageLooksLikeBase64(raw)) {
      try {
        final part = raw.contains(',') ? raw.split(',').last : raw;
        _bytes = base64Decode(part.replaceAll(RegExp(r'\s'), ''));
      } catch (_) {}
      return;
    }
    _resolvingStorage = true;
    unawaited(_resolveStorage(raw, lower));
  }

  Future<void> _resolveStorage(String raw, String lower) async {
    try {
      final ref = lower.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(raw)
          : FirebaseStorage.instance.ref(raw);
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _resolvedHttp = url;
        _resolvingStorage = false;
      });
    } catch (_) {
      if (mounted) setState(() => _resolvingStorage = false);
    }
  }

  Widget _placeholder({bool loading = false}) => Container(
        height: widget.height,
        width: double.infinity,
        color: const Color(0xFFFFF4E8),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF8A00),
                ),
              )
            : Icon(Icons.restaurant_menu_rounded,
                size: 36, color: Colors.orange.shade200),
      );

  @override
  Widget build(BuildContext context) {
    final raw = widget.raw.trim();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (widget.height * dpr).round().clamp(96, 240);

    // HTTP URLs paint immediately — no setState delay.
    if (raw.toLowerCase().startsWith('http://') ||
        raw.toLowerCase().startsWith('https://')) {
      return ResilientCachedNetworkImage(
        url: raw,
        height: widget.height,
        width: double.infinity,
        fit: widget.fit,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
        showSpinner: false,
        placeholderColor: const Color(0xFFFFF4E8),
      );
    }

    final resolved = (_resolvedHttp ?? '').trim();
    if (resolved.isNotEmpty) {
      return ResilientCachedNetworkImage(
        url: resolved,
        height: widget.height,
        width: double.infinity,
        fit: widget.fit,
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
        height: widget.height,
        width: double.infinity,
        fit: widget.fit,
        cacheWidth: cachePx,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    if (_resolvingStorage) return _placeholder(loading: true);
    return _placeholder();
  }
}

// ── Food card ────────────────────────────────────────────────────────────────
class _FoodCard extends StatelessWidget {
  const _FoodCard({
    required this.item, required this.accent, required this.ink,
    required this.onTap, this.userLat, this.userLng,
  });

  final FoodModel item;
  final Color accent, ink;
  final VoidCallback onTap;
  final double? userLat, userLng;

  @override
  Widget build(BuildContext context) {
    String? distLabel;
    if (userLat != null && userLng != null &&
        item.latitude != null && item.longitude != null) {
      final d = FoodService.distanceKm(
          userLat!, userLng!, item.latitude!, item.longitude!);
      if (d != null) {
        distLabel = d < 1
            ? '${(d * 1000).round()} m'
            : '${d.toStringAsFixed(1)} km';
      }
    }
    final cat = ((item.category ?? 'Meals').trim().isEmpty)
        ? 'Meals' : item.category!.trim();

    var etaLine = _foodEtaLabel(item, userLat, userLng);
    if (distLabel != null) etaLine = '$etaLine · $distLabel';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _FoodImageTile(
                        raw: item.FoodImage.trim().isNotEmpty
                            ? item.FoodImage
                            : (item.gallery.isNotEmpty
                                ? item.gallery.first
                                : ''),
                        height: 112,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(item.FoodName, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 2),
                  Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text(
                    etaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'MWK ${item.price.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onTap,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shopping_cart_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Icon(
                Icons.favorite_border_rounded,
                size: 20,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.accent,
      required this.ink, required this.onSeeAll});

  final String title;
  final Color accent, ink;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
    child: Row(children: [
      Expanded(child: Text(title, style: TextStyle(fontSize: 18,
          fontWeight: FontWeight.w900, color: ink, letterSpacing: -0.3))),
      TextButton(
        onPressed: onSeeAll,
        child: Text('See All', style: TextStyle(fontWeight: FontWeight.w700,
            color: accent, fontSize: 13)),
      ),
    ]),
  );
}

// ── Camera button ─────────────────────────────────────────────────────────────
class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.onTap, required this.color});
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
          color: color.withOpacity(0.12), shape: BoxShape.circle),
      child: Icon(Icons.camera_alt_outlined, color: color, size: 18),
    ),
  );
}

// ── Filter button ─────────────────────────────────────────────────────────────
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onTap, required this.color});
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: color.withOpacity(0.40),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
    ),
  );
}
