import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/GernalServices/merchant_identity.dart';
import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/GernalServices/role_session_service.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart'
    show openVeroMainShell;
import 'package:vero360_app/utils/toasthelper.dart';

/// Customer ↔ merchant on the same Firebase uid.
///
/// Backend: PUT `/users/me` `{ role, merchantService? }` and Firestore
/// `users/{uid}.role`. Shop docs stay; only the active session role changes.
class SellerMode {
  const SellerMode._();

  static const _orange = Color(0xFFFF8A00);
  static const _navy = Color(0xFF16284C);

  static const _verticals = <({String key, String name, String hint, IconData icon})>[
    (
      key: 'marketplace',
      name: 'Marketplace',
      hint: 'Products, shops, and classifieds',
      icon: Icons.store_rounded,
    ),
    (
      key: 'food',
      name: 'Food & restaurants',
      hint: 'Menus, orders, and delivery',
      icon: Icons.restaurant_rounded,
    ),
    (
      key: 'accommodation',
      name: 'Accommodation',
      hint: 'Rooms, stays, and bookings',
      icon: Icons.hotel_rounded,
    ),
  ];

  static String? cachedVertical(SharedPreferences prefs, {String? uid}) {
    final id = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    return normalizeMerchantServiceKey(
          id.isEmpty
              ? null
              : prefs.getString(MerchantIdentityStore.prefsServiceKeyForUid(id)),
        ) ??
        normalizeMerchantServiceKey(
          prefs.getString(RoleSessionService.intendedServiceKey),
        ) ??
        normalizeMerchantServiceKey(prefs.getString('merchant_service'));
  }

  static Future<void> remountShell(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final email = (prefs.getString('email') ?? '').trim();
    if (!context.mounted) return;
    openVeroMainShell(
      context,
      email: email,
      tabIndex: 4,
    );
  }

  /// Turn seller mode on. Reuses the last vertical for this uid when present.
  static Future<bool> enter(
    BuildContext context, {
    String? merchantService,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      if (context.mounted) {
        ToastHelper.showCustomToast(
          context,
          'Sign in to start selling.',
          isSuccess: false,
          errorMessage: '',
        );
      }
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = cachedVertical(prefs, uid: user.uid);
    var service = normalizeMerchantServiceKey(merchantService) ?? cached;
    if (!isKnownMerchantServiceKey(service)) {
      if (!context.mounted) return false;
      service = await pickVertical(context);
    }
    if (!isKnownMerchantServiceKey(service) || !context.mounted) return false;

    final ok = await RoleSessionService.switchToMerchant(
      merchantService: service!,
    );
    if (!context.mounted) return ok;
    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Could not switch to seller mode. Try again.',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    }
    ToastHelper.showCustomToast(
      context,
      'Seller mode is on. Set up your shop from the dashboard.',
      isSuccess: true,
      errorMessage: '',
    );
    await remountShell(context);
    return true;
  }

  /// Turn seller mode off and shop as a customer. Shop listings stay on this uid.
  static Future<bool> exit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Shop as a customer?'),
            content: const Text(
              'You will browse and buy as a customer. Your shop stays on this account — switch Seller mode back on anytime to sell again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Switch'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return false;

    final ok = await RoleSessionService.switchToCustomerShopping();
    if (!context.mounted) return ok;
    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Could not switch to shopping. Try again.',
        isSuccess: false,
        errorMessage: '',
      );
      return false;
    }
    ToastHelper.showCustomToast(
      context,
      'Switched to shopping as a customer',
      isSuccess: true,
      errorMessage: '',
    );
    await remountShell(context);
    return true;
  }

  static Future<String?> pickVertical(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(ctx).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'What do you want to sell?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Same account — we just switch your role to merchant and open the matching dashboard.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              for (final item in _verticals) ...[
                _VerticalTile(
                  icon: item.icon,
                  name: item.name,
                  hint: item.hint,
                  onTap: () => Navigator.pop(ctx, item.key),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VerticalTile extends StatelessWidget {
  const _VerticalTile({
    required this.icon,
    required this.name,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SellerMode._orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SellerMode._orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
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
