import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_guard.dart';

import '../../Home/homepage.dart';
import '../Marketplace/presentation/pages/main_marketPlace.dart';
import '../Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';

import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';

// Merchant dashboards
import 'package:vero360_app/features/ride_share/presentation/pages/driver_dashboard.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';

class Bottomnavbar extends StatefulWidget {
  const Bottomnavbar({super.key, required this.email});
  final String email;

  @override
  State<Bottomnavbar> createState() => _BottomnavbarState();
}

class _BottomnavbarState extends State<Bottomnavbar>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  bool _isLoading = true;
  bool _isMerchant = false;
  bool _isDriver = false;
  bool _isLoggedIn = false;

  late List<Widget> _pages;

  final cartService = CartServiceProvider.getInstance();

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandOrangeDark = Color(0xFFE07000);
  static const Color _brandOrangeGlow = Color(0xFFFFE2BF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance
        .authStateChanges()
        .listen((_) => _refreshAuthState());
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _tabIsProtected(int index) => index >= 2;

  Future<void> _initialize() async {
    // Load role and build pages from SharedPreferences first so hot restart
    // always shows correct navbar (merchant/customer) before auth is restored.
    await _checkUserRoleAndSetup();
    await _refreshAuthState();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshAuthState() async {
    final loggedIn = await AuthHandler.isAuthenticated();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);

    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) {
      setState(() => _selectedIndex = 0);
    }
    // When logged in, fetch role from backend so navbar reflects merchant/driver correctly.
    if (loggedIn) {
      await _fetchAndUpdateRoleFromServer();
    }
  }

  /// Fetch /users/me and persist role to SharedPreferences so role matches backend.
  Future<void> _fetchAndUpdateRoleFromServer() async {
    final token = await AuthHandler.getTokenForApi();
    if (token == null || token.isEmpty) return;
    try {
      final resp = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final decoded = json.decode(resp.body);
      final user = (decoded is Map && decoded['data'] is Map)
          ? Map<String, dynamic>.from(decoded['data'])
          : (decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{});
      final prefs = await SharedPreferences.getInstance();
      final isMerchant = _userIsMerchant(user);
      final isDriver = !isMerchant && _userIsDriver(user);
      if (isMerchant) {
        await prefs.setString('user_role', 'merchant');
        await prefs.setString('role', 'merchant');
      } else if (isDriver) {
        await prefs.setString('user_role', 'driver');
        await prefs.setString('role', 'driver');
      } else {
        await prefs.setString('user_role', 'customer');
        await prefs.setString('role', 'customer');
      }
      final raw = isMerchant ? 'merchant' : (isDriver ? 'driver' : 'customer');
      debugPrint(
          'ℹ️ BottomNavbar: role from /users/me: $raw (merchant=$isMerchant, driver=$isDriver)');
      if (mounted && (_isMerchant != isMerchant || _isDriver != isDriver)) {
        await _checkUserRoleAndSetup();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  static bool _userIsMerchant(Map<String, dynamic> u) {
    final role = (u['role'] ?? u['accountType'] ?? '').toString().toLowerCase();
    final roles = (u['roles'] is List)
        ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final flags = {
      'isMerchant': u['isMerchant'] == true,
      'merchant': u['merchant'] == true,
      'merchantId': (u['merchantId'] ?? '').toString().isNotEmpty,
    };
    return role == 'merchant' ||
        roles.contains('merchant') ||
        flags.values.any((v) => v == true);
  }

  static bool _userIsDriver(Map<String, dynamic> u) {
    final role = (u['role'] ?? u['accountType'] ?? '').toString().toLowerCase();
    final roles = (u['roles'] is List)
        ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final flags = {
      'isDriver': u['isDriver'] == true,
      'driver': u['driver'] == true,
      'driverId': (u['driverId'] ?? '').toString().isNotEmpty,
    };
    return role == 'driver' ||
        roles.contains('driver') ||
        flags.values.any((v) => v == true);
  }

  Future<void> _checkUserRoleAndSetup() async {
     final prefs = await SharedPreferences.getInstance();
     // Read role from persisted prefs. Default to customer if missing/invalid.
     final raw = (prefs.getString('user_role') ?? prefs.getString('role') ?? '')
         .toLowerCase()
         .trim();
     // Only treat as merchant/driver when explicitly set; otherwise default to customer.
     _isMerchant = raw == 'merchant';
     _isDriver = raw == 'driver';
     // (anything else → customer: _isMerchant and _isDriver both false)
     
     debugPrint("ℹ️ BottomNavbar: role='$raw', _isMerchant=$_isMerchant, _isDriver=$_isDriver (default=customer)");

     // Home page: DriverDashboard for drivers, Homepage for others
     final homePage = _isDriver 
         ? DriverDashboard()
         : Vero360Homepage(email: widget.email);

     _pages = [
       homePage,
       MarketPage(cartService: cartService),
       const AuthGuard(
         featureName: 'Messages',
         showChildBehindDialog: true,
         child: ChatListPage(),
       ),
       AuthGuard(
         featureName: 'Cart',
         showChildBehindDialog: true,
         child: CartPage(cartService: cartService),
       ),
       // Profile/Dashboard: merchants see dashboard, drivers see profile, customers see profile
       AuthGuard(
         featureName: _isMerchant ? 'Dashboard' : 'Profile',
         showChildBehindDialog: true,
         child: _isMerchant
             ? MarketplaceMerchantDashboard(
                 email: widget.email,
                 onBackToHomeTab: () {
                   setState(() => _selectedIndex = 0);
                 },
                 embeddedInMainNav: true,
               )
             : const ProfilePage(),
       ),
     ];
  
     if (_isMerchant && mounted) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) _redirectMerchant(prefs);
       });
     }
   }

  void _redirectMerchant(SharedPreferences prefs) {
    final service =
        (prefs.getString('merchant_service') ?? '').toLowerCase();
    final email = prefs.getString('email') ?? widget.email;

    Widget page = switch (service) {
      'food' => FoodMerchantDashboard(email: email),
      'taxi' => DriverDashboard(),
      'accommodation' => AccommodationMerchantDashboard(email: email),
      'courier' => CourierMerchantDashboard(email: email),
      _ => MarketplaceMerchantDashboard(email: email, onBackToHomeTab: () {  },),
    };

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => page),
      (route) => route.isFirst,
    );
  }

  void _onItemTapped(int index) {
    // Do not block tab changes on network/auth checks – this was causing
    // noticeable lag. We only use the latest known `_isLoggedIn` value here
    // and refresh auth state in the background.
    if (!_isLoggedIn && _tabIsProtected(index)) {
      _showAuthDialog();
      // Fire-and-forget refresh so state stays reasonably up to date.
      _refreshAuthState();
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _selectedIndex = index;
    });

    // Keep auth/role fresh without delaying navigation.
    _refreshAuthState();
  }

  /// Body when a protected tab is selected but user is not logged in must not show;
  /// we never set _selectedIndex to a protected tab when !_isLoggedIn (see _onItemTapped).
  Widget _buildBody() {
    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) {
      return const Center(child: CircularProgressIndicator());
    }
    return _pages[_selectedIndex];
  }

  void _showAuthDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Login Required"),
        content: const Text("Please login to access this feature."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/login');
              },
              child: const Text("Login")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _GlassPillNavBar(
            selectedIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: [
              const _NavItemData(icon: Icons.home_rounded, label: "Home"),
              const _NavItemData(icon: Icons.store_rounded, label: "Market"),
              const _NavItemData(icon: Icons.message_rounded, label: "Messages"),
              const _NavItemData(icon: Icons.shopping_cart_rounded, label: "Cart"),
              _NavItemData(
                icon: _isMerchant ? Icons.dashboard_rounded : Icons.person_rounded,
                label: _isMerchant ? "Dashboard" : "Profile",
              ),
            ],
            selectedGradient: const LinearGradient(
              colors: [_brandOrange, _brandOrangeDark],
            ),
            glowColor: _brandOrangeGlow,
            selectedIconColor: Colors.white,
            unselectedIconColor: Colors.black87,
            unselectedLabelColor: Colors.black54,
          ),
        ),
      ),
    );
  }
}

/// ================= GLASS NAV BAR =================

class _GlassPillNavBar extends StatelessWidget {
  const _GlassPillNavBar({
    required this.selectedIndex,
    required this.onTap,
    required this.items,
    required this.selectedGradient,
    required this.glowColor,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.unselectedLabelColor,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<_NavItemData> items;

  final Gradient selectedGradient;
  final Color glowColor;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final Color unselectedLabelColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(height: 82, color: Colors.white.withOpacity(0.55)),
          ),
          Container(
            height: 82,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ClipRect(
              child: Row(
                children: [
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _AnimatedNavButton(
                        data: items[i],
                        selected: i == selectedIndex,
                        onTap: () => onTap(i),
                        selectedGradient: selectedGradient,
                        glowColor: glowColor,
                        selectedIconColor: selectedIconColor,
                        unselectedIconColor: unselectedIconColor,
                        unselectedLabelColor: unselectedLabelColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedNavButton extends StatelessWidget {
  const _AnimatedNavButton({
    required this.data,
    required this.selected,
    required this.onTap,
    required this.selectedGradient,
    required this.glowColor,
    required this.selectedIconColor,
    required this.unselectedIconColor,
    required this.unselectedLabelColor,
  });

  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;
  final Gradient selectedGradient;
  final Color glowColor;
  final Color selectedIconColor;
  final Color unselectedIconColor;
  final Color unselectedLabelColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final canShowLabel = selected && w >= 92;

        return Center(
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: canShowLabel ? 14 : 10,
                vertical: 8,
              ),
              constraints: const BoxConstraints(
                minHeight: 44,
                maxHeight: 52,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: selected ? selectedGradient : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: glowColor.withOpacity(0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween:
                        Tween(begin: 1.0, end: selected ? 1.12 : 1.0),
                    duration: const Duration(milliseconds: 220),
                    builder: (_, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Icon(
                      data.icon,
                      size: 26,
                      color:
                          selected ? selectedIconColor : unselectedIconColor,
                    ),
                  ),
                  if (canShowLabel) ...[
                    const SizedBox(width: 8),
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}