import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_feed_item.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';

/// Loads food / stays and merges them into the marketplace hub feed.
class MarketplaceHubLoader {
  MarketplaceHubLoader._();

  static const int perVerticalCap = 24;

  static Future<List<MarketplaceFeedItem>> loadFood({
    String query = '',
    double? latitude,
    double? longitude,
  }) async {
    try {
      final svc = FoodService();
      final q = query.trim();
      final list = q.length >= 2
          ? await svc.searchFoodByNameOrRestaurant(
              q,
              latitude: latitude,
              longitude: longitude,
              attachPrep: false,
            )
          : await svc.fetchFoodItems(
              latitude: latitude,
              longitude: longitude,
              attachPrep: false,
            );
      return list
          .take(perVerticalCap)
          .map(MarketplaceFeedItem.fromFood)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<MarketplaceFeedItem>> loadStays({
    String query = '',
  }) async {
    try {
      final svc = AccommodationService();
      final q = query.trim();
      final list = q.length >= 2
          ? await svc.fetch(location: q)
          : await svc.fetch();
      // If location filter returned empty for a name-like query, fall back to name filter.
      if (list.isEmpty && q.length >= 2) {
        final all = await svc.fetch();
        final lower = q.toLowerCase();
        return all
            .where((a) {
              final hay =
                  '${a.name} ${a.location} ${a.accommodationType} ${a.description}'
                      .toLowerCase();
              return hay.contains(lower);
            })
            .take(perVerticalCap)
            .map(MarketplaceFeedItem.fromStay)
            .toList();
      }
      return list
          .take(perVerticalCap)
          .map(MarketplaceFeedItem.fromStay)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Load food + stays in parallel for the All hub.
  static Future<(List<MarketplaceFeedItem>, List<MarketplaceFeedItem>)>
      loadFoodAndStays({
    String query = '',
    double? latitude,
    double? longitude,
  }) async {
    final results = await Future.wait([
      loadFood(query: query, latitude: latitude, longitude: longitude),
      loadStays(query: query),
    ]);
    return (results[0], results[1]);
  }

  /// Mix verticals into one feed sorted by recency, with soft type-mixing so a
  /// 2-column grid does not look like "products left / food right".
  static List<MarketplaceFeedItem> mergeMixed(
    List<List<MarketplaceFeedItem>> sources, {
    int maxTotal = 120,
  }) {
    final pooled = <MarketplaceFeedItem>[];
    final seen = <String>{};
    for (final src in sources) {
      for (final item in src) {
        final key = '${item.kind.name}:${item.id}';
        if (seen.add(key)) pooled.add(item);
      }
    }

    pooled.sort((a, b) {
      final ta = a.createdAt;
      final tb = b.createdAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    // Soft de-band: avoid long same-kind runs (which become column stripes).
    final rest = List<MarketplaceFeedItem>.from(pooled);
    final out = <MarketplaceFeedItem>[];
    MarketplaceFeedKind? lastKind;
    while (rest.isNotEmpty && out.length < maxTotal) {
      var pick = 0;
      if (lastKind != null) {
        final alt = rest.indexWhere((e) => e.kind != lastKind);
        if (alt >= 0 && alt < 10) pick = alt;
      }
      final item = rest.removeAt(pick);
      out.add(item);
      lastKind = item.kind;
    }
    return out;
  }

  /// Build shop hits from product rows whose merchant name matches [query].
  static List<MarketplaceFeedItem> shopsFromProducts(
    Iterable<MarketplaceFeedItem> products,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];

    final byMerchant = <String, MarketplaceFeedItem>{};
    final counts = <String, int>{};

    for (final p in products) {
      if (p.kind != MarketplaceFeedKind.product) continue;
      final mid = (p.merchantId ?? '').trim();
      if (mid.isEmpty) continue;
      final name = (p.merchantName ?? '').trim();
      final hay = name.toLowerCase();
      if (hay.isEmpty || !hay.contains(q)) continue;
      counts[mid] = (counts[mid] ?? 0) + 1;
      byMerchant.putIfAbsent(
        mid,
        () => MarketplaceFeedItem.shop(
          merchantId: mid,
          merchantName: name,
          logoUrl: p.sellerLogoUrl,
          listingCount: 0,
        ),
      );
    }

    return byMerchant.entries.map((e) {
      final base = e.value;
      return MarketplaceFeedItem.shop(
        merchantId: base.merchantId!,
        merchantName: base.merchantName ?? base.title,
        logoUrl: base.sellerLogoUrl,
        listingCount: counts[e.key] ?? 0,
      );
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}
