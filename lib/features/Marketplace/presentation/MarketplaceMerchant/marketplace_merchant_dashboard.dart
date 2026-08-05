import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';

import 'package:crypto/crypto.dart' show sha256;

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/PostlatestArrival.dart';
import 'package:vero360_app/features/Promotions/presentation/Postpromotion.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace_moderation.dart';

import 'package:vero360_app/GernalServices/merchant_service_helper.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_seller_loader.dart';
import 'package:vero360_app/GernalServices/profile_photo_cache.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/Gernalproviders/cart_service_provider.dart';
import 'package:vero360_app/widgets/vero_thumb_image.dart';
import 'package:vero360_app/settings/Settings.dart';
import 'package:vero360_app/utils/toasthelper.dart';
// Add login screen import (using your correct path)
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/kyc_verification_screen.dart';
import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart'
    show veroFloatingNavClearance;

import 'package:vero360_app/Home/homepage.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/main_marketPlace.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/cartpage.dart';
import 'package:vero360_app/GernalScreens/chat_list_page.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/utils/app_wallet_pin.dart';

import 'package:vero360_app/Home/myorders.dart';
import 'package:vero360_app/Home/post_story_page.dart';
import 'package:vero360_app/Home/story_ring_widget.dart';
import 'package:vero360_app/GeneralPages/ToRefund.dart';
import 'package:vero360_app/GeneralPages/Toreceive.dart';
import 'package:vero360_app/GeneralPages/Toship.dart';
import 'package:vero360_app/Gernalproviders/notification_store.dart';
import 'package:vero360_app/GernalServices/order_service.dart';
import 'package:vero360_app/GeneralModels/order_model.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_history_screen.dart';

import 'package:intl/intl.dart'; // G£à NEW

// ----------------- G£à PRICE FORMAT HELPERS (MWK with commas) -----------------
final NumberFormat _mwk0Fmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);
final NumberFormat _mwk2Fmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 2);

num _asNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  final s = v.toString().replaceAll(',', '').trim();
  return num.tryParse(s) ?? 0;
}

String mwk0(dynamic v) => _mwk0Fmt.format(_asNum(v)); // MWK 12,500
String mwk2(dynamic v) => _mwk2Fmt.format(_asNum(v)); // MWK 12,500.00
// ---------------------------------------------------------------------------

/// GÇ£Your ItemsGÇ¥ / GÇ£My ItemsGÇ¥ grids: taller cells on narrow screens + large text scale
/// so [_ModernItemMiniCard] / [_ItemCard] never bottom-overflow inside the cell.
SliverGridDelegate _merchantItemsGridDelegate(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final textScale =
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.8).scale(14) /
          14.0;

  // Lower ratio = taller cells (more room for status / reject reason).
  var ratio = 0.72;
  var spacing = 12.0;
  if (w < 330) {
    ratio = 0.48;
    spacing = 8;
  } else if (w < 360) {
    ratio = 0.52;
    spacing = 8;
  } else if (w < 400) {
    ratio = 0.58;
    spacing = 10;
  } else if (w < 430) {
    ratio = 0.64;
    spacing = 10;
  }

  if (textScale > 1.08) {
    ratio -= 0.06 * ((textScale - 1.0) * 2).clamp(0.0, 1.0);
  }
  ratio = ratio.clamp(0.42, 0.78);

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
    childAspectRatio: ratio,
  );
}

/// Filters out Firebase identifiers (e.g. +firebase_xxx) so we show real phone numbers only.
String _sanitizePhone(String s) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return '';
  if (t.toLowerCase().startsWith('+firebase_') ||
      t.toLowerCase().contains('firebase_')) {
    return '';
  }
  return t;
}

class LocalMedia {
  final Uint8List bytes;
  final String filename;
  final String? mime;
  final bool isVideo;
  const LocalMedia({
    required this.bytes,
    required this.filename,
    this.mime,
    this.isVideo = false,
  });
}

class MarketplaceMerchantDashboard extends StatefulWidget {
  final String email;
  /// When true, this dashboard is shown as a tab inside the main app bottom nav;
  /// hide our own bottom nav to avoid two overlapping bars.
  final bool embeddedInMainNav;

  const MarketplaceMerchantDashboard({
    super.key,
    required this.email,
    required void Function() onBackToHomeTab,
    this.embeddedInMainNav = false,
  });

  /// Drop My Items memory on logout / account switch.
  static void clearSessionCaches() {
    _MarketplaceMerchantDashboardState.clearSessionCaches();
  }

  @override
  State<MarketplaceMerchantDashboard> createState() =>
      _MarketplaceMerchantDashboardState();
}

class _MarketplaceMerchantDashboardState
    extends State<MarketplaceMerchantDashboard> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  final OrderService _orderService = OrderService();

  // G£à Use CartService singleton from provider
  final CartService _cartService = CartServiceProvider.getInstance();

  final _picker = ImagePicker();

  // Form controllers (create)
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  final _stock = TextEditingController(text: '1');
  int _stockQty = 1;

  late TabController _marketplaceTabs;

  // Create form state
  bool _isActive = true;
  bool _submitting = false;

  LocalMedia? _cover;

  // G£à multi-photos for posting
  static const int _maxGalleryPhotos = 5;
  final List<LocalMedia> _gallery = <LocalMedia>[];

  static const List<String> _kCategories = <String>[
    'food',
    'drinks',
    'electronics',
    'clothes',
    'shoes',
    'other',
  ];
  String? _category = 'other';

  // Items
  List<Map<String, dynamic>> _items = [];
  bool _loadingItems = true;
  bool _busyRow = false;

  /// Instant My Items cache (survives tab switches / reopen in-session).
  static final Map<String, List<Map<String, dynamic>>> _itemsMemoryByUid =
      <String, List<Map<String, dynamic>>>{};

  static void clearSessionCaches() {
    _itemsMemoryByUid.clear();
  }

  static const String _prefsItemsCachePrefix = 'merchant_my_items_cache_v1_';

  // Filters (My Items)
  String _searchQuery = '';
  String _filterCategory = 'all'; // all | food | ...
  String _filterStatus = 'all'; // all | active | inactive | pending | rejected

  // Dashboard state
  /// Real sold orders (confirmed+paid or delivered) from OrderService for Recent Sales.
  List<OrderItem> _recentSalesOrders = [];
  final TextEditingController _recentSalesSearchController = TextEditingController();
  final FocusNode _recentSalesSearchFocus = FocusNode();
  bool _isLoading = true;
  bool _initialLoadComplete = false;

  String _uid = '';
  String _businessName = ''; // resolved name for UI
  double _walletBalance = 0;

  // Stats
  int _totalItems = 0;
  int _activeItems = 0;
  int _soldItems = 0;
  double _totalEarnings = 0;
  double _rating = 0.0;
  String _status = 'pending';

  /// Didit KYC: verified | pending | rejected | (empty = not started)
  String _kycStatus = '';
  String _kycRejectionReason = '';

  // Merchant profile details
  String _merchantEmail = 'No Email';
  String _merchantPhone = 'No Phone';
  String _merchantProfileUrl = '';
  /// Short public blurb shown on shop + product details (max 120 chars).
  String _businessDescription = '';
  /// Local disk path from [ProfilePhotoCache] for instant avatar display.
  String? _localPhotoPath;

  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  /// Dart [DateTime.weekday] values: 1 = Mon GÇª 7 = Sun. Empty = every day.
  Set<int> _openDays = {};

  bool _loadingMe = false;
  bool _profileUploading = false;

  Timer? _ticker;

  // G£à prevent periodic refresh while an edit sheet is open (stops random crashes)
  bool _sheetOpen = false;

  // First-time merchant guide (show once after login, then persist as done)
  static const String _kMerchantGuidePrefKey = 'marketplace_merchant_guide_v1_done';
  static const String _kMerchantGuideShowOnNextOpenKey = 'marketplace_merchant_guide_show_on_next_open';
  static const String _kBusinessDescPrefKey = 'merchant_business_description';
  static const String _kShopHoursPrefKey = 'merchant_shop_opening_hours';
  static const String _kShopDaysPrefKey = 'merchant_shop_opening_days';
  static const int _kBusinessDescMaxLen = 120;
  bool _showMerchantGuide = false;
  int _merchantGuideStep = 0;
  bool _merchantGuideCheckScheduled = false;

  // Brand
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _dialogFieldFill = Color(0xFFF4F6FA);

  InputDecoration _walletPinFieldDecoration(String hint) {
    final r = BorderRadius.circular(12);
    return InputDecoration(
      hintText: hint,
      counterText: '',
      isDense: true,
      filled: true,
      fillColor: _dialogFieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: _brandOrange, width: 2),
      ),
    );
  }

  Widget _walletPinDialogHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A00), Color(0xFFFFA64D)],
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletPinDialogShell({
    required BuildContext context,
    required Widget header,
    required Widget body,
    required Widget footer,
  }) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height - viewInsets.vertical - 24;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: maxHeight,
        ),
        child: Material(
          color: Colors.white,
          elevation: 18,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                body,
                const Divider(height: 1, thickness: 1),
                footer,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------- Wallet lock (PIN) -----------------
  DateTime? _walletUnlockedUntil;
  static const Duration _walletUnlockDuration = Duration(minutes: 5);

  bool get _walletUnlockedNow {
    final until = _walletUnlockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  /// Display phone; filters out Firebase identifiers so we never show +firebase_xxx.
  String get _displayMerchantPhone {
    final s = _sanitizePhone(_merchantPhone);
    return s.isEmpty ? 'No Phone' : _merchantPhone;
  }

  void _toastOk(String msg) {
    ToastHelper.showCustomToast(
      context,
      msg,
      isSuccess: true,
      errorMessage: '',
    );
  }

  void _toastErr(String msg) {
    ToastHelper.showCustomToast(
      context,
      msg,
      isSuccess: false,
      errorMessage: '',
    );
  }

  Random _safeRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _randomSalt([int len = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = _safeRandom();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin::$salt');
    return sha256.convert(bytes).toString();
  }

  Future<bool> _ensureAppPinExists() async {
    final sp = await SharedPreferences.getInstance();
    final existingHash = sp.getString('app_pin_hash');
    final existingSalt = sp.getString('app_pin_salt');

    if (existingHash != null &&
        existingHash.trim().isNotEmpty &&
        existingSalt != null &&
        existingSalt.trim().isNotEmpty) {
      return true;
    }

    final pin = await _showSetPinDialog();
    if (pin == null) return false;

    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);

    await sp.setString('app_pin_salt', salt);
    await sp.setString('app_pin_hash', hash);

    if (!mounted) return true;
    _toastOk('Wallet password set');
    return true;
  }

  Future<bool> _unlockWalletWithPin() async {
    if (_walletUnlockedNow) return true;

    final ok = await AppWalletPin.verifyWalletUnlock(context);
    if (!ok || !mounted) return false;

    setState(() {
      _walletUnlockedUntil = DateTime.now().add(_walletUnlockDuration);
    });
    return true;
  }

  Future<String?> _showEnterPinDialog() async {
    final controller = TextEditingController();
    String? shortPinHint;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return _walletPinDialogShell(
            context: ctx,
            header: _walletPinDialogHeader(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Unlock wallet',
              subtitle: 'Enter your 4GÇô6 digit PIN.',
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) {
                      if (shortPinHint != null) {
                        setLocal(() => shortPinHint = null);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                    decoration: _walletPinFieldDecoration('Wallet PIN (4GÇô6 digits)'),
                  ),
                  if (shortPinHint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      shortPinHint!,
                      style: TextStyle(
                        color: _brandNavy.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        final pin = controller.text.trim();
                        if (pin.length < 4) {
                          setLocal(() => shortPinHint =
                              'Enter at least 4 digits.');
                          return;
                        }
                        Navigator.of(dialogContext).pop(pin);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Unlock',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
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

  Future<String?> _showSetPinDialog() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return _walletPinDialogShell(
            context: ctx,
            header: _walletPinDialogHeader(
              icon: Icons.pin_rounded,
              title: 'Set wallet PIN',
              subtitle: 'Create a 4GÇô6 digit PIN.',
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: p1,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) {
                      if (err != null) {
                        setLocal(() => err = null);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                    decoration: _walletPinFieldDecoration('New PIN (4GÇô6 digits)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: p2,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) {
                      if (err != null) {
                        setLocal(() => err = null);
                      }
                    },
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                    decoration: _walletPinFieldDecoration('Confirm PIN'),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      err!,
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        final a = p1.text.trim();
                        final b = p2.text.trim();

                        if (a.length < 4) {
                          setLocal(
                              () => err = 'PIN must be at least 4 digits.');
                          return;
                        }
                        if (a != b) {
                          setLocal(() => err = 'PINs do not match.');
                          return;
                        }
                        Navigator.of(dialogContext).pop(a);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save PIN',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
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

  @override
  void initState() {
    super.initState();
    if (widget.embeddedInMainNav) _selectedIndex = 4;
    _marketplaceTabs = TabController(length: 3, vsync: this);
    _marketplaceTabs.addListener(() {
      if (_marketplaceTabs.indexIsChanging) return;
      // My Items tab: ensure cached list is visible immediately.
      if (_marketplaceTabs.index == 2 && _items.isEmpty) {
        _hydrateItemsFromLocalCache();
        if (_items.isEmpty) {
          unawaited(_hydrateItemsFromPrefsCache());
        } else if (mounted) {
          setState(() => _loadingItems = false);
        }
        unawaited(_loadItems(showLoading: false));
      }
    });

    _uid = _auth.currentUser?.uid ?? '';

    // Instant My Items from memory/prefs before any network.
    _hydrateItemsFromLocalCache();

    // 1) Instant UI from Auth + prefs (no network).
    _hydrateFromFirebaseAuth();
    unawaited(_bootstrapFast());

    // 2) Items + wallet ASAP (cache-first). Don't flash skeleton if cache hit.
    unawaited(_loadItems(showLoading: _items.isEmpty));
    unawaited(_loadWalletBalance());

    // 3) Heavier network work after first frame GÇö don't block skeleton exit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadMerchantData());
      unawaited(_fetchCurrentUserMe());
      unawaited(_pullPhoneAndProfileFromFirestore());
      unawaited(_loadKycStatus());
      unawaited(_ensureBusinessName());
      // Backfill can rewrite many docs GÇö defer so dashboard opens fast.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_syncBackendUserIdToFirestore());
      });
    });

    _startPeriodicUpdates();
  }

  /// Prefs + clear loading shell without waiting on APIs.
  Future<void> _bootstrapFast() async {
    await _loadMerchantProfileFromPrefs();
    // Disk cache may be ready after prefs GÇö apply if memory was empty.
    if (_items.isEmpty) {
      await _hydrateItemsFromPrefsCache();
    }
    if (!mounted) return;
    // Show dashboard chrome immediately; sections fill in as data arrives.
    setState(() {
      _isLoading = false;
      _initialLoadComplete = true;
      if (_items.isNotEmpty) _loadingItems = false;
    });
  }

  void _hydrateItemsFromLocalCache() {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) return;
    final mem = _itemsMemoryByUid[uid];
    if (mem == null || mem.isEmpty) return;
    _items = mem.map((e) => Map<String, dynamic>.from(e)).toList();
    _totalItems = _items.length;
    _activeItems = _items.where((e) => e['isActive'] == true).length;
    _loadingItems = false;
  }

  Future<void> _hydrateItemsFromPrefsCache() async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsItemsCachePrefix$uid');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is Map) {
          list.add(Map<String, dynamic>.from(e));
        }
      }
      if (list.isEmpty) return;
      _itemsMemoryByUid[uid] =
          list.map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _totalItems = list.length;
        _activeItems = list.where((e) => e['isActive'] == true).length;
        _loadingItems = false;
      });
    } catch (_) {}
  }

  Future<void> _persistItemsCache(List<Map<String, dynamic>> items) async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) return;
    final copy = items.map((e) => Map<String, dynamic>.from(e)).toList();
    _itemsMemoryByUid[uid] = copy;
    try {
      // Keep prefs payload small GÇö drop huge base64 blobs from disk cache.
      final slim = copy.map((e) {
        final m = Map<String, dynamic>.from(e);
        final img = (m['image'] ?? '').toString();
        if (img.length > 4000) m.remove('image');
        final gal = m['gallery'];
        if (gal is List && gal.isNotEmpty) {
          m['gallery'] = gal.take(2).where((x) {
            return x.toString().length < 4000;
          }).toList();
        }
        return m;
      }).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsItemsCachePrefix$uid',
        jsonEncode(slim),
      );
    } catch (_) {}
  }

  void _applyItemsToUi(List<Map<String, dynamic>> list, {bool persist = true}) {
    final total = list.length;
    final active = list.where((e) => e['isActive'] == true).length;
    if (!mounted) {
      if (persist) unawaited(_persistItemsCache(list));
      return;
    }
    setState(() {
      _items = list;
      _totalItems = total;
      _activeItems = active;
      _loadingItems = false;
    });
    if (persist) unawaited(_persistItemsCache(list));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _marketplaceTabs.dispose();
    _name.dispose();
    _price.dispose();
    _location.dispose();
    _desc.dispose();
    _stock.dispose();
    _recentSalesSearchController.dispose();
    _recentSalesSearchFocus.dispose();
    super.dispose();
  }

  void _startPeriodicUpdates() {
    _ticker?.cancel();
    var tick = 0;
    // Lighter polling on low-RAM devices: wallet often, heavy order dump rarely.
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      if (_sheetOpen) return;
      tick++;
      _hydrateFromFirebaseAuth();
      unawaited(_loadWalletBalance());
      if (tick % 2 == 0) unawaited(_loadItems(showLoading: false));
      if (tick % 3 == 0) unawaited(_loadOrderStats());
      if (tick % 4 == 0) unawaited(_fetchCurrentUserMe());
    });
  }

  // ----------------- Business name FIX (Auth GåÆ Firestore GåÆ API GåÆ Prefs) -----------------
  void _hydrateFromFirebaseAuth() {
    final u = _auth.currentUser;
    if (u == null) return;

    _uid = u.uid;

    final email = (u.email ?? '').trim();
    final phone = _sanitizePhone(u.phoneNumber ?? '');
    final photo = (u.photoURL ?? '').trim();

    if (mounted) {
      setState(() {
        if (email.isNotEmpty) _merchantEmail = email;
        if (phone.isNotEmpty) _merchantPhone = phone;
        if (photo.isNotEmpty) {
          _merchantProfileUrl = photo;
        } else {
          // Avoid keeping a previous account's avatar while prefs/Firestore load.
          _localPhotoPath = null;
        }
      });
    }
    if (photo.isNotEmpty) {
      unawaited(_warmProfilePhotoCache(photo));
    } else {
      // Drop disk avatar if Auth has no photo for this user yet.
      unawaited(ProfilePhotoCache.peekLocalPath().then((path) async {
        if (path != null) await ProfilePhotoCache.clear();
      }));
    }
  }

  /// Pull phone and profile picture from Firestore users/{uid} when Auth/prefs are empty.
  Future<void> _pullPhoneAndProfileFromFirestore() async {
    final uid = _auth.currentUser?.uid ?? _uid;
    if (uid.isEmpty) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null || !mounted) return;
      final phoneVal = _sanitizePhone(
          (data['phone'] ?? '').toString().trim());
      final picVal = (data['profilePicture'] ?? data['profilepicture'] ?? '')
          .toString()
          .trim();
      final descVal = (data['businessDescription'] ?? data['description'] ?? '')
          .toString()
          .trim();
      final hoursVal = (data['openingHours'] ?? '').toString().trim();
      final daysVal = data['openingDays'];
      if (phoneVal.isEmpty &&
          picVal.isEmpty &&
          descVal.isEmpty &&
          hoursVal.isEmpty &&
          daysVal == null) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (phoneVal.isNotEmpty) {
        await prefs.setString('phone', phoneVal);
        await prefs.setString('merchant_profile_phone', phoneVal);
      }
      if (picVal.isNotEmpty) await prefs.setString('profilepicture', picVal);
      if (descVal.isNotEmpty) {
        await prefs.setString(_kBusinessDescPrefKey, descVal);
      }
      if (hoursVal.isNotEmpty) {
        await prefs.setString(_kShopHoursPrefKey, hoursVal);
      }
      if (daysVal != null) {
        final tmp = <int>{};
        if (daysVal is List) {
          for (final e in daysVal) {
            final n = e is int ? e : int.tryParse('$e');
            if (n != null && n >= 1 && n <= 7) tmp.add(n);
          }
        }
        if (tmp.isNotEmpty) {
          await prefs.setString(
              _kShopDaysPrefKey, (tmp.toList()..sort()).join(','));
        }
      }
      if (!mounted) return;
      setState(() {
        if (phoneVal.isNotEmpty && _merchantPhone == 'No Phone') {
          _merchantPhone = phoneVal;
        }
        if (picVal.isNotEmpty) {
          _merchantProfileUrl = picVal;
        }
        if (descVal.isNotEmpty) {
          _businessDescription = descVal;
        }
        if (hoursVal.isNotEmpty) {
          _applyOpeningHoursString(hoursVal);
        }
        if (daysVal != null) {
          _applyOpeningDays(daysVal);
        }
      });
      if (picVal.isNotEmpty) {
        unawaited(_warmProfilePhotoCache(picVal));
      }
    } catch (_) {}
  }

  Future<void> _syncBackendUserIdToFirestore() async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) return;
    final nestRaw = await _getNestUserId();
    final backendId = int.tryParse(nestRaw ?? '');
    if (backendId == null || backendId <= 0) return;
    try {
      await _firestore.collection('marketplace_merchants').doc(uid).set(
        {
          'backendUserId': backendId,
          'userId': backendId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _firestore.collection('users').doc(uid).set(
        {
          'userId': backendId,
          'backendUserId': backendId,
          'firebaseUid': uid,
          'uid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _backfillMerchantBackendIdOnItems(uid, backendId, nestRaw!);
    } catch (e) {
      debugPrint('sync backendUserId: $e');
    }
  }

  /// Tags existing Firestore listings so buyers can open chat (merchantBackendId).
  Future<void> _backfillMerchantBackendIdOnItems(
    String firebaseUid,
    int backendId,
    String nestUserId,
  ) async {
    try {
      final snap = await _firestore
          .collection('marketplace_items')
          .where('merchantId', isEqualTo: firebaseUid)
          .limit(100)
          .get();
      if (snap.docs.isEmpty) return;

      final batch = _firestore.batch();
      var updates = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final existing = data['merchantBackendId'];
        final seller = data['sellerUserId']?.toString().trim() ?? '';
        final existingId = existing is num
            ? existing.toInt()
            : int.tryParse('${existing ?? ''}');
        final needsBackendId = existingId == null || existingId <= 0;
        final sellerIsUid = seller.isEmpty ||
            RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(seller);
        if (!needsBackendId && !sellerIsUid) continue;

        batch.set(
          doc.reference,
          {
            if (needsBackendId) 'merchantBackendId': backendId,
            if (sellerIsUid) 'sellerUserId': nestUserId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        updates++;
        if (updates >= 450) break;
      }
      if (updates > 0) await batch.commit();
    } catch (e) {
      debugPrint('backfill merchantBackendId: $e');
    }
  }

  Future<void> _ensureBusinessName() async {
    final u = _auth.currentUser;
    if (u == null) return;

    final authDisplay = (u.displayName ?? '').trim();
    if (authDisplay.isNotEmpty) {
      if (mounted) setState(() => _businessName = authDisplay);
      return;
    }

    String resolved = '';

    // 1) Firestore marketplace_merchants
    try {
      final doc =
          await _firestore.collection('marketplace_merchants').doc(u.uid).get();
      final data = doc.data();
      if (data != null) {
        resolved =
            (data['businessName'] ?? data['name'] ?? '').toString().trim();
        final desc = (data['businessDescription'] ?? data['description'] ?? '')
            .toString()
            .trim();
        final hours = (data['openingHours'] ?? '').toString().trim();
        final days = data['openingDays'];
        if (desc.isNotEmpty && mounted) {
          setState(() => _businessDescription = desc);
          unawaited(SharedPreferences.getInstance().then((p) {
            p.setString(_kBusinessDescPrefKey, desc);
          }));
        }
        if ((hours.isNotEmpty || days != null) && mounted) {
          setState(() {
            if (hours.isNotEmpty) _applyOpeningHoursString(hours);
            if (days != null) _applyOpeningDays(days);
          });
          unawaited(SharedPreferences.getInstance().then((p) {
            if (hours.isNotEmpty) p.setString(_kShopHoursPrefKey, hours);
            if (days is List) {
              final tmp = <int>[];
              for (final e in days) {
                final n = e is int ? e : int.tryParse('$e');
                if (n != null && n >= 1 && n <= 7) tmp.add(n);
              }
              if (tmp.isNotEmpty) {
                tmp.sort();
                p.setString(_kShopDaysPrefKey, tmp.join(','));
              }
            }
          }));
        }
      }
    } catch (_) {}

    // 2) Firestore users
    if (resolved.isEmpty) {
      try {
        final doc = await _firestore.collection('users').doc(u.uid).get();
        final data = doc.data();
        if (data != null) {
          resolved = (data['businessName'] ??
                  data['fullName'] ??
                  data['name'] ??
                  data['displayName'] ??
                  '')
              .toString()
              .trim();
        }
      } catch (_) {}
    }

    // 3) API /users/me
    if (resolved.isEmpty) {
      try {
        final bearer = await _getBearerTokenForApi();
        if (bearer != null && bearer.isNotEmpty) {
          final base = await ApiConfig.readBase();
          final resp = await http.get(
            Uri.parse('$base/users/me'),
            headers: {
              'Authorization': 'Bearer $bearer',
              'Accept': 'application/json'
            },
          );
          if (resp.statusCode == 200) {
            final decoded = jsonDecode(resp.body);
            final Map<String, dynamic> payload = (decoded is Map &&
                    decoded['data'] is Map)
                ? Map<String, dynamic>.from(decoded['data'])
                : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
            final user = (payload['user'] is Map)
                ? Map<String, dynamic>.from(payload['user'] as Map)
                : payload;

            final business =
                (user['businessName'] ?? user['merchantName'] ?? '')
                    .toString()
                    .trim();
            final name = (user['name'] ?? '').toString().trim();
            final first = (user['firstName'] ?? '').toString().trim();
            final last = (user['lastName'] ?? '').toString().trim();
            final joined =
                [first, last].where((x) => x.isNotEmpty).join(' ').trim();

            resolved = business.isNotEmpty
                ? business
                : (name.isNotEmpty ? name : joined);
          }
        }
      } catch (_) {}
    }

    // 4) Prefs fallback
    if (resolved.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      resolved = (prefs.getString('business_name') ??
              prefs.getString('fullName') ??
              prefs.getString('name') ??
              '')
          .trim();
    }

    if (resolved.isEmpty) resolved = 'Marketplace Merchant';

    // backfill FirebaseAuth displayName
    try {
      if ((u.displayName ?? '').trim().isEmpty &&
          resolved != 'Marketplace Merchant') {
        await u.updateDisplayName(resolved);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _businessName = resolved);
  }

  String _displayBusinessName() {
    final authName = (_auth.currentUser?.displayName ?? '').trim();
    if (authName.isNotEmpty) return authName;
    if (_businessName.trim().isNotEmpty) return _businessName.trim();
    return 'Marketplace Merchant';
  }

  // ----------------- API auth: prefs token OR Firebase idToken -----------------
  /// [forceRefresh] true = get a new Firebase ID token (use before sensitive/upload calls to avoid auth/id-token-expired).
  Future<String?> _getBearerTokenForApi({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && forceRefresh) {
      try {
        final idToken = await user.getIdToken(true);
        final t = idToken?.trim();
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString('jwt_token') ??
        prefs.getString('token') ??
        prefs.getString('authToken') ??
        prefs.getString('jwt');

    if (fromPrefs != null && fromPrefs.trim().isNotEmpty) {
      return fromPrefs.trim();
    }

    if (user == null) return null;

    try {
      final idToken = await user.getIdToken(forceRefresh);
      final t = idToken?.trim();
      if (t == null || t.isEmpty) return null;
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMerchantProfileFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final currentUid = (_auth.currentUser?.uid ?? _uid).trim();
    final phone = _sanitizePhone(
      prefs.getString('merchant_profile_phone') ?? prefs.getString('phone') ?? '',
    );
    final pic =
        (prefs.getString('profilepicture') ?? '').trim();
    final desc = (prefs.getString(_kBusinessDescPrefKey) ?? '').trim();
    final hours = (prefs.getString(_kShopHoursPrefKey) ?? '').trim();
    final daysRaw = (prefs.getString(_kShopDaysPrefKey) ?? '').trim();

    // Only use on-disk avatar when it matches this account + URL.
    final localPath = pic.isEmpty
        ? null
        : await ProfilePhotoCache.peekLocalPath(forRemoteUrl: pic);

    if (!mounted) return;

    // Prefer live Firebase Auth photo over a stale prefs URL from another session.
    final authPhoto = (_auth.currentUser?.photoURL ?? '').trim();
    final nextPic = pic.isNotEmpty
        ? pic
        : (authPhoto.isNotEmpty ? authPhoto : _merchantProfileUrl);

    setState(() {
      if (currentUid.isNotEmpty) _uid = currentUid;
      _merchantEmail = prefs.getString('email') ?? _merchantEmail;
      if (phone.isNotEmpty) _merchantPhone = phone;
      _merchantProfileUrl = nextPic;
      _localPhotoPath = localPath;
      if (desc.isNotEmpty) _businessDescription = desc;
      if (hours.isNotEmpty) _applyOpeningHoursString(hours);
      if (daysRaw.isNotEmpty) _applyOpeningDays(daysRaw);
    });
    // Warm/refresh disk cache in background so next open is instant.
    if (_merchantProfileUrl.trim().isNotEmpty) {
      unawaited(_warmProfilePhotoCache(_merchantProfileUrl));
    }
  }

  Future<void> _warmProfilePhotoCache([String? url]) async {
    final remote = (url ?? _merchantProfileUrl).trim();
    if (remote.isEmpty) return;
    final file = await ProfilePhotoCache.ensureCached(remote);
    if (!mounted || file == null) return;
    if (_localPhotoPath == file.path) return;
    setState(() => _localPhotoPath = file.path);
  }

  Future<void> _editBusinessDescription() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BusinessDescriptionSheet(
        initialText: _businessDescription,
        maxLength: _kBusinessDescMaxLen,
        brandColor: _brandOrange,
      ),
    );
    if (saved == null || !mounted) return;
    await _saveBusinessDescription(saved);
  }

  Future<void> _saveBusinessDescription(String raw) async {
    final desc = raw.trim();
    if (desc.length > _kBusinessDescMaxLen) {
      _toastErr('Keep it under $_kBusinessDescMaxLen characters.');
      return;
    }
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) {
      _toastErr('Please sign in again.');
      return;
    }

    try {
      final payload = <String, dynamic>{
        'businessDescription': desc,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await Future.wait([
        _firestore
            .collection('marketplace_merchants')
            .doc(uid)
            .set(payload, SetOptions(merge: true)),
        _firestore
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true)),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBusinessDescPrefKey, desc);
      if (!mounted) return;
      setState(() => _businessDescription = desc);
      _toastOk(desc.isEmpty ? 'Description cleared' : 'Description saved');
    } catch (e) {
      debugPrint('Save business description: $e');
      if (!mounted) return;
      _toastErr('Could not save description. Try again.');
    }
  }

  String _formatShopTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay? _parseShopTime(String raw) {
    final t = raw.trim().split(':');
    if (t.length != 2) return null;
    final h = int.tryParse(t[0]);
    final m = int.tryParse(t[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  void _applyOpeningHoursString(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      _openTime = null;
      _closeTime = null;
      return;
    }
    final parts = s.replaceAll('GÇô', '-').replaceAll('GÇö', '-').split('-');
    if (parts.length != 2) return;
    final open = _parseShopTime(parts[0]);
    final close = _parseShopTime(parts[1]);
    if (open == null || close == null) return;
    _openTime = open;
    _closeTime = close;
  }

  void _applyOpeningDays(dynamic raw) {
    final next = <int>{};
    if (raw is List) {
      for (final e in raw) {
        final n = e is int ? e : int.tryParse('$e');
        if (n != null && n >= 1 && n <= 7) next.add(n);
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      for (final part in raw.split(RegExp(r'[,;\s]+'))) {
        final n = int.tryParse(part.trim());
        if (n != null && n >= 1 && n <= 7) next.add(n);
      }
    }
    _openDays = next;
  }

  static const _kDayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatOpenDaysLabel(Set<int> days) {
    if (days.isEmpty || days.length == 7) return 'Every day';
    final sorted = days.toList()..sort();
    // Contiguous ranges GåÆ MonGÇôFri style
    final ranges = <String>[];
    int start = sorted.first;
    int prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final d = sorted[i];
      if (d == prev + 1) {
        prev = d;
        continue;
      }
      ranges.add(start == prev
          ? _kDayLabels[start - 1]
          : '${_kDayLabels[start - 1]}GÇô${_kDayLabels[prev - 1]}');
      start = prev = d;
    }
    ranges.add(start == prev
        ? _kDayLabels[start - 1]
        : '${_kDayLabels[start - 1]}GÇô${_kDayLabels[prev - 1]}');
    return ranges.join(', ');
  }

  String get _shopHoursSummary {
    if (_openTime == null || _closeTime == null) return 'Set shop hours';
    final times =
        '${_formatShopTime(_openTime!)}GÇô${_formatShopTime(_closeTime!)}';
    return '${_formatOpenDaysLabel(_openDays)} -+ $times';
  }

  bool get _isShopOpenNow {
    final open = _openTime;
    final close = _closeTime;
    if (open == null || close == null) return false;
    final today = DateTime.now().weekday; // 1=Mon GÇª 7=Sun
    if (_openDays.isNotEmpty && !_openDays.contains(today)) return false;
    final now = TimeOfDay.now();
    final nowM = now.hour * 60 + now.minute;
    final openM = open.hour * 60 + open.minute;
    final closeM = close.hour * 60 + close.minute;
    if (openM == closeM) return false;
    if (openM < closeM) {
      return nowM >= openM && nowM < closeM;
    }
    return nowM >= openM || nowM < closeM;
  }

  Future<void> _editShopHours() async {
    final result = await showModalBottomSheet<
        ({TimeOfDay open, TimeOfDay close, Set<int> days})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ShopHoursSheet(
        initialOpen: _openTime ?? const TimeOfDay(hour: 8, minute: 0),
        initialClose: _closeTime ?? const TimeOfDay(hour: 17, minute: 0),
        initialDays: _openDays.isEmpty
            ? {1, 2, 3, 4, 5, 6, 7}
            : Set<int>.from(_openDays),
        brandColor: _brandOrange,
      ),
    );
    if (result == null || !mounted) return;
    await _saveShopHours(result.open, result.close, result.days);
  }

  Future<void> _saveShopHours(
    TimeOfDay open,
    TimeOfDay close,
    Set<int> days,
  ) async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) {
      _toastErr('Please sign in again.');
      return;
    }
    final hours = '${_formatShopTime(open)}GÇô${_formatShopTime(close)}';
    final dayList = (days.isEmpty || days.length == 7)
        ? <int>[1, 2, 3, 4, 5, 6, 7]
        : (days.toList()..sort());
    try {
      final payload = <String, dynamic>{
        'openingHours': hours,
        'openingDays': dayList,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await Future.wait([
        _firestore
            .collection('marketplace_merchants')
            .doc(uid)
            .set(payload, SetOptions(merge: true)),
        _firestore
            .collection('users')
            .doc(uid)
            .set(payload, SetOptions(merge: true)),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kShopHoursPrefKey, hours);
      await prefs.setString(_kShopDaysPrefKey, dayList.join(','));
      MerchantSellerLoader.cacheOpeningHours(uid, hours);
      MerchantSellerLoader.cacheOpeningDays(uid, dayList);
      if (!mounted) return;
      setState(() {
        _openTime = open;
        _closeTime = close;
        _openDays = dayList.toSet();
      });
      _toastOk('Shop hours saved');
    } catch (e) {
      debugPrint('Save shop hours: $e');
      if (!mounted) return;
      _toastErr('Could not save hours. Try again.');
    }
  }

  // G£à /users/me for email/phone/pic/rating
  Future<void> _fetchCurrentUserMe() async {
    if (!mounted) return;

    setState(() {
      _loadingMe = true;
    });

    try {
      final bearer = await _getBearerTokenForApi();
      if (bearer == null || bearer.isEmpty) {
        if (mounted) setState(() => _loadingMe = false);
        return;
      }

      final base = await ApiConfig.readBase();
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json'
        },
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final Map<String, dynamic> payload =
            (decoded is Map && decoded['data'] is Map)
                ? Map<String, dynamic>.from(decoded['data'])
                : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
        final user = (payload['user'] is Map)
            ? Map<String, dynamic>.from(payload['user'] as Map)
            : payload;

        final emailVal =
            (user['email'] ?? user['userEmail'] ?? '').toString().trim();
        final phoneVal = _sanitizePhone(
            (user['phone'] ?? '').toString().trim());
        final picVal = (user['profilepicture'] ?? user['profilePicture'] ?? '')
            .toString()
            .trim();

        final apiRating = user['rating'];
        if (apiRating is num) _rating = apiRating.toDouble();

        // Pull verification/status from API (e.g. pending, approved, under_review)
        final apiStatus = (user['status'] ?? user['verificationStatus'] ?? '')
            .toString()
            .trim();
        if (apiStatus.isNotEmpty) _status = apiStatus;

        final prefs = await SharedPreferences.getInstance();
        if (emailVal.isNotEmpty) await prefs.setString('email', emailVal);
        if (phoneVal.isNotEmpty) {
          await prefs.setString('phone', phoneVal);
          await prefs.setString('merchant_profile_phone', phoneVal);
        }
        if (picVal.isNotEmpty) await prefs.setString('profilepicture', picVal);

        if (!mounted) return;
        final authPhoto = (_auth.currentUser?.photoURL ?? '').trim();
        final nextPic = authPhoto.isNotEmpty
            ? authPhoto
            : (picVal.isNotEmpty ? picVal : _merchantProfileUrl);
        setState(() {
          if (emailVal.isNotEmpty) _merchantEmail = emailVal;
          if (phoneVal.isNotEmpty) _merchantPhone = phoneVal;
          // Prefer Firebase Auth photo; else use API profile picture
          if (nextPic.trim().isNotEmpty) _merchantProfileUrl = nextPic;
        });
        if (nextPic.trim().isNotEmpty) {
          unawaited(_warmProfilePhotoCache(nextPic));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching /users/me');
    } finally {
      if (mounted) setState(() => _loadingMe = false);
    }
  }

  // ----------------- Dashboard API + Wallet -----------------
  Future<void> _loadMerchantData() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? _uid;

    if (_uid.isNotEmpty) {
      try {
        final dashboardFuture =
            _helper.getMerchantDashboardData(_uid, 'marketplace');
        final walletFuture = _loadWalletBalance();
        final results = await Future.wait([dashboardFuture, walletFuture]);
        final dashboardData = results[0] as Map<String, dynamic>;
        if (!dashboardData.containsKey('error')) {
          final merchant = dashboardData['merchant'];

          if (!mounted) return;
          setState(() {
            // Recent sales come from real orders in _loadOrderStats(), not dashboard API

            _totalEarnings = (dashboardData['totalRevenue'] is num)
                ? (dashboardData['totalRevenue'] as num).toDouble()
                : double.tryParse('${dashboardData['totalRevenue']}') ?? 0;

            final ti = dashboardData['totalItems'];
            final ai = dashboardData['activeItems'];
            final si = dashboardData['soldItems'];
            if (ti is int) _totalItems = ti;
            if (ai is int) _activeItems = ai;
            if (si is int) _soldItems = si;

            if (merchant is Map) {
              final mr = merchant['rating'];
              if (mr is num) _rating = mr.toDouble();

              final ms = merchant['status'];
              if (ms != null && ms.toString().trim().isNotEmpty) {
                _status = ms.toString().trim();
              }

              final mp = _sanitizePhone(
                  (merchant['phone'] ?? '').toString().trim());
              if (mp.isNotEmpty) {
                _merchantPhone = mp;
                unawaited(prefs.setString('merchant_profile_phone', mp));
              }
            }
          });
        }

        // Load order stats in background (real sold/earnings)
        unawaited(_loadOrderStats());
      } catch (e) {
        debugPrint('Error loading dashboard: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _initialLoadComplete = true;
      });
    }
  }

  /// Load sold items count, total earnings, and recent sales from real confirmed+paid orders.
  Future<void> _loadOrderStats() async {
    if (!mounted) return;
    try {
      final myFirebaseUid = (_auth.currentUser?.uid ?? '').trim();
      final orders = await _orderService.getMyOrders();
      final sold = orders.where((o) {
        final sellerUid = (o.merchantUid ?? '').trim();
        // Merchant dashboard stats must only reflect orders sold by this merchant.
        if (myFirebaseUid.isEmpty || sellerUid.isEmpty || sellerUid != myFirebaseUid) {
          return false;
        }
        if (o.status == OrderStatus.delivered) return true;
        if (o.status == OrderStatus.confirmed && o.paymentStatus == PaymentStatus.paid) return true;
        return false;
      }).toList();
      // Sort by date descending (most recent first)
      sold.sort((a, b) {
        final da = a.orderDate ?? DateTime(0);
        final db = b.orderDate ?? DateTime(0);
        return db.compareTo(da);
      });
      final count = sold.length;
      final earnings = sold.fold<double>(0, (sum, o) => sum + o.total.toDouble());
      if (!mounted) return;
      setState(() {
        _soldItems = count;
        _totalEarnings = earnings;
        // Keep only recent rows in memory for the UI list.
        _recentSalesOrders = sold.take(25).toList(growable: false);
      });
    } catch (e) {
      debugPrint('Error loading order stats: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final firebaseUid = _auth.currentUser?.uid ?? _uid;
      if (firebaseUid.trim().isEmpty) return;

      final ref = _firestore.collection('merchant_wallets').doc(firebaseUid);
      DocumentSnapshot<Map<String, dynamic>>? walletDoc;
      try {
        final cached = await ref.get(const GetOptions(source: Source.cache));
        if (cached.exists) walletDoc = cached;
      } catch (_) {}
      walletDoc ??= await ref.get();

      if (!walletDoc.exists || !mounted) return;

      final raw = walletDoc.data()?['balance'];
      double val = 0;
      if (raw is num) {
        val = raw.toDouble();
      } else {
        val = double.tryParse(raw?.toString() ?? '') ?? 0;
      }

      setState(() => _walletBalance = val);
    } catch (e) {
      debugPrint('Error loading wallet: $e');
    }
  }

  // ----------------- Nest/API userId (for sellerUserId filter) -----------------
  String? _cachedNestUserId;

  Future<String?> _getNestUserId({bool allowNetwork = true}) async {
    if (_cachedNestUserId != null && _cachedNestUserId!.isNotEmpty) {
      return _cachedNestUserId;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = (sp.getString('merchant_nest_user_id') ?? '').trim();
      if (cached.isNotEmpty) {
        _cachedNestUserId = cached;
        return cached;
      }

      final token = sp.getString('jwt') ??
          sp.getString('token') ??
          sp.getString('jwt_token') ??
          sp.getString('authToken');

      if (token != null && token.trim().isNotEmpty) {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payloadJson =
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
          final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
          final rawId = payload['sub'] ?? payload['id'] ?? payload['userId'];
          if (rawId != null) {
            final id = rawId.toString();
            _cachedNestUserId = id;
            unawaited(sp.setString('merchant_nest_user_id', id));
            return id;
          }
        }
      }

      if (!allowNetwork) return null;

      final bearer = await _getBearerTokenForApi();
      if (bearer == null || bearer.isEmpty) return null;

      final base = await ApiConfig.readBase();
      final resp = await http.get(
        Uri.parse('$base/users/me'),
        headers: {
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json'
        },
      );
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body);
      final Map<String, dynamic> payload =
          (decoded is Map && decoded['data'] is Map)
              ? Map<String, dynamic>.from(decoded['data'])
              : (decoded is Map ? Map<String, dynamic>.from(decoded) : {});
      final user = (payload['user'] is Map) ? payload['user'] as Map : payload;

      final rawId = user['id'] ?? user['userId'] ?? user['sub'];
      if (rawId == null) return null;
      final id = rawId.toString();
      _cachedNestUserId = id;
      unawaited(sp.setString('merchant_nest_user_id', id));
      return id;
    } catch (_) {
      return null;
    }
  }

  // ----------------- Items load + counts (total/active) -----------------
  /// When [showLoading] is false, keeps the current grid visible while refreshing
  /// in the background (used by periodic updates so the UI stays stable).
  Future<void> _loadItems({bool showLoading = true}) async {
    // Prefer showing cached items GÇö never blank the grid while refreshing.
    if (_items.isEmpty) {
      _hydrateItemsFromLocalCache();
      if (_items.isEmpty) await _hydrateItemsFromPrefsCache();
    }

    if (showLoading && mounted && _items.isEmpty) {
      setState(() => _loadingItems = true);
    } else if (mounted && _items.isNotEmpty) {
      setState(() => _loadingItems = false);
    }

    try {
      final firebaseUid = (_auth.currentUser?.uid ?? _uid).trim();
      // Prefer Firebase UID query first (no network). Nest id is optional merge.
      final nestSellerId = await _getNestUserId(allowNetwork: false);

      Future<QuerySnapshot<Map<String, dynamic>>> runQuery(
        Query<Map<String, dynamic>> query, {
        required bool preferCache,
      }) async {
        if (preferCache) {
          try {
            final cached =
                await query.get(const GetOptions(source: Source.cache));
            if (cached.docs.isNotEmpty) return cached;
          } catch (_) {}
        }
        return query.get();
      }

      final byMerchant = <String, Map<String, dynamic>>{};

      if (firebaseUid.isNotEmpty) {
        final q = _firestore
            .collection('marketplace_items')
            .where('merchantId', isEqualTo: firebaseUid);
        final snap = await runQuery(q, preferCache: true);
        for (final doc in snap.docs) {
          byMerchant[doc.id] = {...doc.data(), 'id': doc.id};
        }
        // Paint cache/server merchantId results immediately.
        if (byMerchant.isNotEmpty) {
          _applyItemsToUi(byMerchant.values.toList());
        }
      }

      // Optional: also match sellerUserId (Nest) without blocking first paint.
      final nestId =
          nestSellerId ?? await _getNestUserId(allowNetwork: true);
      if (nestId != null && nestId.trim().isNotEmpty) {
        final q = _firestore
            .collection('marketplace_items')
            .where('sellerUserId', isEqualTo: nestId.trim());
        final snap = await runQuery(q, preferCache: true);
        for (final doc in snap.docs) {
          byMerchant[doc.id] = {...doc.data(), 'id': doc.id};
        }
      }

      // Refresh merchantId from server once (after cache paint).
      if (firebaseUid.isNotEmpty) {
        try {
          final server = await _firestore
              .collection('marketplace_items')
              .where('merchantId', isEqualTo: firebaseUid)
              .get(const GetOptions(source: Source.server));
          for (final doc in server.docs) {
            byMerchant[doc.id] = {...doc.data(), 'id': doc.id};
          }
        } catch (_) {}
      }

      _applyItemsToUi(byMerchant.values.toList());
    } catch (e) {
      debugPrint('Error loading items: $e');
      if (!mounted) return;
      if (showLoading && _items.isEmpty) {
        setState(() {
          _items = [];
          _totalItems = 0;
          _activeItems = 0;
          _loadingItems = false;
        });
      } else if (mounted) {
        setState(() => _loadingItems = false);
      }
    }
  }

  List<Map<String, dynamic>> _filteredItems() {
    final q = _searchQuery.trim().toLowerCase();
    return _items.where((it) {
      final name = (it['name'] ?? '').toString().toLowerCase();
      final cat = (it['category'] ?? 'other').toString().toLowerCase();
      final review = _itemReviewStatus(it);
      final active = it['isActive'] == true && review == 'approved';

      final okQ = q.isEmpty || name.contains(q);
      final okCat = (_filterCategory == 'all') || cat == _filterCategory;
      final okStatus = (_filterStatus == 'all') ||
          (_filterStatus == 'active' && active) ||
          (_filterStatus == 'inactive' &&
              review == 'approved' &&
              it['isActive'] != true) ||
          (_filterStatus == 'pending' &&
              (review == 'pending' || review.isEmpty && it['isActive'] != true)) ||
          (_filterStatus == 'rejected' && review == 'rejected');

      return okQ && okCat && okStatus;
    }).toList();
  }

  /// `pending` | `approved` | `rejected` | '' (legacy).
  static String _itemReviewStatus(Map<String, dynamic> it) {
    final raw = (it['reviewStatus'] ?? '').toString().trim().toLowerCase();
    if (raw == 'pending' || raw == 'approved' || raw == 'rejected') return raw;
    // Legacy listings without reviewStatus: treat active as approved.
    if (it['isActive'] == true) return 'approved';
    return '';
  }

  static String _reviewLabel(Map<String, dynamic> it) {
    final review = _itemReviewStatus(it);
    if (review == 'pending') return 'Under review';
    if (review == 'rejected') return 'Rejected';
    if (it['isActive'] == true) return 'Live';
    return 'Inactive';
  }

  static Color _reviewColor(Map<String, dynamic> it) {
    final review = _itemReviewStatus(it);
    if (review == 'pending') return Colors.orange;
    if (review == 'rejected') return Colors.red;
    if (it['isActive'] == true) return Colors.green;
    return Colors.grey;
  }

  // ----------------- Pull-to-refresh -----------------
  Future<void> _refreshAll() async {
    _hydrateFromFirebaseAuth();
    await _pullPhoneAndProfileFromFirestore();
    await _loadKycStatus();
    await _ensureBusinessName();
    await _fetchCurrentUserMe();
    await _loadMerchantData();
    await _loadItems(showLoading: false);
    await _loadOrderStats();
    if (_merchantProfileUrl.trim().isNotEmpty) {
      unawaited(_warmProfilePhotoCache(_merchantProfileUrl));
    }
  }

  Future<void> _loadKycStatus() async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final status = (data['kycStatus'] ?? '').toString().trim().toLowerCase();
      final reason = (data['kycRejectionReason'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _kycStatus = status;
        _kycRejectionReason = reason;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('KYC status load failed: $e');
    }
  }

  Future<void> _openKycVerification() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const KycVerificationScreen()),
    );
    if (!mounted) return;
    await _loadKycStatus();
  }

  // ----------------- Profile image helpers -----------------
  ImageProvider? _profileImageProvider() {
    final local = _localPhotoPath;
    if (!kIsWeb && local != null && local.isNotEmpty) {
      try {
        final f = File(local);
        if (f.existsSync()) return FileImage(f);
      } catch (_) {}
    }
    final s = _merchantProfileUrl.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return CachedNetworkImageProvider(s);
    }
    try {
      final bytes = base64Decode(s);
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ----------------- Profile photo (Firebase Storage) -----------------
  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfile(ImageSource.camera);
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: _brandOrange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_camera_outlined,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Take a photo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadProfile(ImageSource.gallery);
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E88E5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library_outlined,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Choose from gallery',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_merchantProfileUrl.trim().isNotEmpty)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePhoto();
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.remove_circle_outline,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Remove current photo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF222222),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _viewProfilePhoto() {
    final img = _profileImageProvider();
    if (img == null) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Image(image: img, fit: BoxFit.cover),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
              if (_merchantProfileUrl.trim().isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Remove profile photo?'),
                          content: const Text(
                            'This will remove your current profile picture.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text(
                                'Remove',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      await _removeProfilePhoto();
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text(
                      'Remove profile photo',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfile(ImageSource src) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final file = await _picker.pickImage(
      source: src,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;

    try {
      setState(() => _profileUploading = true);
      String url;
      final pickedBytes = await file.readAsBytes();

      // Prefer backend upload (works when Firebase Storage returns 404 / App Check).
      try {
        url = await _uploadProfileViaBackend(file);
      } catch (backendErr) {
        debugPrint('Backend profile upload failed: $backendErr');
        try {
          url = await _uploadProfileToFirebaseStorage(user.uid, file);
        } on FirebaseException catch (e) {
          if ((e.code == 'object-not-found' || e.code == 'unknown') && (e.message?.contains('404') == true)) {
            url = await _uploadProfileViaBackend(file);
          } else {
            rethrow;
          }
        }
      }

      await user.updatePhotoURL(url);
      await user.reload();

      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);

      // Persist bytes locally so the avatar shows instantly next time.
      final local = await ProfilePhotoCache.saveBytes(
        pickedBytes,
        remoteUrl: url,
      );

      if (!mounted) return;
      setState(() {
        _merchantProfileUrl = url;
        _localPhotoPath = local?.path ?? _localPhotoPath;
      });

      _toastOk('Profile picture updated');
    } on FirebaseException catch (e) {
      debugPrint('Profile upload error: ${e.code} ${e.message}');
      if (!mounted) return;
      try {
        final url = await _uploadProfileViaBackend(file);
        if (url.isNotEmpty) {
          final u = _auth.currentUser;
          if (u != null) {
            await u.updatePhotoURL(url);
            await u.reload();
            await _firestore.collection('users').doc(u.uid).set({
              'profilePicture': url,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('profilepicture', url);
            final bytes = await file.readAsBytes();
            final local = await ProfilePhotoCache.saveBytes(
              bytes,
              remoteUrl: url,
            );
            setState(() {
              _merchantProfileUrl = url;
              _localPhotoPath = local?.path ?? _localPhotoPath;
            });
            _toastOk('Profile picture updated');
            return;
          }
        }
      } catch (fallbackErr) {
        debugPrint('Backend fallback failed: $fallbackErr');
      }
      if (e.code == 'object-not-found' || (e.message ?? '').contains('404')) {
        _toastErr('Upload failed. Check network and that the server is running.');
      } else {
        _toastErr('Failed to upload photo. Please try again.');
      }
    } catch (e) {
      debugPrint('Profile upload error: $e');
      if (!mounted) return;
      _toastErr('Failed to upload photo. Please try again.');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  /// Upload via backend POST /vero/users/me/profile-picture. Uses a fresh ID token to avoid auth/id-token-expired.
  Future<String> _uploadProfileViaBackend(XFile file) async {
    String bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
    if (bearer.isEmpty) throw Exception('Not authenticated');
    final uri = ApiConfig.endpoint('/users/me/profile-picture');
    final bytes = await file.readAsBytes();
    final mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    final contentType = parts.length == 2 ? MediaType(parts[0], parts[1]) : null;

    Future<http.StreamedResponse> sendRequest(String token) async {
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'profile.jpg',
          contentType: contentType,
        ));
      return req.send();
    }

    var sent = await sendRequest(bearer);
    var resp = await http.Response.fromStream(sent);

    if (resp.statusCode == 401) {
      bearer = await _getBearerTokenForApi(forceRefresh: true) ?? '';
      if (bearer.isEmpty) throw Exception('Session expired. Please sign in again.');
      sent = await sendRequest(bearer);
      resp = await http.Response.fromStream(sent);
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 404) throw Exception('Profile picture endpoint not found');
      if (resp.statusCode == 401) throw Exception('Session expired. Please sign in again.');
      throw Exception('Upload failed (${resp.statusCode}) ${resp.body}');
    }
    final body = jsonDecode(resp.body);
    final data = (body is Map && body['data'] is Map)
        ? body['data'] as Map
        : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
    final url = (data['profilepicture'] ?? data['profilePicture'] ?? data['url'])?.toString();
    if (url == null || url.isEmpty) throw Exception('No URL in response');
    return url;
  }

  /// Upload profile image to Firebase Storage.
  /// Uses a single path segment (profile_photos/uid_timestamp.ext) to avoid 404 with nested refs.
  Future<String> _uploadProfileToFirebaseStorage(String uid, XFile file) async {
    final rawExt = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final ext = rawExt.isEmpty || rawExt.length > 4 ? 'jpg' : rawExt;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'profile_photos/${uid}_$timestamp.$ext';
    final ref = FirebaseStorage.instance.ref().child(path);

    final bytes = await file.readAsBytes();
    final mime = lookupMimeType(file.name, headerBytes: bytes) ?? 'image/jpeg';
    await ref.putData(bytes, SettableMetadata(contentType: mime));
    return await ref.getDownloadURL();
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      setState(() => _profileUploading = true);

      await user.updatePhotoURL(null);
      await user.reload();
      if (_auth.currentUser?.photoURL == null || _auth.currentUser!.photoURL!.isEmpty) {
        if (mounted) setState(() => _merchantProfileUrl = '');
      }

      await _firestore.collection('users').doc(user.uid).set({
        'profilePicture': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', '');
      await ProfilePhotoCache.clear();

      if (!mounted) return;
      setState(() {
        _merchantProfileUrl = '';
        _localPhotoPath = null;
      });

      _toastOk('Profile picture removed');
    } catch (e) {
      debugPrint('Remove photo error: $e');
      if (!mounted) return;
      _toastErr('Failed to remove photo. Please try again.');
    } finally {
      if (mounted) setState(() => _profileUploading = false);
    }
  }

  // ----------------- G£à More photos helpers -----------------
  Future<void> _pickMorePhotos() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 2048,
      );

      if (files.isEmpty) return;

      final remaining = _maxGalleryPhotos - _gallery.length;
      if (remaining <= 0) {
        if (!mounted) return;
        _toastErr('You can add up to $_maxGalleryPhotos photos.');
        return;
      }

      final toAdd = files.take(remaining).toList();
      for (final x in toAdd) {
        final bytes = await x.readAsBytes();
        _gallery.add(
          LocalMedia(
            bytes: bytes,
            filename: x.name,
            mime: lookupMimeType(x.name, headerBytes: bytes),
          ),
        );
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Pick more photos error: $e');
      if (!mounted) return;
      _toastErr('Could not pick photos. Please try again.');
    }
  }

  void _removeGalleryAt(int index) {
    if (index < 0 || index >= _gallery.length) return;
    setState(() => _gallery.removeAt(index));
  }

  String _firestoreWriteErrorMessage(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'You donGÇÖt have permission to post this listing. Please sign in again and try once more.';
        case 'unauthenticated':
          return 'Please sign in to post on Marketplace.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'WeGÇÖre having trouble connecting. Check your internet and try again.';
        case 'resource-exhausted':
          return 'Too many requests right now. Please wait a moment and try again.';
        default:
          return 'CouldnGÇÖt post your listing. Please try again.';
      }
    }
    if (e is StateError) {
      final msg = e.message.trim();
      if (msg.isNotEmpty &&
          !msg.toLowerCase().contains('firestore') &&
          !msg.toLowerCase().contains('firebase')) {
        return msg;
      }
    }
    return 'CouldnGÇÖt post your listing. Please try again.';
  }

  // ----------------- CREATE item -----------------
  Future<void> _create() async {
    // Sync lock BEFORE any await so one tap cannot post twice on slow networks.
    if (_submitting) return;
    _submitting = true;
    if (mounted) setState(() {});

    try {
      if (_cover == null) {
        _toastErr('Please pick a cover photo');
        return;
      }
      if (_name.text.isEmpty || _price.text.isEmpty || _location.text.isEmpty) {
        _toastErr('Please fill all required fields');
        return;
      }

      final stockRaw = _stock.text.trim();
      final stock = int.tryParse(stockRaw);
      if (stockRaw.isEmpty || stock == null || stock < 1) {
        _toastErr('Enter how many items you have in stock (at least 1)');
        return;
      }
      _stockQty = stock;

      final blockReason = MarketplaceModeration.clientBlockReason(
        title: _name.text,
        description: _desc.text,
      );
      if (blockReason != null) {
        _toastErr(blockReason);
        return;
      }

      final user = _auth.currentUser;
      unawaited(AuthHandler.refreshFirebaseTokenIfSignedIn());

      final firebaseUid = user?.uid ?? _uid;
      if (firebaseUid.trim().isEmpty) {
        _toastErr('Missing user id GÇö sign in and try again.');
        return;
      }
      final sellerId = await _getNestUserId();
      final merchantDisplay = _displayBusinessName();
      final effectiveSellerId =
          (sellerId != null && sellerId.trim().isNotEmpty)
              ? sellerId.trim()
              : firebaseUid;

      final svc = MarketplaceService();
      String? coverUrl;
      String? coverBase64;
      String? coverHash;
      final galleryUrls = <String>[];
      final galleryBase64 = <String>[];
      final galleryHashes = <String>[];

      // Prefer backend upload URLs; fall back to base64 in Firestore if server is unreachable.
      try {
        coverUrl = await svc.uploadBytes(
          _cover!.bytes,
          filename: _cover!.filename ?? 'cover.jpg',
          mimeType: _cover!.mime,
        );
        coverHash = await svc.computeVisualHash(_cover!.bytes);

        for (final m in _gallery) {
          final url = await svc.uploadBytes(
            m.bytes,
            filename: m.filename.isNotEmpty ? m.filename : 'gallery.jpg',
            mimeType: m.mime,
          );
          galleryUrls.add(url);
          final gHash = await svc.computeVisualHash(m.bytes);
          if (gHash != null) galleryHashes.add(gHash);
        }
      } catch (uploadErr) {
        debugPrint('Backend upload failed, saving to Firestore as base64: $uploadErr');
        if (_cover!.bytes.length > 450000) {
          throw StateError(
            'Image upload failed and the photo is too large to save offline. '
            'Check internet and that your backend server is running.',
          );
        }
        coverBase64 = base64Encode(_cover!.bytes);
        coverHash = await svc.computeVisualHash(_cover!.bytes);
        for (final m in _gallery) {
          galleryBase64.add(base64Encode(m.bytes));
          final gHash = await svc.computeVisualHash(m.bytes);
          if (gHash != null) galleryHashes.add(gHash);
        }
      }

      final imageHashes = <String>{
        if (coverHash != null) coverHash,
        ...galleryHashes,
      }.toList();

      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0,
        if (coverUrl != null) 'imageUrl': coverUrl,
        if (coverBase64 != null) 'image': coverBase64,
        if (galleryUrls.isNotEmpty) 'galleryUrls': galleryUrls,
        if (galleryBase64.isNotEmpty) 'gallery': galleryBase64,
        if (coverHash != null) 'imageHash': coverHash,
        if (galleryHashes.isNotEmpty) 'galleryHashes': galleryHashes,
        if (imageHashes.isNotEmpty) 'imageHashes': imageHashes,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'location': _location.text.trim(),
        // Always pending until Cloud Function auto-moderation approves.
        'isActive': false,
        'reviewStatus': 'pending',
        'category': _category ?? 'other',
        'createdAt': FieldValue.serverTimestamp(),
        'sellerUserId': effectiveSellerId,
        'merchantId': firebaseUid,
        'firebaseUid': firebaseUid,
        if (sellerId != null)
          'merchantBackendId': int.tryParse(sellerId.trim()),
        'merchantName': merchantDisplay,
        'serviceType': 'marketplace',
        'stockQuantity': _stockQty,
        'quantity': _stockQty,
      };

      await _firestore.collection('marketplace_items').add(data);
      debugPrint('Firestore write OK GåÆ marketplace_items (pending review)');

      if (!mounted) return;
      _toastOk('Submitted for review. WeGÇÖll notify you when itGÇÖs live.');

      _name.clear();
      _price.clear();
      _location.clear();
      _desc.clear();
      _stock.text = '1';
      _stockQty = 1;
      _cover = null;
      _gallery.clear();
      _isActive = true;
      _category = 'other';

      setState(() {});
      unawaited(_loadItems(showLoading: false));
      _marketplaceTabs.animateTo(2);
    } on FirebaseException catch (e) {
      debugPrint('Create item Firestore error: ${e.code} ${e.message}');
      if (!mounted) return;
      _toastErr(_firestoreWriteErrorMessage(e));
    } catch (e) {
      debugPrint('Create item error: $e');
      if (!mounted) return;
      _toastErr(_firestoreWriteErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item'),
        content: Text('Delete "${item['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyRow = true);
    try {
      final id = item['id'] as String;
      await _firestore.collection('marketplace_items').doc(id).delete();
      _items.removeWhere((e) => e['id'] == id);
      unawaited(_persistItemsCache(_items));

      if (!mounted) return;
      _toastOk('Deleted GÇó ${item['name']}');

      setState(() {
        _totalItems = _items.length;
        _activeItems = _items.where((e) => e['isActive'] == true).length;
      });
    } catch (e) {
      debugPrint('Delete item error: $e');
      if (!mounted) return;
      _toastErr('Delete failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busyRow = false);
    }
  }

  // G£à FIXED: no parent setState while sheet is closing + no crash after save
  Future<void> _openEditItemSheet(Map<String, dynamic> item) async {
    final id = (item['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    _sheetOpen = true;

    final rootCtx = context;

    final nameCtrl =
        TextEditingController(text: (item['name'] ?? '').toString());
    final priceCtrl =
        TextEditingController(text: (item['price'] ?? '').toString());
    final locationCtrl =
        TextEditingController(text: (item['location'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (item['description'] ?? '').toString());
    final stockCtrl = TextEditingController(
      text: (() {
        final raw = item['stockQuantity'] ?? item['quantity'] ?? item['stock'];
        final n = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
        return '${(n == null || n < 1) ? 1 : n}';
      })(),
    );
    int stockQty = int.tryParse(stockCtrl.text) ?? 1;

    String category = (item['category'] ?? 'other').toString();
    bool isActive = item['isActive'] == true;

    LocalMedia? newCover;

    final didSave = await showModalBottomSheet<bool>(
      context: rootCtx,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        bool saving = false;

        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;

            Future<void> pickNewCoverFrom(ImageSource src) async {
              final x = await _picker.pickImage(
                source: src,
                maxWidth: 1800,
                imageQuality: 90,
              );
              if (x == null) return;

              final bytes = await x.readAsBytes();
              setSheet(() {
                newCover = LocalMedia(
                  bytes: bytes,
                  filename: x.name,
                  mime: lookupMimeType(x.name, headerBytes: bytes),
                );
              });
            }

            void showEditCoverSource() {
              showModalBottomSheet(
                context: sheetCtx,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (_) => SafeArea(
                  child: Wrap(
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.pop(_);
                          pickNewCoverFrom(ImageSource.camera);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF8A00),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_outlined,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Take a photo',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF222222),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.pop(_);
                          pickNewCoverFrom(ImageSource.gallery);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1E88E5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.photo_library_outlined,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Choose from gallery',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF222222),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Future<void> save() async {
              if (saving) return;

              FocusScope.of(sheetCtx).unfocus();

              final n = nameCtrl.text.trim();
              final p = double.tryParse(priceCtrl.text.trim()) ?? 0;
              final loc = locationCtrl.text.trim();
              final stockRaw = stockCtrl.text.trim();
              final stock = int.tryParse(stockRaw);

              if (n.isEmpty || p <= 0 || loc.isEmpty) {
                ToastHelper.showCustomToast(
                  rootCtx,
                  'Fill name, price and location',
                  isSuccess: false,
                  errorMessage: '',
                );
                return;
              }
              if (stockRaw.isEmpty || stock == null || stock < 1) {
                ToastHelper.showCustomToast(
                  rootCtx,
                  'Enter quantity in stock (at least 1)',
                  isSuccess: false,
                  errorMessage: '',
                );
                return;
              }
              stockQty = stock;

              setSheet(() => saving = true);

              try {
                final blockReason = MarketplaceModeration.clientBlockReason(
                  title: n,
                  description: descCtrl.text,
                );
                if (blockReason != null) {
                  ToastHelper.showCustomToast(
                    rootCtx,
                    blockReason,
                    isSuccess: false,
                    errorMessage: '',
                  );
                  setSheet(() => saving = false);
                  return;
                }

                final prevReview = _itemReviewStatus(item);
                final patch = <String, dynamic>{
                  'name': n,
                  'price': p,
                  'location': loc,
                  'category': category,
                  'description': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'stockQuantity': stockQty,
                  'quantity': stockQty,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (prevReview == 'rejected' || prevReview == 'pending') {
                  // Resubmit for auto-moderation.
                  patch['isActive'] = false;
                  patch['reviewStatus'] = 'pending';
                  patch['rejectedReason'] = FieldValue.delete();
                  patch['moderationResubmittedAt'] =
                      FieldValue.serverTimestamp();
                } else {
                  // Already approved: merchant can pause/unpause.
                  patch['isActive'] = isActive;
                }

                if (newCover != null) {
                  patch['image'] = base64Encode(newCover!.bytes);
                  final coverHash = await MarketplaceService().computeVisualHash(newCover!.bytes);
                  if (coverHash != null) {
                    patch['imageHash'] = coverHash;
                    patch['imageHashes'] = FieldValue.arrayUnion([coverHash]);
                  }
                  if (prevReview == 'approved') {
                    // New cover on live item GåÆ re-review.
                    patch['isActive'] = false;
                    patch['reviewStatus'] = 'pending';
                  }
                }

                await _firestore.collection('marketplace_items').doc(id).update(
                      patch,
                    );

                if (Navigator.of(sheetCtx).canPop()) {
                  Navigator.of(sheetCtx).pop(true);
                }
              } catch (e) {
                debugPrint('Update item error: $e');
                ToastHelper.showCustomToast(
                  rootCtx,
                  'Update failed. Please try again.',
                  isSuccess: false,
                  errorMessage: '',
                );
                try {
                  setSheet(() => saving = false);
                } catch (_) {}
              }
            }

            final coverWidget = newCover != null
                ? Image.memory(newCover!.bytes, fit: BoxFit.cover)
                : _ImageAny(_coverImageSourceFromItem(item));

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 14,
                bottom: 16 + bottomInset,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Edit Item',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 160,
                        width: double.infinity,
                        child: coverWidget,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: saving ? null : showEditCoverSource,
                      icon: const Icon(Icons.photo),
                      label: const Text(
                        'Change Cover',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: _inputDecoration(label: 'Item Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(label: 'Price (MWK)'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Quantity in stock *',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: saving || stockQty <= 1
                              ? null
                              : () => setSheet(() {
                                    stockQty =
                                        (stockQty - 1).clamp(1, 99999);
                                    stockCtrl.text = '$stockQty';
                                  }),
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        SizedBox(
                          width: 56,
                          child: TextField(
                            controller: stockCtrl,
                            enabled: !saving,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v) ?? 1;
                              setSheet(
                                  () => stockQty = n.clamp(1, 99999));
                            },
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: saving
                              ? null
                              : () => setSheet(() {
                                    stockQty =
                                        (stockQty + 1).clamp(1, 99999);
                                    stockCtrl.text = '$stockQty';
                                  }),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locationCtrl,
                      decoration: _inputDecoration(label: 'Location'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      items: _kCategories
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child:
                                    Text(c[0].toUpperCase() + c.substring(1)),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => setSheet(() => category = v ?? 'other'),
                      decoration: _inputDecoration(label: 'Category'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      minLines: 3,
                      maxLines: 5,
                      decoration:
                          _inputDecoration(label: 'Description (optional)'),
                    ),
                    const SizedBox(height: 12),
                    if (_itemReviewStatus(item) == 'rejected') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFCDD2)),
                        ),
                        child: Text(
                          (item['rejectedReason'] ??
                                  'This listing was not approved. Edit the photo/text and save to resubmit for review.')
                              .toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.35,
                            color: Color(0xFFB71C1C),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tip: use a clear product photo on a plain background â€” avoid people, selfies, or suggestive poses.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.3,
                          color: Color(0xFF6B778C),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_itemReviewStatus(item) == 'pending') ...[
                      const Text(
                        'Under review GÇö edits will keep this listing pending until approved.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_itemReviewStatus(item) == 'approved')
                      Row(
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: saving
                                ? null
                                : (v) => setSheet(() => isActive = v),
                          ),
                          Text(
                            isActive ? 'Live' : 'Inactive',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: _filledBtnStyle(),
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _itemReviewStatus(item) == 'rejected' ||
                                  _itemReviewStatus(item) == 'pending'
                              ? 'Post on Marketplace'
                              : 'Save Changes',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // G£à allow sheet route to fully finish closing animation before disposing
    await Future.delayed(const Duration(milliseconds: 350));
    nameCtrl.dispose();
    priceCtrl.dispose();
    locationCtrl.dispose();
    descCtrl.dispose();
    stockCtrl.dispose();
    _sheetOpen = false;

    if (didSave == true && mounted) {
      await _loadItems(showLoading: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _toastOk('Item updated');
      });
    }
  }

  // ----------------- Location helpers -----------------
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        _toastErr('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          _toastErr('Location permissions are denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        _toastErr('Location permissions are permanently denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isEmpty) {
        if (!mounted) return;
        _toastErr('Could not fetch address.');
        return;
      }

      final place = placemarks[0];
      final address = [
        place.name,
        place.street,
        place.locality,
        place.administrativeArea,
        place.country,
      ].where((e) => e != null && e.isNotEmpty).join(', ');

      setState(() => _location.text = address);
    } catch (e) {
      debugPrint('Location error: $e');
      if (!mounted) return;
      _toastErr('Failed to get location. Please try again.');
    }
  }

  Future<void> _openGoogleMap() async {
    if (_location.text.trim().isEmpty) {
      _toastErr('Enter a location first.');
      return;
    }
    final query = Uri.encodeComponent(_location.text.trim());
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _toastErr('Could not open Google Maps.');
    }
  }

  // ----------------- UI helpers -----------------
  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black12),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandOrange, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  ButtonStyle _filledBtnStyle({double padV = 14}) => FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: EdgeInsets.symmetric(vertical: padV, horizontal: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      );

  Widget _compactStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------- NAV + Scaffold -----------------
  int _selectedIndex = 0;

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: _selectedIndex == 4 ? _buildDashboardAppBar() : null,
      body: _getCurrentPage(),
      bottomNavigationBar: widget.embeddedInMainNav ? null : _buildMerchantNavBar(),
    );
  }

  AppBar _buildDashboardAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: 22,
          ),
          SizedBox(width: 8),
          Text(
            'Merchant Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
      backgroundColor: _brandOrange,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              StoryProfileRing(
                merchantId: _auth.currentUser?.uid ?? _uid,
                merchantName: _businessName.isNotEmpty
                    ? _businessName
                    : (_auth.currentUser?.displayName ?? 'Merchant'),
                merchantImageUrl:
                    _merchantProfileUrl.isNotEmpty ? _merchantProfileUrl : null,
                size: 36,
                imageProvider: _profileImageProvider(),
                placeholderIcon: Icons.person,
                onNoStoriesTap: () {
                  final uid = _auth.currentUser?.uid;
                  if (uid == null) {
                    _toastErr('Please sign in to post a story');
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute<bool>(
                      builder: (_) => PostStoryPage(
                        merchantId: uid,
                        merchantName: _businessName.isNotEmpty
                            ? _businessName
                            : (_auth.currentUser?.displayName ?? 'Merchant'),
                        merchantImageUrl: _merchantProfileUrl.isNotEmpty
                            ? _merchantProfileUrl
                            : null,
                        serviceType: 'marketplace',
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    final uid = _auth.currentUser?.uid;
                    if (uid == null) {
                      _toastErr('Please sign in to post a story');
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute<bool>(
                        builder: (_) => PostStoryPage(
                          merchantId: uid,
                          merchantName: _businessName.isNotEmpty
                              ? _businessName
                              : (_auth.currentUser?.displayName ?? 'Merchant'),
                          merchantImageUrl: _merchantProfileUrl.isNotEmpty
                              ? _merchantProfileUrl
                              : null,
                          serviceType: 'marketplace',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF25D366),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(onBackToHomeTab: () {}),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _getCurrentPage() {
    switch (_selectedIndex) {
      case 0:
        return Vero360Homepage(email: widget.email);
      case 1:
        return MarketPage(
          cartService: _cartService,
          onBackToHome: () => setState(() => _selectedIndex = 0),
        );
      case 2:
        return CartPage(cartService: _cartService);
      case 3:
        return const ChatListPage();
      case 4:
        return _buildDashboardContent();
      default:
        return Vero360Homepage(email: widget.email);
    }
  }

  String _merchantGuideDoneKey([String? uid]) {
    final id = (uid ?? _auth.currentUser?.uid ?? '').trim();
    if (id.isEmpty) return _kMerchantGuidePrefKey;
    return '${_kMerchantGuidePrefKey}_$id';
  }

  Future<bool> _isMerchantGuideDone(SharedPreferences prefs) async {
    final uid = (_auth.currentUser?.uid ?? '').trim();
    final scoped = _merchantGuideDoneKey(uid);
    if (prefs.getBool(scoped) == true) return true;
    // Migrate legacy device-wide flag â†’ per-account.
    if (prefs.getBool(_kMerchantGuidePrefKey) == true) {
      if (uid.isNotEmpty) {
        await prefs.setBool(scoped, true);
      }
      return true;
    }
    return false;
  }

  Future<void> _maybeShowMerchantGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Show guide until the merchant has completed or skipped it (once per account).
      if (await _isMerchantGuideDone(prefs)) return;
      if (!mounted) return;
      setState(() {
        _showMerchantGuide = true;
        _merchantGuideStep = 0;
      });
      // Match the first card (Add Item) to the Add Item tab GÇö not the previous tab.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showMerchantGuide) return;
        _syncMerchantGuideTab(_merchantGuideStep);
      });
    } catch (_) {}
  }

  /// Tabs: 0 Dashboard, 1 Add Item, 2 My Items GÇö align with [_merchantGuideSteps] copy.
  void _syncMerchantGuideTab(int step) {
    if (step < 0 || step >= _merchantGuideSteps.length) return;
    final int tab = switch (step) {
      0 => 1, // Add Item
      1 => 2, // My Items
      2 || 3 => 0, // Wallet + orders / recent sales on Dashboard
      _ => 0,
    };
    if (_marketplaceTabs.index == tab) return;
    _marketplaceTabs.animateTo(tab);
  }

  Future<void> _completeMerchantGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = (_auth.currentUser?.uid ?? '').trim();
      await prefs.setBool(_merchantGuideDoneKey(uid), true);
      // Legacy key kept so older login checks still treat the guide as finished.
      await prefs.setBool(_kMerchantGuidePrefKey, true);
      await prefs.setBool(_kMerchantGuideShowOnNextOpenKey, false);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _showMerchantGuide = false;
      _merchantGuideStep = 0;
    });
  }

  static const List<({String title, String body, IconData icon})> _merchantGuideSteps = [
    (title: 'ikani katundu wanu koyamba', body: 'Dinani "Add Item" kuti muike katundu wanu. kenako ikani  name, price, photo and category.', icon: Icons.add_box_rounded),
    (title: 'kulongosola katundu wanu', body: 'Yuzani "My Items"  kt mu wone, musithe,kuika ndikuchosa katundu wanu pa msika.', icon: Icons.inventory_2_rounded),
    (title: 'Tsegulani waleti yanu', body: 'tsegulani Waleti yanu pa dashboard kuti muthe kulandila ma payments and ikani PIN kuti muteteze waleti yanu.', icon: Icons.account_balance_wallet_rounded),
    (title: 'Mukagulisa', body: 'pitani ku dashboard dinani send parcels,ikani receipt ya courier tumizani katundu kenako dikililani ndalama zanu . onani zomwe mwagulisa pa recent Sales  ndipo pangani makasitomala anu kukhala a tcheru.', icon: Icons.local_shipping_rounded),
  ];

  Widget _buildMerchantGuideOverlay() {
    final step = _merchantGuideSteps[_merchantGuideStep];
    final isLast = _merchantGuideStep == _merchantGuideSteps.length - 1;

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Stack(
          children: [
            GestureDetector(onTap: () {}),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Quick guide',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _brandOrange,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _completeMerchantGuide(),
                            style: TextButton.styleFrom(foregroundColor: _brandOrange),
                            child: const Text('Skip'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _brandOrange.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(step.icon, size: 48, color: _brandOrange),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        step.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        step.body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _merchantGuideSteps.length,
                          (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _merchantGuideStep ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _merchantGuideStep
                                  ? _brandOrange
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _brandOrange,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            if (isLast) {
                              _completeMerchantGuide();
                              return;
                            }
                            setState(() => _merchantGuideStep++);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _syncMerchantGuideTab(_merchantGuideStep);
                            });
                          },
                          child: Text(
                            isLast ? 'Ndamva!' : 'Next',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const _DashboardSkeleton();
    }

    if (!_merchantGuideCheckScheduled) {
      _merchantGuideCheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowMerchantGuide());
    }

    // G£à removed DefaultTabController (it can trigger dependents assertion in some setups)
    return Stack(
      children: [
        Column(
          children: [
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _marketplaceTabs,
                labelColor: _brandOrange,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _brandOrange,
                tabs: const [
                  Tab(text: 'Dashboard'),
                  Tab(text: 'Add Item'),
                  Tab(text: 'My Items'),
                 //  Tab(text: 'Vero Ride'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _marketplaceTabs,
                children: [
                  RefreshIndicator(
                    onRefresh: _refreshAll,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        veroFloatingNavClearance(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildModernHeaderCard(),
                          const SizedBox(height: 12),
                          _buildKycSection(),
                          const SizedBox(height: 12),
                          _buildStatsSection(),
                          const SizedBox(height: 12),
                          _buildQuickActionsSection(),
                          const SizedBox(height: 12),
                          _buildWalletSummary(),
                          const SizedBox(height: 12),
                          _buildRecentSales(),
                          const SizedBox(height: 12),
                          _buildAllClientItemsSection(),
                        ],
                      ),
                    ),
                  ),
                  _buildAddItemTab(),
                  _buildMyItemsTab(),
                ],
              ),
            ),
          ],
        ),
        if (_showMerchantGuide) _buildMerchantGuideOverlay(),
      ],
    );
  }

  // ----------------- Header (modern) -----------------
  Widget _buildKycSection() {
    final status = _kycStatus.trim().toLowerCase();
    final verified = status == 'verified' || status == 'approved';
    final pending = status == 'pending' || status == 'in_review' || status == 'submitted';
    final rejected = status == 'rejected' || status == 'declined';

    late final String title;
    late final String subtitle;
    late final Color badgeBg;
    late final Color badgeFg;
    late final String badgeLabel;
    late final IconData icon;

    if (verified) {
      title = 'Identity verified';
      subtitle = 'Your KYC check is complete.';
      badgeBg = const Color(0xFFE7F6EC);
      badgeFg = Colors.green.shade700;
      badgeLabel = 'Verified';
      icon = Icons.verified_user_rounded;
    } else if (pending) {
      title = 'Verification in progress';
      subtitle = 'We are reviewing your Didit submission.';
      badgeBg = const Color(0xFFFFF3E5);
      badgeFg = const Color(0xFFB86E00);
      badgeLabel = 'Pending';
      icon = Icons.hourglass_top_rounded;
    } else if (rejected) {
      title = 'Verification needs attention';
      subtitle = _kycRejectionReason.isNotEmpty
          ? _kycRejectionReason
          : 'Your previous attempt was declined. Try again.';
      badgeBg = const Color(0xFFFFEDEE);
      badgeFg = Colors.red.shade700;
      badgeLabel = 'Rejected';
      icon = Icons.gpp_bad_outlined;
    } else {
      title = 'Verify your identity';
      subtitle =
          'Complete a quick ID + face check with Didit to unlock full merchant trust.';
      badgeBg = const Color(0xFFFFF3E5);
      badgeFg = const Color(0xFFB86E00);
      badgeLabel = 'Required';
      icon = Icons.badge_outlined;
    }

    final canStart = !verified;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: canStart ? _openKycVerification : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _brandOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _brandOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'KYC verification',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: badgeFg,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF101010),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (canStart) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeaderCard() {
    final business = _displayBusinessName();
    final st = _status.trim().toLowerCase();
    final statusText = st.isEmpty ? 'PENDING' : st.toUpperCase();

    Color statusBg;
    Color statusFg;
    if (st == 'approved' || st == 'active') {
      statusBg = const Color(0xFFE7F6EC);
      statusFg = Colors.green.shade700;
    } else if (st == 'pending' || st == 'under_review' || st == 'submitted') {
      statusBg = const Color(0xFFFFF3E5);
      statusFg = const Color(0xFFB86E00);
    } else {
      statusBg = const Color(0xFFFFEDEE);
      statusFg = Colors.red.shade700;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_brandNavy, _brandNavy.withOpacity(0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                StoryProfileRing(
                  merchantId: _uid.isNotEmpty ? _uid : (_auth.currentUser?.uid ?? ''),
                  merchantName: business,
                  merchantImageUrl:
                      _merchantProfileUrl.isNotEmpty ? _merchantProfileUrl : null,
                  size: 56,
                  imageProvider: _profileImageProvider(),
                  placeholderIcon: Icons.storefront_rounded,
                  onNoStoriesTap: _viewProfilePhoto,
                ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: _showPhotoSheet,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _brandOrange,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _profileUploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.edit,
                                size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _merchantEmail,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _displayMerchantPhone,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _editBusinessDescription,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _businessDescription.trim().isEmpty
                                    ? 'Add a short business description'
                                    : _businessDescription.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _editShopHours,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _shopHoursSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: Colors.white54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(statusText,
                            style: TextStyle(
                                color: statusFg,
                                fontWeight: FontWeight.w900,
                                fontSize: 12)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isShopOpenNow
                              ? const Color(0xFFE7F6EC)
                              : const Color(0xFFFFEDEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _isShopOpenNow ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: _isShopOpenNow
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                      if (_loadingMe)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- Smaller Business Overview cards -----------------
  Widget _buildStatsSection() {
    // Use fixed Rows (not nested GridView) so TabBarView/scroll nesting
    // cannot invent a full-viewport empty gap under the tiles.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Business Overview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _twoColumnTiles(
          height: 74,
          children: [
            _compactStatTile(
              title: 'Total Items',
              value: '$_totalItems',
              icon: Icons.inventory_2,
              color: _brandOrange,
            ),
            _compactStatTile(
              title: 'Active Items',
              value: '$_activeItems',
              icon: Icons.verified_rounded,
              color: Colors.green,
            ),
            _compactStatTile(
              title: 'Sold Items',
              value: '$_soldItems',
              icon: Icons.shopping_bag_rounded,
              color: Colors.blue,
            ),
            _compactStatTile(
              title: 'Earnings',
              value: mwk0(_totalEarnings),
              icon: Icons.payments_rounded,
              color: Colors.green,
            ),
          ],
        ),
      ],
    );
  }

  /// Compact 2-column tile grid without nested scrollables.
  Widget _twoColumnTiles({
    required List<Widget> children,
    double height = 74,
    double gap = 12,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: gap));
      final right = i + 1 < children.length ? children[i + 1] : null;
      rows.add(
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              SizedBox(width: gap),
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  // ----------------- Quick actions + profile actions -----------------
  Widget _buildQuickActionsSection() {
    final actions = <Widget>[
      _QuickActionTile(
        title: 'Add Item',
        icon: Icons.add_circle_outline,
        color: _brandOrange,
        onTap: () => _marketplaceTabs.animateTo(1),
      ),
      _QuickActionTile(
        title: 'My Items',
        icon: Icons.inventory_2_outlined,
        color: _brandNavy,
        onTap: () => _marketplaceTabs.animateTo(2),
      ),
      _QuickActionTile(
        title: 'My Orders',
        icon: Icons.receipt_long,
        color: Colors.green,
        badgeRoute: NotificationStore.kBadgeMyOrders,
        onTap: () => _openBottomSheet(const OrdersPage()),
      ),
      _QuickActionTile(
        title: 'Latest Arrivals',
        icon: Icons.rocket,
        color: Colors.orange,
        badgeRoute: NotificationStore.kBadgePostArrival,
        onTap: () => _openBottomSheet(const LatestArrivalsCrudPage()),
      ),
      _QuickActionTile(
        title: 'Send parcels',
        icon: Icons.local_shipping_outlined,
        color: Colors.orange,
        badgeRoute: NotificationStore.kBadgeShipped,
        onTap: () => _openBottomSheet(const ToShipPage()),
      ),
      _QuickActionTile(
        title: 'Received',
        icon: Icons.move_to_inbox_outlined,
        color: Colors.blue,
        badgeRoute: NotificationStore.kBadgeReceived,
        onTap: () => _openBottomSheet(const DeliveredOrdersPage()),
      ),
      _QuickActionTile(
        title: 'Refund',
        icon: Icons.replay_circle_filled_outlined,
        color: Colors.red,
        badgeRoute: NotificationStore.kBadgeRefund,
        onTap: () => _openBottomSheet(const ToRefundPage()),
      ),
      _QuickActionTile(
        title: 'Promotions',
        icon: Icons.campaign_outlined,
        color: Colors.orange,
        badgeRoute: NotificationStore.kBadgePromotions,
        onTap: () => _openBottomSheet(const PromotionsCrudPage()),
      ),
      _QuickActionTile(
        title: 'My Vero Ride',
        icon: Icons.directions_car_filled_rounded,
        color: Colors.orange,
        onTap: _openRideHistory,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _twoColumnTiles(height: 74, children: actions),
      ],
    );
  }

  void _openRideHistory() {
    _openBottomSheet(
      const RideHistoryScreen(mode: RideHistoryMode.passenger),
    );
  }

  void _openBottomSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: child,
      ),
    );
  }

  // ----------------- Wallet Summary (LOCKED) -----------------
  Widget _buildWalletSummary() {
    final titleName = _displayBusinessName();
    final unlocked = _walletUnlockedNow;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (unlocked ? Colors.green : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              unlocked
                  ? Icons.account_balance_wallet_rounded
                  : Icons.lock_rounded,
              color: unlocked ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wallet Balance',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  unlocked ? mwk2(_walletBalance) : 'MWK GÇóGÇóGÇóGÇó', // G£à commas
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: unlocked ? Colors.green : Colors.black54,
                  ),
                ),
                if (!unlocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Locked GÇö tap Open to unlock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              final ok = await _unlockWalletWithPin();
              if (!ok || !mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: titleName,
                    serviceType: 'marketplace',
                  ),
                ),
              );
            },
            child: const Text('Open',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ----------------- Recent Sales (real confirmed+paid orders) -----------------
  static final DateFormat _recentSaleDateFmt =
      DateFormat('dd MMM yyyy, HH:mm');

  Widget _buildRecentSales() {
    final query = _recentSalesSearchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _recentSalesOrders
        : _recentSalesOrders.where((o) {
            return o.orderNumber.toLowerCase().contains(query) ||
                o.itemName.toLowerCase().contains(query);
          }).toList();
    final displayList = filtered.take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Recent Sales',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => _recentSalesSearchFocus.requestFocus(),
              tooltip: 'Search by order number or item name',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: _recentSalesSearchController,
            focusNode: _recentSalesSearchFocus,
            decoration: InputDecoration(
              hintText: 'Order No or item name',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () {
                        _recentSalesSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 6),
        if (_recentSalesOrders.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No sales yet')),
          )
        else if (displayList.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: Center(
                child: Text('No matches for "$query"')),
          )
        else
          ...displayList.map((o) {
            final dateStr = o.orderDate != null
                ? _recentSaleDateFmt.format(o.orderDate!.toLocal())
                : 'GÇö';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _brandOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shopping_bag_rounded,
                      color: _brandOrange),
                ),
                title: Text(o.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Order: ${o.orderNumber}'),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: o.orderNumber));
                              ToastHelper.showCustomToast(context, 'Order number copied', isSuccess: true, errorMessage: '');
                            },
                            tooltip: 'Copy order number',
                          ),
                        ],
                      ),
                      Text('${mwk0(o.total)}  -+  $dateStr'),
                    ],
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Paid',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ),
            );
          }),
      ],
    );
  }


  // ----------------- GÇ£Top itemsGÇ¥ replaced: list ALL merchant items -----------------
  Widget _buildAllClientItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('My Items',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        if (_loadingItems)
          const _ItemsGridSkeleton(count: 6)
        else if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No items yet')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: _merchantItemsGridDelegate(context),
            itemBuilder: (_, i) => _ModernItemMiniCard(item: _items[i]),
          ),
      ],
    );
  }

  // ----------------- G£à Add Item Tab (with multi-photos) -----------------
  Widget _buildAddItemTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        veroFloatingNavClearance(context),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AbsorbPointer(
            absorbing: _submitting,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add New Item',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              const Text('Cover Image',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _cover == null
                    ? Container(
                        height: 160,
                        color: const Color(0xFFF3F4F7),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.image,
                                  size: 40, color: Colors.black26),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: _brandOrange),
                                onPressed: _showCoverImageSource,
                                icon: const Icon(Icons.add_photo_alternate),
                                label: const Text('Select Image'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          Image.memory(
                            _cover!.bytes,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: InkWell(
                              onTap: () => setState(() => _cover = null),
                              child: const CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),

              // G£à More Photos
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'More Photos (optional)',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '${_gallery.length}/$_maxGalleryPhotos',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _gallery.length >= _maxGalleryPhotos
                          ? null
                          : _showMorePhotosSource,
                      icon: const Icon(Icons.collections_outlined),
                      label: Text(
                        _gallery.isEmpty ? 'Add Photos' : 'Add More',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_gallery.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => setState(() => _gallery.clear()),
                      child: const Text('Clear',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_gallery.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _gallery.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (_, i) {
                    final m = _gallery[i];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            m.bytes,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: InkWell(
                            onTap: () => _removeGalleryAt(i),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

              const SizedBox(height: 14),

              TextField(
                  controller: _name,
                  decoration: _inputDecoration(label: 'Item Name')),
              const SizedBox(height: 10),
              TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(label: 'Price (MWK)')),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Quantity in stock *',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _stockQty <= 1
                        ? null
                        : () => setState(() {
                              _stockQty = (_stockQty - 1).clamp(1, 99999);
                              _stock.text = '$_stockQty';
                            }),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _stock,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v) ?? 1;
                        setState(() => _stockQty = n.clamp(1, 99999));
                      },
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _stockQty = (_stockQty + 1).clamp(1, 99999);
                      _stock.text = '$_stockQty';
                    }),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _location,
                decoration: _inputDecoration(label: 'Location').copyWith(
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.my_location),
                          onPressed: _getCurrentLocation),
                      IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: _openGoogleMap),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: _kCategories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c[0].toUpperCase() + c.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v),
                decoration: _inputDecoration(label: 'Category'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                minLines: 3,
                maxLines: 5,
                decoration: _inputDecoration(label: 'Description (optional)'),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD59A)),
                ),
                child: const Text(
                  'New listings are reviewed automatically before going live. '
                  'YouGÇÖll get a notification when yours is approved.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: _filledBtnStyle(),
                  onPressed: _submitting ? null : _create,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_rounded),
                  label: Text(
                    _submitting ? 'PostingGÇª' : 'Post on Marketplace',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------- My Items Tab: Search + Filter chips + Edit -----------------
  Widget _buildMyItemsTab() {
    final filtered = _filteredItems();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search items...',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _brandOrange, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip(
                      label: 'All Categories',
                      selected: _filterCategory == 'all',
                      onTap: () => setState(() => _filterCategory = 'all'),
                    ),
                    ..._kCategories.map((c) => _chip(
                          label: c[0].toUpperCase() + c.substring(1),
                          selected: _filterCategory == c,
                          onTap: () => setState(() => _filterCategory = c),
                        )),
                    const SizedBox(width: 10),
                    _chip(
                      label: 'All',
                      selected: _filterStatus == 'all',
                      onTap: () => setState(() => _filterStatus = 'all'),
                    ),
                    _chip(
                      label: 'Live',
                      selected: _filterStatus == 'active',
                      onTap: () => setState(() => _filterStatus = 'active'),
                    ),
                    _chip(
                      label: 'Under review',
                      selected: _filterStatus == 'pending',
                      onTap: () => setState(() => _filterStatus = 'pending'),
                    ),
                    _chip(
                      label: 'Rejected',
                      selected: _filterStatus == 'rejected',
                      onTap: () => setState(() => _filterStatus = 'rejected'),
                    ),
                    _chip(
                      label: 'Inactive',
                      selected: _filterStatus == 'inactive',
                      onTap: () => setState(() => _filterStatus = 'inactive'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingItems
              ? const _ItemsGridSkeleton(count: 8)
              : filtered.isEmpty
                  ? const Center(child: Text('No items match your filters'))
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        veroFloatingNavClearance(context),
                      ),
                      itemCount: filtered.length,
                      gridDelegate: _merchantItemsGridDelegate(context),
                      itemBuilder: (_, i) => _ItemCard(
                        item: filtered[i],
                        busy: _busyRow,
                        onDelete: () => _deleteItem(filtered[i]),
                        onEdit: () => _openEditItemSheet(filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: _brandOrange.withOpacity(0.16),
        labelStyle: TextStyle(color: selected ? _brandOrange : Colors.black87),
        side: const BorderSide(color: Colors.black12),
      ),
    );
  }

  // ----------------- cover picker -----------------
  void _showCoverImageSource() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickCover(ImageSource.camera);
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF8A00),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Take a photo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickCover(ImageSource.gallery);
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E88E5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Choose from gallery',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCover(ImageSource src) async {
    final x = await _picker.pickImage(
      source: src,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _cover = LocalMedia(
        bytes: bytes,
        filename: x.name,
        mime: lookupMimeType(x.name, headerBytes: bytes),
      );
    });
  }

  void _showMorePhotosSource() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickMorePhotosFromCamera();
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF8A00),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Take a photo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickMorePhotos();
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E88E5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Choose from gallery',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF222222),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMorePhotosFromCamera() async {
    try {
      if (_gallery.length >= _maxGalleryPhotos) {
        _toastErr('You can add up to $_maxGalleryPhotos photos.');
        return;
      }
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2048,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _gallery.add(
          LocalMedia(
            bytes: bytes,
            filename: x.name,
            mime: lookupMimeType(x.name, headerBytes: bytes),
          ),
        );
      });
    } catch (e) {
      debugPrint('Pick from camera error: $e');
      if (!mounted) return;
      _toastErr('Could not take photo. Please try again.');
    }
  }

  // ----------------- Bottom nav -----------------
  Widget _buildMerchantNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -6))
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(child: _buildNavItem(Icons.home_rounded, 'Home', 0)),
              Expanded(
                  child: _buildNavItem(
                      Icons.storefront_rounded, 'Marketplace', 1)),
              Expanded(
                  child: _buildNavItem(
                      Icons.shopping_cart_rounded, 'Cart', 2)),
              Expanded(
                  child: _buildNavItem(Icons.message_rounded, 'Messages', 3)),
              Expanded(
                  child: _buildNavItem(
                      Icons.dashboard_rounded, 'Dashboard', 4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    final sw = MediaQuery.sizeOf(context).width;
    final narrow = sw < 400;
    final hPad = narrow ? 2.0 : 5.0;
    final iconSize = narrow ? 22.0 : 24.0;
    final fontSize = narrow ? 10.0 : 12.0;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: narrow ? 8 : 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isSelected ? _brandOrange.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isSelected ? _brandOrange : Colors.grey[600],
                size: iconSize),
            SizedBox(height: narrow ? 2 : 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                color: isSelected ? _brandOrange : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
} // G£à END of _MarketplaceMerchantDashboardState

// ----------------- Quick action tile -----------------
class _QuickActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  /// When set, shows unread count from [NotificationStore] and clears on tap.
  final String? badgeRoute;

  const _QuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
    this.badgeRoute,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationStore.instance,
      builder: (context, _) {
        final n = badgeRoute == null
            ? 0
            : NotificationStore.instance.unreadCountForBadgeRoute(badgeRoute!);
        return Material(
          color: Colors.white,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (badgeRoute != null) {
                unawaited(
                  NotificationStore.instance.markBadgeRouteAsRead(badgeRoute!),
                );
              }
              onTap();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.black38),
                    ],
                  ),
                ),
                if (n > 0)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        n > 99 ? '99+' : '$n',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ----------------- Skeletons -----------------
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w}) => Container(
          height: h,
          width: w ?? double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEFF3),
            borderRadius: BorderRadius.circular(16),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEFF3),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: box(74)),
            const SizedBox(width: 12),
            Expanded(child: box(74))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: box(74)),
            const SizedBox(width: 12),
            Expanded(child: box(74))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: box(74)),
            const SizedBox(width: 12),
            Expanded(child: box(74))
          ]),
          const SizedBox(height: 12),
          box(90),
          const SizedBox(height: 12),
          box(110),
          const SizedBox(height: 12),
          const _ItemsGridSkeleton(count: 6),
        ],
      ),
    );
  }
}

class _ItemsGridSkeleton extends StatelessWidget {
  final int count;
  const _ItemsGridSkeleton({required this.count});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: _merchantItemsGridDelegate(context),
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFF3),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}

// ----------------- Cards -----------------

/// Firestore `marketplace_items` may use `image` (base64), `imageUrl` (upload flow),
/// or only `gallery` / `galleryUrls` GÇö same as [main_marketPlace] / MerchantProductsPage.
String? _coverImageSourceFromItem(Map<String, dynamic> item) {
  String? take(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  final direct = take(item['imageUrl']) ??
      take(item['image']) ??
      take(item['photo']) ??
      take(item['picture']);
  if (direct != null) return direct;

  final urls = item['galleryUrls'];
  if (urls is List) {
    for (final e in urls) {
      final u = e.toString().trim();
      if (u.isNotEmpty) return u;
    }
  }
  final gal = item['gallery'];
  if (gal is List) {
    for (final e in gal) {
      final u = e.toString().trim();
      if (u.isNotEmpty) return u;
    }
  }
  return null;
}

class _ModernItemMiniCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ModernItemMiniCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final statusLabel = _MarketplaceMerchantDashboardState._reviewLabel(item);
    final statusColor = _MarketplaceMerchantDashboardState._reviewColor(item);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 168;
          final padH = narrow ? 8.0 : 10.0;
          final padV = narrow ? 5.0 : 7.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: _ImageAny(_coverImageSourceFromItem(item)),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['name'] ?? 'Unknown').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: narrow ? 12.0 : 13.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mwk0(item['price']),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.green,
                          fontSize: narrow ? 11.5 : 13.0,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.circle,
                                size: narrow ? 8 : 10, color: statusColor),
                            SizedBox(width: narrow ? 4 : 6),
                            Flexible(
                              child: Text(
                                statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black54,
                                  fontSize: narrow ? 10.5 : 12,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ItemCard({
    required this.item,
    required this.busy,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = _MarketplaceMerchantDashboardState._reviewLabel(item);
    final statusColor = _MarketplaceMerchantDashboardState._reviewColor(item);
    final isRejected =
        _MarketplaceMerchantDashboardState._itemReviewStatus(item) ==
            'rejected';
    final rejectReason = (item['rejectedReason'] ?? '').toString().trim();
    final showRejectReason = isRejected && rejectReason.isNotEmpty;

    // Flex layout: image shrinks; text never overflows the grid cell.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 168;
            final padH = narrow ? 8.0 : 10.0;
            final padV = narrow ? 5.0 : 7.0;
            final nameSize = narrow ? 12.0 : 13.5;
            final priceSize = narrow ? 11.5 : 13.0;
            final metaSize = narrow ? 10.5 : 12.0;
            final reasonSize = narrow ? 9.5 : 10.5;

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: showRejectReason ? 5 : 6,
                      child: _ImageAny(_coverImageSourceFromItem(item)),
                    ),
                    Expanded(
                      flex: showRejectReason ? 5 : 4,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (item['name'] ?? 'Unknown').toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: nameSize,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mwk0(item['price']),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                                fontSize: priceSize,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (item['category'] ?? 'other').toString(),
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w800,
                                fontSize: metaSize,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (showRejectReason) ...[
                              const SizedBox(height: 2),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    rejectReason,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w700,
                                      fontSize: reasonSize,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: narrow ? 8 : 10,
                      vertical: narrow ? 4 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: narrow ? 10.5 : 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iconBtn(
                        icon: Icons.edit,
                        color: const Color(0xFF16284C),
                        onTap: onEdit,
                        compact: narrow,
                      ),
                      SizedBox(width: narrow ? 4 : 6),
                      _iconBtn(
                        icon: Icons.delete,
                        color: Colors.red,
                        onTap: busy ? null : onDelete,
                        compact: narrow,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    bool compact = false,
  }) {
    final size = compact ? 28.0 : 32.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: IconButton(
        icon: Icon(icon),
        iconSize: compact ? 15 : 17,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        color: color,
        onPressed: onTap,
      ),
    );
  }
}

// Image widget: supports http(s), data:image, or raw base64 â€” decode-capped for low RAM.
class _ImageAny extends StatelessWidget {
  final dynamic imageData;
  const _ImageAny(this.imageData);

  @override
  Widget build(BuildContext context) {
    return VeroThumbImage(
      imageData,
      decodeLogicalPx: 360,
    );
  }
}

/// Owns [TextEditingController] for the business-description editor sheet.
class _BusinessDescriptionSheet extends StatefulWidget {
  const _BusinessDescriptionSheet({
    required this.initialText,
    required this.maxLength,
    required this.brandColor,
  });

  final String initialText;
  final int maxLength;
  final Color brandColor;

  @override
  State<_BusinessDescriptionSheet> createState() =>
      _BusinessDescriptionSheetState();
}

class _BusinessDescriptionSheetState extends State<_BusinessDescriptionSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Business description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Short blurb customers see on your shop and product pages '
              '(max ${widget.maxLength} characters).',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLength: widget.maxLength,
              maxLines: 3,
              minLines: 2,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  Navigator.pop(context, _controller.text.trim()),
              decoration: InputDecoration(
                hintText: 'e.g. Fresh produce & household goods in Lilongwe',
                filled: true,
                fillColor: const Color(0xFFF4F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                counterStyle: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: widget.brandColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () =>
                  Navigator.pop(context, _controller.text.trim()),
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ShopHoursSheet extends StatefulWidget {
  const _ShopHoursSheet({
    required this.initialOpen,
    required this.initialClose,
    required this.initialDays,
    required this.brandColor,
  });

  final TimeOfDay initialOpen;
  final TimeOfDay initialClose;
  final Set<int> initialDays;
  final Color brandColor;

  @override
  State<_ShopHoursSheet> createState() => _ShopHoursSheetState();
}

class _ShopHoursSheetState extends State<_ShopHoursSheet> {
  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late TimeOfDay _open;
  late TimeOfDay _close;
  late Set<int> _days;

  @override
  void initState() {
    super.initState();
    _open = widget.initialOpen;
    _close = widget.initialClose;
    _days = Set<int>.from(widget.initialDays);
    if (_days.isEmpty) {
      _days = {1, 2, 3, 4, 5, 6, 7};
    }
  }

  String _fmt(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickOpen() async {
    final t = await showTimePicker(context: context, initialTime: _open);
    if (t != null) setState(() => _open = t);
  }

  Future<void> _pickClose() async {
    final t = await showTimePicker(context: context, initialTime: _close);
    if (t != null) setState(() => _close = t);
  }

  void _toggleDay(int day) {
    setState(() {
      if (_days.contains(day)) {
        if (_days.length > 1) _days.remove(day);
      } else {
        _days.add(day);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final openBtn = OutlinedButton.icon(
      onPressed: _pickOpen,
      icon: const Icon(Icons.wb_sunny_outlined, size: 18),
      label: Text(
        'Open ${_fmt(_open)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final closeBtn = OutlinedButton.icon(
      onPressed: _pickClose,
      icon: const Icon(Icons.nights_stay_outlined, size: 18),
      label: Text(
        'Close ${_fmt(_close)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Shop hours',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Customers see OPEN or CLOSED based on these days and times.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Open days',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(
                      _labels[i - 1],
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: _days.contains(i)
                            ? Colors.white
                            : Colors.grey.shade800,
                      ),
                    ),
                    selected: _days.contains(i),
                    onSelected: (_) => _toggleDay(i),
                    selectedColor: widget.brandColor,
                    checkmarkColor: Colors.white,
                    backgroundColor: const Color(0xFFF4F6FA),
                    side: BorderSide(
                      color: _days.contains(i)
                          ? widget.brandColor
                          : Colors.grey.shade300,
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _days = {1, 2, 3, 4, 5, 6, 7}),
                child: Text(
                  'Every day',
                  style: TextStyle(
                    color: widget.brandColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (narrow) ...[
              openBtn,
              const SizedBox(height: 10),
              closeBtn,
            ] else
              Row(
                children: [
                  Expanded(child: openBtn),
                  const SizedBox(width: 10),
                  Expanded(child: closeBtn),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: widget.brandColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(
                context,
                (open: _open, close: _close, days: Set<int>.from(_days)),
              ),
              child: const Text(
                'Save hours',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
