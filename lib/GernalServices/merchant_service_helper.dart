// lib/services/merchant_service_helper.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Maps backend/Firestore spellings to the routing key (lowercase) used in the app.
const kKnownMerchantServices = {
  'marketplace',
  'food',
  'accommodation',
  'courier',
};

String? normalizeMerchantServiceKey(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'accomodation') return 'accommodation';
  return s;
}

bool isKnownMerchantServiceKey(String? raw) {
  final k = normalizeMerchantServiceKey(raw);
  return k != null && kKnownMerchantServices.contains(k);
}

String? merchantCollectionForService(String? raw) {
  final k = normalizeMerchantServiceKey(raw);
  if (k == null || !kKnownMerchantServices.contains(k)) return null;
  return k == 'marketplace' ? 'marketplace_merchants' : '${k}_merchants';
}

/// Name-only stubs (e.g. from display-name sync) must not count as a vertical.
bool looksLikeRealMerchantShopDoc(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;
  if (isKnownMerchantServiceKey(data['serviceType']?.toString()) ||
      isKnownMerchantServiceKey(data['merchantService']?.toString()) ||
      isKnownMerchantServiceKey(data['merchant_service']?.toString())) {
    return true;
  }
  if (data['status'] != null &&
      (data['uid'] != null ||
          data['businessAddress'] != null ||
          data['isActive'] != null)) {
    return true;
  }
  return data.containsKey('completedOrders') || data.containsKey('totalRatings');
}

String? _merchantServiceFromUserMap(Map<String, dynamic> data) {
  final fromRoleFields = normalizeMerchantServiceKey(
    data['merchantService']?.toString() ?? data['merchant_service']?.toString(),
  );
  if (isKnownMerchantServiceKey(fromRoleFields)) return fromRoleFields;
  return null;
}

/// Persists API `merchantService` without replacing a non-marketplace local value
/// with the generic `marketplace` default many backends return.
Future<void> persistMerchantServiceFromApi(
  SharedPreferences prefs,
  String? rawFromApi,
) async {
  final fromApi = normalizeMerchantServiceKey(rawFromApi);
  if (fromApi == null || fromApi.isEmpty || !isKnownMerchantServiceKey(fromApi)) {
    return;
  }
  final existing = normalizeMerchantServiceKey(prefs.getString('merchant_service'));
  final intendedUid = (prefs.getString('session_intended_uid') ?? '').trim();
  final intendedService =
      normalizeMerchantServiceKey(prefs.getString('session_intended_merchant_service'));
  final fbUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (fbUid.isNotEmpty &&
      intendedUid == fbUid &&
      isKnownMerchantServiceKey(intendedService)) {
    await prefs.setString('merchant_service', intendedService!);
    return;
  }
  if (existing == null || existing.isEmpty) {
    await prefs.setString('merchant_service', fromApi);
    return;
  }
  // Do not let a generic API default clobber food/stay/courier.
  if (fromApi == 'marketplace' && existing != 'marketplace') {
    return;
  }
  await prefs.setString('merchant_service', fromApi);
}

/// Prefer `users/{uid}` merchant type when prefs are empty. Never infer from
/// `serviceType` (cart/listing field) or from leftover shop-name stubs.
Future<void> hydrateMerchantServiceFromFirestore(SharedPreferences prefs) async {
  try {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb == null) return;
    final intendedUid = (prefs.getString('session_intended_uid') ?? '').trim();
    final intendedService =
        normalizeMerchantServiceKey(prefs.getString('session_intended_merchant_service'));
    if (intendedUid == fb.uid && isKnownMerchantServiceKey(intendedService)) {
      await prefs.setString('merchant_service', intendedService!);
      return;
    }
    final existing = normalizeMerchantServiceKey(prefs.getString('merchant_service'));
    if (isKnownMerchantServiceKey(existing)) return;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(fb.uid).get();
    if (!doc.exists || doc.data() == null) return;
    final fromDoc = _merchantServiceFromUserMap(doc.data()!);
    if (!isKnownMerchantServiceKey(fromDoc)) return;
    await prefs.setString('merchant_service', fromDoc!);
  } catch (_) {}
}

/// Discover the merchant vertical for [uid] from the user profile first.
/// Shop collections are only used when the doc looks like a real shop.
Future<String?> resolveMerchantServiceForUid(String uid) async {
  final id = uid.trim();
  if (id.isEmpty) return null;

  try {
    final prefs = await SharedPreferences.getInstance();
    final intendedUid = (prefs.getString('session_intended_uid') ?? '').trim();
    final intendedService =
        normalizeMerchantServiceKey(prefs.getString('session_intended_merchant_service'));
    if (intendedUid == id && isKnownMerchantServiceKey(intendedService)) {
      return intendedService;
    }
    // Offline / flaky network: never drop a known local vertical.
    final cached = normalizeMerchantServiceKey(prefs.getString('merchant_service'));
    if (isKnownMerchantServiceKey(cached)) {
      return cached;
    }
  } catch (_) {}

  String? fromUsers;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .get()
        .timeout(const Duration(seconds: 4));
    if (doc.exists && doc.data() != null) {
      fromUsers = _merchantServiceFromUserMap(doc.data()!);
    }
  } catch (_) {}
  if (isKnownMerchantServiceKey(fromUsers)) return fromUsers;

  // Parallel probe — stop as soon as one vertical matches (faster on weak networks).
  const services = ['food', 'marketplace', 'accommodation', 'courier'];
  try {
    final probes = await Future.wait(
      services.map((service) async {
        try {
          final collectionName = merchantCollectionForService(service)!;
          final merchantDoc = await FirebaseFirestore.instance
              .collection(collectionName)
              .doc(id)
              .get()
              .timeout(const Duration(seconds: 3));
          if (merchantDoc.exists &&
              looksLikeRealMerchantShopDoc(merchantDoc.data())) {
            return service;
          }
        } catch (_) {}
        return null;
      }),
    );
    for (final hit in probes) {
      if (isKnownMerchantServiceKey(hit)) return hit;
    }
  } catch (_) {}
  return null;
}

class MerchantServiceHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> _recentOrdersForMerchant(
    String serviceKey,
    String uid,
  ) async {
    String collection = 'orders';
    String ownerField = 'merchantId';
    Set<String> allowedStatuses = {'pending', 'processing', 'completed'};

    switch (serviceKey) {
      case 'food':
        collection = 'food_orders';
        ownerField = 'merchantId';
        allowedStatuses = {'pending', 'preparing', 'ready', 'delivered'};
        break;
      case 'taxi':
        collection = 'taxi_rides';
        ownerField = 'driverId';
        allowedStatuses = {'requested', 'accepted', 'in_progress', 'completed'};
        break;
      case 'accommodation':
        collection = 'bookings';
        ownerField = 'accommodationId';
        allowedStatuses = {'pending', 'confirmed', 'checked_in', 'checked_out'};
        break;
      case 'courier':
        collection = 'courier_orders';
        ownerField = 'courierId';
        allowedStatuses = {'pending', 'accepted', 'in_transit', 'delivered'};
        break;
      default:
        break;
    }

    // Index-safe strategy: filter by owner only, then filter/sort in memory.
    final snapshot = await _firestore
        .collection(collection)
        .where(ownerField, isEqualTo: uid)
        .limit(120)
        .get();

    final rows = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    final filtered = rows.where((row) {
      final status = (row['status']?.toString().toLowerCase() ?? '').trim();
      return allowedStatuses.contains(status);
    }).toList();

    filtered.sort((a, b) {
      final ad = a['createdAt'];
      final bd = b['createdAt'];
      DateTime at = DateTime.fromMillisecondsSinceEpoch(0);
      DateTime bt = DateTime.fromMillisecondsSinceEpoch(0);
      if (ad is Timestamp) at = ad.toDate();
      if (bd is Timestamp) bt = bd.toDate();
      return bt.compareTo(at);
    });

    return filtered.take(20).toList();
  }

  // Get merchant dashboard data
  Future<Map<String, dynamic>> getMerchantDashboardData(String uid, String serviceKey) async {
    try {
      final collectionName = '${serviceKey}_merchants';
      final merchantFuture =
          _firestore.collection(collectionName).doc(uid).get();
      final ordersFuture = _recentOrdersForMerchant(serviceKey, uid);

      final results =
          await Future.wait<dynamic>([merchantFuture, ordersFuture]);
      final merchantDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final orders = results[1] as List<Map<String, dynamic>>;

      if (!merchantDoc.exists) {
        return {'error': 'Merchant profile not found'};
      }

      final merchantData = merchantDoc.data() as Map<String, dynamic>;
      
      // Calculate stats
      double totalRevenue = 0;
      int completedOrders = 0;
      
      for (var order in orders) {
        if (order['status'] == 'completed' || 
            order['status'] == 'delivered' ||
            order['status'] == 'checked_out') {
          completedOrders++;
          final raw = order['totalAmount'];
          totalRevenue += raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
        }
      }
      
      return {
        'merchant': merchantData,
        'recentOrders': orders,
        'totalOrders': orders.length,
        'completedOrders': completedOrders,
        'totalRevenue': totalRevenue,
        'pendingOrders': orders.where((o) => o['status'] == 'pending').length,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Get merchant's service type from SharedPreferences
  static Future<String?> getMerchantService() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('merchant_service');
  }

  // Check if user is a merchant
  static Future<bool> isMerchant() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    return role == 'merchant';
  }

  // Get merchant business info
  static Future<Map<String, String>> getMerchantBusinessInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'businessName': prefs.getString('business_name') ?? '',
      'businessAddress': prefs.getString('business_address') ?? '',
    };
  }

  // Update merchant status
  Future<bool> updateMerchantStatus(String uid, String status) async {
    try {
      // Get merchant service from users collection
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data();
      
      if (userData == null) return false;
      
      final serviceKey = userData['merchantService'];
      if (serviceKey == null) return false;
      
      // Update in users collection
      await _firestore.collection('users').doc(uid).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Update in service-specific collection
      final collectionName = '${serviceKey}_merchants';
      await _firestore
          .collection(collectionName)
          .doc(uid)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      return true;
    } catch (e) {
      return false;
    }
  }
}