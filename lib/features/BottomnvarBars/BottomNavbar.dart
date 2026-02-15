import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_guard.dart';

import '../../Home/homepage.dart';
import '../Marketplace/presentation/pages/main_marketPlace.dart';
import '../Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/settings/Settings.dart';

import '../Cart/CartService/cart_services.dart';
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
    await _refreshAuthState();
    await _checkUserRoleAndSetup();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshAuthState() async {
    final loggedIn = await AuthHandler.isAuthenticated();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);

    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) {
      setState(() => _selectedIndex = 0);
    }
  }

  Future<void> _checkUserRoleAndSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final role =
        _isLoggedIn ? (prefs.getString('role') ?? '').toLowerCase() : '';

    _isMerchant = role == 'merchant';

    _pages = [
      Vero360Homepage(email: widget.email),
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
      // Customers see Profile; merchants are redirected and never see this tab
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

    if (_isMerchant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redirectMerchant(prefs);
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
      (_) => false,
    );
  }

  void _onItemTapped(int index) async {
    await _refreshAuthState();

    if (!_isLoggedIn && _tabIsProtected(index)) {
      _showAuthDialog();
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _selectedIndex = index;
    });
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