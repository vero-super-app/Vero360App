// lib/Pages/Home/food_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

class FoodPage extends StatefulWidget {
  const FoodPage({super.key});

  @override
  _FoodPageState createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  // ── Brand palette ─────────────────────────────────────────────────────────
  static const Color _primaryRed   = Color(0xFFC62828);
  static const Color _ink          = Color(0xFF1A1109);
  static const Color _pageBg       = Color(0xFFF8F8F8);
  static const Color _cardBg       = Colors.white;
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

  static const List<String> _kCategoryChips = [
    'All', 'Meals', 'Pizza', 'Burger', 'Drinks', 'Asian',
  ];

  String _navEmail = '';
  bool _isMerchant = false;

  late Future<List<FoodModel>> _future;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNavPrefs();
      if (!kIsWeb) _initLocation();
    });
  }

  Future<void> _loadNavPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final role =
        (p.getString('user_role') ?? p.getString('role') ?? '').toLowerCase();
    setState(() {
      _navEmail = p.getString('email') ?? '';
      _isMerchant = role == 'merchant';
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
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
      return _sortByDistanceIfPossible(items);
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
      return _sortByDistanceIfPossible(items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<FoodModel>> _searchByPhoto(File file) async {
    setState(() { _loading = true; _photoMode = true; });
    try {
      final items = await foodService.searchFoodByPhoto(file);
      return _sortByDistanceIfPossible(items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _initLocation() async {
    if (kIsWeb) return;
    setState(() => _locationLoading = true);
    try {
      final pos = await _locationService.getCurrentLocation();
      if (!mounted) return;
      if (pos == null) {
        setState(() { _locationLoading = false; _locationLabel = null; });
        return;
      }
      String? label;
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final pl = marks.first;
          final parts = <String>[
            if ((pl.locality ?? '').trim().isNotEmpty) pl.locality!.trim(),
            if ((pl.subAdministrativeArea ?? '').trim().isNotEmpty)
              pl.subAdministrativeArea!.trim(),
          ];
          label = parts.isNotEmpty
              ? parts.join(', ')
              : (pl.country ?? '').trim().isNotEmpty ? pl.country : null;
        }
      } catch (_) {}
      setState(() {
        _userPosition   = pos;
        _locationLabel  = label;
        _locationLoading = false;
      });
      if (!mounted) return;
      setState(() => _future = _loadAll());
    } catch (_) {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  // ── Search handlers ────────────────────────────────────────────────────────
  void _onSearchChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _future = _searchByQuery(_searchCtrl.text));
    });
  }

  void _onSubmit(String value) {
    _debounce?.cancel();
    setState(() => _future = _searchByQuery(value));
  }

  Future<void> _pickAndSearchPhoto(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1280);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _future = _searchByPhoto(File(picked.path)));
  }

  Future<void> _showPhotoPickerSheet() async {
    if (kIsWeb) {
      final XFile? picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1280);
      if (picked == null || !mounted) return;
      setState(() => _future = _searchByPhoto(File(picked.path)));
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
              color: _primaryRed,
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
    setState(() => _future = _loadAll());
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
                activeColor: _primaryRed,
                onChanged: (v) => setModal(() => radius = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() { _radiusKm = radius; _future = _loadAll(); });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryRed, foregroundColor: Colors.white,
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
            child: CircularProgressIndicator(strokeWidth: 2, color: _primaryRed),
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
            color: _primaryRed.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _primaryRed.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.my_location_rounded, color: _primaryRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.isNotEmpty
                      ? 'Near $label · prioritising nearby food'
                      : 'Using GPS · prioritising food near you',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: _primaryRed.withOpacity(0.9)),
                ),
              ),
              GestureDetector(
                onTap: _initLocation,
                child: Icon(Icons.refresh_rounded,
                    color: _primaryRed.withOpacity(0.7), size: 18),
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
                      color: _primaryRed, fontSize: 12)),
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
        _FilterButton(onTap: _showDiscoverySheet, color: _primaryRed),
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
        cursorColor: _primaryRed,
        decoration: InputDecoration(
          hintText: 'Search food or restaurant…',
          hintStyle: TextStyle(color: Colors.grey.shade400,
              fontWeight: FontWeight.w400, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded,
              color: Color(0xFFC62828), size: 22),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (hasText)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: Colors.grey.shade500, size: 18),
                  onPressed: () { _searchCtrl.clear(); _onSubmit(''); },
                ),
              _CameraButton(onTap: _showPhotoPickerSheet, color: _primaryRed),
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
              borderSide: const BorderSide(color: _primaryRed, width: 1.5)),
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
        itemCount: _kCategoryChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final label = _kCategoryChips[i];
          final sel = _categoryFilter == label;
          return GestureDetector(
            onTap: () => setState(() => _categoryFilter = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? _primaryRed : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: sel ? _primaryRed : _divider),
                boxShadow: sel
                    ? [BoxShadow(color: _primaryRed.withOpacity(0.30),
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
      // ── App bar ──────────────────────────────────────────────────────────
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _pageBg,
        foregroundColor: _ink,
        centerTitle: false,
        titleSpacing: 20,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        title: Row(
          children: [
            // Avatar
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                    blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                child: Icon(Icons.person_rounded,
                    color: Color(0xFFC62828), size: 22),
              ),
            ),
            const Spacer(),
            // Notification bell
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                    blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: IconButton(
                icon: Icon(Icons.notifications_none_rounded,
                    color: Colors.grey.shade800, size: 22),
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),

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

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 26,
                        fontWeight: FontWeight.w900, color: _ink, height: 1.2),
                    children: const [
                      TextSpan(text: 'Choose Your\n'),
                      TextSpan(text: 'Favorite '),
                      TextSpan(text: 'Food',
                          style: TextStyle(color: _primaryRed)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                  color: _primaryRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _primaryRed.withOpacity(0.22)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.image_search_rounded,
                        size: 18, color: _primaryRed),
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
              color: _primaryRed,
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
                    return _buildError(snapshot.error.toString());
                  }
                  final items = snapshot.data ?? const <FoodModel>[];
                  if (items.isEmpty) return _buildEmpty();

                  final filtered = items.where(_matchesCategoryChip).toList();
                  if (filtered.isEmpty) return _buildEmptyCategory();

                  final p = _userPosition;
                  final popular = filtered.take(12).toList();
                  final nearest = p != null
                      ? FoodService.sortByDistanceToUser(
                          List<FoodModel>.from(filtered),
                          p.latitude, p.longitude).take(12).toList()
                      : popular;

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 28),
                    children: [
                      _SectionHeader(title: 'Popular Food', accent: _primaryRed,
                          ink: _ink, onSeeAll: () {}),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 276,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: popular.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (_, i) => _FoodCard(
                            item: popular[i],
                            userLat: p?.latitude, userLng: p?.longitude,
                            accent: _primaryRed, ink: _ink,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) =>
                                    FoodDetailsPage(foodItem: popular[i]))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionHeader(title: 'Nearest', accent: _primaryRed,
                          ink: _ink, onSeeAll: () {}),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 276,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: nearest.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (_, i) => _FoodCard(
                            item: nearest[i],
                            userLat: p?.latitude, userLng: p?.longitude,
                            accent: _primaryRed, ink: _ink,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) =>
                                    FoodDetailsPage(foodItem: nearest[i]))),
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
              backgroundColor: _primaryRed,
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
  if (userLat != null &&
      userLng != null &&
      item.latitude != null &&
      item.longitude != null) {
    final d = FoodService.distanceKm(
        userLat, userLng, item.latitude!, item.longitude!);
    if (d != null) {
      final mins = (18 + d * 2.8).round().clamp(18, 55);
      return '~$mins min';
    }
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

class _FoodImageTile extends StatelessWidget {
  const _FoodImageTile({required this.raw, this.height = 116});
  final String raw;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      height: height, width: double.infinity,
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_menu_rounded,
          size: 36, color: Colors.grey.shade300),
    );

    if (raw.isEmpty) return placeholder();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Image.network(raw, height: height, width: double.infinity,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
    }
    if (_foodImageLooksLikeBase64(raw)) {
      try {
        final part = raw.contains(',') ? raw.split(',').last : raw;
        final bytes = base64Decode(part.replaceAll(RegExp(r'\s'), ''));
        return Image.memory(bytes, height: height, width: double.infinity,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
      } catch (_) {}
    }
    return placeholder();
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
        width: 172,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07),
                blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Stack(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                child: _FoodImageTile(raw: item.FoodImage, height: 116),
              ),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10),
                          blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Icon(Icons.favorite_border_rounded,
                      size: 16, color: Colors.grey.shade400),
                ),
              ),
            ]),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.FoodName, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 2),
                    Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    _foodMetaRow(
                        Icons.place_outlined, _foodListingLocationLine(item)),
                    const SizedBox(height: 3),
                    _foodMetaRow(Icons.schedule_rounded, etaLine),
                    const SizedBox(height: 3),
                    _foodMetaRow(
                      Icons.storefront_outlined,
                      item.RestrauntName.trim().isEmpty
                          ? 'Kitchen'
                          : item.RestrauntName,
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text('MWK ${item.price.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w900, color: accent)),
                        ),
                        GestureDetector(
                          onTap: onTap,
                          child: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.add_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
        color: color, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withOpacity(0.40),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
    ),
  );
}
