// lib/Pages/bottom_navbar.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/screens/chat_list_page.dart';

import 'homepage.dart';
import '../Pages/marketPlace.dart';
import '../Pages/cartpage.dart';
import '../Pages/Home/Profilepage.dart';
import '../services/cart_services.dart';
// Add these imports after the existing ones:
import 'package:vero360_app/Pages/MerchantDashboards/food_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/taxi_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/Pages/MerchantDashboards/courier_merchant_dashboard.dart';
import 'package:vero360_app/Pages/merchantbottomnavbar.dart';

class Bottomnavbar extends StatefulWidget {
  const Bottomnavbar({super.key, required this.email});

  final String email;

  @override
  State<Bottomnavbar> createState() => _BottomnavbarState();
}

class _BottomnavbarState extends State<Bottomnavbar> {
  int _selectedIndex = 0;
  late List<Widget> _pages = [];
  bool _isInitialized = false;
  bool _isMerchant = false;
  bool _isLoading = true;

  final cartService = CartService('https://heflexitservice.co.za', apiPrefix: 'vero');

  // ====== Brand (ORANGE) ======
  static const Color _brandOrange = Color(0xFFFF8A00); // primary
  static const Color _brandOrangeDark = Color(0xFFE07000); // deeper shade
  static const Color _brandOrangeGlow = Color(0xFFFFE2BF); // soft glow

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Check user role and set up appropriate pages
    await _checkUserRoleAndSetup();
    
    setState(() {
      _isLoading = false;
      _isInitialized = true;
    });
  }

  Future<void> _checkUserRoleAndSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role') ?? '';
    final merchantService = prefs.getString('merchant_service') ?? '';
    
    setState(() {
      _isMerchant = role == 'merchant';
    });

    if (_isMerchant) {
      // Merchant should be redirected, but set up placeholder pages for safety
      _pages = [
        Vero360Homepage(email: widget.email),
        MarketPage(cartService: cartService),
        ChatListPage(),
        CartPage(cartService: cartService),
        ProfilePage(),
      ];
      
      // If merchant is here by mistake, redirect them
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redirectMerchantToServiceDashboard(prefs);
      });
    } else {
      // Customer: Set up normal customer pages
      _pages = [
        Vero360Homepage(email: widget.email),
        MarketPage(cartService: cartService),
        ChatListPage(),
        CartPage(cartService: cartService),
        ProfilePage(),
      ];
    }
  }

  void _redirectMerchantToServiceDashboard(SharedPreferences prefs) async {
    final merchantService = prefs.getString('merchant_service') ?? '';
    final email = prefs.getString('email') ?? widget.email;
    
    // Import merchant dashboards
    Widget merchantDashboard;
    
    switch (merchantService) {
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
        merchantDashboard = MerchantBottomnavbar(email: email);
    }
    
    // Navigate to merchant dashboard
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => merchantDashboard),
        (_) => false,
      );
    }
  }

  void _onItemTapped(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    final role = prefs.getString('role') ?? '';

    // If user is merchant, redirect them
    if (role == 'merchant') {
      _redirectMerchantToServiceDashboard(prefs);
      return;
    }

    // Protected indices: 2 (Messages), 3 (Cart), 4 (Dashboard)
    if (token == null && index >= 2) {
      _showAuthDialog(index);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _selectedIndex = index);
  }

  void _showAuthDialog(int index) {
    String featureName = "";
    switch (index) {
      case 2:
        featureName = "Messages";
        break;
      case 3:
        featureName = "Cart";
        break;
      case 4:
        featureName = "Dashboard";
        break;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Login Required"),
        content: Text("You need to log in or sign up to access $featureName."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            child: const Text("Login"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking role
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: _brandOrange),
              const SizedBox(height: 20),
              Text(
                _isMerchant 
                  ? 'Redirecting to merchant dashboard...'
                  : 'Loading...',
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // If merchant is somehow still here (should have been redirected), show message
    if (_isMerchant) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.swap_horiz,
                size: 60,
                color: _brandOrange,
              ),
              const SizedBox(height: 20),
              const Text(
                'Redirecting to Merchant Dashboard...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _brandOrange,
                ),
              ),
              const SizedBox(height: 10),
              const CircularProgressIndicator(color: _brandOrange),
            ],
          ),
        ),
      );
    }

    // For customers, show the normal bottom navbar
    return Scaffold(
      body: _pages[_selectedIndex],
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
            // ORANGE selected pill
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
          // Glass blur
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 1),
              ),
            ),
          ),

          // Subtle gradient + shadow (kept neutral so pill pops)
          Container(
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.34)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
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
                          color: glowColor.withValues(alpha: 0.55),
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
                  // Icon bounce
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
                  // Label
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: canShowLabel
                        ? Padding(
                            key: const ValueKey('label'),
                            padding: const EdgeInsets.only(left: 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: w - 40),
                              child: const Text(
                                '',
                              ),
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('nolabel'),
                            width: 0,
                            height: 0,
                          ),
                  ),
                  if (canShowLabel)
                    const SizedBox(width: 8),
                  if (canShowLabel)
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