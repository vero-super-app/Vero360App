// lib/services/food_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/features/Restraurants/Models/restaurant_model.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/config/api_config.dart';

class FoodService {
  /// GET /marketplace?category=food&lat=&lng=&radiusKm= (backend may use these for filtering)
  Future<List<FoodModel>> fetchFoodItems({
    double? latitude,
    double? longitude,
    double radiusKm = 30,
  }) async {
    try {
      // Kick API + both Firestore sources in parallel so images can paint sooner.
      final apiFuture = _fetchMarketplaceApi(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
      final fsFuture = _fetchFirestoreFoodListings();
      final menuFuture = _fetchFirestoreFoodMenuItems();

      final results = await Future.wait([
        apiFuture,
        fsFuture,
        menuFuture,
      ]);

      final merged = _mergeFoodLists(
        _mergeFoodLists(results[0], results[1]),
        results[2],
      );

      final withPrep = await _attachRestaurantPrep(merged);

      return prioritizeNearUser(
        withPrep,
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
    } catch (_) {
      throw const ApiException(
        message: 'Unable to load food items. Please try again.',
      );
    }
  }

  Future<List<FoodModel>> _fetchMarketplaceApi({
    double? latitude,
    double? longitude,
    double radiusKm = 30,
  }) async {
    final params = <String, String>{'category': 'food'};
    if (latitude != null && longitude != null) {
      params['lat'] = latitude.toString();
      params['lng'] = longitude.toString();
      params['radiusKm'] = radiusKm.toString();
    }

    final uri = ApiConfig.endpoint('/marketplace').replace(
      queryParameters: params,
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 10));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const ApiException(message: 'Could not load food items.');
    }

    final decoded = jsonDecode(res.body);
    final List list = decoded is Map && decoded['data'] is List
        ? decoded['data']
        : decoded is List
            ? decoded
            : const [];

    return list.map<FoodModel>((row) {
      return FoodModel.fromJson(_adaptMarketplaceToFoodJson(
        Map<String, dynamic>.from(row as Map),
      ));
    }).toList();
  }

  /// Extra food rows from Firestore (legacy / fallback postings).
  Future<List<FoodModel>> _fetchFirestoreFoodListings() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('marketplace_items')
          .where('category', isEqualTo: 'food')
          .limit(80)
          .get();

      final out = <FoodModel>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isActive'] == false) continue;
        final name = '${data['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final price = (data['price'] is num)
            ? (data['price'] as num).toDouble()
            : double.tryParse('${data['price']}') ?? 0.0;
        final img = _pickImageUrl(data);
        final seller = '${data['merchantName'] ?? data['businessName'] ?? 'Local kitchen'}';
        double? la;
        double? lo;
        final rawLa = data['latitude'];
        final rawLo = data['longitude'];
        if (rawLa is num) la = rawLa.toDouble();
        if (rawLo is num) lo = rawLo.toDouble();
        la ??= double.tryParse('$rawLa');
        lo ??= double.tryParse('$rawLo');

        final mid = data['merchantId']?.toString().trim();
        final rid = data['restaurantId']?.toString().trim();
        final listingLoc = _listingLocationFromRaw(
          Map<String, dynamic>.from(data),
        );
        final gallery = _pickGallery(data);
        out.add(FoodModel.fromJson({
          ...Map<String, dynamic>.from(data),
          'id': doc.id.hashCode.abs() % 2000000000,
          'FoodName': name,
          'FoodImage': img,
          'RestrauntName': seller,
          'price': price,
          'category': 'food',
          'latitude': la,
          'longitude': lo,
          'listingLocation': listingLoc,
          'gallery': gallery,
          'merchantId': (mid != null && mid.isNotEmpty) ? mid : null,
          'restaurantId': (rid != null && rid.isNotEmpty) ? rid : null,
          'firestoreListingId': doc.id,
        }));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Merchant kitchen menu (posted via food dashboard → `food_menu_items`).
  Future<List<FoodModel>> _fetchFirestoreFoodMenuItems() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('food_menu_items')
          .limit(100)
          .get();

      final out = <FoodModel>[];
      for (final doc in snap.docs) {
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
        final rid = data['restaurantId']?.toString().trim();
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
          'restaurantId': (rid != null && rid.isNotEmpty) ? rid : null,
          'firestoreListingId': doc.id,
        }));
      }
      return out;
    } catch (_) {
      return [];
    }
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
    final gallery = _pickGallery(data);
    return gallery.isNotEmpty ? gallery.first : '';
  }

  static List<String> _pickGallery(Map<String, dynamic> data) {
    final out = <String>[];
    void addList(dynamic raw) {
      if (raw is! List) return;
      for (final e in raw) {
        final s = '$e'.trim();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
    }

    addList(data['gallery']);
    addList(data['galleryUrls']);
    addList(data['images']);
    return out;
  }

  List<FoodModel> _mergeFoodLists(List<FoodModel> a, List<FoodModel> b) {
    final out = List<FoodModel>.from(a);
    for (final f in b) {
      final dup = out.any((x) =>
          x.FoodName == f.FoodName &&
          x.RestrauntName == f.RestrauntName &&
          (x.price - f.price).abs() < 0.01);
      if (!dup) out.add(f);
    }
    return out;
  }

  /// Nearest dishes first. In-radius kitchens stay ahead of far ones.
  static List<FoodModel> prioritizeNearUser(
    List<FoodModel> items, {
    double? latitude,
    double? longitude,
    double radiusKm = 30,
  }) {
    if (latitude == null || longitude == null || items.isEmpty) {
      return List<FoodModel>.from(items);
    }

    final r = radiusKm.clamp(1.0, 200.0);
    final inRadius = <FoodModel>[];
    final noCoords = <FoodModel>[];
    final outRadius = <FoodModel>[];

    for (final f in items) {
      if (f.latitude == null || f.longitude == null) {
        noCoords.add(f);
        continue;
      }
      final d = distanceKm(latitude, longitude, f.latitude!, f.longitude!);
      if (d != null && d <= r) {
        inRadius.add(f);
      } else {
        outRadius.add(f);
      }
    }

    int byDistance(FoodModel a, FoodModel b) {
      final da = distanceKm(latitude, longitude, a.latitude!, a.longitude!) ??
          double.infinity;
      final db = distanceKm(latitude, longitude, b.latitude!, b.longitude!) ??
          double.infinity;
      return da.compareTo(db);
    }

    inRadius.sort(byDistance);
    outRadius.sort(byDistance);

    // Local food first; far kitchens only after nearby + unknown-coords.
    if (inRadius.isNotEmpty) {
      return [...inRadius, ...noCoords, ...outRadius];
    }
    return [...outRadius, ...noCoords];
  }

  /// Items within [radiusKm] of the user (empty if none / no location).
  static List<FoodModel> filterWithinRadius(
    List<FoodModel> items, {
    required double latitude,
    required double longitude,
    double radiusKm = 25,
  }) {
    final r = radiusKm.clamp(1.0, 200.0);
    final out = <FoodModel>[];
    for (final f in items) {
      if (f.latitude == null || f.longitude == null) continue;
      final d = distanceKm(latitude, longitude, f.latitude!, f.longitude!);
      if (d != null && d <= r) out.add(f);
    }
    out.sort((a, b) {
      final da = distanceKm(latitude, longitude, a.latitude!, a.longitude!)!;
      final db = distanceKm(latitude, longitude, b.latitude!, b.longitude!)!;
      return da.compareTo(db);
    });
    return out;
  }

  /// Haversine distance in km (Earth radius 6371 km).
  static double? distanceKm(
    double userLat,
    double userLng,
    double itemLat,
    double itemLng,
  ) {
    const earthKm = 6371.0;
    final p1 = userLat * math.pi / 180;
    final p2 = itemLat * math.pi / 180;
    final dLat = (itemLat - userLat) * math.pi / 180;
    final dLon = (itemLng - userLng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1) *
            math.cos(p2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthKm * c;
  }

  /// Puts items with coordinates first, nearest first; items without coords keep stable order.
  static List<FoodModel> sortByDistanceToUser(
    List<FoodModel> items,
    double userLat,
    double userLng,
  ) {
    final copy = List<FoodModel>.from(items);
    copy.sort((a, b) {
      final aHas = a.latitude != null && a.longitude != null;
      final bHas = b.latitude != null && b.longitude != null;
      if (!aHas && !bHas) return 0;
      if (!aHas) return 1;
      if (!bHas) return -1;
      final da = distanceKm(userLat, userLng, a.latitude!, a.longitude!)!;
      final db = distanceKm(userLat, userLng, b.latitude!, b.longitude!)!;
      return da.compareTo(db);
    });
    return copy;
  }

  /// Text search by FoodName OR RestrauntName (client-side filter).
  Future<List<FoodModel>> searchFoodByNameOrRestaurant(
    String query, {
    double? latitude,
    double? longitude,
    double radiusKm = 30,
  }) async {
    final q = query.trim().toLowerCase();

    // If query is too short, just return all food items
    if (q.length < 2) {
      return fetchFoodItems(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
    }

    final all = await fetchFoodItems(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
    );

    final filtered = all.where((f) {
      final name = f.FoodName.toLowerCase();
      final restaurant = f.RestrauntName.toLowerCase();
      return name.contains(q) || restaurant.contains(q);
    }).toList();

    if (latitude != null && longitude != null) {
      return sortByDistanceToUser(filtered, latitude, longitude);
    }
    return filtered;
  }

  /// Photo search
  Future<List<FoodModel>> searchFoodByPhoto(File imageFile) async {
    try {
      final uri = ApiConfig.endpoint('/marketplace/search/photo');

      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath(
          'photo',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ));

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw const ApiException(message: 'Photo search failed.');
      }

      final decoded = jsonDecode(res.body);
      final List list = decoded is Map && decoded['data'] is List
          ? decoded['data']
          : decoded is List
              ? decoded
              : const [];

      final out = <FoodModel>[];
      for (final row in list) {
        final m = _adaptMarketplaceToFoodJson(
          Map<String, dynamic>.from(row as Map),
        );
        if (m['category']?.toString().toLowerCase() == 'food') {
          out.add(FoodModel.fromJson(m));
        }
      }
      return out;
    } catch (_) {
      throw const ApiException(
        message: 'Could not search by photo. Please try again.',
      );
    }
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String? _listingLocationFromRaw(Map<String, dynamic> raw) {
    String? pick(String? s) {
      final t = s?.trim();
      if (t == null || t.isEmpty) return null;
      return t;
    }

    final loc = raw['location'];
    if (loc is String) return pick(loc);
    if (loc is Map) {
      final m = Map<String, dynamic>.from(loc);
      for (final k in ['formattedAddress', 'address', 'name', 'label']) {
        final v = pick(m[k]?.toString());
        if (v != null) return v;
      }
    }
    return pick(raw['address']?.toString()) ??
        pick(raw['pickupAddress']?.toString()) ??
        pick(raw['merchantAddress']?.toString());
  }

  Map<String, dynamic> _adaptMarketplaceToFoodJson(Map<String, dynamic> raw) {
    String s(dynamic v) => v?.toString() ?? '';

    final sp = raw['serviceProvider'] ?? raw['merchant'] ?? raw['seller'];
    final sellerName = (sp is Map)
        ? sp['businessName']?.toString() ?? 'Marketplace'
        : 'Marketplace';

    double? lat;
    double? lng;

    void pullFromMap(Map? m) {
      if (m == null) return;
      lat ??= _parseDouble(m['latitude'] ?? m['lat']);
      lng ??= _parseDouble(m['longitude'] ?? m['lng']);
    }

    pullFromMap(raw);

    final loc = raw['location'];
    if (loc is Map) {
      pullFromMap(Map<String, dynamic>.from(loc));
    }

    if (sp is Map) {
      pullFromMap(Map<String, dynamic>.from(sp));
    }

    final mid = raw['merchantId']?.toString().trim();
    final sid = raw['sellerUserId']?.toString().trim();
    final merchantKey =
        (mid != null && mid.isNotEmpty) ? mid : ((sid != null && sid.isNotEmpty) ? sid : null);
    final restaurantId = raw['restaurantId']?.toString().trim();

    final listingLoc = _listingLocationFromRaw(raw);

    final gallery = <String>[];
    void addGallery(dynamic rawGal) {
      if (rawGal is! List) return;
      for (final e in rawGal) {
        final s = e.toString().trim();
        if (s.isNotEmpty && !gallery.contains(s)) gallery.add(s);
      }
    }

    addGallery(raw['gallery']);
    addGallery(raw['galleryUrls']);
    addGallery(raw['images']);

    String cover = '';
    for (final key in [
      'image',
      'imageUrl',
      'FoodImage',
      'photo',
      'picture',
      'coverImage',
      'coverUrl',
    ]) {
      final v = s(raw[key]).trim();
      if (v.isNotEmpty) {
        cover = v;
        break;
      }
    }
    if (cover.isEmpty && gallery.isNotEmpty) cover = gallery.first;

    return {
      'id': int.tryParse(raw['id']?.toString() ?? '') ?? 0,
      'FoodName': s(raw['name']),
      'FoodImage': cover,
      'RestrauntName': sellerName,
      'price': double.tryParse(raw['price']?.toString() ?? '0') ?? 0.0,
      'description': raw['description']?.toString(),
      'category': raw['category']?.toString(),
      'latitude': lat,
      'longitude': lng,
      if (gallery.isNotEmpty) 'gallery': gallery,
      if (listingLoc != null) 'listingLocation': listingLoc,
      if (merchantKey != null) 'merchantId': merchantKey,
      if (restaurantId != null && restaurantId.isNotEmpty)
        'restaurantId': restaurantId,
      if (raw['variants'] != null) 'variants': raw['variants'],
      if (raw['addOns'] != null) 'addOns': raw['addOns'],
      if (raw['addons'] != null) 'addons': raw['addons'],
      if (raw['prepTimeMinutes'] != null)
        'prepTimeMinutes': raw['prepTimeMinutes'],
    };
  }

  /// Stamp [FoodModel.restaurantAvgPrepTimeMinutes] from `restaurants` so ETA
  /// can use kitchen prep without a per-card lookup.
  Future<List<FoodModel>> _attachRestaurantPrep(List<FoodModel> items) async {
    if (items.isEmpty) return items;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('restaurants')
          .limit(80)
          .get();
      final byId = <String, int>{};
      final byOwner = <String, int>{};
      for (final d in snap.docs) {
        final r = RestaurantModel.fromFirestore(d);
        if (r.id.isNotEmpty) byId[r.id] = r.avgPrepTimeMinutes;
        if (r.ownerUid.isNotEmpty) byOwner[r.ownerUid] = r.avgPrepTimeMinutes;
      }
      return items.map((f) {
        int? mins;
        final rid = f.restaurantId?.trim();
        if (rid != null && rid.isNotEmpty) mins = byId[rid];
        final mid = f.merchantId?.trim();
        if (mins == null && mid != null && mid.isNotEmpty) mins = byOwner[mid];
        if (mins == null || mins <= 0) return f;
        return f.copyWith(restaurantAvgPrepTimeMinutes: mins);
      }).toList();
    } catch (_) {
      return items;
    }
  }
}
