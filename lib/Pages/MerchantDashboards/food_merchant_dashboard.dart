// lib/Pages/MerchantDashboards/food_merchant_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/MerchantDashboards/merchant_wallet.dart';
import 'package:vero360_app/services/merchant_service_helper.dart';

class FoodMerchantDashboard extends StatefulWidget {
  final String email;
  const FoodMerchantDashboard({super.key, required this.email});

  @override
  State<FoodMerchantDashboard> createState() => _FoodMerchantDashboardState();
}

class _FoodMerchantDashboardState extends State<FoodMerchantDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  
  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentOrders = [];
  List<dynamic> _menuItems = [];
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats
  int _totalOrders = 0;
  int _completedOrders = 0;
  int _pendingOrders = 0;
  double _totalRevenue = 0;
  double _rating = 0.0;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _loadMerchantData();
    _startPeriodicUpdates();
  }

  void _startPeriodicUpdates() {
    // Refresh data every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadMerchantData();
      }
    });
  }

  Future<void> _loadMerchantData() async {
    setState(() => _isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    _businessName = prefs.getString('business_name') ?? 'Food Business';
    
    if (_uid.isNotEmpty) {
      try {
        // 1. Get merchant dashboard data
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'food');
        
        if (dashboardData.containsKey('error')) {
          print('Error loading dashboard: ${dashboardData['error']}');
        } else {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentOrders = dashboardData['recentOrders'] ?? [];
            _totalOrders = dashboardData['totalOrders'] ?? 0;
            _completedOrders = dashboardData['completedOrders'] ?? 0;
            _pendingOrders = dashboardData['pendingOrders'] ?? 0;
            _totalRevenue = dashboardData['totalRevenue'] ?? 0;
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
          });
        }

        // 2. Load menu items
        await _loadMenuItems();

        // 3. Load wallet balance
        await _loadWalletBalance();

        // 4. Load reviews
        await _loadReviews();

      } catch (e) {
        print('Error loading merchant data: $e');
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadMenuItems() async {
    try {
      final snapshot = await _firestore
          .collection('food_menu_items')
          .where('merchantId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      
      _menuItems = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading menu items: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(_uid)
          .get();
      
      if (walletDoc.exists) {
        setState(() {
          _walletBalance = (walletDoc.data()?['balance'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      print('Error loading wallet: $e');
    }
  }

  Future<void> _loadReviews() async {
    try {
      final snapshot = await _firestore
          .collection('food_reviews')
          .where('merchantId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      _reviews = snapshot.docs.map((doc) => doc.data()).toList();
      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading reviews: $e');
    }
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await _firestore
          .collection('food_orders')
          .doc(orderId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      // Refresh data
      _loadMerchantData();
    } catch (e) {
      print('Error updating order: $e');
    }
  }

  Future<void> _addMenuItem() async {
    // Navigate to add menu item page
    // This would be a separate screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Merchant Dashboard'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Bottomnavbar(email: widget.email),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: _businessName,
                    serviceType: 'food', // Fixed: Added serviceType parameter
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  _buildWelcomeSection(),
                  
                  // Stats Overview
                  _buildStatsSection(),
                  
                  // Quick Actions
                  _buildQuickActions(),
                  
                  // Wallet Summary
                  _buildWalletSummary(),
                  
                  // Recent Orders
                  _buildRecentOrders(),
                  
                  // Menu Items
                  _buildMenuItems(),
                  
                  // Recent Reviews
                  _buildRecentReviews(),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.restaurant, size: 50, color: Colors.orange),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _businessName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Food Merchant Dashboard',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        label: Text(_status.toUpperCase()),
                        backgroundColor: _status == 'approved' 
                            ? Colors.green[100] 
                            : _status == 'pending'
                              ? Colors.orange[100]
                              : Colors.red[100],
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Row(
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}'),
                          ],
                        ),
                        backgroundColor: Colors.amber[100],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Business Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _StatCard(
              title: 'Total Orders',
              value: '$_totalOrders',
              icon: Icons.shopping_bag,
              color: Colors.blue,
            ),
            _StatCard(
              title: 'Total Revenue',
              value: 'MWK ${_totalRevenue.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              color: Colors.green,
            ),
            _StatCard(
              title: 'Pending Orders',
              value: '$_pendingOrders',
              icon: Icons.pending_actions,
              color: Colors.orange,
            ),
            _StatCard(
              title: 'Completed',
              value: '$_completedOrders',
              icon: Icons.check_circle,
              color: Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              avatar: const Icon(Icons.restaurant_menu, size: 20),
              label: const Text('Manage Menu'),
              onPressed: _addMenuItem,
            ),
            ActionChip(
              avatar: const Icon(Icons.inventory, size: 20),
              label: const Text('Inventory'),
              onPressed: () {
                // Navigate to inventory
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.analytics, size: 20),
              label: const Text('Analytics'),
              onPressed: () {
                // Navigate to analytics
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.discount, size: 20),
              label: const Text('Promotions'),
              onPressed: () {
                // Navigate to promotions
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.settings, size: 20),
              label: const Text('Settings'),
              onPressed: () {
                // Navigate to settings
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.support_agent, size: 20),
              label: const Text('Support'),
              onPressed: () {
                // Contact support
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWalletSummary() {
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wallet Balance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MWK ${_walletBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MerchantWalletPage(
                          merchantId: _uid,
                          merchantName: _businessName,
                          serviceType: 'food', // Fixed: Added serviceType parameter
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('View Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Available for withdrawal',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentOrders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Orders',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Navigate to all orders
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentOrders.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No orders yet')),
            ),
          )
        else
          ..._recentOrders.take(3).map((order) {
            final orderMap = order as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.restaurant_menu, color: Colors.orange),
                title: Text('Order #${orderMap['orderId']?.toString().substring(0, 8) ?? 'N/A'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer: ${orderMap['customerName'] ?? 'N/A'}'),
                    Text('Amount: MWK ${orderMap['totalAmount'] ?? '0'}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(orderMap['status'] ?? 'pending'),
                      backgroundColor: _getStatusColor(orderMap['status']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        _showOrderActions(orderMap);
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildMenuItems() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Menu Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: _addMenuItem,
              child: const Text('Add Item'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_menuItems.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No menu items yet')),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.8,
            ),
            itemCount: _menuItems.length,
            itemBuilder: (context, index) {
              final item = _menuItems[index] as Map<String, dynamic>;
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: item['imageUrl'] != null
                          ? Image.network(
                              item['imageUrl'],
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.fastfood, size: 40),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] ?? 'Unnamed Item',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'MWK ${(item['price'] ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.green),
                          ),
                          Chip(
                            label: Text(
                              item['isAvailable'] == true ? 'Available' : 'Unavailable',
                              style: TextStyle(
                                color: item['isAvailable'] == true ? Colors.green : Colors.red,
                              ),
                            ),
                            backgroundColor: item['isAvailable'] == true 
                                ? Colors.green[50] 
                                : Colors.red[50],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildRecentReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Recent Reviews',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No reviews yet')),
            ),
          )
        else
          ..._reviews.map((review) {
            final reviewMap = review as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    reviewMap['customerName']?.toString().substring(0, 1) ?? '?',
                  ),
                ),
                title: Row(
                  children: [
                    Text(reviewMap['customerName'] ?? 'Anonymous'),
                    const Spacer(),
                    ...List.generate(5, (index) {
                      return Icon(
                        Icons.star,
                        size: 16,
                        color: index < (reviewMap['rating'] ?? 0) 
                            ? Colors.amber 
                            : Colors.grey[300],
                      );
                    }),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reviewMap['comment'] ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      'Order: #${reviewMap['orderId']?.toString().substring(0, 8) ?? 'N/A'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return Colors.green[100]!;
      case 'preparing':
        return Colors.blue[100]!;
      case 'pending':
        return Colors.orange[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  void _showOrderActions(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to order details
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Mark as Preparing'),
                onTap: () {
                  Navigator.pop(context);
                  _updateOrderStatus(order['id'], 'preparing');
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_shipping),
                title: const Text('Mark as Ready'),
                onTap: () {
                  Navigator.pop(context);
                  _updateOrderStatus(order['id'], 'ready');
                },
              ),
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('Mark as Delivered'),
                onTap: () {
                  Navigator.pop(context);
                  _updateOrderStatus(order['id'], 'delivered');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel Order'),
                onTap: () {
                  Navigator.pop(context);
                  _updateOrderStatus(order['id'], 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}