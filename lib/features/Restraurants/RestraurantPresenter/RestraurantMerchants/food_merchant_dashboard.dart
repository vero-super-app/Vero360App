// lib/Pages/MerchantDashboards/food_merchant_dashboard.dart
import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:vero360_app/features/BottomnvarBars/BottomNavbar.dart';
import 'package:vero360_app/features/Marketplace/presentation/MarketplaceMerchant/merchant_wallet.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_time.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/marketplace.service.dart';
import 'package:vero360_app/utils/app_wallet_pin.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_menu_post_page.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/kyc_verification_screen.dart';
import 'package:vero360_app/Home/post_story_page.dart';
import 'package:vero360_app/settings/Settings.dart';
import 'package:vero360_app/utils/kyc_gate.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/kyc_status_card.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/GernalServices/profile_photo_cache.dart';
import 'package:vero360_app/features/Restraurants/RestraurantsService/food_courier_dispatch.dart';
import 'package:vero360_app/features/ride_share/presentation/pages/ride_history_screen.dart';
import 'package:vero360_app/features/Restraurants/RestraurantPresenter/RestraurantMerchants/food_business_location_picker.dart';
import 'package:vero360_app/GeneralModels/place_model.dart';
import 'package:vero360_app/GernalServices/google_places_service.dart';
import 'package:vero360_app/utils/display_name_sync.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

final NumberFormat _mwk0Fmt =
    NumberFormat.currency(locale: 'en_US', symbol: 'MWK ', decimalDigits: 0);

String _mwk0(num v) => _mwk0Fmt.format(v);

class FoodMerchantDashboard extends StatefulWidget {
  final String email;
  /// Firebase uid this kitchen dashboard is bound to (single source of truth).
  final String? merchantUid;
  /// When [Bottomnavbar] already wraps this screen (tab 4), hide the bar to avoid duplicates.
  final bool embeddedInMainNav;
  const FoodMerchantDashboard({
    super.key,
    required this.email,
    this.merchantUid,
    this.embeddedInMainNav = false,
  });

  @override
  State<FoodMerchantDashboard> createState() => _FoodMerchantDashboardState();
}

class _FoodMerchantDashboardState extends State<FoodMerchantDashboard>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late TabController _foodTabs;
  /// Slow fallback for wallet + reviews only — orders arrive via [_ordersSub].
  Timer? _refreshTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  String _ordersSubscribedUid = '';
  bool _ordersBaselineReady = false;

  /// Every Firestore read is capped so a hung network call cannot block the dashboard forever.
  static const Duration _firestoreTimeout = Duration(seconds: 12);

  /// Throttle repeated timeout / error logs when the emulator or network is unhealthy.
  DateTime? _lastOrdersSummaryErrorLog;

  List<dynamic> _recentOrders = [];
  List<dynamic> _menuItems = [];
  List<dynamic> _reviews = [];
  bool _isFetching = false;
  bool _profileBusy = false;
  String _uid = '';
  String _businessName = '';
  String _merchantEmail = '';
  String _merchantPhone = '';
  String _businessDescription = '';
  String _profileUrl = '';
  /// Disk-cached avatar for instant paint (same pattern as marketplace).
  String? _localPhotoPath;
  String _openingHours = '';
  List<int> _openingDays = const [1, 2, 3, 4, 5, 6, 7];
  String _businessLocation = '';
  double? _businessLat;
  double? _businessLng;
  double _walletBalance = 0;

  int _totalOrders = 0;
  int _completedOrders = 0;
  int _pendingOrders = 0;
  double _totalRevenue = 0;
  double _rating = 0.0;
  int _reviewCount = 0;
  String _status = 'pending';
  KycStatusSnapshot _kyc = const KycStatusSnapshot();
  final ImagePicker _picker = ImagePicker();

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  ImageProvider? _profileImageProvider() {
    final local = (_localPhotoPath ?? '').trim();
    if (local.isNotEmpty) {
      try {
        final f = File(local);
        if (f.existsSync()) return FileImage(f);
      } catch (_) {}
    }
    final remote = _profileUrl.trim();
    if (remote.isNotEmpty) return NetworkImage(remote);
    return null;
  }

  static String _foodBusinessNamePrefsKey(String uid) =>
      'food_business_name_v1_$uid';

  /// Sync paint from Auth before prefs/Firestore — avoids blank name/avatar flash.
  void _bootstrapIdentityFast() {
    final pinned = (widget.merchantUid ?? '').trim();
    final user = _auth.currentUser;
    _uid = pinned.isNotEmpty ? pinned : (user?.uid ?? '');
    final authName = (user?.displayName ?? '').trim();
    if (authName.isNotEmpty) {
      _businessName = authName;
    }
    final authPic = (user?.photoURL ?? '').trim();
    if (authPic.isNotEmpty) {
      _profileUrl = authPic;
    }
    final email = (user?.email ?? widget.email).trim();
    if (email.isNotEmpty) _merchantEmail = email;
  }

  Future<void> _warmProfilePhotoCache([String? url]) async {
    final remote = (url ?? _profileUrl).trim();
    if (remote.isEmpty) return;
    try {
      final peeked = await ProfilePhotoCache.peekLocalPath(forRemoteUrl: remote);
      if (peeked != null && mounted && _localPhotoPath != peeked) {
        setState(() => _localPhotoPath = peeked);
      }
    } catch (_) {}
    final file = await ProfilePhotoCache.ensureCached(remote);
    if (!mounted || file == null) return;
    if (_localPhotoPath == file.path) return;
    setState(() => _localPhotoPath = file.path);
  }

  @override
  void initState() {
    super.initState();
    _foodTabs = TabController(length: 4, vsync: this);
    _bootstrapIdentityFast();
    unawaited(_loadMerchantData(showLoader: false));
    // Orders are live via snapshots(); wallet/reviews are less time-critical.
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted || _uid.isEmpty) return;
      unawaited(_loadWalletBalance());
      unawaited(_loadReviews());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ordersSub?.cancel();
    _foodTabs.dispose();
    super.dispose();
  }

  Future<void> _loadMerchantData({bool showLoader = true}) async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinned = (widget.merchantUid ?? '').trim();
      _uid = pinned.isNotEmpty
          ? pinned
          : (_auth.currentUser?.uid ?? prefs.getString('uid') ?? _uid);
      // Prefer uid-scoped name (survives logout). Session `business_name` is
      // cleared on sign-out and can be overwritten by Nest with the signup name.
      final scopedName = _uid.isNotEmpty
          ? (prefs.getString(_foodBusinessNamePrefsKey(_uid)) ?? '').trim()
          : '';
      final prefsName = (prefs.getString('business_name') ?? '').trim();
      if (scopedName.isNotEmpty) {
        _businessName = scopedName;
      } else if (prefsName.isNotEmpty) {
        _businessName = prefsName;
      } else if (_businessName.trim().isEmpty) {
        _businessName = 'Restaurant Business';
      }
      final prefsEmail = (prefs.getString('email') ?? '').trim();
      if (prefsEmail.isNotEmpty) {
        _merchantEmail = prefsEmail;
      } else if (_merchantEmail.trim().isEmpty) {
        _merchantEmail = widget.email;
      }
      _merchantPhone = (prefs.getString('phone') ?? _merchantPhone).trim();
      final prefsPic = (prefs.getString('profilepicture') ??
              prefs.getString('profilePicture') ??
              '')
          .trim();
      if (prefsPic.isNotEmpty) {
        _profileUrl = prefsPic;
      } else {
        final authPic = (_auth.currentUser?.photoURL ?? '').trim();
        if (authPic.isNotEmpty && _profileUrl.trim().isEmpty) {
          _profileUrl = authPic;
        }
      }
      _businessDescription =
          (prefs.getString('food_business_description') ?? '').trim();
      _openingHours =
          MarketplaceShopHours.normalize(prefs.getString('food_opening_hours')) ??
              (prefs.getString('food_opening_hours') ?? '').trim();
      _businessLocation =
          (prefs.getString('food_business_location') ?? '').trim();
      _businessLat = prefs.getDouble('food_business_lat');
      _businessLng = prefs.getDouble('food_business_lng');
      final dayPref = prefs.getStringList('food_opening_days');
      if (dayPref != null && dayPref.isNotEmpty) {
        _openingDays = MarketplaceShopHours.parseDays(dayPref);
      }

      // Paint name/photo immediately — do not wait for menu/wallet/Firestore.
      if (mounted) setState(() {});
      if (_profileUrl.trim().isNotEmpty) {
        unawaited(_warmProfilePhotoCache(_profileUrl));
      }

      if (_uid.isNotEmpty) {
        _subscribeToOrders();
        // Hydrate profile in parallel with menu/wallet so a slow network cannot
        // leave merchants staring at a blank shell (or fall back to customer UI).
        unawaited(_hydrateProfileFromFirestore().then((_) {
          if (mounted) setState(() {});
          if (_profileUrl.trim().isNotEmpty) {
            unawaited(_warmProfilePhotoCache(_profileUrl));
          }
        }));
        await Future.wait<void>([
          _loadMenuItems(),
          _loadWalletBalance(),
          _loadReviews(),
          _loadKycStatus(),
        ]);
      }
      if (mounted) setState(() {});
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _hydrateProfileFromFirestore() async {
    if (_uid.isEmpty) return;
    try {
      final results = await Future.wait([
        _firestore.collection('users').doc(_uid).get().timeout(
              _firestoreTimeout,
            ),
        _firestore.collection('food_merchants').doc(_uid).get().timeout(
              _firestoreTimeout,
            ),
        _firestore
            .collection('restaurants')
            .where('ownerUid', isEqualTo: _uid)
            .limit(1)
            .get()
            .timeout(_firestoreTimeout),
      ]);

      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final merchantSnap = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final restQ = results[2] as QuerySnapshot<Map<String, dynamic>>;

      final u = userDoc.data() ?? {};
      final fsName = (u['businessName'] ??
              u['merchantName'] ??
              u['name'] ??
              u['fullName'] ??
              u['displayName'] ??
              '')
          .toString()
          .trim();
      if (fsName.isNotEmpty) _businessName = fsName;
      final fsPhone =
          (u['phone'] ?? u['phoneNumber'] ?? '').toString().trim();
      final fsPic = (u['profilepicture'] ??
              u['profilePicture'] ??
              u['photoURL'] ??
              u['avatar'] ??
              '')
          .toString()
          .trim();
      final fsDesc =
          (u['businessDescription'] ?? u['description'] ?? '')
              .toString()
              .trim();
      final fsHours = MarketplaceShopHours.normalize(
            (u['openingHours'] ?? u['shopHours'] ?? '').toString(),
          ) ??
          '';
      final fsDays = MarketplaceShopHours.parseDays(u['openingDays']);
      final fsLoc = (u['businessLocation'] ??
              u['address'] ??
              u['location'] ??
              u['listingLocation'] ??
              '')
          .toString()
          .trim();
      final fsLat = u['latitude'] ?? u['lat'];
      final fsLng = u['longitude'] ?? u['lng'];
      if (fsPhone.isNotEmpty) _merchantPhone = fsPhone;
      if (fsPic.isNotEmpty) _profileUrl = fsPic;
      if (fsDesc.isNotEmpty) _businessDescription = fsDesc;
      if (fsHours.isNotEmpty) _openingHours = fsHours;
      if (fsDays.isNotEmpty) _openingDays = fsDays;
      if (fsLoc.isNotEmpty) _businessLocation = fsLoc;
      if (fsLat is num) _businessLat = fsLat.toDouble();
      if (fsLng is num) _businessLng = fsLng.toDouble();

      if (merchantSnap.exists) {
        final m = merchantSnap.data() ?? {};
        final mName =
            (m['businessName'] ?? m['name'] ?? '').toString().trim();
        final mPhone = (m['phone'] ?? '').toString().trim();
        final mDesc =
            (m['description'] ?? m['businessDescription'] ?? '')
                .toString()
                .trim();
        final mPic = (m['profileImage'] ??
                m['logo'] ??
                m['logoUrl'] ??
                m['image'] ??
                '')
            .toString()
            .trim();
        final mHours = MarketplaceShopHours.normalize(
              (m['openingHours'] ?? m['shopHours'] ?? '').toString(),
            ) ??
            '';
        final mDays = MarketplaceShopHours.parseDays(m['openingDays']);
        final mStatus = (m['status'] ?? '').toString().trim();
        final mLoc = (m['businessLocation'] ??
                m['address'] ??
                m['location'] ??
                m['listingLocation'] ??
                '')
            .toString()
            .trim();
        final mLat = m['latitude'] ?? m['lat'];
        final mLng = m['longitude'] ?? m['lng'];
        if (mName.isNotEmpty) _businessName = mName;
        if (mPhone.isNotEmpty) _merchantPhone = mPhone;
        if (mDesc.isNotEmpty) _businessDescription = mDesc;
        if (mPic.isNotEmpty) _profileUrl = mPic;
        if (mHours.isNotEmpty) _openingHours = mHours;
        if (mDays.isNotEmpty) _openingDays = mDays;
        if (mStatus.isNotEmpty) _status = mStatus;
        if (mLoc.isNotEmpty) _businessLocation = mLoc;
        if (mLat is num) _businessLat = mLat.toDouble();
        if (mLng is num) _businessLng = mLng.toDouble();
      }

      if (restQ.docs.isNotEmpty) {
        final r = restQ.docs.first.data();
        final rName =
            (r['name'] ?? r['businessName'] ?? '').toString().trim();
        final rPhone =
            (r['phone'] ?? r['contact'] ?? '').toString().trim();
        final rDesc =
            (r['description'] ?? r['about'] ?? '').toString().trim();
        final rPic = (r['logoUrl'] ??
                r['logo'] ??
                r['image'] ??
                r['coverImageUrl'] ??
                '')
            .toString()
            .trim();
        final rHoursRaw = r['openingHours'];
        String rHours = '';
        if (rHoursRaw is String) {
          rHours = MarketplaceShopHours.normalize(rHoursRaw) ?? '';
        } else if (r['shopHours'] != null) {
          rHours =
              MarketplaceShopHours.normalize(r['shopHours']?.toString()) ??
                  '';
        }
        final rDays = MarketplaceShopHours.parseDays(r['openingDays']);
        if (rName.isNotEmpty &&
            (_businessName.isEmpty ||
                _businessName == 'Restaurant Business')) {
          _businessName = rName;
        }
        if (rPhone.isNotEmpty && _merchantPhone.isEmpty) {
          _merchantPhone = rPhone;
        }
        if (rDesc.isNotEmpty && _businessDescription.isEmpty) {
          _businessDescription = rDesc;
        }
        if (rPic.isNotEmpty && _profileUrl.isEmpty) _profileUrl = rPic;
        if (rHours.isNotEmpty && _openingHours.isEmpty) {
          _openingHours = rHours;
        }
        if (rDays.isNotEmpty && _openingDays.length == 7) {
          _openingDays = rDays;
        }
        final rLoc = (r['address'] ??
                r['businessLocation'] ??
                r['location'] ??
                r['listingLocation'] ??
                '')
            .toString()
            .trim();
        final rLat = r['latitude'] ?? r['lat'];
        final rLng = r['longitude'] ?? r['lng'];
        if (rLoc.isNotEmpty && _businessLocation.isEmpty) {
          _businessLocation = rLoc;
        }
        if (rLat is num && _businessLat == null) {
          _businessLat = rLat.toDouble();
        }
        if (rLng is num && _businessLng == null) {
          _businessLng = rLng.toDouble();
        }
      }

      // Keep next open instant from prefs (incl. after logout → re-login).
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_businessName.trim().isNotEmpty &&
            _businessName != 'Restaurant Business') {
          final name = _businessName.trim();
          await prefs.setString('business_name', name);
          await prefs.setString(_foodBusinessNamePrefsKey(_uid), name);
        }
        if (_profileUrl.trim().isNotEmpty) {
          await prefs.setString('profilepicture', _profileUrl.trim());
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Hydrate food merchant profile: $e');
    }
  }

  void _subscribeToOrders() {
    if (_uid.isEmpty) return;
    if (_ordersSubscribedUid == _uid && _ordersSub != null) return;

    _ordersSub?.cancel();
    _ordersSubscribedUid = _uid;
    _ordersBaselineReady = false;
    _ordersSub = _firestore
        .collection('food_orders')
        .where('merchantId', isEqualTo: _uid)
        .limit(120)
        .snapshots()
        .listen(
          _onOrdersSnapshot,
          onError: (Object e) {
            final now = DateTime.now();
            if (_lastOrdersSummaryErrorLog == null ||
                now.difference(_lastOrdersSummaryErrorLog!) >
                    const Duration(minutes: 1)) {
              _lastOrdersSummaryErrorLog = now;
              debugPrint('Error streaming orders summary: $e');
            }
          },
        );
  }

  void _onOrdersSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final rows = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    rows.sort((a, b) {
      final ad = a['createdAt'];
      final bd = b['createdAt'];
      DateTime at = DateTime.fromMillisecondsSinceEpoch(0);
      DateTime bt = DateTime.fromMillisecondsSinceEpoch(0);
      if (ad is Timestamp) at = ad.toDate();
      if (bd is Timestamp) bt = bd.toDate();
      return bt.compareTo(at);
    });

    int completed = 0;
    int pending = 0;
    double revenue = 0;
    for (final o in rows) {
      final s = (o['status']?.toString().toLowerCase() ?? '').trim();
      if (s == 'delivered' || s == 'completed') {
        completed++;
        final amt = o['totalAmount'] ?? o['totalMwk'];
        revenue += amt is num ? amt.toDouble() : double.tryParse('$amt') ?? 0;
      } else if (s == 'pending' || s == 'preparing' || s == 'ready') {
        pending++;
      }
    }

    final newPending = <Map<String, dynamic>>[];
    if (_ordersBaselineReady) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final s =
            (data['status']?.toString().toLowerCase() ?? 'pending').trim();
        if (s != 'pending') continue;
        newPending.add({'id': change.doc.id, ...data});
      }
    }
    _ordersBaselineReady = true;

    if (!mounted) return;
    setState(() {
      _recentOrders = rows.take(60).toList();
      _totalOrders = rows.length;
      _completedOrders = completed;
      _pendingOrders = pending;
      _totalRevenue = revenue;
    });

    if (newPending.isNotEmpty) {
      _alertNewPendingOrders(newPending);
    }
  }

  /// Kitchen POS-style ping: haptic + system alert + banner. No extra package —
  /// [audioplayers] is already used for voice notes, not ticket chimes.
  void _alertNewPendingOrders(List<Map<String, dynamic>> orders) {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);

    final n = orders.length;
    late final String summary;
    if (n == 1) {
      final o = orders.first;
      final customer = (o['customerName'] ?? 'A customer').toString().trim();
      final who = customer.isEmpty ? 'A customer' : customer;
      summary = 'New order from $who';
    } else {
      summary = '$n new food orders';
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          summary,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _brandOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _loadMenuItems() async {
    try {
      final snapshot = await _firestore
          .collection('food_menu_items')
          .where('merchantId', isEqualTo: _uid)
          .limit(50)
          .get()
          .timeout(_firestoreTimeout);

      final rows = snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();
      rows.sort((a, b) {
        final ad = a['createdAt'];
        final bd = b['createdAt'];
        DateTime at = DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bt = DateTime.fromMillisecondsSinceEpoch(0);
        if (ad is Timestamp) at = ad.toDate();
        if (bd is Timestamp) bt = bd.toDate();
        return bt.compareTo(at);
      });
      _menuItems = rows;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading menu items: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(_uid)
          .get()
          .timeout(_firestoreTimeout);

      if (walletDoc.exists) {
        final b = walletDoc.data()?['balance'];
        setState(() {
          _walletBalance = b is num ? b.toDouble() : double.tryParse('$b') ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading wallet: $e');
    }
  }

  Future<void> _loadReviews() async {
    try {
      final snapshot = await _firestore
          .collection('food_reviews')
          .where('merchantId', isEqualTo: _uid)
          .limit(50)
          .get()
          .timeout(_firestoreTimeout);

      final rows = snapshot.docs.map((doc) => doc.data()).toList();
      rows.sort((a, b) {
        final ad = a['createdAt'];
        final bd = b['createdAt'];
        DateTime at = DateTime.fromMillisecondsSinceEpoch(0);
        DateTime bt = DateTime.fromMillisecondsSinceEpoch(0);
        if (ad is Timestamp) at = ad.toDate();
        if (bd is Timestamp) bt = bd.toDate();
        return bt.compareTo(at);
      });

      double sum = 0;
      int counted = 0;
      for (final a in rows) {
        final r = a['rating'] ?? a['stars'] ?? a['score'];
        final v = r is num
            ? r.toDouble()
            : double.tryParse(r?.toString() ?? '');
        if (v == null || v <= 0) continue;
        sum += v;
        counted += 1;
      }

      int totalCount = counted;
      try {
        final agg = await _firestore
            .collection('food_reviews')
            .where('merchantId', isEqualTo: _uid)
            .count()
            .get()
            .timeout(const Duration(seconds: 6));
        totalCount = agg.count ?? counted;
      } catch (_) {}

      _reviews = rows.take(5).toList();
      _reviewCount = totalCount;
      _rating = counted > 0 ? (sum / counted) : 0.0;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading reviews: $e');
    }
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await _firestore.collection('food_orders').doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final s = status.toLowerCase();
      if (s == 'ready') {
        Map<String, dynamic> order = {};
        for (final o in _recentOrders) {
          if (o is! Map) continue;
          final map = Map<String, dynamic>.from(o);
          final oid = '${map['id'] ?? map['orderId'] ?? ''}';
          if (oid == orderId) {
            order = map;
            break;
          }
        }
        final code = await FoodCourierDispatch.dispatchForReadyOrder(
          orderId: orderId,
          order: order,
          merchantPhone: _merchantPhone,
          merchantEmail: _merchantEmail,
          merchantName: _businessName,
          merchantUid: _uid,
        );
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            code == null || code.isEmpty
                ? 'Marked ready. Vero Courier will pick up — add a restaurant address if dispatch failed.'
                : 'Vero Courier dispatched · $code',
            isSuccess: code != null && code.isNotEmpty,
            errorMessage: code == null || code.isEmpty ? 'Courier dispatch' : '',
          );
        }
      }

      // Delivered / completed → credit kitchen (90%) + platform wallet (10%).
      if (s == 'delivered' || s == 'completed') {
        try {
          await OrderEscrowService.releaseFoodOrderByMerchant(orderId);
          if (mounted) {
            ToastHelper.showCustomToast(
              context,
              'Order paid out — kitchen wallet + 10% platform fee credited.',
              isSuccess: true,
              errorMessage: '',
            );
          }
        } catch (e) {
          debugPrint('Food escrow release failed: $e');
          if (mounted) {
            ToastHelper.showCustomToast(
              context,
              'Order updated, but wallet payout could not finish. Try again shortly.',
              isSuccess: false,
              errorMessage: '',
            );
          }
        }
        unawaited(_loadWalletBalance());
      }
    } catch (e) {
      debugPrint('Error updating order: $e');
    }
  }

  Future<void> _loadKycStatus() async {
    final snap = await KycGate.loadStatus(uid: _uid);
    if (!mounted) return;
    setState(() => _kyc = snap);
  }

  Future<void> _openKycVerification() async {
    if (!_kyc.verified) {
      final go = await showModernKycDialog(
        context,
        title: 'Verify your restaurant',
        message:
            'Complete a quick KYC check to post dishes, receive orders, and unlock wallet payouts.',
      );
      if (go != true || !mounted) return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const KycVerificationScreen()),
    );
    if (!mounted) return;
    await _loadKycStatus();
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
      errorMessage: msg,
    );
  }

  static const int _kDescMax = 280;
  static const _kDayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get _shopHoursSummary {
    final pair = MarketplaceShopHours.parseRange(_openingHours);
    if (pair == null) return 'Set business hours';
    final days = _formatOpenDaysLabel(_openingDays.toSet());
    return '$days · ${MarketplaceShopHours.formatRangeDisplay(pair.open, pair.close)}';
  }

  String _formatOpenDaysLabel(Set<int> days) {
    if (days.isEmpty || days.length == 7) return 'Every day';
    final sorted = days.toList()..sort();
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
          : '${_kDayLabels[start - 1]}–${_kDayLabels[prev - 1]}');
      start = prev = d;
    }
    ranges.add(start == prev
        ? _kDayLabels[start - 1]
        : '${_kDayLabels[start - 1]}–${_kDayLabels[prev - 1]}');
    return ranges.join(', ');
  }

  Future<void> _patchOwnedRestaurants(Map<String, dynamic> payload) async {
    if (_uid.isEmpty) return;
    try {
      final q = await _firestore
          .collection('restaurants')
          .where('ownerUid', isEqualTo: _uid)
          .limit(8)
          .get();
      await Future.wait(
        q.docs.map(
          (d) => d.reference.set(payload, SetOptions(merge: true)),
        ),
      );
    } catch (e) {
      debugPrint('Patch restaurants: $e');
    }
  }

  Future<void> _writeMerchantProfile(Map<String, dynamic> payload) async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) throw Exception('Not signed in');
    final withTs = {
      ...payload,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await Future.wait([
      _firestore
          .collection('food_merchants')
          .doc(uid)
          .set(withTs, SetOptions(merge: true)),
      _firestore
          .collection('users')
          .doc(uid)
          .set(withTs, SetOptions(merge: true)),
      _patchOwnedRestaurants(withTs),
    ]);
  }

  Future<bool> _ensureKycForPosting() {
    return KycGate.ensureVerified(
      context,
      title: 'KYC required for food merchants',
      message:
          'Verify your identity before posting dishes. This protects customers '
          'and lets you receive kitchen payouts.',
      pendingMessage:
          'KYC is still pending. You can post dishes once verification is approved.',
    );
  }

  Future<void> _openPostFood() async {
    if (!mounted) return;
    if (!await _ensureKycForPosting()) return;
    if (!mounted) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const FoodMenuPostPage(),
      ),
    );
    if (added == true && mounted) await _loadMenuItems();
  }

  void _showPhotoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Profile photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFF8A00),
                  child: Icon(Icons.photo_camera_outlined, color: Colors.white),
                ),
                title: const Text(
                  'Take a photo',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_pickAndUploadProfile(ImageSource.camera));
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1E88E5),
                  child: Icon(Icons.photo_library_outlined, color: Colors.white),
                ),
                title: const Text(
                  'Choose from gallery',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_pickAndUploadProfile(ImageSource.gallery));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadProfile(ImageSource source) async {
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) {
      _toastErr('Please sign in again.');
      return;
    }
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1400,
      imageQuality: 85,
    );
    if (file == null) return;
    if (!mounted) return;
    setState(() => _profileBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final mime = lookupMimeType(file.name, headerBytes: bytes);
      final url = await MarketplaceService().uploadBytes(
        bytes,
        filename: file.name.isNotEmpty
            ? file.name
            : 'food_profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: mime,
      );
      if (url.trim().isEmpty) throw Exception('Empty upload URL');

      await _writeMerchantProfile({
        'profilePicture': url,
        'profilepicture': url,
        'profileImage': url,
        'logo': url,
        'logoUrl': url,
        'image': url,
      });

      final user = _auth.currentUser;
      if (user != null) {
        try {
          await user.updatePhotoURL(url);
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profilepicture', url);

      if (!mounted) return;
      setState(() => _profileUrl = url);
      _toastOk('Profile picture updated');
      unawaited(_warmProfilePhotoCache(url));
    } catch (e) {
      debugPrint('Food profile upload: $e');
      if (mounted) _toastErr('Failed to upload photo. Try again.');
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _editShopHours() async {
    final pair = MarketplaceShopHours.parseRange(_openingHours);
    final result = await showModalBottomSheet<
        ({TimeOfDay open, TimeOfDay close, Set<int> days})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FoodShopHoursSheet(
        initialOpen: pair?.open ?? const TimeOfDay(hour: 8, minute: 0),
        initialClose: pair?.close ?? const TimeOfDay(hour: 21, minute: 0),
        initialDays: _openingDays.isEmpty
            ? {1, 2, 3, 4, 5, 6, 7}
            : Set<int>.from(_openingDays),
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
    final hours = MarketplaceShopHours.formatRange(open, close);
    final dayList = (days.isEmpty || days.length == 7)
        ? <int>[1, 2, 3, 4, 5, 6, 7]
        : (days.toList()..sort());
    try {
      setState(() => _profileBusy = true);
      await _writeMerchantProfile({
        'openingHours': hours,
        'shopHours': hours,
        'openingDays': dayList,
        'isOpen': MarketplaceShopHours.isOpenNow(hours, dayList),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('food_opening_hours', hours);
      await prefs.setStringList(
        'food_opening_days',
        dayList.map((e) => '$e').toList(),
      );
      if (!mounted) return;
      setState(() {
        _openingHours = hours;
        _openingDays = dayList;
      });
      _toastOk('Business hours saved');
    } catch (e) {
      debugPrint('Save food hours: $e');
      if (mounted) _toastErr('Could not save hours. Try again.');
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _editPhone() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FoodPhoneSheet(
        initialPhone: _merchantPhone,
        brandColor: _brandOrange,
      ),
    );
    if (saved == null || !mounted) return;
    await _savePhone(saved);
  }

  Future<void> _editBusinessLocation() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => FoodBusinessLocationPickerPage(
          initialAddress: _businessLocation,
          initialLatitude: _businessLat,
          initialLongitude: _businessLng,
        ),
      ),
    );
    if (place == null || !mounted) return;
    var label = place.address.trim().isNotEmpty
        ? place.address.trim()
        : place.name.trim();
    // Decode Plus Codes (e.g. 2QMV+XV) into a real street / area name.
    if (label.isNotEmpty && GooglePlacesService.isPlusCodeLabel(label)) {
      try {
        final decoded = await GooglePlacesService().lookupStreetName(
          label,
          biasLat: place.latitude,
          biasLng: place.longitude,
        );
        final rev = decoded ??
            await GooglePlacesService().reverseGeocode(
              latitude: place.latitude,
              longitude: place.longitude,
            );
        if (rev != null) {
          final name = rev.name.trim();
          final addr = rev.address.trim();
          if (name.isNotEmpty && !GooglePlacesService.isPlusCodeLabel(name)) {
            label = addr.isNotEmpty && !GooglePlacesService.isPlusCodeLabel(addr)
                ? addr
                : name;
          } else if (addr.isNotEmpty &&
              !GooglePlacesService.isPlusCodeLabel(addr)) {
            label = addr;
          }
        }
      } catch (e) {
        debugPrint('Decode plus-code location: $e');
      }
    }
    if (label.isEmpty) {
      _toastErr('Could not read that location. Try again.');
      return;
    }
    try {
      setState(() => _profileBusy = true);
      await _writeMerchantProfile({
        'businessLocation': label,
        'address': label,
        'location': label,
        'listingLocation': label,
        'latitude': place.latitude,
        'longitude': place.longitude,
        'lat': place.latitude,
        'lng': place.longitude,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('food_business_location', label);
      await prefs.setDouble('food_business_lat', place.latitude);
      await prefs.setDouble('food_business_lng', place.longitude);
      if (!mounted) return;
      setState(() {
        _businessLocation = label;
        _businessLat = place.latitude;
        _businessLng = place.longitude;
      });
      _toastOk('Restaurant location saved');
    } catch (e) {
      debugPrint('Save business location: $e');
      if (mounted) _toastErr('Could not save location. Try again.');
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _savePhone(String raw) async {
    final phone = raw.trim();
    if (phone.length < 7) {
      _toastErr('Enter a valid phone number.');
      return;
    }
    try {
      setState(() => _profileBusy = true);
      await _writeMerchantProfile({
        'phone': phone,
        'phoneNumber': phone,
        'contact': phone,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone', phone);
      if (!mounted) return;
      setState(() => _merchantPhone = phone);
      _toastOk('Phone number saved');
    } catch (e) {
      debugPrint('Save phone: $e');
      if (mounted) _toastErr('Could not save phone. Try again.');
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
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
      builder: (ctx) => _FoodBusinessDescriptionSheet(
        initialText: _businessDescription,
        maxLength: _kDescMax,
        brandColor: _brandOrange,
      ),
    );
    if (saved == null || !mounted) return;
    await _saveBusinessDescription(saved);
  }

  Future<void> _editBusinessName() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FoodBusinessNameSheet(
        initialText: _businessName,
        brandColor: _brandOrange,
      ),
    );
    if (saved == null || !mounted) return;
    await _saveBusinessName(saved);
  }

  Future<void> _saveBusinessName(String raw) async {
    final name = raw.trim();
    if (name.length < 2) {
      _toastErr('Enter a restaurant name customers can recognize.');
      return;
    }
    if (name.length > 80) {
      _toastErr('Keep the name under 80 characters.');
      return;
    }
    final uid = (_auth.currentUser?.uid ?? _uid).trim();
    if (uid.isEmpty) {
      _toastErr('Please sign in again.');
      return;
    }
    try {
      setState(() => _profileBusy = true);
      await _writeMerchantProfile({
        'businessName': name,
        'name': name,
        'merchantName': name,
        'fullName': name,
        'displayName': name,
      });
      // Keep menu listings in sync so Food browse shows the new name.
      try {
        final menu = await _firestore
            .collection('food_menu_items')
            .where('merchantId', isEqualTo: uid)
            .limit(200)
            .get();
        final batch = _firestore.batch();
        for (final d in menu.docs) {
          batch.set(
            d.reference,
            {
              'businessName': name,
              'merchantName': name,
              'RestrauntName': name,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        if (menu.docs.isNotEmpty) await batch.commit();
      } catch (e) {
        debugPrint('Sync menu business name: $e');
      }
      // Auth + Nest must match — logout clears prefs and re-login used to
      // restore the old Auth/API signup name.
      try {
        await _auth.currentUser?.updateDisplayName(name);
      } catch (_) {}
      unawaited(DisplayNameSync.syncEverywhere(uid: uid, name: name));
      unawaited(_syncBusinessNameToBackend(name));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('business_name', name);
      await prefs.setString(_foodBusinessNamePrefsKey(uid), name);
      await prefs.setString('fullName', name);
      await prefs.setString('name', name);
      if (!mounted) return;
      setState(() => _businessName = name);
      _toastOk('Restaurant name saved');
    } catch (e) {
      debugPrint('Save business name: $e');
      if (mounted) _toastErr('Could not save name. Try again.');
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _syncBusinessNameToBackend(String name) async {
    try {
      final token = await AuthHandler.getTokenForApi();
      if (token == null || token.isEmpty) return;
      await http
          .put(
            ApiConfig.endpoint('/users/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'name': name,
              'businessName': name,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Sync food business name to API: $e');
    }
  }

  Future<void> _saveBusinessDescription(String raw) async {
    final desc = raw.trim();
    if (desc.length > _kDescMax) {
      _toastErr('Keep it under $_kDescMax characters.');
      return;
    }
    try {
      setState(() => _profileBusy = true);
      await _writeMerchantProfile({
        'businessDescription': desc,
        'description': desc,
        'about': desc,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('food_business_description', desc);
      if (!mounted) return;
      setState(() => _businessDescription = desc);
      _toastOk(desc.isEmpty ? 'Description cleared' : 'Description saved');
    } catch (e) {
      debugPrint('Save description: $e');
      if (mounted) _toastErr('Could not save description. Try again.');
    } finally {
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  AppBar _buildFoodAppBar() {
    return AppBar(
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_rounded, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text(
            'Restaurant Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
      backgroundColor: _brandOrange,
      foregroundColor: Colors.white,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () {
              final uid = _auth.currentUser?.uid;
              if (uid == null) {
                ToastHelper.showCustomToast(
                  context,
                  'Please sign in to post a story',
                  isSuccess: false,
                  errorMessage: '',
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) => PostStoryPage(
                    merchantId: uid,
                    merchantName: _businessName.isNotEmpty
                        ? _businessName
                        : (_auth.currentUser?.displayName ?? 'Restaurant Merchant'),
                    serviceType: 'Restaurant',
                  ),
                ),
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFF58529),
                        Color(0xFFDD2A7B),
                        Color(0xFF8134AF),
                        Color(0xFF515BD4),
                      ],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey.shade200,
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
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
              ],
            ),
          ),
        ),
        // IconButton(
        //   icon: const Icon(Icons.person_outline_rounded),
        //   tooltip: 'Profile',
        //   onPressed: () {
        //     Navigator.push(
        //       context,
        //       MaterialPageRoute(builder: (_) => const ProfilePage()),
        //     );
        //   },
        // ),
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

  Widget _buildModernHeaderCard() {
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

    final emailLine = _merchantEmail.isNotEmpty ? _merchantEmail : widget.email;
    final phoneLine = _merchantPhone.isNotEmpty ? _merchantPhone : '—';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_brandNavy, _brandNavy.withValues(alpha: 0.86)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                backgroundImage: _profileImageProvider(),
                child: _profileImageProvider() == null
                    ? const Icon(Icons.restaurant_rounded,
                        color: Colors.white, size: 28)
                    : null,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: GestureDetector(
                  onTap: _profileBusy ? null : _showPhotoSheet,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _brandOrange,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _profileBusy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.edit, size: 12, color: Colors.white),
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
                  _businessName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  emailLine,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  phoneLine,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusFg,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 14),
                          Text(
                            ' ${_rating.toStringAsFixed(1)} · $_reviewCount review${_reviewCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
              color: color.withValues(alpha: 0.12),
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
            mainAxisExtent: 74,
          ),
          itemBuilder: (_, i) {
            switch (i) {
              case 0:
                return _compactStatTile(
                  title: 'Total orders',
                  value: '$_totalOrders',
                  icon: Icons.shopping_bag_rounded,
                  color: _brandOrange,
                );
              case 1:
                return _compactStatTile(
                  title: 'Revenue',
                  value: _mwk0(_totalRevenue),
                  icon: Icons.payments_rounded,
                  color: Colors.green,
                );
              case 2:
                return _compactStatTile(
                  title: 'Pending',
                  value: '$_pendingOrders',
                  icon: Icons.pending_actions_rounded,
                  color: Colors.blue,
                );
              default:
                return _compactStatTile(
                  title: 'Completed',
                  value: '$_completedOrders',
                  icon: Icons.check_circle_rounded,
                  color: Colors.purple,
                );
            }
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 74,
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
          ),
          children: [
            _FoodQuickActionTile(
              title: 'Post food',
              icon: Icons.add_circle_outline_rounded,
              color: _brandOrange,
              onTap: _openPostFood,
            ),
            _FoodQuickActionTile(
              title: 'My orders',
              icon: Icons.receipt_long_rounded,
              color: _brandNavy,
              onTap: () => _foodTabs.animateTo(2),
            ),
            _FoodQuickActionTile(
              title: 'Browse app',
              icon: Icons.storefront_outlined,
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Bottomnavbar(email: widget.email),
                  ),
                );
              },
            ),
            _FoodQuickActionTile(
              title: 'Post story',
              icon: Icons.auto_stories_outlined,
              color: const Color(0xFFDD2A7B),
              onTap: () {
                final uid = _auth.currentUser?.uid;
                if (uid == null) {
                  ToastHelper.showCustomToast(
                    context,
                    'Please sign in to post a story',
                    isSuccess: false,
                    errorMessage: '',
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => PostStoryPage(
                      merchantId: uid,
                      merchantName: _businessName.isNotEmpty
                          ? _businessName
                          : (_auth.currentUser?.displayName ?? 'Food Merchant'),
                      serviceType: 'food',
                    ),
                  ),
                );
              },
            ),
            _FoodQuickActionTile(
              title: 'My Vero Ride',
              icon: Icons.directions_car_filled_rounded,
              color: Colors.orange,
              onTap: _openRideHistory,
            ),
          ],
        ),
      ],
    );
  }

  void _openRideHistory() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            const RideHistoryScreen(mode: RideHistoryMode.passenger),
      ),
    );
  }

  Widget _buildWalletSummary() {
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
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wallet balance',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  _mwk0(_walletBalance),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'Available for withdrawal',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final ok = await AppWalletPin.verifyWalletUnlock(context);
              if (!ok || !mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid,
                    merchantName: _businessName,
                    serviceType: 'food',
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentOrders({bool showAll = false}) {
    final orders = showAll
        ? _recentOrders
        : _recentOrders.take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              showAll ? 'Received orders' : 'Recent orders',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            if (!showAll)
              TextButton(
                onPressed: () => _foodTabs.animateTo(2),
                child: const Text('View all'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No orders yet')),
          )
        else
          ...orders.map((order) {
            final orderMap = Map<String, dynamic>.from(order as Map);
            return _orderDetailCard(orderMap);
          }),
      ],
    );
  }

  String _orderItemsSummary(Map<String, dynamic> order) {
    final raw = order['lineItems'] ?? order['items'] ?? order['cartItems'];
    if (raw is! List || raw.isEmpty) {
      final single = (order['foodName'] ?? order['itemName'] ?? '').toString().trim();
      return single.isEmpty ? 'Food order' : single;
    }
    final names = <String>[];
    for (final e in raw.take(4)) {
      if (e is! Map) continue;
      final n = (e['name'] ?? e['FoodName'] ?? e['title'] ?? '').toString().trim();
      final qty = e['quantity'] ?? e['qty'] ?? 1;
      if (n.isEmpty) continue;
      names.add(qty == 1 || qty == '1' ? n : '${qty}x $n');
    }
    if (names.isEmpty) return 'Food order';
    final extra = raw.length - names.length;
    return extra > 0 ? '${names.join(', ')} +$extra more' : names.join(', ');
  }

  String _orderWhenLabel(Map<String, dynamic> order) {
    final raw = order['createdAt'];
    DateTime? at;
    if (raw is Timestamp) at = raw.toDate();
    if (raw is DateTime) at = raw;
    if (at == null) return '';
    return DateFormat('dd MMM · HH:mm').format(at.toLocal());
  }

  Widget _orderDetailCard(Map<String, dynamic> orderMap) {
    final oid = orderMap['orderId']?.toString() ?? orderMap['id']?.toString() ?? '';
    final shortId =
        oid.length > 8 ? oid.substring(0, 8) : (oid.isEmpty ? 'N/A' : oid);
    final amount = orderMap['totalAmount'] ?? orderMap['totalMwk'] ?? orderMap['total'];
    final amountNum =
        amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0;
    final customer = (orderMap['customerName'] ?? 'Customer').toString().trim();
    final address = (orderMap['deliveryAddress'] ??
            orderMap['dropoffAddress'] ??
            orderMap['address'] ??
            '')
        .toString()
        .trim();
    final track = '${orderMap['courierTrackingNumber'] ?? ''}'.trim();
    final when = _orderWhenLabel(orderMap);
    final itemsLine = _orderItemsSummary(orderMap);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _brandOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: _brandOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order #$shortId',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Chip(
                      label: Text(
                        '${orderMap['status'] ?? 'pending'}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: _getStatusColor(orderMap['status']),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  itemsLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customer: ${customer.isEmpty ? 'N/A' : customer}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                Text(
                  'Amount: ${_mwk0(amountNum)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.green,
                  ),
                ),
                if (address.isNotEmpty)
                  Text(
                    'Deliver to: $address',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                Text(
                  track.isEmpty
                      ? 'Vero Courier${when.isEmpty ? '' : ' · $when'}'
                      : 'Vero Courier · $track${when.isEmpty ? '' : ' · $when'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showOrderActions(orderMap),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My menu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            TextButton.icon(
              onPressed: _openPostFood,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('Post food'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_menuItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No menu items yet — tap Post food')),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: _menuItems.length,
            itemBuilder: (context, index) {
              final item = _menuItems[index] as Map<String, dynamic>;
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15)),
                            child: item['imageUrl'] != null
                                ? Image.network(
                                    item['imageUrl'] as String,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.fastfood_rounded,
                                        size: 40, color: Colors.grey),
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['name']?.toString() ?? 'Unnamed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              Text(
                                _mwk0((item['price'] is num)
                                    ? (item['price'] as num)
                                    : num.tryParse('${item['price']}') ?? 0),
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w700),
                              ),
                              Chip(
                                label: Text(
                                  item['isAvailable'] == true
                                      ? 'Available'
                                      : 'Unavailable',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: item['isAvailable'] == true
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: item['isAvailable'] == true
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildRecentReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent reviews',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (_reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No reviews yet')),
          )
        else
          ..._reviews.map((review) {
            final reviewMap = review as Map<String, dynamic>;
            final name = reviewMap['customerName']?.toString() ?? 'Anonymous';
            final initial =
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
            final rid = reviewMap['orderId']?.toString() ?? '';
            final rshort =
                rid.length > 8 ? rid.substring(0, 8) : (rid.isEmpty ? 'N/A' : rid);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                leading: CircleAvatar(child: Text(initial)),
                title: Row(
                  children: [
                    Expanded(child: Text(name)),
                    ...List.generate(5, (index) {
                      final r = reviewMap['rating'] is num
                          ? (reviewMap['rating'] as num).round()
                          : int.tryParse('${reviewMap['rating']}') ?? 0;
                      return Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: index < r ? Colors.amber : Colors.grey.shade300,
                      );
                    }),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reviewMap['comment']?.toString() ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      'Order: #$rshort',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPostFoodTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Food listings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _openPostFood,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _brandOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_rounded,
                        color: _brandOrange,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Post a dish',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add dishes to your in-app menu. They appear below after you save.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade500),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openPostFood,
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text(
              'Post food',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 20),
          _buildMenuGrid(),
        ],
      ),
    );
  }

  Widget _buildOrdersTab() {
    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: _loadMerchantData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: _buildRecentOrders(showAll: true),
      ),
    );
  }

  Widget _buildProfileTab() {
    final openNow = MarketplaceShopHours.isOpenNow(_openingHours, _openingDays);
    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: _loadMerchantData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernHeaderCard(),
            const SizedBox(height: 12),
            KycStatusCard(
              snapshot: _kyc,
              onTap: _openKycVerification,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: const Color(0xFFFFF3E5),
                        backgroundImage: _profileImageProvider(),
                        child: _profileImageProvider() == null
                            ? const Icon(
                                Icons.restaurant_rounded,
                                size: 42,
                                color: _brandOrange,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: -2,
                        child: Material(
                          color: _brandOrange,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _profileBusy ? null : _showPhotoSheet,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: _profileBusy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _businessName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_reviewCount review${_reviewCount == 1 ? '' : 's'} · ${_rating.toStringAsFixed(1)} ★',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: openNow
                          ? const Color(0xFFE7F6EC)
                          : const Color(0xFFFFEDEE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      openNow ? 'OPEN now' : 'CLOSED',
                      style: TextStyle(
                        color: openNow
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _profileEditTile(
              icon: Icons.storefront_rounded,
              title: 'Restaurant business name',
              subtitle: _businessName.trim().isEmpty
                  ? 'Name customers see on Food'
                  : _businessName.trim(),
              onTap: _editBusinessName,
            ),
            const SizedBox(height: 10),
            _profileEditTile(
              icon: Icons.schedule_rounded,
              title: 'Business hours',
              subtitle: _shopHoursSummary,
              onTap: _editShopHours,
            ),
            const SizedBox(height: 10),
            _profileEditTile(
              icon: Icons.phone_rounded,
              title: 'Phone number',
              subtitle:
                  _merchantPhone.isNotEmpty ? _merchantPhone : 'Add phone number',
              onTap: _editPhone,
            ),
            const SizedBox(height: 10),
            _profileEditTile(
              icon: Icons.location_on_rounded,
              title: 'Restaurant location',
              subtitle: _businessLocation.trim().isEmpty
                  ? 'Type, search, or pin your kitchen location'
                  : _businessLocation.trim(),
              onTap: _editBusinessLocation,
            ),
            const SizedBox(height: 10),
            _profileEditTile(
              icon: Icons.notes_rounded,
              title: 'Business description',
              subtitle: _businessDescription.trim().isEmpty
                  ? 'Tell customers about your kitchen'
                  : _businessDescription.trim(),
              onTap: _editBusinessDescription,
            ),
            const SizedBox(height: 10),
            _profileEditTile(
              icon: Icons.settings_rounded,
              title: 'Account settings',
              subtitle: 'Security, notifications, and more',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(onBackToHomeTab: () {}),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileEditTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _profileBusy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _brandOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, color: Colors.black38, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      color: _brandOrange,
      onRefresh: _loadMerchantData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernHeaderCard(),
            const SizedBox(height: 10),
            KycStatusCard(
              snapshot: _kyc,
              onTap: _openKycVerification,
            ),
            const SizedBox(height: 10),
            _buildStatsSection(),
            const SizedBox(height: 10),
            _buildQuickActionsSection(),
            const SizedBox(height: 10),
            _buildWalletSummary(),
            const SizedBox(height: 10),
            _buildRecentOrders(),
            const SizedBox(height: 10),
            _buildRecentReviews(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainNav = widget.embeddedInMainNav
        ? null
        : VeroMainNavigationBar(
            selectedIndex: 4,
            isDark: isDark,
            isMerchant: true,
            onTap: (i) {
              if (i == 4) return;
              final em = _merchantEmail.isNotEmpty
                  ? _merchantEmail
                  : widget.email;
              openVeroMainShell(context, email: em, tabIndex: i);
            },
          );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F7),
      extendBody: mainNav != null,
      appBar: _buildFoodAppBar(),
      bottomNavigationBar: mainNav,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _foodTabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              labelColor: _brandOrange,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _brandOrange,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Dashboard'),
                Tab(text: 'Post food'),
                Tab(text: 'Orders'),
                Tab(text: 'Profile'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _foodTabs,
              children: [
                _buildDashboardTab(),
                _buildPostFoodTab(),
                _buildOrdersTab(),
                _buildProfileTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return Colors.green.shade100;
      case 'preparing':
        return Colors.blue.shade100;
      case 'pending':
        return Colors.orange.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  void _showOrderActions(Map<String, dynamic> order) {
    final docId = order['id']?.toString() ?? order['orderId']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_rounded),
                title: const Text('View details'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: const Text('Mark as preparing'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'preparing');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delivery_dining_rounded),
                title: const Text('Mark as ready'),
                subtitle: const Text('Dispatch Vero Courier for pickup'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'ready');
                },
              ),
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Mark as delivered'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'delivered');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel order'),
                onTap: () {
                  Navigator.pop(context);
                  if (docId.isNotEmpty) _updateOrderStatus(docId, 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FoodQuickActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _FoodQuickActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
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
                  color: color.withValues(alpha: 0.12),
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
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodShopHoursSheet extends StatefulWidget {
  const _FoodShopHoursSheet({
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
  State<_FoodShopHoursSheet> createState() => _FoodShopHoursSheetState();
}

class _FoodPhoneSheet extends StatefulWidget {
  const _FoodPhoneSheet({
    required this.initialPhone,
    required this.brandColor,
  });

  final String initialPhone;
  final Color brandColor;

  @override
  State<_FoodPhoneSheet> createState() => _FoodPhoneSheetState();
}

class _FoodPhoneSheetState extends State<_FoodPhoneSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPhone);
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
              'Phone number',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Customers and couriers can reach you on this number.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  Navigator.pop(context, _controller.text.trim()),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
              ],
              decoration: InputDecoration(
                hintText: 'e.g. +265 99 123 4567',
                filled: true,
                fillColor: const Color(0xFFF4F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: widget.brandColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: const Text(
                'Save phone',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodShopHoursSheetState extends State<_FoodShopHoursSheet> {
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
    if (_days.isEmpty) _days = {1, 2, 3, 4, 5, 6, 7};
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
              'Business hours',
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
                    backgroundColor: const Color(0xFFF4F6FA),
                    side: BorderSide(
                      color: _days.contains(i)
                          ? widget.brandColor
                          : Colors.grey.shade300,
                    ),
                    showCheckmark: false,
                  ),
              ],
            ),
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickOpen,
                    icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                    label: Text('Open ${_fmt(_open)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickClose,
                    icon: const Icon(Icons.nights_stay_outlined, size: 18),
                    label: Text('Close ${_fmt(_close)}'),
                  ),
                ),
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
          ],
        ),
      ),
    );
  }
}

class _FoodBusinessDescriptionSheet extends StatefulWidget {
  const _FoodBusinessDescriptionSheet({
    required this.initialText,
    required this.maxLength,
    required this.brandColor,
  });

  final String initialText;
  final int maxLength;
  final Color brandColor;

  @override
  State<_FoodBusinessDescriptionSheet> createState() =>
      _FoodBusinessDescriptionSheetState();
}

class _FoodBusinessDescriptionSheetState
    extends State<_FoodBusinessDescriptionSheet> {
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
              'Short blurb customers see on your restaurant profile '
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
              maxLines: 4,
              minLines: 2,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Home-style Malawian meals, fresh daily',
                filled: true,
                fillColor: const Color(0xFFF4F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
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
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: const Text(
                'Save description',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodBusinessNameSheet extends StatefulWidget {
  const _FoodBusinessNameSheet({
    required this.initialText,
    required this.brandColor,
  });

  final String initialText;
  final Color brandColor;

  @override
  State<_FoodBusinessNameSheet> createState() => _FoodBusinessNameSheetState();
}

class _FoodBusinessNameSheetState extends State<_FoodBusinessNameSheet> {
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
              'Restaurant business name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'This name appears in orange on Food for customers.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLength: 80,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  Navigator.pop(context, _controller.text.trim()),
              decoration: InputDecoration(
                hintText: 'e.g. Queens Tavern Steakhouse',
                filled: true,
                fillColor: const Color(0xFFF4F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
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
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: const Text(
                'Save name',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
