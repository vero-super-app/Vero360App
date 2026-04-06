import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:vero360_app/Home/driver_homepage.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/GernalServices/role_helper.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_guard.dart';

import '../../Home/homepage.dart';
import '../Marketplace/presentation/pages/main_marketPlace.dart';
import '../Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';

import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';

// Merchant dashboards
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_merchant_dashboard.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/AccomodationMerchant/accommodation_merchant_dashboard.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/VeroCourierMerchant/courier_merchant_dashboard.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────
const _kOrange      = Color(0xFFFF8A00);
const _kOrangeDark  = Color(0xFFE07000);
const _kOrangeDeep  = Color(0xFFC05800);
const _kOrangeGlow  = Color(0x40FF8A00);
const _kOrangeLight = Color(0xFFFFF0D9);
const _kNavBg       = Colors.white;
const _kNavBgDark   = Color(0xFF1A1A1A);
const _kIconOff     = Color(0xFFAAAAAA);
const _kLabelOff    = Color(0xFF999999);

class Bottomnavbar extends StatefulWidget {
  const Bottomnavbar({
    super.key,
    required this.email,
    this.initialIndex = 0,
  });
  final String email;
  /// Tab to show first (0–4). Use `4` to open merchant dashboard for food merchants.
  final int initialIndex;

  @override
  State<Bottomnavbar> createState() => _BottomnavbarState();
}

class _BottomnavbarState extends State<Bottomnavbar>
    with WidgetsBindingObserver {
  late int _selectedIndex;

  bool _isLoading = true;
  bool _isMerchant = false;
  bool _isDriver = false;
  bool _isLoggedIn = false;

  late List<Widget> _pages;

  final cartService = CartServiceProvider.getInstance();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 4);
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.authStateChanges().listen((_) => _refreshAuthState());
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _tabIsProtected(int index) => index >= 2;

  Future<void> _initialize() async {
    try {
      await _checkUserRoleAndSetup();
      await _refreshAuthState();
    } catch (e, st) {
      assert(() { debugPrint('BottomNavbar._initialize: $e\n$st'); return true; }());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAuthState() async {
    final loggedIn = await AuthHandler.isAuthenticated();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);
    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) {
      setState(() => _selectedIndex = 0);
    }
    if (loggedIn) await _fetchAndUpdateRoleFromServer();
  }

  Future<void> _fetchAndUpdateRoleFromServer() async {
    final token = await AuthHandler.getTokenForApi();
    if (token == null || token.isEmpty) return;
    try {
      final resp = await http.get(
        ApiConfig.endpoint('/users/me'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final decoded = json.decode(resp.body);
      final user = (decoded is Map && decoded['data'] is Map)
          ? Map<String, dynamic>.from(decoded['data'])
          : (decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{});
      final prefs = await SharedPreferences.getInstance();
      final backendRole = (user['role'] ?? '').toString().toLowerCase();
      final cachedRole = (prefs.getString('user_role') ?? '').toLowerCase();
      if (cachedRole.isNotEmpty && cachedRole != 'customer' && backendRole == 'customer') {
        await _putRoleToBackend(token, cachedRole); return;
      }
      if (backendRole == 'customer') {
        final firestoreRole = await _getRoleFromFirestore();
        if (firestoreRole != null && firestoreRole != 'customer' && firestoreRole != backendRole) {
          await prefs.setString('user_role', firestoreRole);
          await prefs.setString('role', firestoreRole);
          await _putRoleToBackend(token, firestoreRole);
          if (mounted) { await _checkUserRoleAndSetup(); setState(() {}); }
          return;
        }
      }
      final isMerchant = RoleHelper.isMerchant(user);
      final isDriver = !isMerchant && RoleHelper.isDriver(user);
      final newRole = isMerchant ? 'merchant' : (isDriver ? 'driver' : 'customer');
      if (cachedRole != newRole) { await prefs.setString('user_role', newRole); await prefs.setString('role', newRole); }
      if (mounted && (_isMerchant != isMerchant || _isDriver != isDriver)) { await _checkUserRoleAndSetup(); if (mounted) setState(() {}); }
    } catch (_) {}
  }

  Future<void> _putRoleToBackend(String token, String role) async {
    try { await http.put(ApiConfig.endpoint('/users/me'), headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json', 'Content-Type': 'application/json'}, body: json.encode({'role': role})).timeout(const Duration(seconds: 6)); } catch (_) {}
  }

  Future<String?> _getRoleFromFirestore() async {
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) return null;
      final doc = await FirebaseFirestore.instance.collection('users').doc(fbUser.uid).get();
      if (doc.exists && doc.data() != null) return (doc.data()!['role'] ?? '').toString().toLowerCase();
    } catch (_) {}
    return null;
  }

  Future<void> _checkUserRoleAndSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString('user_role') ?? prefs.getString('role') ?? '').toLowerCase().trim();
    _isMerchant = raw == 'merchant';
    _isDriver = raw == 'driver';

    final homePage = _isDriver
        ? Vero360DriverHomepage(email: widget.email)
        : Vero360Homepage(email: widget.email);

    _pages = [
      homePage,
      MarketPage(cartService: cartService),
      const AuthGuard(featureName: 'Messages', showChildBehindDialog: true, child: ChatListPage()),
      AuthGuard(featureName: 'Cart', showChildBehindDialog: true, child: CartPage(cartService: cartService)),
      AuthGuard(
        featureName: _isMerchant ? 'Dashboard' : 'Profile',
        showChildBehindDialog: true,
        child: _isMerchant ? _merchantProfileTab(prefs) : const ProfilePage(),
      ),
    ];

    if (_isMerchant && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _redirectMerchant(prefs); });
    }
  }

  Widget _merchantProfileTab(SharedPreferences prefs) {
    final email = prefs.getString('email') ?? widget.email;
    final key = normalizeMerchantServiceKey(prefs.getString('merchant_service')) ?? 'marketplace';
    return switch (key) {
      'food' => FoodMerchantDashboard(email: email),
      'accommodation' => AccommodationMerchantDashboard(email: email),
      'courier' => CourierMerchantDashboard(email: email),
      _ => MarketplaceMerchantDashboard(email: email, onBackToHomeTab: () => setState(() => _selectedIndex = 0), embeddedInMainNav: true),
    };
  }

  void _redirectMerchant(SharedPreferences prefs) {
    final key = normalizeMerchantServiceKey(prefs.getString('merchant_service')) ?? 'marketplace';
    final email = prefs.getString('email') ?? widget.email;
    if (key == 'food') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => Bottomnavbar(email: email, initialIndex: 4),
        ),
        (route) => false,
      );
      return;
    }
    Widget page = switch (key) {
      'accommodation' => AccommodationMerchantDashboard(email: email),
      'courier' => CourierMerchantDashboard(email: email),
      _ => MarketplaceMerchantDashboard(email: email, onBackToHomeTab: () {}),
    };
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => page), (route) => false);
  }

  void _onItemTapped(int index) {
    if (!_isLoggedIn && _tabIsProtected(index)) {
      _showAuthDialog();
      _refreshAuthState();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _selectedIndex = index);
    _refreshAuthState();
  }

  Widget _buildBody() {
    if (!_isLoggedIn && _tabIsProtected(_selectedIndex)) return const Center(child: CircularProgressIndicator());
    return _pages[_selectedIndex];
  }

  void _showAuthDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Login Required', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('Please log in to access this feature.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () { Navigator.pop(context); Navigator.pushNamed(context, '/login'); },
            child: const Text('Log In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: _kOrange)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,                    // body goes under the nav for depth
      body: _buildBody(),
      bottomNavigationBar: VeroMainNavigationBar(
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
        isDark: isDark,
        isMerchant: _isMerchant,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// NAV ITEM DATA (shared with FoodPage / shells)
// ─────────────────────────────────────────────
class VeroNavItemData {
  final IconData icon;
  final String label;
  const VeroNavItemData({required this.icon, required this.label});
}

List<VeroNavItemData> veroMainNavItems({required bool isMerchant}) => [
      const VeroNavItemData(icon: Icons.home_rounded, label: 'Home'),
      const VeroNavItemData(icon: Icons.store_rounded, label: 'Market'),
      const VeroNavItemData(icon: Icons.chat_bubble_rounded, label: 'Messages'),
      const VeroNavItemData(icon: Icons.shopping_bag_rounded, label: 'Cart'),
      VeroNavItemData(
        icon: isMerchant ? Icons.dashboard_rounded : Icons.person_rounded,
        label: isMerchant ? 'Dashboard' : 'Profile',
      ),
    ];

/// Opens the main app shell ([Bottomnavbar]) on a given tab (0–4).
void openVeroMainShell(BuildContext context, {required String email, int tabIndex = 0}) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => Bottomnavbar(
        email: email,
        initialIndex: tabIndex.clamp(0, 4),
      ),
    ),
    (route) => false,
  );
}

// ─────────────────────────────────────────────
// VERO NAV BAR  — floating frosted pill
// ─────────────────────────────────────────────
class VeroMainNavigationBar extends StatelessWidget {
  const VeroMainNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.isDark,
    required this.isMerchant,
  });

  /// Highlighted tab; pass `null` when no tab applies (e.g. standalone Food screen).
  final int? selectedIndex;
  final ValueChanged<int> onTap;
  final bool isDark;
  final bool isMerchant;

  @override
  Widget build(BuildContext context) {
    final items = veroMainNavItems(isMerchant: isMerchant);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withOpacity(0.72)
                    : Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kOrange.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (int i = 0; i < items.length; i++)
                    Expanded(
                      child: _VeroNavButton(
                        item: items[i],
                        selected:
                            selectedIndex != null && i == selectedIndex,
                        isDark: isDark,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// INDIVIDUAL NAV BUTTON  — morph + ripple + label
// ─────────────────────────────────────────────
class _VeroNavButton extends StatefulWidget {
  const _VeroNavButton({
    required this.item,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final VeroNavItemData item;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_VeroNavButton> createState() => _VeroNavButtonState();
}

class _VeroNavButtonState extends State<_VeroNavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Selection animations
  late Animation<double>  _pillScale;
  late Animation<double>  _pillOpacity;
  late Animation<double>  _iconBounce;
  late Animation<double>  _labelFade;
  late Animation<Offset>  _labelSlide;
  late Animation<double>  _iconShift;   // icon moves up when selected
  late Animation<Color?>  _iconColor;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _buildAnimations();
    if (widget.selected) _ctrl.value = 1.0;
  }

  void _buildAnimations() {
    _pillScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.elasticOut)),
    );
    _pillOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _iconBounce = Tween<double>(begin: 1.0, end: 1.0).animate(_ctrl); // handled via iconShift
    _labelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.35, 0.85, curve: Curves.easeOut)),
    );
    _labelSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic)),
    );
    _iconShift = Tween<double>(begin: 0.0, end: -3.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );
    _iconColor = ColorTween(begin: _kIconOff, end: Colors.white).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.1, 0.6, curve: Curves.easeOut)),
    );
  }

  @override
  void didUpdateWidget(covariant _VeroNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          final iconColor = _iconColor.value ?? _kIconOff;
          final labelColor = widget.isDark ? Colors.white : Colors.white;
          final unselIconColor = widget.isDark ? Colors.white60 : _kIconOff;

          return AnimatedScale(
            scale: _pressed ? 0.90 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: SizedBox(
              height: 70,
              child: Stack(alignment: Alignment.center, children: [
                // ── AMBER PILL BACKGROUND ──
                ScaleTransition(
                  scale: _pillScale,
                  child: FadeTransition(
                    opacity: _pillOpacity,
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kOrange, _kOrangeDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _kOrange.withOpacity(0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── ICON + LABEL STACK ──
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // Icon
                  Transform.translate(
                    offset: Offset(0, _iconShift.value),
                    child: Icon(
                      widget.item.icon,
                      size: 24,
                      color: widget.selected ? iconColor : unselIconColor,
                    ),
                  ),

                  // Label (slides up + fades in when selected)
                  if (widget.selected)
                    SlideTransition(
                      position: _labelSlide,
                      child: FadeTransition(
                        opacity: _labelFade,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            widget.item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: labelColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 3 + 13), // preserve height to prevent layout shift
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}