import 'package:flutter/material.dart';

// Make sure these exist in your project (adjust names/paths if needed)
import 'package:vero360_app/Pages/Quickservices/Edu.dart';
import 'package:vero360_app/Pages/Quickservices/Health.dart';
import 'package:vero360_app/Pages/Quickservices/customerservice.dart';
import 'package:vero360_app/Pages/Quickservices/social.dart';

class MorePage extends StatelessWidget {
  const MorePage({Key? key}) : super(key: key);

  static const _brandOrange = Color(0xFFFF8A00);
  static const _brandOrangeSoft = Color(0xFFFFF4E6);
  static const _brandOrangeBorder = Color(0xFFFFE0B3);

  static void _openService(BuildContext context, String key) {
    Widget page;
    switch (key) {
      case 'education':
        page = const EducationPage();
        break;
      case 'health':
        page = const HealthPage();
        break;
      case 'vero_chat':
        page = const SocialPage();
        break;
      case 'mobile_money':
        // Replace with your real page later if you have one
        page = const CustomerServicePage();
        break;
      default:
        page = const CustomerServicePage();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final items = <_Mini>[
      const _Mini('education', 'Education', Icons.school_rounded),
      const _Mini('health', 'Health', Icons.local_hospital_rounded),
      const _Mini('vero_chat', 'Vero AI Chat', Icons.chat_rounded),
      const _Mini('mobile_money', 'Home Cleaning', Icons.cleaning_services_rounded),

      const _Mini('mobile_money', 'Vero Pay', Icons.account_balance_wallet_rounded),
      const _Mini('mobile_money', 'Charity', Icons.volunteer_activism_rounded),


    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('More Quick Services'),
        backgroundColor: _brandOrange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Container(
          decoration: BoxDecoration(
            color: _brandOrangeSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _brandOrangeBorder),
          ),
          padding: const EdgeInsets.all(12),
          child: _MiniIconsGrid(
            items: items,
            onOpen: (key) => _openService(context, key),
          ),
        ),
      ),
    );
  }
}

class _Mini {
  final String key;
  final String label;
  final IconData icon;
  const _Mini(this.key, this.label, this.icon);
}

class _MiniIconsGrid extends StatelessWidget {
  final List<_Mini> items;
  final void Function(String key) onOpen;

  const _MiniIconsGrid({
    Key? key,
    required this.items,
    required this.onOpen,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cross = width >= 1000 ? 6 : width >= 700 ? 5 : width >= 520 ? 4 : 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (context, i) {
        final m = items[i];
        return Material(
          color: Colors.white,
          elevation: 0,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onOpen(m.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // CIRCLE with icon INSIDE
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: _MoreCircle.borderColor),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                          color: Colors.black.withOpacity(0.07),
                        ),
                      ],
                    ),
                    child: Icon(m.icon, size: 28, color: _MoreCircle.iconColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    m.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoreCircle {
  static const iconColor = Color(0xFFFF8A00);
  static Color get borderColor => const Color(0xFFFF8A00).withOpacity(0.25);
}
