import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';


class AccommodationMainPage extends StatefulWidget {
  const AccommodationMainPage({Key? key}) : super(key: key);

  @override
  State<AccommodationMainPage> createState() => _AccommodationMainPageState();
}

class _AccommodationMainPageState extends State<AccommodationMainPage> {
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
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF7F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF020617) : Colors.white,
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          'Discover stays',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchAndLocationBar(context),
            const SizedBox(height: 12),
            _buildTypeChipsRow(context),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
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
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _buildErrorState(
                        context,
                        snapshot.error.toString(),
                      );
                    }
                    final raw = snapshot.data ?? [];
                    final data = _applySearchFilter(raw);

                    if (data.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemBuilder: (context, index) {
                        final item = data[index];
                        return _AccommodationCard(accommodation: item);
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

  Widget _buildSearchAndLocationBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Search
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  offset: const Offset(0, 6),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by name',
                      border: InputBorder.none,
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _searchController.clear();
                    },
                    icon: const Icon(Icons.close, color: Colors.grey),
                    tooltip: 'Clear search',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Location – modern free-text bar (district / area)
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        offset: const Offset(0, 4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    controller: _locationController,
                    decoration: InputDecoration(
                      hintText: 'Search by district or area',
                      border: InputBorder.none,
                      prefixIcon: const Icon(
                        Icons.location_on_outlined,
                        color: Color(0xFFFB923C),
                      ),
                      suffixIcon: _locationQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _locationController.clear();
                              },
                              icon: const Icon(Icons.close, color: Colors.grey),
                              tooltip: 'Clear location',
                            )
                          : null,
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  onPressed: () {
                    // reserved for advanced filters bottom sheet
                  },
                  icon: const Icon(Icons.tune, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChipsRow(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _types[index];
          final isSelected = type == _selectedType;
          return ChoiceChip(
            label: Text(
              type[0].toUpperCase() + type.substring(1),
            ),
            selected: isSelected,
            onSelected: (_) => _onTypeSelected(type),
            selectedColor: const Color(0xFFFF8A00),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFFF8A00)
                    : theme.dividerColor.withOpacity(0.4),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loadFromService();
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hotel_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No accommodations found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try changing type or location, or clear your search.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
  final Accommodation accommodation;

  const _AccommodationCard({Key? key, required this.accommodation}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final name = accommodation.name ?? '';
    final location = accommodation.location ?? '';
    final type = (accommodation.accommodationType ?? '').toLowerCase();

    final owner = accommodation.owner;
    final rating = (owner?.averageRating ?? 0).toDouble();
    final reviewCount = owner?.reviewCount ?? 0;
    final price = accommodation.price.toDouble();

    final imgBytes = accommodation.imageBytes;
    final rawImage = (accommodation.image ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            offset: const Offset(0, 8),
            blurRadius: 18,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imgBytes != null)
                  Ink.image(
                    image: MemoryImage(imgBytes),
                    fit: BoxFit.cover,
                    child: InkWell(
                      onTap: () {
                        // navigate to details page if you have one
                      },
                    ),
                  )
                else if (rawImage.isNotEmpty)
                  accImageFromAnySource(
                    rawImage,
                    fit: BoxFit.cover,
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE5ECFF), Color(0xFFFDF2E9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.photo_size_select_actual_outlined,
                        size: 40,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8A00),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '#${price.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '/night',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8CC),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _capitalize(type),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFF8A00),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        // book / details
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      child: const Text('View details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}