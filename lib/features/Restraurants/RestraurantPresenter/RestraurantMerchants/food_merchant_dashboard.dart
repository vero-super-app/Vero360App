// lib/Pages/MerchantDashboards/food_merchant_dashboard.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/Post_On_Marketplace.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/Home/post_story_page.dart';
import 'package:vero360_app/utils/toasthelper.dart';

final NumberFormat _mwk0Fmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);

String _mwk0(num v) => _mwk0Fmt.format(v);

class FoodMerchantDashboard extends StatefulWidget {
  final String email;
  const FoodMerchantDashboard({super.key, required this.email});

  @override
  State<FoodMerchantDashboard> createState() => _FoodMerchantDashboardState();
}

class _FoodMerchantDashboardState extends State<FoodMerchantDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();

  late TabController _foodTabs;
  Timer? _refreshTimer;

  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentOrders = [];
  List<dynamic> _menuItems = [];
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  String _uid = '';
  String _businessName = '';
  String _merchantEmail = '';
  String _merchantPhone = '';
  double _walletBalance = 0;

  int _totalOrders = 0;
  int _completedOrders = 0;
  int _pendingOrders = 0;
  double _totalRevenue = 0;
  double _rating = 0.0;
  String _status = 'pending';

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  @override
  void initState() {
    super.initState();
    _foodTabs = TabController(length: 3, vsync: this);
    _loadMerchantData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadMerchantData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _foodTabs.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
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
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      ToastHelper.showCustomToast(
        context,
        'Logged out successfully',
        isSuccess: true,
        errorMessage: 'Logged out',
      );

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      ToastHelper.showCustomToast(
        context,
        'Logout failed: $e',
        isSuccess: false,
        errorMessage: 'Logout failed',
      );
    }
  }

  Future<void> _loadMerchantData() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    _businessName = prefs.getString('business_name') ?? 'Food Business';
    _merchantEmail =
        prefs.getString('email') ?? widget.email;
    _merchantPhone = prefs.getString('phone') ?? '';

    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'food');

        if (!dashboardData.containsKey('error')) {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentOrders = dashboardData['recentOrders'] ?? [];
            _totalOrders = dashboardData['totalOrders'] ?? 0;
            _completedOrders = dashboardData['completedOrders'] ?? 0;
            _pendingOrders = dashboardData['pendingOrders'] ?? 0;
            _totalRevenue = (dashboardData['totalRevenue'] is num)
                ? (dashboardData['totalRevenue'] as num).toDouble()
                : double.tryParse('${dashboardData['totalRevenue']}') ?? 0;
            _rating = _merchantData?['rating'] is num
                ? (_merchantData!['rating'] as num).toDouble()
                : double.tryParse('${_merchantData?['rating']}') ?? 0.0;
            _status = _merchantData?['status']?.toString() ?? 'pending';
          });
        }

        await _loadMenuItems();
        await _loadWalletBalance();
        await _loadReviews();
      } catch (e) {
        debugPrint('Error loading merchant data: $e');
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMenuItems() async {
    try {
      final snapshot = await _firestore
          .collection('food_menu_items')
          .where('merchantId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      _menuItems = snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading menu items: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc =
          await _firestore.collection('merchant_wallets').doc(_uid).get();

      if (walletDoc.exists) {
        final b = walletDoc.data()?['balance'];
        setState(() {
          _walletBalance = b is num ? b.toDouble() : double.tryParse('$b') ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading wallet: $e');
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
      debugPrint('Error loading reviews: $e');
    }
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await _firestore.collection('food_orders').doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _loadMerchantData();
    } catch (e) {
      debugPrint('Error updating order: $e');
    }
  }

  Future<void> _openPostFood() async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const MarketplaceCrudPage(initialCategory: 'food'),
      ),
    );
    if (mounted) await _loadMerchantData();
  }

  AppBar _buildFoodAppBar() {
    return AppBar(
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_rounded, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text(
            'Food Merchant',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
      backgroundColor: _brandOrange,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.auto_stories_rounded),
          tooltip: 'Post story (24h)',
          onPressed: () {
            final uid = _auth.currentUser?.uid;
            if (uid == null) {
              ToastHelper.showCustomToast(
                context,
                'Please sign in to post a story',
                isSuccess: false,
                errorMessage: '',
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute<bool>(
                builder: (_) => PostStoryPage(
                  merchantId: uid,
                  merchantName: _businessName.isNotEmpty
                      ? _businessName
                      : (_auth.currentUser?.displayName ?? 'Food Merchant'),
                  serviceType: 'food',
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.shopping_cart_rounded),
          tooltip: 'Browse app',
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
          icon: const Icon(Icons.account_balance_wallet_rounded),
          tooltip: 'Wallet',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MerchantWalletPage(
                  merchantId: _uid,
                  merchantName: _businessName,
                  serviceType: 'food',
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Logout',
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildModernHeaderCard() {
    final st = _status.trim().toLowerCase();
    final statusText = st.isEmpty ? 'PENDING' : st.toUpperCase();

    Color statusBg;
    Color statusFg;
    if (st == 'approved' || st == 'active') {
      statusBg = const Color(0xFFE7F6EC);
      statusFg = Colors.green.shade700;
    } else if (st == 'pending' || st == 'under_review' || st == 'submitted') {
      statusBg = const Color(0xFFFFF3E5);
      statusFg = const Color(0xFFB86E00);
    } else {
      statusBg = const Color(0xFFFFEDEE);
      statusFg = Colors.red.shade700;
    }

    final emailLine = _merchantEmail.isNotEmpty ? _merchantEmail : widget.email;
    final phoneLine = _merchantPhone.isNotEmpty ? _merchantPhone : '—';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_brandNavy, _brandNavy.withValues(alpha: 0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            child: const Icon(Icons.restaurant_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _businessName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  emailLine,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  phoneLine,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusFg,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 14),
                          Text(
                            ' ${_rating.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 74,
          ),
          itemBuilder: (_, i) {
            switch (i) {
              case 0:
                return _compactStatTile(
                  title: 'Total orders',
                  value: '$_totalOrders',
                  icon: Icons.shopping_bag_rounded,
                  color: _brandOrange,
                );
              case 1:
                return _compactStatTile(
                  title: 'Revenue',
                  value: _mwk0(_totalRevenue),
                  icon: Icons.payments_rounded,
                  color: Colors.green,
                );
              case 2:
                return _compactStatTile(
                  title: 'Pending',
                  value: '$_pendingOrders',
                  icon: Icons.pending_actions_rounded,
                  color: Colors.blue,
                );
              default:
                return _compactStatTile(
                  title: 'Completed',
                  value: '$_completedOrders',
                  icon: Icons.check_circle_rounded,
                  color: Colors.purple,
                );
            }
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 74,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            _FoodQuickActionTile(
              title: 'Post food',
              icon: Icons.add_circle_outline_rounded,
              color: _brandOrange,
              onTap: _openPostFood,
            ),
            _FoodQuickActionTile(
              title: 'My menu',
              icon: Icons.restaurant_menu_rounded,
              color: _brandNavy,
              onTap: () => _foodTabs.animateTo(2),
            ),
            _FoodQuickActionTile(
              title: 'Wallet',
              icon: Icons.account_balance_wallet_outlined,
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MerchantWalletPage(
                      merchantId: _uid,
                      merchantName: _businessName,
                      serviceType: 'food',
                    ),
                  ),
                );
              },
            ),
            _FoodQuickActionTile(
              title: 'Browse app',
              icon: Icons.storefront_outlined,
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Bottomnavbar(email: widget.email),
                  ),
                );
              },
            ),
            _FoodQuickActionTile(
              title: 'Post story',
              icon: Icons.auto_stories_outlined,
              color: const Color(0xFFDD2A7B),
              onTap: () {
                final uid = _auth.currentUser?.uid;
                if (uid == null) {
                  ToastHelper.showCustomToast(
                    context,
                    'Please sign in to post a story',
                    isSuccess: false,
                    errorMessage: '',
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => PostStoryPage(
                      merchantId: uid,
                      merchantName: _businessName.isNotEmpty
                          ? _businessName
                          : (_auth.currentUser?.displayName ?? 'Food Merchant'),
                      serviceType: 'food',
                    ),
                  ),
                );
              },
            ),
            _FoodQuickActionTile(
              title: 'Logout',
              icon: Icons.logout_rounded,
              color: Colors.red,
              onTap: _logout,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWalletSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wallet balance',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  _mwk0(_walletBalance),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'Available for withdrawal',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: _businessName,
                    serviceType: 'food',
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentOrders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent orders',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_recentOrders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No orders yet')),
          )
        else
          ..._recentOrders.take(3).map((order) {
            final orderMap = order as Map<String, dynamic>;
            final oid = orderMap['orderId']?.toString() ?? '';
            final shortId =
                oid.length > 8 ? oid.substring(0, 8) : (oid.isEmpty ? 'N/A' : oid);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                leading:
                    const Icon(Icons.restaurant_menu_rounded, color: _brandOrange),
                title: Text('Order #$shortId'),
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
                      label: Text('${orderMap['status'] ?? 'pending'}'),
                      backgroundColor: _getStatusColor(orderMap['status']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded),
                      onPressed: () => _showOrderActions(orderMap),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMenuGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My menu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            TextButton.icon(
              onPressed: _openPostFood,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('Post food'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_menuItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No menu items yet — tap Post food')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: _menuItems.length,
            itemBuilder: (context, index) {
              final item = _menuItems[index] as Map<String, dynamic>;
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15)),
                            child: item['imageUrl'] != null
                                ? Image.network(
                                    item['imageUrl'] as String,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.fastfood_rounded,
                                        size: 40, color: Colors.grey),
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name']?.toString() ?? 'Unnamed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              Text(
                                _mwk0((item['price'] is num)
                                    ? (item['price'] as num)
                                    : num.tryParse('${item['price']}') ?? 0),
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w700),
                              ),
                              Chip(
                                label: Text(
                                  item['isAvailable'] == true
                                      ? 'Available'
                                      : 'Unavailable',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: item['isAvailable'] == true
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: item['isAvailable'] == true
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
        const Text(
          'Recent reviews',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No reviews yet')),
          )
        else
          ..._reviews.map((review) {
            final reviewMap = review as Map<String, dynamic>;
            final name = reviewMap['customerName']?.toString() ?? 'Anonymous';
            final initial =
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
            final rid = reviewMap['orderId']?.toString() ?? '';
            final rshort =
                rid.length > 8 ? rid.substring(0, 8) : (rid.isEmpty ? 'N/A' : rid);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                leading: CircleAvatar(child: Text(initial)),
                title: Row(
                  children: [
                    Expanded(child: Text(name)),
                    ...List.generate(5, (index) {
                      final r = reviewMap['rating'] is num
                          ? (reviewMap['rating'] as num).round()
                          : int.tryParse('${reviewMap['rating']}') ?? 0;
                      return Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: index < r ? Colors.amber : Colors.grey.shade300,
                      );
                    }),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reviewMap['comment']?.toString() ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      'Order: #$rshort',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAccountSection() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              'Account',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          ListTile(
            leading: Icon(Icons.person_rounded, color: _brandNavy),
            title: const Text('Merchant profile'),
            subtitle: Text(_businessName),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded, color: Colors.grey),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.red),
            title: const Text('Logout'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildPostFoodTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Food listings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _openPostFood,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_rounded,
                        color: _brandOrange,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Post a dish',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Opens the listing form with category Food. Use the '
                            'location pin so customers nearby can find your kitchen.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openPostFood,
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text(
              'Open post form',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: _loadMerchantData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernHeaderCard(),
            const SizedBox(height: 12),
            _buildStatsSection(),
            const SizedBox(height: 12),
            _buildQuickActionsSection(),
            const SizedBox(height: 12),
            _buildWalletSummary(),
            const SizedBox(height: 12),
            _buildRecentOrders(),
            const SizedBox(height: 12),
            _buildRecentReviews(),
            const SizedBox(height: 12),
            _buildAccountSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTab() {
    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: _loadMerchantData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: _buildMenuGrid(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: _buildFoodAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _foodTabs,
                    labelColor: _brandOrange,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: _brandOrange,
                    tabs: const [
                      Tab(text: 'Dashboard'),
                      Tab(text: 'Post food'),
                      Tab(text: 'My menu'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _foodTabs,
                    children: [
                      _buildDashboardTab(),
                      _buildPostFoodTab(),
                      _buildMenuTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return Colors.green.shade100;
      case 'preparing':
        return Colors.blue.shade100;
      case 'pending':
        return Colors.orange.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  void _showOrderActions(Map<String, dynamic> order) {
    final docId = order['id']?.toString() ?? order['orderId']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_rounded),
                title: const Text('View details'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: const Text('Mark as preparing'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'preparing');
                },
              ),
              ListTile(
                leading: const Icon(Icons.room_service_rounded),
                title: const Text('Mark as ready'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'ready');
                },
              ),
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Mark as delivered'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'delivered');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel order'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FoodQuickActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _FoodQuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
