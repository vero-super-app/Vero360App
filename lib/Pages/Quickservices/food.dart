// lib/Pages/Home/food_page.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/Pages/Home/food_details.dart';
import 'package:vero360_app/models/food_model.dart';
import 'package:vero360_app/services/food_service.dart';

class FoodPage extends StatefulWidget {
  const FoodPage({Key? key}) : super(key: key);

  @override
  _FoodPageState createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  final FoodService foodService = FoodService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Timer? _debounce;
  bool _loading = false;
  bool _photoMode = false;

  late Future<List<FoodModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- data ----------
  Future<List<FoodModel>> _loadAll() async {
    setState(() {
      _loading = true;
      _photoMode = false;
    });
    try {
      return await foodService.fetchFoodItems();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<FoodModel>> _searchByQuery(String raw) async {
    final q = raw.trim();
    if (q.length < 2) return _loadAll();
    setState(() {
      _loading = true;
      _photoMode = false;
    });
    try {
      return await foodService.searchFoodByNameOrRestaurant(q);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<FoodModel>> _searchByPhoto(File file) async {
    setState(() {
      _loading = true;
      _photoMode = true;
    });
    try {
      return await foodService.searchFoodByPhoto(file);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- search handlers ----------
  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _future = _searchByQuery(_searchCtrl.text));
    });
  }

  void _onSubmit(String value) {
    _debounce?.cancel();
    setState(() => _future = _searchByQuery(value));
  }

  Future<void> _showPhotoPickerSheet() async {
    if (kIsWeb) {
      // On web, we don’t have camera permissions by default; fall back to gallery and warn.
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (picked == null) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo search works best on mobile builds.')),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Use Camera'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? picked = await _picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 85,
                  maxWidth: 1280,
                );
                if (picked != null) {
                  final file = File(picked.path);
                  setState(() => _future = _searchByPhoto(file));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? picked = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                  maxWidth: 1280,
                );
                if (picked != null) {
                  final file = File(picked.path);
                  setState(() => _future = _searchByPhoto(file));
                }
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    _searchCtrl.clear();
    setState(() => _future = _loadAll());
    await _future;
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          "Restaurants & Food",
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Search bar with photo icon
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmit,
              decoration: InputDecoration(
                hintText: "Search by food or restaurant...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSubmit('');
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _showPhotoPickerSheet,
                      tooltip: 'Search by Photo',
                    ),
                  ],
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),

          if (_photoMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: const [
                  Icon(Icons.image_search, size: 16),
                  SizedBox(width: 6),
                  Text("Showing results similar to your photo"),
                ],
              ),
            ),

          // Results
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<FoodModel>>(
                future: _future,
                builder: (context, snapshot) {
                  if (_loading && snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final err = snapshot.error.toString();
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              const Text("Failed to fetch food", style: TextStyle(color: Colors.red)),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text(err, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  final items = snapshot.data ?? const <FoodModel>[];
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text("No food available", style: TextStyle(color: Colors.red))),
                      ],
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 700;
                        final crossAxisCount = isWide ? 3 : 2;
                        final childAspectRatio = isWide ? 0.72 : 0.70;

                        return GridView.builder(
                          itemCount: items.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            return _FoodCard(
                              item: item,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FoodDetailsPage(foodItem: item),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}



/* ---------- card widget (fixes pixel overflow) ---------- */

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.item, required this.onPressed});

  final FoodModel item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed, // tap whole card → details
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // image — use Expanded to avoid vertical overflow
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: (item.FoodImage.isEmpty)
                    ? Container(
                        color: Colors.grey[300],
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image),
                      )
                    : Image.network(
                        item.FoodImage,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[300],
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
              ),
            ),

            // title + subtitle + price
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.FoodName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.RestrauntName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "MWK ${item.price}",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green),
                  ),
                ],
              ),
            ),

            // CTA button – fixed height to avoid overflow
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: onPressed, // button → details too
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Order Food Now"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
