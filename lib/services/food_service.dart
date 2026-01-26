// lib/services/food_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:vero360_app/models/food_model.dart';
import 'package:vero360_app/services/api_client.dart';
import 'package:vero360_app/services/api_exception.dart';
import 'package:vero360_app/config/api_config.dart';

class FoodService {
  /// GET /marketplace?category=food
  Future<List<FoodModel>> fetchFoodItems() async {
    try {
      final uri = ApiConfig.endpoint('/marketplace')
          .replace(queryParameters: {'category': 'food'});

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
        return FoodModel.fromJson(_adaptMarketplaceToFoodJson(row));
      }).toList();
    } catch (_) {
      throw const ApiException(
        message: 'Unable to load food items. Please try again.',
      );
    }
  }

  /// Text search by FoodName OR RestrauntName (client-side filter).
  Future<List<FoodModel>> searchFoodByNameOrRestaurant(String query) async {
    final q = query.trim().toLowerCase();

    // If query is too short, just return all food items
    if (q.length < 2) {
      return fetchFoodItems();
    }

    final all = await fetchFoodItems();

    return all.where((f) {
      final name = f.FoodName.toLowerCase();
      final restaurant = f.RestrauntName.toLowerCase();
      return name.contains(q) || restaurant.contains(q);
    }).toList();
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
        final m = _adaptMarketplaceToFoodJson(row);
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

  Map<String, dynamic> _adaptMarketplaceToFoodJson(Map raw) {
    String _s(dynamic v) => v?.toString() ?? '';

    final sp = raw['serviceProvider'] ?? raw['merchant'] ?? raw['seller'];
    final sellerName = (sp is Map)
        ? sp['businessName']?.toString() ?? 'Marketplace'
        : 'Marketplace';

    return {
      'id': int.tryParse(raw['id']?.toString() ?? '') ?? 0,
      'FoodName': _s(raw['name']),
      'FoodImage': _s(raw['image']),
      'RestrauntName': sellerName,
      'price': double.tryParse(raw['price']?.toString() ?? '0') ?? 0.0,
      'description': raw['description']?.toString(),
      'category': raw['category']?.toString(),
    };
  }
}
