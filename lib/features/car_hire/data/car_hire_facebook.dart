import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';

/// Mirrors a published car-hire listing into Firestore so the same Cloud
/// Function that shares marketplace items can post it on the Vero360 Page.
class CarHireFacebookQueue {
  CarHireFacebookQueue._();

  static const collection = 'car_hire_listings';

  static Future<void> syncListing({
    required FleetUnit unit,
    required String operatorId,
    required String companyName,
    bool? postToFacebook,
    bool? published,
  }) async {
    final id = unit.id;
    if (id <= 0) return;
    final car = unit.car;
    final live = published ?? (car.isPublished || car.isAvailable);
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final owner = uid.isNotEmpty
        ? uid
        : (operatorId.trim().isNotEmpty ? operatorId.trim() : id.toString());

    final payload = <String, dynamic>{
      'carId': id,
      'name': car.title,
      'title': car.title,
      'make': car.make,
      'model': car.model,
      'year': car.year,
      'dailyRate': car.dailyRate,
      'price': car.dailyRate,
      'currency': car.currency.isEmpty ? 'MWK' : car.currency,
      'imageUrl': car.primaryImage,
      'images': car.galleryImages,
      'location': (car.pickupArea ?? '').trim(),
      'merchantName': companyName.trim(),
      'merchantId': owner,
      'operatorId': operatorId.trim(),
      'listingStatus': live ? 'PUBLISHED' : 'DRAFT',
      'isActive': live,
      'isAvailable': live,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (postToFacebook != null) {
      payload['postToFacebook'] = postToFacebook;
    }

    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc('$id')
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CarHireFacebook] queue failed for $id: $e');
      }
    }
  }
}
