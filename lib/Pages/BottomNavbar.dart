import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/settings/Settings.dart';

import 'homepage.dart';
import '../Pages/marketPlace.dart';
import '../Pages/cartpage.dart';
import 'package:vero360_app/screens/chat_list_page.dart';

import '../services/cart_services.dart';
import 'package:vero360_app/providers/cart_service_provider.dart';

// Merchant dashboards
import 'package:vero360_app/Pages/MerchantDashboards/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/food_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/taxi_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/courier_merchant_dashboard.dart';

class Bottomnavbar extends StatefulWidget {
  const Bottomnavbar({super.key, required this.email});
  final String email;

  @override
  State<Bottomnavbar> createState() => _BottomnavbarState();
}

class _BottomnavbarState extends State<Bottomnavbar> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  bool _isLoading = true;
  bool _isMerchant = false;
  bool _isLoggedIn = false;

  late List<Widget> _pages;

  // ✅ Use CartService singleton from provider
  final cartService = CartServiceProvider.getInstance();

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandOrangeDark = Color(0xFFE07000);
  static const Color _brandOrangeGlow = Color(0xFFFFE2BF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // React immediately when Firebase sign-in/out happens
    FirebaseAuth.instance.authStateChanges().listen((_) => _refreshAuthState());

    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If user logs out in another page, refresh when app resumes
    if (state == AppLifecycleState.resumed) {
      _refreshAuthState();
    }
  }

  bool _tabIsProtected(int index) => index == 2 || index == 3 || index == 4;

  String _featureName(int index) {
    switch (index) {
      case 2:
        return 'Messages';
      case 3:
        return 'Cart';
      case 4:
        return 'Dashboard';
      default:
        return 'this feature';
    }
  }

  String? _readToken(SharedPreferences p) {
    return p.getString('jwt_token') ??
        p.getString('token') ??
        p.getString('authToken') ??
        p.getString('jwt');
  }

  Future<void> _initialize() async {
    await _refreshAuthState();
    await _checkUserRoleAndSetup();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _readToken(prefs);
    final fbUser = FirebaseAuth.instance.currentUser;

    final loggedIn =
        (token != null && token.trim().isNotEmpty) || (fbUser != null);

    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);

    // If user logged out while on protected tab, force Home
    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) {
      setState(() => _selectedIndex = 0);
    }
  }

  Future<void> _checkUserRoleAndSetup() async {
    final prefs = await SharedPreferences.getInstance();

    // If not logged in, do NOT treat as merchant (prevents wrong redirect)
    final role = _isLoggedIn
        ? ((prefs.getString('role') ?? prefs.getString('user_role') ?? '')
            .toLowerCase())
        : '';

    setState(() => _isMerchant = role == 'merchant');

    _pages = [
      Vero360Homepage(email: widget.email),
      MarketPage(cartService: cartService),

      // protected tabs
      const ChatListPage(),
      CartPage(cartService: cartService),
      SettingsPage(
        onBackToHomeTab: () => setState(() => _selectedIndex = 0),
      ),
    ];

    if (_isMerchant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redirectMerchantToServiceDashboard(prefs);
      });
    }
  }

  void _redirectMerchantToServiceDashboard(SharedPreferences prefs) {
    final merchantService =
        (prefs.getString('merchant_service') ?? '').toLowerCase();
    final email = prefs.getString('email') ?? widget.email;

    Widget merchantDashboard;
    switch (merchantService) {
      case 'marketplace':
        merchantDashboard = MarketplaceMerchantDashboard(email: email);
        break;
      case 'food':
        merchantDashboard = FoodMerchantDashboard(email: email);
        break;
      case 'taxi':
        merchantDashboard = TaxiMerchantDashboard(email: email);
        break;
      case 'accommodation':
        merchantDashboard = AccommodationMerchantDashboard(email: email);
        break;
      case 'courier':
        merchantDashboard = CourierMerchantDashboard(email: email);
        break;
      default:
        merchantDashboard = MarketplaceMerchantDashboard(email: email);
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => merchantDashboard),
      (_) => false,
    );
  }

  Future<bool> _onWillPop() async {
    // ✅ Android back should go to Home tab first
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false;
    }
    return true; // now allow app to close
  }

  void _onItemTapped(int index) async {
    // Always re-check auth state right before decision (fixes “still access after logout”)
    await _refreshAuthState();

    final prefs = await SharedPreferences.getInstance();
    final role = _isLoggedIn
        ? ((prefs.getString('role') ?? prefs.getString('user_role') ?? '')
            .toLowerCase())
        : '';

    if (role == 'merchant') {
      _redirectMerchantToServiceDashboard(prefs);
      return;
    }

    // ✅ block protected tabs when logged out
    if (!_isLoggedIn && _tabIsProtected(index)) {
      _showAuthDialog(_featureName(index));
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _selectedIndex = index);
  }

  void _showAuthDialog(String feature) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text("Login Required"),
        content: Text("You need to log in or sign up to access $feature."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/login');
            },
            child: const Text("Login"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/signup');
            },
            child: const Text("Sign Up"),
          ),
        ],
      ),
    );
  }

  Widget _guardedBody() {
    // merchant should never stay here
    if (_isMerchant) {
      return const Center(child: CircularProgressIndicator(color: _brandOrange));
    }

    // second line of defense (deep links / weird state)
    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showAuthDialog(_featureName(_selectedIndex));
          setState(() => _selectedIndex = 0);
        }
      });
      return _pages[0];
    }

    return _pages[_selectedIndex];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _brandOrange)),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: _guardedBody(),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _GlassPillNavBar(
              selectedIndex: _selectedIndex,
              onTap: _onItemTapped,
              items: const [
                _NavItemData(icon: Icons.home_rounded, label: "Home"),
                _NavItemData(icon: Icons.store_rounded, label: "Market"),
                _NavItemData(icon: Icons.message_rounded, label: "Messages"),
                _NavItemData(icon: Icons.shopping_cart_rounded, label: "Cart"),
                _NavItemData(icon: Icons.dashboard_rounded, label: "Dashboard"),
              ],
              selectedGradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_brandOrange, _brandOrangeDark],
              ),
              glowColor: _brandOrangeGlow,
              selectedIconColor: Colors.white,
              unselectedIconColor: Colors.black87,
              unselectedLabelColor: Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}

/// Glassy container + animated pill buttons
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
            child: Container(
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                border: Border.all(
                  color: Colors.white.withOpacity(0.65),
                  width: 1,
                ),
              ),
            ),
          ),
          Container(
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.55),
                  Colors.white.withOpacity(0.34),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
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
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final bool canShowLabel = selected && w >= 84;

          return InkWell(
            onTap: onTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: canShowLabel ? 14 : 10,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: selected ? selectedGradient : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: glowColor.withOpacity(0.55),
                          blurRadius: 18,
                          spreadRadius: 1,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: selected ? 1.18 : 1.0),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: Icon(
                        data.icon,
                        size: 26,
                        color: selected ? selectedIconColor : unselectedIconColor,
                      ),
                    ),
                  ),
                  if (canShowLabel) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: w - 40),
                      child: Text(
                        data.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}
