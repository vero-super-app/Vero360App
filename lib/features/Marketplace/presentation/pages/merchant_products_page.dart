import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_detail_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as marketplaceModel;
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';

class MerchantProductsPage extends StatefulWidget {
  final String merchantId;
  final String merchantName;

  const MerchantProductsPage({
    super.key,
    required this.merchantId,
    required this.merchantName,
  });

  @override
  State<MerchantProductsPage> createState() => _MerchantProductsPageState();
}

class _MerchantProductsPageState extends State<MerchantProductsPage> {
  final _firestore = FirebaseFirestore.instance;
  late Future<List<MarketplaceDetailModel>> _future;
  final CartService _cartService =
      CartService('unused', apiPrefix: ApiConfig.apiPrefix);

  // Brand color to match main marketplace UI
  static const Color _brandOrange = Color(0xFFFF8A00);

  // Small cache for Firebase download URLs (gs:// or storage paths)
  final Map<String, Future<String>> _dlUrlCache = {};

  bool _isHttp(String s) => s.startsWith('http://') || s.startsWith('https://');
  bool _isGs(String s) => s.startsWith('gs://');

  Future<String?> _toFirebaseDownloadUrl(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (_isHttp(s)) return s;

    if (_dlUrlCache.containsKey(s)) return _dlUrlCache[s]!.then((v) => v);

    Future<String> fut() async {
      if (_isGs(s)) {
        return FirebaseStorage.instance.refFromURL(s).getDownloadURL();
      }
      return FirebaseStorage.instance.ref(s).getDownloadURL();
    }

    _dlUrlCache[s] = fut();
    try {
      return await _dlUrlCache[s]!;
    } catch (_) {
      return null;
    }
  }

  /// Match main marketplace image handling: base64 bytes, http(s), gs://, and storage paths.
  Widget buildItemImage(MarketplaceDetailModel item) {
    if (item.imageBytes != null) {
      return Image.memory(
        item.imageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    final raw = item.image.trim();
    if (raw.isEmpty) {
      return Container(
        color: const Color(0xFFEDEDED),
        child: const Center(
          child: Icon(
            Icons.image_not_supported_rounded,
            color: Colors.black38,
          ),
        ),
      );
    }

    // Direct http(s) URL
    if (_isHttp(raw)) {
      return Image.network(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFEDEDED),
          child: const Center(
            child: Icon(
              Icons.image_not_supported_rounded,
              color: Colors.black38,
            ),
          ),
        ),
      );
    }

    // Firebase gs:// or storage path
    return FutureBuilder<String?>(
      future: _toFirebaseDownloadUrl(raw),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Container(
            color: const Color(0xFFEDEDED),
            child: const Center(
              child: Icon(
                Icons.image_not_supported_rounded,
                color: Colors.black38,
              ),
            ),
          );
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFEDEDED),
            child: const Center(
              child: Icon(
                Icons.image_not_supported_rounded,
                color: Colors.black38,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _loadMerchantItems();
  }

  Future<List<MarketplaceDetailModel>> _loadMerchantItems() async {
    try {
      // Same collection used elsewhere: 'marketplace_items'
      final String id = widget.merchantId.trim();
      final String name = widget.merchantName.trim();

      // 1) Try match by merchantId (new items) – no orderBy here to avoid composite index requirement
      final idSnap = await _firestore
          .collection('marketplace_items')
          .where('merchantId', isEqualTo: id)
          .get();

      var docs = idSnap.docs;

      // 2) Fallback: some older items may only have merchantName or numeric merchantId
      if (docs.isEmpty && name.isNotEmpty) {
        final nameSnap = await _firestore
            .collection('marketplace_items')
            .where('merchantName', isEqualTo: name)
            .get();
        docs = nameSnap.docs;
      }

      final all = docs
          .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
          .where((item) => item.isActive)
          .toList();

      // Sort in-memory by createdAt desc so newest items appear first
      all.sort((a, b) {
        final da = a.createdAt;
        final db = b.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      return all;
    } catch (e) {
      debugPrint('Error loading merchant items: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        title: Text('${widget.merchantName} Store'),
      ),
      body: FutureBuilder<List<MarketplaceDetailModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load products\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final items = snapshot.data ?? const <MarketplaceDetailModel>[];
          if (items.isEmpty) {
            return const Center(
              child: Text('No products from this merchant yet.'),
            );
          }

          final width = MediaQuery.of(context).size.width;
          final cols = width >= 1200
              ? 4
              : width >= 800
                  ? 3
                  : 2;
          final ratio = width >= 1200
              ? 0.95
              : width >= 800
                  ? 0.85
                  : 0.72;

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: ratio,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final it = items[index];
              return _MerchantProductCard(
                item: it,
                imageBuilder: (item) => buildItemImage(item),
                onOpen: () {
                  // If the Firestore item has a valid backend/sql id, open the full details page.
                  if (!it.hasValidSqlItemId) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailsPage(
                        item: marketplaceModel.MarketplaceDetailModel(
                          id: it.sqlItemId!,
                          name: it.name,
                          image: it.image,
                          price: it.price,
                          description: it.description ?? '',
                          location: it.location ?? '',
                          comment: null,
                          category: it.category,
                          gallery: const [],
                          videos: const [],
                          sellerBusinessName: null,
                          sellerOpeningHours: null,
                          sellerStatus: null,
                          sellerBusinessDescription: null,
                          sellerRating: null,
                          sellerLogoUrl: null,
                          serviceProviderId: null,
                          sellerUserId: null,
                          merchantId: widget.merchantId,
                          merchantName: widget.merchantName,
                          serviceType: 'marketplace',
                        ),
                        cartService: _cartService,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MerchantProductCard extends StatelessWidget {
  final MarketplaceDetailModel item;
  final VoidCallback onOpen;
  final Widget Function(MarketplaceDetailModel) imageBuilder;

  const _MerchantProductCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 0.6,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: imageBuilder(item),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MWK ${item.price.toStringAsFixed(0)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image() {
    final raw = item.image.trim();
    if (raw.isEmpty) {
      return Container(
        color: const Color(0xFFEDEDED),
        child: const Center(
          child: Icon(
                                             Icons.image_not_supported_rounded,
            color: Colors.black38,
          ),
        ),
      );
    }

    return Image.network(
      raw,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFEDEDED),
        child: const Center(
          child: Icon(
            Icons.image_not_supported_rounded,
            color: Colors.black38,
          ),
        ),
      ),
    );
  }
}