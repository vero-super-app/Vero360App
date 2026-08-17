import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vero360_app/app_nav_key.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart'
    as core;
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_share_link.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/Marketplace_detailsPage.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';

/// Opens a shared marketplace product or merchant shop from https / vero360:// links.
class MarketplaceShareNavigation {
  static int _stablePositiveIdFromString(String s) {
    var hash = 0;
    for (final code in s.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    if (hash == 0) hash = 1;
    return hash;
  }

  static Future<void> openFromUri(Uri uri, CartService cartService) async {
    final productId = marketplaceProductIdFromShareUri(uri);
    if (productId != null && productId.isNotEmpty) {
      await _openProduct(productId, uri, cartService);
      return;
    }
    final shopId = marketplaceShopIdFromShareUri(uri);
    if (shopId != null && shopId.isNotEmpty) {
      _openShop(shopId, uri);
    }
  }

  static Future<void> _openProduct(
    String id,
    Uri uri,
    CartService cartService,
  ) async {
    final nav = appNavKey.currentState;
    if (nav == null) return;

    final sqlId = int.tryParse(id);
    if (sqlId != null && sqlId > 0) {
      try {
        final item = await MarketplaceService().getItemDetails(sqlId);
        if (item != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => DetailsPage(item: item, cartService: cartService),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .doc(id)
          .get();
      if (doc.exists) {
        final item = _coreModelFromFirestore(doc);
        if (item != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => DetailsPage(item: item, cartService: cartService),
            ),
          );
          return;
        }
      }
    } catch (_) {}

    final q = marketplaceSearchQueryFromShareUri(uri);
    nav.push(
      MaterialPageRoute(
        builder: (_) => MerchantProductsPage(
          merchantId: q ?? id,
          merchantName: uri.queryParameters['merchant'] ??
              uri.queryParameters['name'] ??
              'Merchant',
        ),
      ),
    );
  }

  static core.MarketplaceDetailModel? _coreModelFromFirestore(
    DocumentSnapshot doc,
  ) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;

    double price = 0;
    final p = data['price'];
    if (p is num) {
      price = p.toDouble();
    } else if (p != null) {
      price = double.tryParse(p.toString()) ?? 0;
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().replaceAll(RegExp(r'[^\d]'), ''));
    }

    List<String> gallery = [];
    final g = data['gallery'];
    if (g is List) {
      gallery = g
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final rawSql = data['sqlItemId'] ?? data['backendId'] ?? data['itemId'];
    final sqlId = parseInt(rawSql);
    final cartId = (sqlId != null && sqlId > 0)
        ? sqlId
        : _stablePositiveIdFromString(doc.id);

    return core.MarketplaceDetailModel(
      id: cartId,
      firestoreDocId: doc.id,
      name: (data['name'] ?? '').toString(),
      image: (data['image'] ?? data['imageUrl'] ?? '').toString(),
      price: price,
      description: (data['description'] ?? '').toString(),
      location: (data['location'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      gallery: gallery,
      merchantId: data['merchantId']?.toString(),
      merchantName: data['merchantName']?.toString(),
      sellerUserId: (data['sellerUserId'] ?? data['ownerId'])?.toString(),
      serviceProviderId: data['serviceProviderId']?.toString(),
      sellerBusinessName: data['sellerBusinessName']?.toString(),
      stockQuantity: parseInt(data['stockQuantity'] ?? data['quantity']),
    );
  }

  static void _openShop(String merchantId, Uri uri) {
    final nav = appNavKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => MerchantProductsPage(
          merchantId: merchantId,
          merchantName: uri.queryParameters['name'] ??
              uri.queryParameters['merchant'] ??
              'Merchant',
        ),
      ),
    );
  }
}
