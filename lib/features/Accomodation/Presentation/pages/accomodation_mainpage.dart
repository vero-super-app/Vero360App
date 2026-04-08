import 'dart:async';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/my_Accodation_bookingdata_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/Accomodation_service.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/mybookingData_service.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accommodation_booking_page.dart';
import 'package:vero360_app/features/Accomodation/Presentation/pages/accommodation_my_bookings_tab.dart';
import 'package:vero360_app/features/Accomodation/Presentation/widgets/accommodation_listing_image.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

class AccommodationMainPage extends StatefulWidget {
  /// After paying, open stays with this listing scrolled into view (if it appears in results).
  final int? focusAccommodationId;

  /// `0` = Discover, `1` = My bookings (e.g. after successful payment).
  final int initialTabIndex;

  const AccommodationMainPage({
    super.key,
    this.focusAccommodationId,
    this.initialTabIndex = 0,
  }) : assert(initialTabIndex >= 0 && initialTabIndex < 2);

  @override
  State<AccommodationMainPage> createState() => _AccommodationMainPageState();
}

class _AccommodationMainPageState extends State<AccommodationMainPage>
    with SingleTickerProviderStateMixin {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _pageBg = Color(0xFFF4F6FA);
  static const Color _surfaceBorder = Color(0xFFE2E6EF);

  final AccommodationService _service = AccommodationService();
  late final TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  /// Debounce: only fetch after user stops typing (avoids API call on every keystroke).
  int _locationDebounceStamp = 0;

  /// Values must match backend `accommodationType` (singular), e.g. `apartment` not `apartments`.
  final List<String> _types = const [
    'all',
    'hostel',
     'bnb',
    'hotel',
    'lodge',
    'house',
    'apartment',
   
  ];

  String _selectedType = 'all';
  String _searchQuery = '';
  String _locationQuery = '';

  static const List<String> _malawiDistricts = [
    // Northern
    'Chitipa',
    'Karonga',
    'Likoma',
    'Mzimba',
    'Nkhata Bay',
    'Nkhotakota',
    // Central
    'Dedza',
    'Dowa',
    'Kasungu',
    'Lilongwe City',
    'Lilongwe',
    'Lilongwe Rural',
    'Mchinji',
    'Ntcheu',
    'Ntchisi',
    // Southern
    'Balaka',
    'Blantyre City',
    'Blantyre Rural',
    'Chikwawa',
    'Chiradzulu',
    'Machinga',
    'Mangochi',
    'Mulanje',
    'Mwanza',
    'Neno',
    'Nsanje',
    'Phalombe',
  ];

  Future<List<Accommodation>>? _future;

  final GlobalKey _focusCardKey = GlobalKey();
  bool _didScrollToFocus = false;

  /// Discover list: drives “Book now” vs “Sign in to book” on cards.
  bool _authReady = false;
  bool _isLoggedIn = false;
  bool _isAccommodationMerchantUser = false;
  int? _openingAccommodationId;

  /// Paid stays for the signed-in guest — used to disable “Book now” on check-in days.
  List<BookingItem> _guestPaidStays = [];
  final MyBookingService _myBookingService = MyBookingService();
  final Map<int, String> _hostelGenderByApiId = <int, String>{};
  final Map<int, String> _hostelRoomTypeByApiId = <int, String>{};
  final Map<int, bool> _hostelAvailabilityByApiId = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _tabController.addListener(_onAccommodationTabChanged);
    _loadFromService();
    _refreshSession();
    _searchController.addListener(_onSearchChanged);
    _locationController.addListener(_onLocationChanged);
  }

  Future<void> _refreshSession() async {
    final ok = await AuthHandler.isAuthenticated();
    var isAccommodationMerchant = false;
    if (ok) {
      isAccommodationMerchant = await _detectCurrentUserIsAccommodationMerchant();
    }
    if (!mounted) return;
    setState(() {
      _isLoggedIn = ok;
      _authReady = true;
      _isAccommodationMerchantUser = isAccommodationMerchant;
    });
    if (isAccommodationMerchant && _tabController.index != 0) {
      _tabController.animateTo(0);
    }
    if (ok) {
      await _loadGuestPaidStays();
    } else if (mounted) {
      setState(() => _guestPaidStays = []);
    }
  }

  bool get _showMyBookingsTab => !_isAccommodationMerchantUser;

  Future<bool> _detectCurrentUserIsAccommodationMerchant() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return false;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('accommodation_merchants').doc(uid).get();
      if (doc.exists) return true;
    } catch (_) {}
    try {
      final rooms = await FirebaseFirestore.instance
          .collection('accommodation_rooms')
          .where('merchantId', isEqualTo: uid)
          .limit(1)
          .get();
      return rooms.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _onAccommodationTabChanged() {
    if (!mounted || _tabController.index != 0) return;
    unawaited(_loadGuestPaidStays());
  }

  Future<void> _loadGuestPaidStays() async {
    if (!await AuthHandler.isAuthenticated()) {
      if (mounted) setState(() => _guestPaidStays = []);
      return;
    }
    try {
      final list = await _myBookingService.getGuestStaysForDiscoverOverlay();
      if (mounted) setState(() => _guestPaidStays = list);
    } catch (_) {
      if (mounted) setState(() => _guestPaidStays = []);
    }
  }

  bool _isSingleUnitType(String type) {
    return type == 'house' || type == 'bnb' || type == 'apartment';
  }

  bool _isBookedTodayForListing(Accommodation accommodation) {
    final accommodationId = accommodation.id;
    if (accommodationId <= 0) return false;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final todaysBookings = _guestPaidStays
        .where((b) => b.stayCoversCalendarDay(today, accommodationId))
        .length;
    if (todaysBookings <= 0) return false;

    final type = accommodation.accommodationType.toLowerCase().trim();
    if (type == 'hostel') {
      final explicitlyAvailable = _hostelAvailabilityByApiId[accommodationId];
      if (explicitlyAvailable == false) return true;
    }
    if (_isSingleUnitType(type)) return true;
    if (type == 'hotel' || type == 'lodge') {
      return todaysBookings >= accommodation.roomsAvailable;
    }
    return false;
  }

  Future<void> _openBookingFlow(Accommodation accommodation) async {
    if (_openingAccommodationId == accommodation.id) return;
    if (mounted) {
      setState(() => _openingAccommodationId = accommodation.id);
    }
    try {
    // Fast path: if auth state is already known + logged in, navigate immediately.
    if (_authReady && _isLoggedIn) {
      await _pushBookingPage(accommodation);
      if (mounted) {
        unawaited(_refreshSession());
        unawaited(_loadGuestPaidStays());
      }
      return;
    }

    // Fallback: refresh only when auth state is unknown/stale.
    if (!_authReady) {
      await _refreshSession();
      if (!mounted) return;
    }

    if (!_isLoggedIn) {
      await _showMembersOnlyBookSheet(context);
      if (!mounted) return;
      await _refreshSession();
      if (!_isLoggedIn) return;
    }
    if (!mounted) return;
    await _pushBookingPage(accommodation);
    if (mounted) {
      unawaited(_refreshSession());
      unawaited(_loadGuestPaidStays());
    }
    } finally {
      if (mounted) {
        setState(() => _openingAccommodationId = null);
      }
    }
  }

  Future<void> _pushBookingPage(Accommodation accommodation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AccommodationBookingPage.fromAccommodation(
          accommodation,
          afterSuccessfulPayment: (bookingCtx, accId) {
            if (!bookingCtx.mounted) return;
            Navigator.of(bookingCtx).pop();
            Navigator.of(bookingCtx).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AccommodationMainPage(
                  focusAccommodationId: accId,
                  initialTabIndex: 1,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showMembersOnlyBookSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: _brandOrange,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Members only',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _brandNavy,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Booking and payment are available to signed-in guests only. '
                'We’ll load your name, email, and phone into the booking form.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _brandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Sign in to book',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Not now',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onAccommodationTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  void _onLocationChanged() {
    _locationQuery = _locationController.text.trim();
    setState(() {}); // Update search filter immediately
    // Debounce API call: wait 500ms after last keystroke before fetching
    final stamp = ++_locationDebounceStamp;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || stamp != _locationDebounceStamp) return;
      _loadFromService();
      setState(() {});
    });
  }

  void _onTypeSelected(String type) {
    setState(() {
      _selectedType = type;
      _loadFromService();
    });
  }

  void _loadFromService() {
    _future = _fetchDiscoverListWithPricing();
  }

  /// API listings often omit `pricingPeriod`; merge from `accommodation_rooms` when hosts saved it.
  Future<List<Accommodation>> _fetchDiscoverListWithPricing() async {
    final list = await _service.fetch(
      type: _selectedType,
      location: _locationQuery.isEmpty ? null : _locationQuery,
    );
    return _mergePricingPeriodFromFirestore(list);
  }

  Future<List<Accommodation>> _mergePricingPeriodFromFirestore(
    List<Accommodation> list,
  ) async {
    if (list.isEmpty) return list;
    final ids = list.map((a) => a.id).where((id) => id > 0).toSet();
    if (ids.isEmpty) return list;

    final byApiId = <int, AccommodationPricePeriod>{};
    final byApiIdCapacity = <int, int>{};
    final byApiIdHostelGender = <int, String>{};
    final byApiIdRoomType = <int, String>{};
    final byApiIdAvailability = <int, bool>{};
    try {
      final idList = ids.toList();
      for (var i = 0; i < idList.length; i += 10) {
        final chunk = idList.sublist(i, min(i + 10, idList.length));
        final snap = await FirebaseFirestore.instance
            .collection('accommodation_rooms')
            .where('apiAccommodationId', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final rawId = d['apiAccommodationId'];
          int? apiId;
          if (rawId is int) {
            apiId = rawId;
          } else if (rawId is num) {
            apiId = rawId.toInt();
          } else {
            apiId = int.tryParse(rawId?.toString() ?? '');
          }
          if (apiId == null || apiId <= 0) continue;
          if (d.containsKey('pricingPeriod') || d.containsKey('pricePeriod')) {
            byApiId[apiId] = accommodationPricePeriodFromDynamic(
              d['pricingPeriod'] ?? d['pricePeriod'],
            );
          }
          final capRaw = d['capacity'] ?? d['roomsAvailable'] ?? d['roomCount'];
          final cap = capRaw is num
              ? capRaw.toInt()
              : int.tryParse(capRaw?.toString() ?? '');
          if (cap != null && cap > 0) {
            byApiIdCapacity[apiId] = cap;
          }
          final rawHostelGender = d['hostelGender']?.toString().trim().toLowerCase();
          if (rawHostelGender != null &&
              (rawHostelGender == 'boys' ||
                  rawHostelGender == 'girls' ||
                  rawHostelGender == 'mixed')) {
            byApiIdHostelGender[apiId] = rawHostelGender;
          }
          final rawRoomType = d['roomType']?.toString().trim().toLowerCase();
          if (rawRoomType != null &&
              (rawRoomType == 'single' ||
                  rawRoomType == 'double' ||
                  rawRoomType == 'hall')) {
            byApiIdRoomType[apiId] = rawRoomType;
          }
          final rawAvailable = d['isAvailable'];
          if (rawAvailable is bool) {
            byApiIdAvailability[apiId] = rawAvailable;
          }
        }
      }
    } catch (_) {
      return list;
    }

    _hostelGenderByApiId
      ..clear()
      ..addAll(byApiIdHostelGender);
    _hostelRoomTypeByApiId
      ..clear()
      ..addAll(byApiIdRoomType);
    _hostelAvailabilityByApiId
      ..clear()
      ..addAll(byApiIdAvailability);

    if (byApiId.isEmpty && byApiIdCapacity.isEmpty) return list;
    return list
        .map((a) {
          final p = byApiId[a.id];
          final cap = byApiIdCapacity[a.id];
          var updated = a;
          if (p != null) updated = updated.withPricingPeriod(p);
          if (cap != null) updated = updated.withRoomsAvailable(cap);
          return updated;
        })
        .toList();
  }

  void _showDistrictPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _brandOrange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.map_rounded,
                        color: _brandOrange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Pick a district',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _brandNavy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Malawi districts — tap to fill location',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: _malawiDistricts.length,
                itemBuilder: (context, i) {
                  final d = _malawiDistricts[i];
                  return ListTile(
                    leading: Icon(Icons.place_outlined,
                        color: Colors.grey.shade600, size: 22),
                    title: Text(
                      d,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      _locationController.text = d;
                      Navigator.pop(ctx);
                      setState(() {
                        _loadFromService();
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Accommodation> _applySearchFilter(List<Accommodation> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((a) {
      final name = a.name.toLowerCase();
      final loc = a.location.toLowerCase();
      return name.contains(q) || loc.contains(q);
    }).toList();
  }

  Widget _buildDiscoverTab(BuildContext context, bool isDark) {
    return Column(
      children: [
        _buildSearchAndLocationBar(context, isDark),
        const SizedBox(height: 10),
        _buildTypeChipsRow(context, isDark),
        const SizedBox(height: 6),
        Expanded(
          child: RefreshIndicator(
            color: _brandOrange,
            onRefresh: () async {
              setState(() {
                _loadFromService();
              });
              await _future;
              await _loadGuestPaidStays();
            },
            child: FutureBuilder<List<Accommodation>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return AppSkeletonShimmer(
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        for (var i = 0; i < 5; i++) ...[
                          AppSkeletonAccommodationCardCore(isDark: isDark),
                          if (i < 4) const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorState(
                    context,
                    snapshot.error.toString(),
                    isDark,
                  );
                }
                final raw = snapshot.data ?? [];
                final data = _applySearchFilter(raw);

                if (data.isEmpty) {
                  return _buildEmptyState(context, isDark);
                }

                final focusId = widget.focusAccommodationId;
                if (focusId != null && !_didScrollToFocus) {
                  final hit = data.any((e) => e.id == focusId);
                  if (hit) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final ctx = _focusCardKey.currentContext;
                      if (ctx != null) {
                        Scrollable.ensureVisible(
                          ctx,
                          alignment: 0.12,
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                        );
                        setState(() => _didScrollToFocus = true);
                      }
                    });
                  } else {
                    _didScrollToFocus = true;
                  }
                }

                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemBuilder: (context, index) {
                    final item = data[index];
                    final isFocus = focusId != null && item.id == focusId;
                    Widget card = _AccommodationCard(
                      accommodation: item,
                      isDark: isDark,
                      highlight: isFocus,
                      authReady: _authReady,
                      isLoggedIn: _isLoggedIn,
                      bookedToday: _isBookedTodayForListing(item),
                      isOpening: _openingAccommodationId == item.id,
                      hostelGender: _hostelGenderByApiId[item.id],
                      hostelRoomType: _hostelRoomTypeByApiId[item.id],
                      hostelAvailable: _hostelAvailabilityByApiId[item.id],
                      onBookStay: _openBookingFlow,
                    );
                    if (isFocus) {
                      card = KeyedSubtree(
                        key: _focusCardKey,
                        child: card,
                      );
                    }
                    return card;
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: data.length,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : _pageBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.hotel_rounded, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Stays',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        bottom: _showMyBookingsTab
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Discover'),
                  Tab(text: 'My bookings'),
                ],
              )
            : null,
      ),
      body: SafeArea(
        child: _showMyBookingsTab
            ? TabBarView(
                controller: _tabController,
                children: [
                  _buildDiscoverTab(context, isDark),
                  AccommodationMyBookingsTab(isDark: isDark),
                ],
              )
            : _buildDiscoverTab(context, isDark),
      ),
    );
  }

  Widget _buildSearchAndLocationBar(BuildContext context, bool isDark) {
    final card = isDark ? const Color(0xFF1E293B) : Colors.white;
    final hint = isDark ? Colors.white54 : Colors.grey.shade500;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find your stay',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Booking is for signed-in guests only.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white12 : _surfaceBorder,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1D26),
              ),
              cursorColor: _brandOrange,
              decoration: InputDecoration(
                hintText: 'type bnb, hotel, house, hostel, etc...',
                hintStyle: TextStyle(color: hint, fontWeight: FontWeight.w500),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _brandOrange, size: 26),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: Icon(Icons.close_rounded,
                            color: Colors.grey.shade600),
                        tooltip: 'Clear',
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Location',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white12 : _surfaceBorder,
                    ),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: TextField(
                    controller: _locationController,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1D26),
                    ),
                    cursorColor: _brandOrange,
                    decoration: InputDecoration(
                      hintText: 'District or area',
                      hintStyle:
                          TextStyle(color: hint, fontWeight: FontWeight.w500),
                      prefixIcon: const Icon(
                        Icons.location_on_rounded,
                        color: _brandOrange,
                        size: 22,
                      ),
                      suffixIcon: _locationQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () => _locationController.clear(),
                              icon: Icon(Icons.close_rounded,
                                  color: Colors.grey.shade600),
                              tooltip: 'Clear location',
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 14),
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: _brandOrange,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _showDistrictPicker,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.map_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChipsRow(BuildContext context, bool isDark) {
    final card = isDark ? const Color(0xFF1E293B) : Colors.white;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _types[index];
          final isSelected = type == _selectedType;
          final label = type == 'all'
              ? 'All'
              : type == 'apartment'
                  ? 'Apartments'
                  : type[0].toUpperCase() + type.substring(1);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _onTypeSelected(type),
            child: Chip(
              label: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              backgroundColor: isSelected
                  ? _brandOrange
                  : (isDark ? card : Colors.grey.shade300),
              side: BorderSide(
                color: isSelected
                    ? _brandOrange
                    : (isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message, bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(Icons.error_outline_rounded,
            size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Could not load stays',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                _loadFromService();
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(Icons.hotel_outlined, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No stays found',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Try another type, location, or clear your search.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatPriceWhole(num value) =>
    NumberFormat('#,##0').format(value.round());

/// Auto-advancing gallery (same idea as [main_marketPlace] `_AutoSlideImageCarousel`).
class _AccommodationSlideCarousel extends StatefulWidget {
  const _AccommodationSlideCarousel({
    super.key,
    required this.sources,
    required this.itemBuilder,
    required this.accentColor,
  });

  final List<String> sources;
  final Widget Function(String source) itemBuilder;
  final Color accentColor;

  @override
  State<_AccommodationSlideCarousel> createState() =>
      _AccommodationSlideCarouselState();
}

class _AccommodationSlideCarouselState extends State<_AccommodationSlideCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.sources.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_index + 1) % widget.sources.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.sources.length,
          physics: widget.sources.length > 1
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => widget.itemBuilder(widget.sources[i]),
        ),
        if (widget.sources.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.sources.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: active ? 14 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? widget.accentColor
                        : Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.black26, width: 0.4),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

// ====== Card widget using your Accommodation model ======

class _AccommodationCard extends StatelessWidget {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _surfaceBorder = Color(0xFFE2E6EF);

  final Accommodation accommodation;
  final bool isDark;
  final bool highlight;
  final bool authReady;
  final bool isLoggedIn;
  /// Paid stay covers **today** for this listing — freeze Book now.
  final bool bookedToday;
  final bool isOpening;
  final String? hostelGender;
  final String? hostelRoomType;
  final bool? hostelAvailable;
  final Future<void> Function(Accommodation acc) onBookStay;

  const _AccommodationCard({
    required this.accommodation,
    required this.isDark,
    this.highlight = false,
    required this.authReady,
    required this.isLoggedIn,
    this.bookedToday = false,
    this.isOpening = false,
    this.hostelGender,
    this.hostelRoomType,
    this.hostelAvailable,
    required this.onBookStay,
  });

  /// Cover + [Accommodation.gallery], deduped; multiple URLs → sliding carousel.
  Widget _heroMedia() {
    final rawImage = (accommodation.image ?? '').trim();
    final imgBytes = accommodation.imageBytes;
    final gallery = accommodation.gallery
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty);

    final sources = <String>[
      if (rawImage.isNotEmpty) rawImage,
      ...gallery,
    ];
    final deduped = <String>[];
    final seen = <String>{};
    for (final s in sources) {
      if (seen.add(s)) deduped.add(s);
    }

    if (deduped.isEmpty && imgBytes != null) {
      return Image.memory(imgBytes, fit: BoxFit.cover);
    }

    if (deduped.length <= 1) {
      if (deduped.isEmpty) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _brandNavy.withValues(alpha: 0.12),
                _brandOrange.withValues(alpha: 0.15),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            Icons.photo_size_select_actual_outlined,
            size: 44,
            color: Colors.grey.shade400,
          ),
        );
      }
      final only = deduped.first;
      if (imgBytes != null && accListingLooksLikeBase64(only)) {
        return Image.memory(imgBytes, fit: BoxFit.cover);
      }
      return accImageFromAnySource(only, fit: BoxFit.cover);
    }

    return _AccommodationSlideCarousel(
      key: ValueKey('acc-hero-${accommodation.id}-${deduped.length}'),
      sources: deduped,
      accentColor: _brandOrange,
      itemBuilder: (src) => accImageFromAnySource(
        src,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  Widget _metaChip(
    String label, {
    required bool isDark,
    Color? textColor,
    Color? background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ??
            (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : _brandOrange.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? (isDark ? Colors.white : _brandNavy),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = accommodation.name;
    final location = accommodation.location;
    final description = accommodation.description.trim();
    final type = accommodation.accommodationType.toLowerCase();
    final isHotelOrLodge = type == 'hotel' || type == 'lodge';
    final isHostel = type == 'hostel';
    final roomCount = accommodation.roomsAvailable < 1
        ? 1
        : accommodation.roomsAvailable;
    final hostelGenderLabel = (() {
      final v = hostelGender?.trim().toLowerCase();
      if (v == null || v.isEmpty) return null;
      return '${v[0].toUpperCase()}${v.substring(1)} hostel';
    })();
    final hostelRoomTypeLabel = (() {
      final v = hostelRoomType?.trim().toLowerCase();
      if (v == null || v.isEmpty) return null;
      return '${v[0].toUpperCase()}${v.substring(1)} room';
    })();
    final isHostelBooked = bookedToday || (hostelAvailable == false);

    final owner = accommodation.owner;
    final rating = (owner?.averageRating ?? 0).toDouble();
    final reviewCount = owner?.reviewCount ?? 0;
    final price = accommodation.price.toDouble();

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Material(
      color: cardBg,
      elevation: highlight ? 2 : 0,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlight
                ? _brandOrange
                : (isDark ? Colors.white12 : _surfaceBorder),
            width: highlight ? 2.2 : 1,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: _heroMedia()),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (reviewCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '($reviewCount)',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (bookedToday || (isHostel && hostelAvailable == false))
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_busy_rounded,
                                size: 15, color: Colors.teal.shade50),
                            const SizedBox(width: 5),
                            Text(
                              isHostel
                                  ? 'Booked / unavailable'
                                  : (isHotelOrLodge
                                      ? 'Fully booked today'
                                      : 'Booked today'),
                              style: TextStyle(
                                color: Colors.teal.shade50,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (isHotelOrLodge)
                    Positioned(
                      top: bookedToday ? 44 : 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          '$roomCount room${roomCount == 1 ? '' : 's'} available',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _brandOrange,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: _brandOrange.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(
                            'MWK ${_formatPriceWhole(price)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            accommodation.pricePeriod.uiSuffix.trimLeft(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : _brandNavy,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location.isEmpty ? '—' : location,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (isHostel &&
                      (hostelGenderLabel != null ||
                          hostelRoomTypeLabel != null ||
                          hostelAvailable != null)) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (hostelGenderLabel != null)
                          _metaChip(
                            hostelGenderLabel,
                            isDark: isDark,
                          ),
                        if (hostelRoomTypeLabel != null)
                          _metaChip(
                            hostelRoomTypeLabel,
                            isDark: isDark,
                          ),
                        _metaChip(
                          isHostelBooked ? 'Booked' : 'Available',
                          isDark: isDark,
                          textColor: isHostelBooked
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                          background: isHostelBooked
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                        ),
                      ],
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.72)
                            : Colors.grey.shade700,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _brandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _capitalize(type),
                          style: const TextStyle(
                            color: _brandOrange,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (authReady && !isLoggedIn)
                        OutlinedButton.icon(
                          onPressed: accommodation.id <= 0
                              ? null
                              : () => onBookStay(accommodation),
                          icon: Icon(
                            Icons.lock_outline_rounded,
                            size: 17,
                            color: _brandOrange.withValues(alpha: 0.95),
                          ),
                          label: const Text(
                            'Sign in to book',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _brandNavy,
                            side: BorderSide(
                              color: _brandOrange.withValues(alpha: 0.85),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: isOpening ||
                                  accommodation.id <= 0 ||
                                  (authReady &&
                                      isLoggedIn &&
                                      isHostelBooked)
                              ? null
                              : () => onBookStay(accommodation),
                          icon: isOpening
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isHostelBooked
                                      ? Icons.lock_clock_rounded
                                      : authReady && isLoggedIn
                                          ? Icons.event_available_rounded
                                          : Icons.hotel_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                          label: Text(
                            isOpening
                                ? 'Opening...'
                                : isHostelBooked
                                ? (isHostel
                                    ? 'Booked / unavailable'
                                    : (isHotelOrLodge
                                        ? 'Fully booked today'
                                        : 'Booked today'))
                                : authReady
                                    ? 'Book now'
                                    : 'Book',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: bookedToday
                                ? Colors.grey.shade500
                                : _brandOrange,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade400,
                            disabledForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
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

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}