// lib/services/food_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
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
      final params = <String, String>{'category': 'food'};
      if (latitude != null && longitude != null) {
        params['lat'] = latitude.toString();
        params['lng'] = longitude.toString();
        params['radiusKm'] = radiusKm.toString();
      }

      final uri = ApiConfig.endpoint('/marketplace').replace(
        queryParameters: params,
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw const ApiException(message: 'Could not load food items.');
      }

      final decoded = jsonDecode(res.body);
      final List list = decoded is Map && decoded['data'] is List
          ? decoded['data']
          : decoded is List
              ? decoded
              : const [];

      final fromApi = list.map<FoodModel>((row) {
        return FoodModel.fromJson(_adaptMarketplaceToFoodJson(
          Map<String, dynamic>.from(row as Map),
        ));
      }).toList();

      final fromFs = await _fetchFirestoreFoodListings();
      final merged = _mergeFoodLists(fromApi, fromFs);

      return _applyRadiusFilter(
        merged,
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
        final img = '${data['image'] ?? ''}';
        final seller = '${data['merchantName'] ?? 'Local kitchen'}';
        double? la;
        double? lo;
        final rawLa = data['latitude'];
        final rawLo = data['longitude'];
        if (rawLa is num) la = rawLa.toDouble();
        if (rawLo is num) lo = rawLo.toDouble();
        la ??= double.tryParse('$rawLa');
        lo ??= double.tryParse('$rawLo');

        final mid = data['merchantId']?.toString().trim();
        final listingLoc = _listingLocationFromRaw(
          Map<String, dynamic>.from(data),
        );
        out.add(FoodModel(
          id: doc.id.hashCode.abs() % 2000000000,
          FoodName: name,
          FoodImage: img,
          RestrauntName: seller,
          price: price,
          description: data['description']?.toString(),
          category: 'food',
          latitude: la,
          longitude: lo,
          listingLocation: listingLoc,
          merchantId: (mid != null && mid.isNotEmpty) ? mid : null,
          firestoreListingId: doc.id,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
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

  List<FoodModel> _applyRadiusFilter(
    List<FoodModel> items, {
    double? latitude,
    double? longitude,
    double radiusKm = 30,
  }) {
    if (latitude == null || longitude == null) return items;
    final withCoords = items
        .where((f) => f.latitude != null && f.longitude != null)
        .toList();
    if (withCoords.isEmpty) return items;

    final r = radiusKm.clamp(1.0, 200.0);
    final inRadius = <FoodModel>[];
    final outRadius = <FoodModel>[];
    for (final f in withCoords) {
      final d = distanceKm(latitude, longitude, f.latitude!, f.longitude!);
      if (d != null && d <= r) {
        inRadius.add(f);
      } else {
        outRadius.add(f);
      }
    }
    final noCoords = items
        .where((f) => f.latitude == null || f.longitude == null)
        .toList();

    if (inRadius.isEmpty) return items;

    inRadius.sort((a, b) {
      final da = distanceKm(latitude, longitude, a.latitude!, a.longitude!)!;
      final db = distanceKm(latitude, longitude, b.latitude!, b.longitude!)!;
      return da.compareTo(db);
    });
    return [...inRadius, ...noCoords, ...outRadius];
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

    final listingLoc = _listingLocationFromRaw(raw);

    return {
      'id': int.tryParse(raw['id']?.toString() ?? '') ?? 0,
      'FoodName': s(raw['name']),
      'FoodImage': s(raw['image']),
      'RestrauntName': sellerName,
      'price': double.tryParse(raw['price']?.toString() ?? '0') ?? 0.0,
      'description': raw['description']?.toString(),
      'category': raw['category']?.toString(),
      'latitude': lat,
      'longitude': lng,
      if (listingLoc != null) 'listingLocation': listingLoc,
      if (merchantKey != null) 'merchantId': merchantKey,
    };
  }
}
