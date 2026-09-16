import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_model.dart';

/// Vertical filter on the marketplace hub.
enum MarketplaceHubVertical {
  all,
  products,
  food,
  stays,
}

/// Card kind in the mixed marketplace feed.
enum MarketplaceFeedKind {
  product,
  food,
  stay,
  shop,
}

/// One row/card in the marketplace hub (product, dish, stay, or shop hit).
class MarketplaceFeedItem {
  final MarketplaceFeedKind kind;
  final String id;
  final String title;
  final String image;
  final double price;
  final String subtitle;
  final DateTime? createdAt;
  final List<String> gallery;

  /// Local marketplace product model (typed in UI layer).
  final Object? product;
  final FoodModel? food;
  final Accommodation? stay;
  final String? merchantId;
  final String? merchantName;
  final String? sellerLogoUrl;
  final String? category;
  final bool isActive;
  final bool isOutOfStock;

  const MarketplaceFeedItem({
    required this.kind,
    required this.id,
    required this.title,
    this.image = '',
    this.price = 0,
    this.subtitle = '',
    this.createdAt,
    this.gallery = const [],
    this.product,
    this.food,
    this.stay,
    this.merchantId,
    this.merchantName,
    this.sellerLogoUrl,
    this.category,
    this.isActive = true,
    this.isOutOfStock = false,
  });

  factory MarketplaceFeedItem.fromFood(FoodModel f) {
    final id = (f.firestoreListingId ?? '').trim().isNotEmpty
        ? f.firestoreListingId!.trim()
        : (f.id != 0 ? '${f.id}' : f.FoodName);
    final img = f.FoodImage.trim().isNotEmpty
        ? f.FoodImage.trim()
        : (f.gallery.isNotEmpty ? f.gallery.first.trim() : '');
    return MarketplaceFeedItem(
      kind: MarketplaceFeedKind.food,
      id: id,
      title: f.FoodName,
      image: img,
      price: f.price,
      subtitle: f.RestrauntName.trim().isEmpty
          ? 'Food'
          : f.RestrauntName.trim(),
      gallery: f.gallery,
      food: f,
      merchantId: f.merchantId,
      merchantName:
          f.RestrauntName.trim().isEmpty ? null : f.RestrauntName.trim(),
      category: 'food',
    );
  }

  factory MarketplaceFeedItem.fromStay(Accommodation a) {
    final img = (a.image ?? '').trim().isNotEmpty
        ? a.image!.trim()
        : (a.gallery.isNotEmpty ? a.gallery.first.trim() : '');
    final type = a.accommodationType.trim();
    return MarketplaceFeedItem(
      kind: MarketplaceFeedKind.stay,
      id: '${a.id}',
      title: a.name,
      image: img,
      price: a.price.toDouble(),
      subtitle: [
        if (type.isNotEmpty) type,
        if (a.location.trim().isNotEmpty) a.location.trim(),
      ].join(' · '),
      gallery: a.gallery,
      stay: a,
      merchantId: a.hostMerchantUid,
      merchantName: a.owner?.name,
      category: 'stays',
    );
  }

  factory MarketplaceFeedItem.shop({
    required String merchantId,
    required String merchantName,
    String? logoUrl,
    String? location,
    int listingCount = 0,
  }) {
    final name = merchantName.trim().isEmpty ? 'Shop' : merchantName.trim();
    return MarketplaceFeedItem(
      kind: MarketplaceFeedKind.shop,
      id: merchantId,
      title: name,
      image: (logoUrl ?? '').trim(),
      price: 0,
      subtitle: listingCount > 0
          ? '$listingCount listing${listingCount == 1 ? '' : 's'}'
          : (location ?? 'Merchant shop'),
      merchantId: merchantId,
      merchantName: name,
      sellerLogoUrl: logoUrl,
      category: 'shop',
    );
  }
}

/// Snapshot returned by marketplace hub load/search.
class MarketplaceHubSnapshot {
  final List<MarketplaceFeedItem> items;
  final List<MarketplaceFeedItem> shops;

  const MarketplaceHubSnapshot({
    this.items = const [],
    this.shops = const [],
  });

  static const empty = MarketplaceHubSnapshot();
}
