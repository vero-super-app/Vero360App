import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'driver_dashboard_home.dart';
import 'driver_profile_settings.dart';

class DriverDashboardShell extends StatefulWidget {
  const DriverDashboardShell({super.key});

  @override
  State<DriverDashboardShell> createState() => _DriverDashboardShellState();
}

class _DriverDashboardShellState extends State<DriverDashboardShell> {
  int _selectedIndex = 0;

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandOrangeDark = Color(0xFFE07000);
  static const Color _brandOrangeGlow = Color(0xFFFFE2BF);

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const DriverDashboardHome(),
      _buildComingSoonPage('Trips', 'Manage your trips'),
      _buildComingSoonPage('Earnings', 'View earnings'),
      _buildComingSoonPage('Messages', 'Driver messages'),
      const DriverProfileSettings(),
    ];
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedIndex = index;
    });
  }

  PreferredSizeWidget _buildSettingsAppBar(BuildContext context) {
    return AppBar(
      title: const Text('Profile'),
      backgroundColor: _brandOrange,
      elevation: 0,
      centerTitle: false,
    );
  }

  Widget _buildComingSoonPage(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 4 ? _buildSettingsAppBar(context) : null,
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
              _NavItemData(icon: Icons.local_taxi_rounded, label: "Trips"),
              _NavItemData(icon: Icons.wallet_rounded, label: "Earnings"),
              _NavItemData(icon: Icons.message_rounded, label: "Messages"),
              _NavItemData(icon: Icons.settings_rounded, label: "Settings"),
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

/// ================= GLASS NAV BAR (Reusable from Bottomnavbar) =================

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
              height: 82,
              color: Colors.white.withValues(alpha: 0.55),
            ),
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
                          color: glowColor.withValues(alpha: 0.45),
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
