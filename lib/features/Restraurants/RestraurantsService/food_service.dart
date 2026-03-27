// lib/services/food_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

      return list.map<FoodModel>((row) {
        return FoodModel.fromJson(_adaptMarketplaceToFoodJson(
          Map<String, dynamic>.from(row as Map),
        ));
      }).toList();
    } catch (_) {
      throw const ApiException(
        message: 'Unable to load food items. Please try again.',
      );
    }
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
    };
  }
}
