import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';


class AccommodationMainPage extends StatefulWidget {
  const AccommodationMainPage({super.key});

  @override
  State<AccommodationMainPage> createState() => _AccommodationMainPageState();
}

class _AccommodationMainPageState extends State<AccommodationMainPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _pageBg = Color(0xFFF4F6FA);
  static const Color _surfaceBorder = Color(0xFFE2E6EF);

  final AccommodationService _service = AccommodationService();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  /// Debounce: only fetch after user stops typing (avoids API call on every keystroke).
  int _locationDebounceStamp = 0;

  final List<String> _types = const [
    'all',
    'hostel',
    'hotel',
    'lodge',
    'apartments',
    'bnb',
  ];

  String _selectedType = 'all';
  String _searchQuery = '';
  String _locationQuery = '';

  static const List<String> _malawiDistricts = [
    // Northern
    'Chitipa',
    'Karonga',
    'Likoma',
    'Mzimba',
    'Nkhata Bay',
    'Nkhotakota',
    // Central
    'Dedza',
    'Dowa',
    'Kasungu',
    'Lilongwe City',
    'Lilongwe Rural',
    'Mchinji',
    'Ntcheu',
    'Ntchisi',
    // Southern
    'Balaka',
    'Blantyre City',
    'Blantyre Rural',
    'Chikwawa',
    'Chiradzulu',
    'Machinga',
    'Mangochi',
    'Mulanje',
    'Mwanza',
    'Neno',
    'Nsanje',
    'Phalombe',
  ];

  Future<List<Accommodation>>? _future;

  @override
  void initState() {
    super.initState();
    _loadFromService();
    _searchController.addListener(_onSearchChanged);
    _locationController.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  void _onLocationChanged() {
    _locationQuery = _locationController.text.trim();
    setState(() {}); // Update search filter immediately
    // Debounce API call: wait 500ms after last keystroke before fetching
    final stamp = ++_locationDebounceStamp;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || stamp != _locationDebounceStamp) return;
      _loadFromService();
      setState(() {});
    });
  }

  void _onTypeSelected(String type) {
    setState(() {
      _selectedType = type;
      _loadFromService();
    });
  }

  void _loadFromService() {
    _future = _service.fetch(
      type: _selectedType,
      location: _locationQuery.isEmpty ? null : _locationQuery,
    );
  }

  void _showDistrictPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _brandOrange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.map_rounded,
                        color: _brandOrange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Pick a district',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _brandNavy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Malawi districts — tap to fill location',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: _malawiDistricts.length,
                itemBuilder: (context, i) {
                  final d = _malawiDistricts[i];
                  return ListTile(
                    leading: Icon(Icons.place_outlined,
                        color: Colors.grey.shade600, size: 22),
                    title: Text(
                      d,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      _locationController.text = d;
                      Navigator.pop(ctx);
                      setState(() {
                        _loadFromService();
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Accommodation> _applySearchFilter(List<Accommodation> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((a) {
      final name = (a.name ?? '').toLowerCase();
      final loc = (a.location ?? '').toLowerCase();
      return name.contains(q) || loc.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : _pageBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.hotel_rounded, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Discover stays',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchAndLocationBar(context, isDark),
            const SizedBox(height: 10),
            _buildTypeChipsRow(context, isDark),
            const SizedBox(height: 6),
            Expanded(
              child: RefreshIndicator(
                color: _brandOrange,
                onRefresh: () async {
                  setState(() {
                    _loadFromService();
                  });
                  await _future;
                },
                child: FutureBuilder<List<Accommodation>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: _brandOrange,
                              strokeWidth: 2.5,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Loading stays…',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return _buildErrorState(
                        context,
                        snapshot.error.toString(),
                        isDark,
                      );
                    }
                    final raw = snapshot.data ?? [];
                    final data = _applySearchFilter(raw);

                    if (data.isEmpty) {
                      return _buildEmptyState(context, isDark);
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemBuilder: (context, index) {
                        final item = data[index];
                        return _AccommodationCard(
                          accommodation: item,
                          isDark: isDark,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: data.length,
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

  Widget _buildSearchAndLocationBar(BuildContext context, bool isDark) {
    final card = isDark ? const Color(0xFF1E293B) : Colors.white;
    final hint = isDark ? Colors.white54 : Colors.grey.shade500;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find your stay',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white12 : _surfaceBorder,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1D26),
              ),
              cursorColor: _brandOrange,
              decoration: InputDecoration(
                hintText: 'Search by property name…',
                hintStyle: TextStyle(color: hint, fontWeight: FontWeight.w500),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _brandOrange, size: 26),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: Icon(Icons.close_rounded,
                            color: Colors.grey.shade600),
                        tooltip: 'Clear',
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Location',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white12 : _surfaceBorder,
                    ),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: TextField(
                    controller: _locationController,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1D26),
                    ),
                    cursorColor: _brandOrange,
                    decoration: InputDecoration(
                      hintText: 'District or area',
                      hintStyle:
                          TextStyle(color: hint, fontWeight: FontWeight.w500),
                      prefixIcon: const Icon(
                        Icons.location_on_rounded,
                        color: _brandOrange,
                        size: 22,
                      ),
                      suffixIcon: _locationQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () => _locationController.clear(),
                              icon: Icon(Icons.close_rounded,
                                  color: Colors.grey.shade600),
                              tooltip: 'Clear location',
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 14),
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: _brandOrange,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _showDistrictPicker,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.map_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChipsRow(BuildContext context, bool isDark) {
    final card = isDark ? const Color(0xFF1E293B) : Colors.white;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _types[index];
          final isSelected = type == _selectedType;
          final label = type == 'all'
              ? 'All'
              : type[0].toUpperCase() + type.substring(1);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _onTypeSelected(type),
            child: Chip(
              label: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              backgroundColor: isSelected
                  ? _brandOrange
                  : (isDark ? card : Colors.grey.shade300),
              side: BorderSide(
                color: isSelected
                    ? _brandOrange
                    : (isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message, bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(Icons.error_outline_rounded,
            size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Could not load stays',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                _loadFromService();
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(Icons.hotel_outlined, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No stays found',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Try another type, location, or clear your search.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Shared image helpers (Firebase / http / base64) ----------

final Map<String, Future<String>> _accDlUrlCache = {};

bool _accIsHttp(String s) => s.startsWith('http://') || s.startsWith('https://');
bool _accIsGs(String s) => s.startsWith('gs://');

bool _accLooksLikeBase64(String s) {
  final x = s.contains(',') ? s.split(',').last.trim() : s.trim();
  if (x.length < 150) return false;
  return RegExp(r'^[A-Za-z0-9+/=\\s]+$').hasMatch(x);
}

Future<String?> _accToFirebaseDownloadUrl(String raw) async {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (_accIsHttp(s)) return s;

  if (_accDlUrlCache.containsKey(s)) return _accDlUrlCache[s]!.then((v) => v);

  Future<String> fut() async {
    if (_accIsGs(s)) {
      return FirebaseStorage.instance.refFromURL(s).getDownloadURL();
    }
    return FirebaseStorage.instance.ref(s).getDownloadURL();
  }

  _accDlUrlCache[s] = fut();
  try {
    return await _accDlUrlCache[s]!;
  } catch (_) {
    return null;
  }
}

Widget accImageFromAnySource(
  String raw, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  BorderRadius? radius,
}) {
  final s = raw.trim();

  Widget wrap(Widget child) {
    if (radius == null) return child;
    return ClipRRect(borderRadius: radius, child: child);
  }

  if (s.isEmpty) {
    return wrap(Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_rounded),
    ));
  }

  // base64 (fallback if not already decoded in model)
  if (_accLooksLikeBase64(s)) {
    try {
      final base64Part = s.contains(',') ? s.split(',').last : s;
      final bytes = base64Decode(base64Part);
      return wrap(Image.memory(bytes, fit: fit, width: width, height: height));
    } catch (_) {}
  }

  // http(s)
  if (_accIsHttp(s)) {
    return wrap(Image.network(
      s,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_rounded),
      ),
      loadingBuilder: (c, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade100,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
    ));
  }

  // firebase gs:// or storage path
  return FutureBuilder<String?>(
    future: _accToFirebaseDownloadUrl(s),
    builder: (context, snap) {
      final url = snap.data;
      if (url == null || url.isEmpty) {
        return wrap(Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        ));
      }
      return wrap(Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_rounded),
        ),
      ));
    },
  );
}

// ====== Card widget using your Accommodation model ======

class _AccommodationCard extends StatelessWidget {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _surfaceBorder = Color(0xFFE2E6EF);

  final Accommodation accommodation;
  final bool isDark;

  const _AccommodationCard({
    required this.accommodation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final name = accommodation.name ?? '';
    final location = accommodation.location ?? '';
    final type = (accommodation.accommodationType ?? '').toLowerCase();

    final owner = accommodation.owner;
    final rating = (owner?.averageRating ?? 0).toDouble();
    final reviewCount = owner?.reviewCount ?? 0;
    final price = accommodation.price.toDouble();

    final imgBytes = accommodation.imageBytes;
    final rawImage = (accommodation.image ?? '').trim();

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Material(
      color: cardBg,
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : _surfaceBorder,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imgBytes != null)
                    Image.memory(imgBytes, fit: BoxFit.cover)
                  else if (rawImage.isNotEmpty)
                    accImageFromAnySource(
                      rawImage,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _brandNavy.withValues(alpha: 0.12),
                            _brandOrange.withValues(alpha: 0.15),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        Icons.photo_size_select_actual_outlined,
                        size: 44,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (reviewCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '($reviewCount)',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _brandOrange,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: _brandOrange.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(
                            'MWK ${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '/ night',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : _brandNavy,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location.isEmpty ? '—' : location,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _brandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _capitalize(type),
                          style: const TextStyle(
                            color: _brandOrange,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          // book / details
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'View details',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
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

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}