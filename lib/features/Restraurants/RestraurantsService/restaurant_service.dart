import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/features/Restraurants/Models/restaurant_model.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';

class RestaurantService {
  RestaurantService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Active restaurants near [lat]/[lng], nearest first.
  /// Docs without coordinates are appended after in-radius results.
  Future<List<RestaurantModel>> fetchRestaurants({
    double? lat,
    double? lng,
    double radiusKm = 15,
  }) async {
    final snap = await _db
        .collection('restaurants')
        .where('isActive', isEqualTo: true)
        .limit(80)
        .get();

    final all = snap.docs
        .map(RestaurantModel.fromFirestore)
        .where((r) => r.businessName.trim().isNotEmpty)
        .toList();

    if (lat == null || lng == null || all.isEmpty) return all;

    final r = radiusKm.clamp(1.0, 200.0);
    final inRadius = <RestaurantModel>[];
    final noCoords = <RestaurantModel>[];
    final outRadius = <RestaurantModel>[];

    for (final rest in all) {
      if (rest.latitude == null || rest.longitude == null) {
        noCoords.add(rest);
        continue;
      }
      final d = FoodService.distanceKm(
        lat,
        lng,
        rest.latitude!,
        rest.longitude!,
      );
      final cap = rest.deliveryRadiusKm > 0
          ? rest.deliveryRadiusKm.clamp(1.0, r)
          : r;
      if (d != null && d <= cap) {
        inRadius.add(rest);
      } else {
        outRadius.add(rest);
      }
    }

    int byDistance(RestaurantModel a, RestaurantModel b) {
      final da = FoodService.distanceKm(
            lat,
            lng,
            a.latitude!,
            a.longitude!,
          ) ??
          double.infinity;
      final db = FoodService.distanceKm(
            lat,
            lng,
            b.latitude!,
            b.longitude!,
          ) ??
          double.infinity;
      return da.compareTo(db);
    }

    inRadius.sort(byDistance);
    outRadius.sort(byDistance);
    if (inRadius.isNotEmpty) return [...inRadius, ...noCoords];
    return [...outRadius, ...noCoords];
  }

  Future<RestaurantModel?> fetchRestaurantById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final doc = await _db.collection('restaurants').doc(trimmed).get();
    if (!doc.exists) return null;
    return RestaurantModel.fromFirestore(doc);
  }

  Future<RestaurantModel?> fetchRestaurantByOwnerUid(String ownerUid) async {
    final uid = ownerUid.trim();
    if (uid.isEmpty) return null;
    final snap = await _db
        .collection('restaurants')
        .where('ownerUid', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return RestaurantModel.fromFirestore(snap.docs.first);
  }

  /// Menu rows for [restaurantId]. Legacy docs without that field are loaded
  /// via the restaurant's [RestaurantModel.ownerUid] as `merchantId`.
  Future<List<FoodModel>> fetchMenuForRestaurant(String restaurantId) async {
    final rid = restaurantId.trim();
    if (rid.isEmpty) return const [];

    final byRestaurant = await _db
        .collection('food_menu_items')
        .where('restaurantId', isEqualTo: rid)
        .limit(100)
        .get();

    var docs = byRestaurant.docs;
    RestaurantModel? restaurant;
    if (docs.isEmpty) {
      restaurant = await fetchRestaurantById(rid);
      final owner = restaurant?.ownerUid.trim() ?? '';
      if (owner.isNotEmpty) {
        final byMerchant = await _db
            .collection('food_menu_items')
            .where('merchantId', isEqualTo: owner)
            .limit(100)
            .get();
        docs = byMerchant.docs;
      }
    }
    restaurant ??= await fetchRestaurantById(rid);
    final kitchenPrep = restaurant?.avgPrepTimeMinutes;

    final out = <FoodModel>[];
    for (final doc in docs) {
      final data = doc.data();
      if (data['isAvailable'] == false) continue;
      final name = '${data['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final price = (data['price'] is num)
          ? (data['price'] as num).toDouble()
          : double.tryParse('${data['price']}') ?? 0.0;
      final img = _pickImageUrl(data);
      final seller =
          '${data['businessName'] ?? data['merchantName'] ?? 'Local kitchen'}';
      final mid = data['merchantId']?.toString().trim();
      final linked = data['restaurantId']?.toString().trim();
      final cat = '${data['category'] ?? ''}'.trim();
      out.add(FoodModel.fromJson({
        ...Map<String, dynamic>.from(data),
        'id': doc.id.hashCode.abs() % 2000000000,
        'FoodName': name,
        'FoodImage': img,
        'RestrauntName': seller,
        'price': price,
        'category': cat.isEmpty ? 'Meals' : cat,
        'gallery': img.isEmpty ? const [] : [img],
        'merchantId': (mid != null && mid.isNotEmpty) ? mid : null,
        'restaurantId':
            (linked != null && linked.isNotEmpty) ? linked : rid,
        'firestoreListingId': doc.id,
        if (kitchenPrep != null && kitchenPrep > 0)
          'restaurantAvgPrepTimeMinutes': kitchenPrep,
      }));
    }
    return out;
  }

  static String _pickImageUrl(Map<String, dynamic> data) {
    for (final key in [
      'image',
      'imageUrl',
      'FoodImage',
      'photo',
      'picture',
      'coverImage',
      'coverUrl',
    ]) {
      final s = '${data[key] ?? ''}'.trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }
}
