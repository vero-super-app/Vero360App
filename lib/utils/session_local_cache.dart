import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_seller_loader.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/profile_photo_cache.dart';

/// Wipes device-local Marketplace / cart / messaging state that must not follow
/// the next account on the same phone (static memory + SharedPreferences).
class SessionLocalCache {
  SessionLocalCache._();

  static const _exactKeys = <String>[
    'merchant_business_description',
    'merchant_shop_opening_hours',
    'merchant_shop_opening_days',
    'marketplace_merchant_guide_v1_done',
    'marketplace_merchant_guide_show_on_next_open',
    'guest_cart_items',
    'firebase_token',
    'merchant_profile_phone',
    'merchant_nest_user_id',
    'app_pin_hash',
    'app_pin_salt',
    'profilepicture',
    'profilepicture_local_path',
    'profilepicture_cached_for_url',
    'profilepicture_cached_for_uid',
    'userId',
    'user_id',
    'messaging_firebase_uid',
  ];

  static const _prefixes = <String>[
    'marketplace_personalization_v1_',
    'merchant_my_items_cache_v1_',
    'merchant_opening_hours_v1_',
    'merchant_opening_days_v1_',
    'merchant_review_prompted_v1_',
    'chat_list_pinned_',
    'chat_list_hidden_',
  ];

  static Future<void> clearOnLogout() async {
    CartService.clearSessionCache();
    CartServiceProvider.clear();
    MerchantSellerLoader.clearSessionCaches();
    MerchantReviewService.clearAllCache();
    MerchantProductsPage.clearSessionCaches();
    MarketplaceMerchantDashboard.clearSessionCaches();
    BackendChatService.clearAuthCache();
    try {
      await BackendMessagingSocket.disconnect();
    } catch (_) {}
    await ProfilePhotoCache.clear();

    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in _exactKeys) {
        await sp.remove(k);
      }
      for (final key in sp.getKeys().toList()) {
        if (_prefixes.any(key.startsWith)) {
          await sp.remove(key);
        }
      }
    } catch (_) {}
  }
}
