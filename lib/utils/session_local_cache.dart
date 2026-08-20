import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/guest_booking_local_cache.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_review_service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_seller_loader.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/marketplace_merchant_dashboard.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_products_page.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_cache.dart';
import 'package:vero360_app/GernalServices/chat_outbox.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/GernalServices/blocked_merchant_service.dart';
import 'package:vero360_app/GernalServices/merchant_identity.dart';
import 'package:vero360_app/GernalServices/local_message_database.dart';
import 'package:vero360_app/GernalServices/profile_photo_cache.dart';
import 'package:vero360_app/features/ride_share/services/active_ride_storage.dart';

/// Wipes device-local Marketplace / cart / messaging state that must not follow
/// the next account on the same phone (static memory + SharedPreferences).
class SessionLocalCache {
  SessionLocalCache._();

  static const _exactKeys = <String>[
    'merchant_business_description',
    'merchant_shop_opening_hours',
    'merchant_shop_opening_days',
    // Keep marketplace_merchant_guide_* across logout so Finish sticks after re-login.
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
    'active_ride_id',
    'active_ride_role',
    'active_ride_status',
    'active_ride_taxi_id',
    'nearby_taxis_cache',
    'has_driver_profile',
  ];

  static const _prefixes = <String>[
    'marketplace_personalization_v1_',
    'merchant_my_items_cache_v1_',
    'merchant_opening_hours_v1_',
    'merchant_opening_days_v1_',
    'merchant_review_prompted_v1_',
    'chat_list_pinned_',
    'chat_list_hidden_',
    'guest_paid_stay_bookings_v1_',
  ];

  static Future<void> clearOnLogout() async {
    await _clearLocalState(accountDeleted: false);
  }

  /// Stronger wipe after account deletion so a new signup on this phone
  /// cannot reopen the previous chats / rides from Hive or prefs.
  static Future<void> clearOnAccountDeletion() async {
    await _clearLocalState(accountDeleted: true);
  }

  static Future<void> _clearLocalState({required bool accountDeleted}) async {
    CartService.clearSessionCache();
    CartServiceProvider.clear();
    MerchantSellerLoader.clearSessionCaches();
    MerchantReviewService.clearAllCache();
    MerchantProductsPage.clearSessionCaches();
    MarketplaceMerchantDashboard.clearSessionCaches();
    BackendChatService.clearAuthCache();
    BlockedMerchantService.clearSessionCache();
    MerchantIdentityStore.clear();

    // Fire-and-forget socket close — do not block Settings logout.
    unawaited(
      BackendMessagingSocket.disconnect().catchError((_) {}),
    );

    try {
      await ProfilePhotoCache.clear();
    } catch (_) {}
    try {
      await GuestBookingLocalCache.clearOnLogout();
    } catch (_) {}
    try {
      await NotificationStore.instance.clearForLogout();
    } catch (_) {}
    try {
      await ActiveRideStorage.clear();
    } catch (_) {}
    try {
      await LocalMessageDatabase.clearAllBoxes();
    } catch (_) {}
    try {
      if (accountDeleted) {
        await BackendMessagingCache.clearAll();
      } else {
        await BackendMessagingCache.clearSessionThreads();
      }
    } catch (_) {}
    try {
      await ChatOutbox.clearAll();
    } catch (_) {}

    try {
      final sp = await SharedPreferences.getInstance();
      final toRemove = <String>[
        ..._exactKeys,
        'guest_paid_stay_bookings_v1',
        'vero360_notifications',
        for (final key in sp.getKeys())
          if (_prefixes.any(key.startsWith)) key,
      ];
      await Future.wait(toRemove.toSet().map(sp.remove));
    } catch (_) {}
  }
}
