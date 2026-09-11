import 'package:flutter/material.dart';
import 'package:vero360_app/app_nav_key.dart';
import 'package:vero360_app/features/Restraurants/Models/food_model.dart';
import 'package:vero360_app/features/Restraurants/Models/food_share_link.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/food_details.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_service.dart';

/// Opens [FoodDetailsPage] from a `vero360.app/food/...` or `vero360://food/...` URI.
class FoodShareNavigation {
  FoodShareNavigation._();

  static Future<void> openFromUri(Uri uri) async {
    final id = foodIdFromShareUri(uri)?.trim() ?? '';
    if (id.isEmpty) return;

    FoodModel? match;
    try {
      final all = await FoodService().fetchFoodItems();
      for (final f in all) {
        final fs = (f.firestoreListingId ?? '').trim();
        if (fs.isNotEmpty && fs == id) {
          match = f;
          break;
        }
        if (f.id != 0 && '${f.id}' == id) {
          match = f;
          break;
        }
      }
      if (match == null) {
        final q = (uri.queryParameters['name'] ??
                uri.queryParameters['q'] ??
                '')
            .trim()
            .toLowerCase();
        if (q.isNotEmpty) {
          for (final f in all) {
            if (f.FoodName.toLowerCase().contains(q)) {
              match = f;
              break;
            }
          }
        }
      }
    } catch (_) {}

    if (match == null) {
      // Fallback shell so the deep link still lands in food UX.
      match = FoodModel(
        id: int.tryParse(id) ?? 0,
        FoodName: (uri.queryParameters['name'] ?? 'Food').trim().isEmpty
            ? 'Food'
            : (uri.queryParameters['name'] ?? 'Food').trim(),
        FoodImage: (uri.queryParameters['img'] ?? '').trim(),
        RestrauntName: (uri.queryParameters['merchant'] ?? '').trim(),
        price: double.tryParse(uri.queryParameters['price'] ?? '') ?? 0,
        description: uri.queryParameters['desc'],
        firestoreListingId: id,
      );
    }

    appNavKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => FoodDetailsPage(foodItem: match!),
      ),
    );
  }
}
