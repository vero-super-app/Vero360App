// lib/Pages/MerchantDashboards/accommodation_merchant_dashboard.dart
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

class AccommodationMerchantDashboard extends StatefulWidget {
  final String email;
  const AccommodationMerchantDashboard({super.key, required this.email});

  @override
  State<AccommodationMerchantDashboard> createState() => _AccommodationMerchantDashboardState();
}

class _AccommodationMerchantDashboardState extends State<AccommodationMerchantDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  // ✅ Use CartService singleton from provider
  final CartService _cartService = CartServiceProvider.getInstance();

  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentBookings = [];
  List<dynamic> _rooms = [];
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats
  int _totalBookings = 0;
  int _activeBookings = 0;
  int _completedBookings = 0;
  double _totalRevenue = 0;
  double _rating = 0.0;
  String _status = 'pending';
  int _availableRooms = 0;

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
    _businessName = prefs.getString('business_name') ?? 'Accommodation Provider';
    
    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'accommodation');
        
        if (!dashboardData.containsKey('error')) {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentBookings = dashboardData['recentOrders'] ?? [];
            _totalBookings = dashboardData['totalOrders'] ?? 0;
            _completedBookings = dashboardData['completedOrders'] ?? 0;
            _totalRevenue = dashboardData['totalRevenue'] ?? 0;
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
          });
        }

        await _loadRooms();
        await _loadWalletBalance();
        await _loadReviews();
        await _calculateActiveBookings();
        await _calculateAvailableRooms();

      } catch (e) {
        print('Error loading accommodation data: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _initialLoadComplete = true;
      });
    }
  }

  Future<void> _loadRooms() async {
    try {
      final snapshot = await _firestore
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: _uid)
          .get();
      
      if (mounted) {
        setState(() {
          _rooms = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading rooms: $e');
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

  Future<void> _loadReviews() async {
    try {
      final snapshot = await _firestore
          .collection('accommodation_reviews')
          .where('merchantId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      if (mounted) {
        setState(() {
          _reviews = snapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print('Error loading reviews: $e');
    }
  }

  Future<void> _calculateActiveBookings() async {
    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('accommodationId', isEqualTo: _uid)
          .where('status', whereIn: ['confirmed', 'checked_in'])
          .get();
      
      if (mounted) {
        setState(() {
          _activeBookings = snapshot.size;
        });
      }
    } catch (e) {
      print('Error calculating active bookings: $e');
    }
  }

  Future<void> _calculateAvailableRooms() async {
    try {
      final availableRooms = _rooms.where((room) {
        final roomMap = room as Map<String, dynamic>;
        return roomMap['isAvailable'] == true;
      }).length;
      
      if (mounted) {
        setState(() {
          _availableRooms = availableRooms;
        });
      }
    } catch (e) {
      print('Error calculating available rooms: $e');
    }
  }

  Future<void> _updateBookingStatus(String bookingId, String status) async {
    try {
      await _firestore
          .collection('bookings')
          .doc(bookingId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      _loadMerchantData();
    } catch (e) {
      print('Error updating booking: $e');
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
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null,
      body: _getCurrentPage(),
      bottomNavigationBar: _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    return AppBar(
      title: Text(_initialLoadComplete ? '$_businessName Dashboard' : 'Loading...'),
      backgroundColor: Colors.purple,
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
                  serviceType: 'accommodation',
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
            Text('Loading accommodation dashboard...'),
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
          _buildRecentBookings(),
          _buildRoomsSection(),
          _buildRecentReviews(),
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
            const Icon(Icons.hotel, size: 50, color: Colors.purple),
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
                  const Text('Accommodation Provider'),
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
              title: 'Total Bookings',
              value: '$_totalBookings',
              icon: Icons.book_online,
              color: Colors.purple,
            ),
            _StatCard(
              title: 'Total Revenue',
              value: 'MWK ${_totalRevenue.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              color: Colors.green,
            ),
            _StatCard(
              title: 'Active Guests',
              value: '$_activeBookings',
              icon: Icons.people,
              color: Colors.blue,
            ),
            _StatCard(
              title: 'Available Rooms',
              value: '$_availableRooms/${_rooms.length}',
              icon: Icons.bed,
              color: Colors.orange,
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
              avatar: const Icon(Icons.add_home_work, size: 20),
              label: const Text('Add Room'),
              onPressed: () {
                // Add room
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.calendar_today, size: 20),
              label: const Text('Calendar'),
              onPressed: () {
                // Calendar view
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
              avatar: const Icon(Icons.discount, size: 20),
              label: const Text('Promotions'),
              onPressed: () {
                // Promotions
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
                          serviceType: 'accommodation',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('View Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Earnings from completed bookings',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentBookings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Bookings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // View all bookings
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentBookings.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No bookings yet')),
            ),
          )
        else
          ..._recentBookings.take(3).map((booking) {
            final bookingMap = booking as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.hotel, color: Colors.purple),
                title: Text('Booking #${bookingMap['bookingId']?.toString().substring(0, 8) ?? 'N/A'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Guest: ${bookingMap['guestName'] ?? 'N/A'}'),
                    Text('Room: ${bookingMap['roomType'] ?? 'N/A'}'),
                    Text('Dates: ${bookingMap['checkIn'] ?? ''} - ${bookingMap['checkOut'] ?? ''}'),
                    Text('Amount: MWK ${bookingMap['totalAmount'] ?? '0'}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(bookingMap['status'] ?? 'pending'),
                      backgroundColor: _getBookingStatusColor(bookingMap['status']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        _showBookingActions(bookingMap);
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

  Widget _buildRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Rooms',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Add room
              },
              child: const Text('Add Room'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_rooms.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No rooms added yet')),
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
            itemCount: _rooms.length,
            itemBuilder: (context, index) {
              final room = _rooms[index] as Map<String, dynamic>;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        room['type'] == 'suite' ? Icons.king_bed : Icons.bed,
                        size: 40,
                        color: Colors.purple,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        room['name'] ?? 'Room ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${room['type'] ?? 'Standard'} Room',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MWK ${(room['price'] ?? 0).toStringAsFixed(2)}/night',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              room['isAvailable'] == true ? 'Available' : 'Booked',
                              style: TextStyle(
                                color: room['isAvailable'] == true 
                                    ? Colors.green 
                                    : Colors.red,
                              ),
                            ),
                            backgroundColor: room['isAvailable'] == true 
                                ? Colors.green[50] 
                                : Colors.red[50],
                          ),
                          const Spacer(),
                          Text(
                            '${room['capacity'] ?? 1} guests',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
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
                    reviewMap['guestName']?.toString().substring(0, 1) ?? 'G',
                  ),
                ),
                title: Row(
                  children: [
                    Text(reviewMap['guestName'] ?? 'Anonymous'),
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
                      'Booking: #${reviewMap['bookingId']?.toString().substring(0, 8) ?? 'N/A'}',
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
          color: isSelected ? Colors.purple.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.purple : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.purple : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBookingStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'checked_out':
        return Colors.green[100]!;
      case 'checked_in':
        return Colors.blue[100]!;
      case 'confirmed':
        return Colors.orange[100]!;
      case 'pending':
        return Colors.yellow[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  void _showBookingActions(Map<String, dynamic> booking) {
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
                  // View booking details
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Confirm Booking'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'confirmed');
                },
              ),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Check In'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'checked_in');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Check Out'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'checked_out');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel Booking'),
                onTap: () {
                  Navigator.pop(context);
                  _updateBookingStatus(booking['id'], 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}