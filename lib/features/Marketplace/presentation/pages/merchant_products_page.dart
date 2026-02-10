import 'package:cloud_firestore/cloud_firestore.dart';
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
    Key? key,
    required this.merchantId,
    required this.merchantName,
  }) : super(key: key);

  @override
  State<MerchantProductsPage> createState() => _MerchantProductsPageState();
}

class _MerchantProductsPageState extends State<MerchantProductsPage> {
  final _firestore = FirebaseFirestore.instance;
  late Future<List<MarketplaceDetailModel>> _future;
  final CartService _cartService =
      CartService('unused', apiPrefix: ApiConfig.apiPrefix);

  @override
  void initState() {
    super.initState();
    _future = _loadMerchantItems();
  }

  Future<List<MarketplaceDetailModel>> _loadMerchantItems() async {
    try {
      // Same collection used elsewhere: 'marketplace_items'
      final snap = await _firestore
          .collection('marketplace_items')
          .where('merchantId', isEqualTo: widget.merchantId.trim())
          .orderBy('createdAt', descending: true)
          .get();

      final all = snap.docs
          .map((doc) => MarketplaceDetailModel.fromFirestore(doc))
          .where((item) => item.isActive)
          .toList();

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
        title: Text(widget.merchantName),
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

  const _MerchantProductCard({
    Key? key,
    required this.item,
    required this.onOpen,
  }) : super(key: key);

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
                child: _image(),
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