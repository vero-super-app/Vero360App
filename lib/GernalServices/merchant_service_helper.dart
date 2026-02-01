// lib/services/merchant_service_helper.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MerchantServiceHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get merchant dashboard data
  Future<Map<String, dynamic>> getMerchantDashboardData(String uid, String serviceKey) async {
    try {
      final collectionName = '${serviceKey}_merchants';
      final merchantDoc = await _firestore
          .collection(collectionName)
          .doc(uid)
          .get();
      
      if (!merchantDoc.exists) {
        return {'error': 'Merchant profile not found'};
      }
      
      final merchantData = merchantDoc.data() as Map<String, dynamic>;
      
      // Get orders for this merchant based on service type
      QuerySnapshot ordersSnapshot;
      switch (serviceKey) {
        case 'food':
          ordersSnapshot = await _firestore
              .collection('food_orders')
              .where('merchantId', isEqualTo: uid)
              .where('status', whereIn: ['pending', 'preparing', 'ready', 'delivered'])
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
          break;
        case 'taxi':
          ordersSnapshot = await _firestore
              .collection('taxi_rides')
              .where('driverId', isEqualTo: uid)
              .where('status', whereIn: ['requested', 'accepted', 'in_progress', 'completed'])
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
          break;
        case 'accommodation':
          ordersSnapshot = await _firestore
              .collection('bookings')
              .where('accommodationId', isEqualTo: uid)
              .where('status', whereIn: ['pending', 'confirmed', 'checked_in', 'checked_out'])
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
          break;
        case 'courier':
          ordersSnapshot = await _firestore
              .collection('courier_orders')
              .where('courierId', isEqualTo: uid)
              .where('status', whereIn: ['pending', 'accepted', 'in_transit', 'delivered'])
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
          break;
        default:
          ordersSnapshot = await _firestore
              .collection('orders')
              .where('merchantId', isEqualTo: uid)
              .where('status', whereIn: ['pending', 'processing', 'completed'])
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
      }
      
      final orders = ordersSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
      // Calculate stats
      double totalRevenue = 0;
      int completedOrders = 0;
      
      for (var order in orders) {
        if (order['status'] == 'completed' || 
            order['status'] == 'delivered' ||
            order['status'] == 'checked_out') {
          completedOrders++;
          totalRevenue += (order['totalAmount'] ?? 0).toDouble();
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