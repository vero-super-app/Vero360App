// lib/Pages/MerchantDashboards/courier_merchant_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/Home/homepage.dart';
// Add login screen import
import 'package:vero360_app/GernalScreens/login_screen.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class CourierMerchantDashboard extends StatefulWidget {
  final String email;
  const CourierMerchantDashboard({super.key, required this.email});

  @override
  State<CourierMerchantDashboard> createState() => _CourierMerchantDashboardState();
}

class _CourierMerchantDashboardState extends State<CourierMerchantDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  // ✅ Use CartService singleton from provider
  final CartService _cartService = CartServiceProvider.getInstance();
  
  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentDeliveries = [];
  List<dynamic> _couriers = [];
  List<dynamic> _vehicles = [];
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats
  int _totalDeliveries = 0;
  int _completedDeliveries = 0;
  int _activeDeliveries = 0;
  double _totalEarnings = 0;
  double _rating = 0.0;
  String _status = 'pending';
  int _availableCouriers = 0;

  // Navigation State
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMerchantData();
    _startPeriodicUpdates();
  }

  void _startPeriodicUpdates() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadMerchantData();
      }
    });
  }

  // ---------------- Logout Functionality ----------------
  Future<void> _logout() async {
    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Sign out from Firebase
      await _auth.signOut();

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Or clear specific keys if you want to keep some data

      // Show success message
      ToastHelper.showCustomToast(
        context,
        'Logged out successfully',
        isSuccess: true,
        errorMessage: 'Logged out',
      );

      // Navigate to login screen and remove all routes
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      
      // Show error message
      ToastHelper.showCustomToast(
        context,
        'Logout failed: $e',
        isSuccess: false,
        errorMessage: 'Logout failed',
      );
    }
  }

  Future<void> _loadMerchantData() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    _businessName = prefs.getString('business_name') ?? 'Courier Service';
    
    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'courier');
        
        if (!dashboardData.containsKey('error')) {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentDeliveries = dashboardData['recentOrders'] ?? [];
            _totalDeliveries = dashboardData['totalOrders'] ?? 0;
            _completedDeliveries = dashboardData['completedOrders'] ?? 0;
            _totalEarnings = dashboardData['totalRevenue'] ?? 0;
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
          });
        }

        await _loadCouriers();
        await _loadVehicles();
        await _loadWalletBalance();
        await _calculateActiveDeliveries();
        await _calculateAvailableCouriers();

      } catch (e) {
        print('Error loading courier data: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _initialLoadComplete = true;
      });
    }
  }

  Future<void> _loadCouriers() async {
    try {
      final snapshot = await _firestore
          .collection('couriers')
          .where('merchantId', isEqualTo: _uid)
          .get();
      
      if (mounted) {
        setState(() {
          _couriers = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading couriers: $e');
    }
  }

  Future<void> _loadVehicles() async {
    try {
      final snapshot = await _firestore
          .collection('courier_vehicles')
          .where('merchantId', isEqualTo: _uid)
          .get();
      
      if (mounted) {
        setState(() {
          _vehicles = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading vehicles: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(_uid)
          .get();
      
      if (walletDoc.exists && mounted) {
        setState(() {
          _walletBalance = (walletDoc.data()?['balance'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      print('Error loading wallet: $e');
    }
  }

  Future<void> _calculateActiveDeliveries() async {
    try {
      final snapshot = await _firestore
          .collection('courier_orders')
          .where('merchantId', isEqualTo: _uid)
          .where('status', whereIn: ['accepted', 'in_transit', 'out_for_delivery'])
          .get();
      
      if (mounted) {
        setState(() {
          _activeDeliveries = snapshot.size;
        });
      }
    } catch (e) {
      print('Error calculating active deliveries: $e');
    }
  }

  Future<void> _calculateAvailableCouriers() async {
    try {
      final available = _couriers.where((courier) {
        final courierMap = courier as Map<String, dynamic>;
        return courierMap['status'] == 'available';
      }).length;
      
      if (mounted) {
        setState(() {
          _availableCouriers = available;
        });
      }
    } catch (e) {
      print('Error calculating available couriers: $e');
    }
  }

  Future<void> _updateDeliveryStatus(String deliveryId, String status) async {
    try {
      await _firestore
          .collection('courier_orders')
          .doc(deliveryId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      _loadMerchantData();
    } catch (e) {
      print('Error updating delivery: $e');
    }
  }

  Future<void> _assignCourier(String deliveryId, String courierId) async {
    try {
      await _firestore
          .collection('courier_orders')
          .doc(deliveryId)
          .update({
            'courierId': courierId,
            'status': 'assigned',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      _loadMerchantData();
    } catch (e) {
      print('Error assigning courier: $e');
    }
  }

  Widget _StatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null, // Dashboard is at index 4
      body: _getCurrentPage(),
      bottomNavigationBar: _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    return AppBar(
      title: Text(_initialLoadComplete ? '$_businessName Dashboard' : 'Loading...'),
      backgroundColor: Colors.teal,
      actions: [
        IconButton(
          icon: const Icon(Icons.switch_account),
          tooltip: 'Switch to Customer View',
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => Bottomnavbar(email: widget.email),
              ),
              (_) => false,
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
                  serviceType: 'courier',
                ),
              ),
            );
          },
        ),
        // Add logout button here
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0: // Home (First position)
        return Vero360Homepage(email: widget.email);
      case 1: // Marketplace (Second position)
        return MarketPage(cartService: _cartService);
      case 2: // Cart (Third position)
        return CartPage(cartService: _cartService);
      case 3: // Messages (Fourth position)
        return ChatListPage();
      case 4: // Dashboard (Fifth/last position)
        return _buildDashboardContent();
      default:
        return Vero360Homepage(email: widget.email);
    }
  }

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Loading dashboard...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeSection(),
          _buildStatsSection(),
          _buildQuickActions(),
          _buildWalletSummary(),
          _buildRecentDeliveries(),
          _buildCouriersSection(),
          _buildVehiclesSection(),
          // Add logout section
          _buildLogoutSection(),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.local_shipping, size: 50, color: Colors.teal),
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
                  const Text('Courier Service Provider'),
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
              title: 'Total Deliveries',
              value: '$_totalDeliveries',
              icon: Icons.local_shipping,
              color: Colors.teal,
            ),
            _StatCard(
              title: 'Total Earnings',
              value: 'MWK ${_totalEarnings.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              color: Colors.green,
            ),
            _StatCard(
              title: 'Active Deliveries',
              value: '$_activeDeliveries',
              icon: Icons.timer,
              color: Colors.orange,
            ),
            _StatCard(
              title: 'Available Couriers',
              value: '$_availableCouriers/${_couriers.length}',
              icon: Icons.person,
              color: Colors.blue,
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
              avatar: const Icon(Icons.person_add, size: 20),
              label: const Text('Add Courier'),
              onPressed: () {
                // Add courier
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.add_circle, size: 20),
              label: const Text('Add Vehicle'),
              onPressed: () {
                // Add vehicle
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.map, size: 20),
              label: const Text('Live Tracking'),
              onPressed: () {
                // Live tracking
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.analytics, size: 20),
              label: const Text('Analytics'),
              onPressed: () {
                // Analytics
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.settings, size: 20),
              label: const Text('Settings'),
              onPressed: () {
                // Settings
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.support_agent, size: 20),
              label: const Text('Support'),
              onPressed: () {
                // Support
              },
            ),
            // Add logout action chip
            ActionChip(
              avatar: const Icon(Icons.logout, size: 20),
              label: const Text('Logout'),
              onPressed: _logout,
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
                          serviceType: 'courier',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('View Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Earnings from completed deliveries',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentDeliveries() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Deliveries',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // View all deliveries
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentDeliveries.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No deliveries yet')),
            ),
          )
        else
          ..._recentDeliveries.take(3).map((delivery) {
            final deliveryMap = delivery as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.local_shipping, color: Colors.teal),
                title: Text('Delivery #${deliveryMap['deliveryId']?.toString().substring(0, 8) ?? 'N/A'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From: ${deliveryMap['pickupAddress'] ?? 'N/A'}'),
                    Text('To: ${deliveryMap['deliveryAddress'] ?? 'N/A'}'),
                    Text('Type: ${deliveryMap['packageType'] ?? 'N/A'}'),
                    Text('Fee: MWK ${deliveryMap['deliveryFee'] ?? '0'}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(deliveryMap['status'] ?? 'pending'),
                      backgroundColor: _getDeliveryStatusColor(deliveryMap['status']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        _showDeliveryActions(deliveryMap);
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

  Widget _buildCouriersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Couriers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Add courier
              },
              child: const Text('Add Courier'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_couriers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No couriers yet')),
            ),
          )
        else
          ..._couriers.map((courier) {
            final courierMap = courier as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal[100],
                  child: Text(
                    courierMap['name']?.toString().substring(0, 1) ?? 'C',
                    style: const TextStyle(color: Colors.teal),
                  ),
                ),
                title: Text(courierMap['name'] ?? 'Unknown Courier'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Phone: ${courierMap['phone'] ?? 'N/A'}'),
                    Text('Vehicle: ${courierMap['vehicleType'] ?? 'N/A'}'),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Chip(
                      label: Text(
                        courierMap['status'] ?? 'inactive',
                        style: TextStyle(
                          color: courierMap['status'] == 'available' 
                              ? Colors.green 
                              : Colors.red,
                        ),
                      ),
                      backgroundColor: courierMap['status'] == 'available' 
                          ? Colors.green[50] 
                          : Colors.red[50],
                    ),
                    Text(
                      '${courierMap['completedDeliveries'] ?? 0} deliveries',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildVehiclesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Vehicles',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_vehicles.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No vehicles yet')),
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
              childAspectRatio: 0.9,
            ),
            itemCount: _vehicles.length,
            itemBuilder: (context, index) {
              final vehicle = _vehicles[index] as Map<String, dynamic>;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        vehicle['type'] == 'motorcycle' ? Icons.motorcycle : Icons.directions_car,
                        size: 40,
                        color: Colors.teal,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        vehicle['make'] ?? 'Vehicle',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Plate: ${vehicle['licensePlate'] ?? 'N/A'}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(
                          vehicle['status'] ?? 'available',
                          style: TextStyle(
                            color: vehicle['status'] == 'available' 
                                ? Colors.green 
                                : Colors.red,
                          ),
                        ),
                        backgroundColor: vehicle['status'] == 'available' 
                            ? Colors.green[50] 
                            : Colors.red[50],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // Add a logout section in the dashboard
  Widget _buildLogoutSection() {
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text('Merchant Profile'),
              subtitle: Text(_businessName),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Add profile navigation here if needed
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Add settings navigation here if needed
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 'Home', 0),
              _buildNavItem(Icons.store, 'Marketplace', 1),
              _buildNavItem(Icons.shopping_cart, 'Cart', 2),
              _buildNavItem(Icons.message, 'Messages', 3),
              _buildNavItem(Icons.dashboard, 'Dashboard', 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.teal : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.teal : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDeliveryStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'delivered':
        return Colors.green[100]!;
      case 'in_transit':
        return Colors.blue[100]!;
      case 'out_for_delivery':
        return Colors.orange[100]!;
      case 'accepted':
        return Colors.yellow[100]!;
      case 'pending':
        return Colors.grey[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  void _showDeliveryActions(Map<String, dynamic> delivery) {
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
                  // View delivery details
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Assign Courier'),
                onTap: () {
                  Navigator.pop(context);
                  _showCourierAssignment(delivery['id']);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_shipping),
                title: const Text('Mark as In Transit'),
                onTap: () {
                  Navigator.pop(context);
                  _updateDeliveryStatus(delivery['id'], 'in_transit');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delivery_dining),
                title: const Text('Mark as Out for Delivery'),
                onTap: () {
                  Navigator.pop(context);
                  _updateDeliveryStatus(delivery['id'], 'out_for_delivery');
                },
              ),
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('Mark as Delivered'),
                onTap: () {
                  Navigator.pop(context);
                  _updateDeliveryStatus(delivery['id'], 'delivered');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel Delivery'),
                onTap: () {
                  Navigator.pop(context);
                  _updateDeliveryStatus(delivery['id'], 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCourierAssignment(String deliveryId) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Assign Courier',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ..._couriers.where((c) {
                final courier = c as Map<String, dynamic>;
                return courier['status'] == 'available';
              }).map((courier) {
                final courierMap = courier as Map<String, dynamic>;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(courierMap['name']?.toString().substring(0, 1) ?? 'C'),
                  ),
                  title: Text(courierMap['name'] ?? 'Unknown'),
                  subtitle: Text('${courierMap['vehicleType'] ?? 'N/A'} - ${courierMap['phone'] ?? ''}'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _assignCourier(deliveryId, courierMap['id']);
                    },
                    child: const Text('Assign'),
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}