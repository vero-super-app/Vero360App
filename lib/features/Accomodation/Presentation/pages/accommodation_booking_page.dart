import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/config/paychangu_config.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_booking_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationModel/accomodation_model.dart';
import 'package:vero360_app/features/Accomodation/AccomodationService/booking_service.dart';
import 'package:vero360_app/features/Accomodation/Presentation/widgets/accommodation_listing_image.dart';
import 'package:vero360_app/features/Auth/AuthPresenter/login_screen.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Cart/CartPresentaztion/pages/checkout_from_cart_page.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart' show DeliveryType;
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/notification_service.dart';
import 'package:vero360_app/GernalServices/order_escrow_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

/// After PayChangu success: [bookingContext] is the booking screen (under the webview).
typedef AccommodationAfterPayCallback = void Function(
  BuildContext bookingContext,
  int accommodationId,
);

/// Guest booking + PayChangu payment; escrow hold for host when [hostMerchantUid] is set.
/// [photoSources] = cover + gallery URLs/paths; [memoryHeroBytes] optional decoded cover.
class AccommodationBookingPage extends StatefulWidget {
  final int accommodationId;
  final String propertyName;
  final String location;
  final num pricePerNight;
  final String accommodationType;
  final int roomsAvailable;
  final AccommodationPricePeriod? pricePeriod;
  final List<String> photoSources;
  final Uint8List? memoryHeroBytes;

  final String? hostMerchantUid;
  final String? hostDisplayName;

  final AccommodationAfterPayCallback? afterSuccessfulPayment;

  const AccommodationBookingPage({
    super.key,
    required this.accommodationId,
    required this.propertyName,
    required this.location,
    required this.pricePerNight,
    this.accommodationType = '',
    this.roomsAvailable = 1,
    this.pricePeriod,
    this.photoSources = const [],
    this.memoryHeroBytes,
    this.hostMerchantUid,
    this.hostDisplayName,
    this.afterSuccessfulPayment,
  });

  /// Collect http(s) URLs from merchant property row (cover + gallery).
  static List<String> photoUrlsFromMerchantRoom(Map<String, dynamic> room) {
    final seen = <String>{};
    final out = <String>[];
    void take(Object? v) {
      final s = v?.toString().trim() ?? '';
      if (!accListingIsHttp(s)) return;
      if (seen.add(s)) out.add(s);
    }

    take(room['imageUrl']);
    take(room['image']);
    final g = room['galleryUrls'];
    if (g is List) {
      for (final e in g) {
        take(e);
      }
    }
    return out;
  }

  factory AccommodationBookingPage.fromAccommodation(
    Accommodation a, {
    AccommodationAfterPayCallback? afterSuccessfulPayment,
  }) {
    final raw = <String>[
      if ((a.image ?? '').trim().isNotEmpty) a.image!.trim(),
      ...a.gallery.map((e) => e.toString().trim()).where((s) => s.isNotEmpty),
    ];
    final seen = <String>{};
    final photoSources = <String>[];
    for (final s in raw) {
      if (seen.add(s)) photoSources.add(s);
    }

    return AccommodationBookingPage(
      accommodationId: a.id,
      propertyName: a.name,
      location: a.location,
      pricePerNight: a.price,
      accommodationType: a.accommodationType,
      roomsAvailable: a.roomsAvailable,
      pricePeriod: a.pricePeriod,
      photoSources: photoSources,
      memoryHeroBytes: a.imageBytes,
      hostMerchantUid: a.hostMerchantUid,
      hostDisplayName: a.owner?.name,
      afterSuccessfulPayment: afterSuccessfulPayment,
    );
  }

  @override
  State<AccommodationBookingPage> createState() =>
      _AccommodationBookingPageState();
}

class _AccommodationBookingPageState extends State<AccommodationBookingPage> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);
  static const Color _surface = Color(0xFFF4F6FA);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final BookingService _bookingService = BookingService();
  late final PageController _heroController;

  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 2));

  bool _submitting = false;
  bool _authReady = false;
  bool _isLoggedIn = false;
  int _heroIndex = 0;
  bool _showSwipeHint = false;
  Timer? _swipeHintTimer;
  String _ownerName = '';
  String _ownerEmail = '';
  String _ownerPhone = '';
  String _ownerPhotoUrl = '';

  List<Widget> get _heroPages {
    final pages = <Widget>[];
    final mem = widget.memoryHeroBytes;
    if (mem != null && mem.isNotEmpty) {
      pages.add(Image.memory(mem, fit: BoxFit.cover, gaplessPlayback: true));
    }
    for (final url in widget.photoSources) {
      if (mem != null &&
          mem.isNotEmpty &&
          accListingLooksLikeBase64(url)) {
        continue;
      }
      pages.add(accImageFromAnySource(url, fit: BoxFit.cover));
    }
    if (pages.isEmpty) {
      pages.add(
        Container(
          color: _brandNavy.withValues(alpha: 0.85),
          alignment: Alignment.center,
          child: Icon(Icons.apartment_rounded,
              size: 72, color: Colors.white.withValues(alpha: 0.35)),
        ),
      );
    }
    return pages;
  }

  @override
  void initState() {
    super.initState();
    _heroController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  void _scheduleSwipeHint(int pageCount) {
    _swipeHintTimer?.cancel();
    if (!mounted) return;
    if (pageCount <= 1) {
      setState(() => _showSwipeHint = false);
      return;
    }
    setState(() => _showSwipeHint = true);
    _swipeHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showSwipeHint = false);
    });
  }

  @override
  void dispose() {
    _swipeHintTimer?.cancel();
    _heroController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadOwnerProfile();
    final ok = await AuthHandler.isAuthenticated();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = ok;
      _authReady = true;
    });
    if (ok) await _prefillFromAccount();
    if (!mounted) return;
    _scheduleSwipeHint(_heroPages.length);
  }

  Future<void> _loadOwnerProfile() async {
    final fallbackName = (widget.hostDisplayName ?? '').trim();
    var ownerName = fallbackName;
    var ownerEmail = '';
    var ownerPhone = '';
    var ownerPhoto = '';
    var ownerUid = (widget.hostMerchantUid ?? '').trim();

    // Fallback when listing did not carry host UID: resolve from Firestore mirror.
    if (ownerUid.isEmpty && widget.accommodationId > 0) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('accommodation_rooms')
            .where('apiAccommodationId', isEqualTo: widget.accommodationId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          ownerUid = (snap.docs.first.data()['merchantId'] ?? '')
              .toString()
              .trim();
        }
      } catch (_) {}
    }

    if (ownerUid.isNotEmpty) {
      try {
        final merchantSnap = await FirebaseFirestore.instance
            .collection('accommodation_merchants')
            .doc(ownerUid)
            .get();
        final merchant = merchantSnap.data();
        if (merchant != null) {
          ownerName = _firstNonEmpty([
            merchant['businessName']?.toString(),
            merchant['business_name']?.toString(),
            merchant['companyName']?.toString(),
            merchant['company_name']?.toString(),
            ownerName,
          ]);
          ownerPhoto = _firstNonEmpty([
            merchant['profilePicture']?.toString(),
            merchant['profilepicture']?.toString(),
            merchant['logo']?.toString(),
            ownerPhoto,
          ]);
        }

        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerUid)
            .get();
        final d = snap.data();
        if (d != null) {
          ownerName = _firstNonEmpty([
            d['businessName']?.toString(),
            d['business_name']?.toString(),
            d['companyName']?.toString(),
            d['company_name']?.toString(),
            d['displayName']?.toString(),
            d['name']?.toString(),
            d['fullName']?.toString(),
            ownerName,
          ]);
          ownerEmail = _firstNonEmpty([
            d['email']?.toString(),
          ]);
          ownerPhone = _firstNonEmpty([
            d['phone']?.toString(),
            d['phoneNumber']?.toString(),
            d['mobile']?.toString(),
          ]);
          ownerPhoto = _firstNonEmpty([
            d['profilePicture']?.toString(),
            d['profilepicture']?.toString(),
            d['photoURL']?.toString(),
          ]);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _ownerName = ownerName;
      _ownerEmail = ownerEmail;
      _ownerPhone = ownerPhone;
      _ownerPhotoUrl = ownerPhoto;
    });
  }

  void _showOwnerPhotoPreview(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white70,
                        size: 72,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOwnerProfileSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final name = _ownerName.trim().isNotEmpty
            ? _ownerName.trim()
            : (widget.hostDisplayName?.trim().isNotEmpty == true
                ? widget.hostDisplayName!.trim()
                : 'Accommodation owner');
        final email = _ownerEmail.trim();
        final phone = _ownerPhone.trim();
        final photo = _ownerPhotoUrl.trim();
        final hasPhoto = photo.startsWith('http://') || photo.startsWith('https://');
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _brandNavy.withValues(alpha: 0.08),
                    child: hasPhoto
                        ? GestureDetector(
                            onTap: () => _showOwnerPhotoPreview(photo),
                            child: ClipOval(
                              child: Image.network(
                                photo,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.person_rounded, size: 28),
                              ),
                            ),
                          )
                        : const Icon(Icons.person_rounded, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _brandNavy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Accommodation business',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Email: $email',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    )),
              ],
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Phone: $phone',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    )),
              ],
              if (hasPhoto) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _showOwnerPhotoPreview(photo),
                  icon: const Icon(Icons.zoom_in_rounded),
                  label: const Text('View profile picture'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _prefillFromAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    final sp = await SharedPreferences.getInstance();

    var name = _firstNonEmpty([
      user?.displayName,
      sp.getString('name'),
    ]);
    var email = _firstNonEmpty([
      user?.email,
      sp.getString('email'),
    ]);
    // Don’t prefill from Firebase Auth phoneNumber — only saved profile / SP.
    var phone = _firstNonEmpty([
      sp.getString('phone'),
    ]);

    if (user != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final d = snap.data();
        if (d != null) {
          if (name.isEmpty) {
            name = _firstNonEmpty([
              d['displayName']?.toString(),
              d['name']?.toString(),
              d['fullName']?.toString(),
            ]);
          }
          if (email.isEmpty) {
            email = _firstNonEmpty([d['email']?.toString()]);
          }
          if (phone.isEmpty) {
            phone = _firstNonEmpty([
              d['phone']?.toString(),
              d['phoneNumber']?.toString(),
              d['mobile']?.toString(),
            ]);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final safePhone = _sanitizeStoredPhone(phone);
    setState(() {
      if (name.isNotEmpty) _nameController.text = name;
      if (email.isNotEmpty) _emailController.text = email;
      _phoneController.text = safePhone;
    });
  }

  String _firstNonEmpty(List<String?> parts) {
    for (final p in parts) {
      final t = p?.trim() ?? '';
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// Rejects internal IDs mistaken for phones (e.g. `+firebase_…` from bad SP/Firestore data).
  String _sanitizeStoredPhone(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.contains('firebase') ||
        lower.contains('firestore') ||
        lower.contains('uid_') ||
        lower.startsWith('+firebase')) {
      return '';
    }
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) return '';
    final letterCount = RegExp(r'[a-zA-Z]').allMatches(s).length;
    if (letterCount > 4) return '';
    return s;
  }

  Future<void> _goToSignIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
    if (!mounted) return;
    final ok = await AuthHandler.isAuthenticated();
    setState(() => _isLoggedIn = ok);
    if (ok) await _prefillFromAccount();
    if (!mounted) return;
    _scheduleSwipeHint(_heroPages.length);
  }

  int get _nights {
    final d = _checkOut.difference(_checkIn).inDays;
    return d < 1 ? 1 : d;
  }

  AccommodationPricePeriod get _effectivePricePeriod =>
      widget.pricePeriod ?? AccommodationPricePeriod.night;

  bool get _isMultiRoomType {
    final t = widget.accommodationType.toLowerCase().trim();
    return t == 'hotel' || t == 'lodge';
  }

  /// For monthly listings: bill in 30-night blocks (rounded up).
  int get _billingMonths {
    final n = _nights;
    return n < 1 ? 1 : (n + 29) ~/ 30;
  }

  num get _billableUnits {
    switch (_effectivePricePeriod) {
      case AccommodationPricePeriod.month:
        return _billingMonths;
      case AccommodationPricePeriod.day:
      case AccommodationPricePeriod.night:
        return _nights;
    }
  }

  num get _totalMwk {
    final unit = widget.pricePerNight;
    if (unit <= 0) return 0;
    return _billableUnits * unit;
  }

  String get _staySummaryLine {
    switch (_effectivePricePeriod) {
      case AccommodationPricePeriod.night:
        return '$_nights night${_nights == 1 ? '' : 's'}';
      case AccommodationPricePeriod.day:
        return '$_nights day${_nights == 1 ? '' : 's'}';
      case AccommodationPricePeriod.month:
        final m = _billingMonths;
        return '$m month${m == 1 ? '' : 's'}';
    }
  }

  Future<void> _pickCheckIn() async {
    final first = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn.isBefore(first) ? first : _checkIn,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkIn = picked;
      if (!_checkOut.isAfter(_checkIn)) {
        _checkOut = _checkIn.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickCheckOut() async {
    final minOut = _checkIn.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut.isBefore(minOut) ? minOut : _checkOut,
      firstDate: minOut,
      lastDate: _checkIn.add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() => _checkOut = picked);
  }

  Future<String?> _resolveHostMerchantUidForAlerts({
    required String? fromListing,
    required dynamic bookingDetails,
    required int accommodationId,
  }) async {
    final a = fromListing?.trim();
    if (a != null &&
        a.isNotEmpty &&
        Accommodation.looksLikeFirebaseAuthUid(a)) {
      return a;
    }
    final fromApi =
        BookingService.extractHostFirebaseUidFromBookingResponse(
            bookingDetails);
    if (fromApi != null &&
        Accommodation.looksLikeFirebaseAuthUid(fromApi)) {
      return fromApi.trim();
    }
    return _lookupHostMerchantUidInFirestore(accommodationId);
  }

  Future<String?> _lookupHostMerchantUidInFirestore(int accommodationId) async {
    if (accommodationId <= 0) return null;
    try {
      final fs = FirebaseFirestore.instance;
      var snap = await fs
          .collection('accommodation_rooms')
          .where('apiAccommodationId', isEqualTo: accommodationId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await fs
            .collection('accommodation_rooms')
            .where('id', isEqualTo: accommodationId.toString())
            .limit(1)
            .get();
      }
      if (snap.docs.isEmpty) return null;
      final mid =
          snap.docs.first.data()['merchantId']?.toString().trim() ?? '';
      if (mid.isNotEmpty && Accommodation.looksLikeFirebaseAuthUid(mid)) {
        return mid;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _submit() async {
    final ok = await AuthHandler.isAuthenticated();
    if (!mounted) return;
    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Sign in to book and pay.',
        isSuccess: false,
        errorMessage: '',
      );
      await _goToSignIn();
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if (widget.accommodationId <= 0) {
      ToastHelper.showCustomToast(
        context,
        'This listing cannot be booked (invalid id).',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    if (_totalMwk <= 0) {
      ToastHelper.showCustomToast(
        context,
        'Listing price is missing. Contact the host.',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_checkIn);
      final payload = VeroBookingsCreatePayload(
        accommodationId: widget.accommodationId,
        bookingDate: dateStr,
        price: _totalMwk,
        bookingFee: 0,
        phoneNumber: _phoneController.text.trim(),
      );
      final result = await _bookingService.createBooking(payload);
      if (!mounted) return;
      final bookingNo = result['bookingRef']?.toString().trim();
      if (bookingNo == null || bookingNo.isEmpty) {
        throw const ApiException(
          message: 'Booking created but no reference from server.',
        );
      }

      final hostForAlerts = await _resolveHostMerchantUidForAlerts(
        fromListing: widget.hostMerchantUid,
        bookingDetails: result['bookingDetails'],
        accommodationId: widget.accommodationId,
      );

      await InternetAddress.lookup('api.paychangu.com');

      final name = _nameController.text.trim();
      final parts = name.split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : 'Guest';
      final lastName =
          parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final txRef =
          'acc-${widget.accommodationId}-$bookingNo-${DateTime.now().millisecondsSinceEpoch}';

      final response = await http
          .post(
            PayChanguConfig.paymentUri,
            headers: PayChanguConfig.authHeaders,
            body: json.encode({
              'tx_ref': txRef,
              'first_name': firstName,
              'last_name': lastName,
              'email': _emailController.text.trim(),
              'phone_number': _phoneController.text.trim(),
              'currency': 'MWK',
              'amount': _totalMwk.round().toString(),
              'payment_methods': ['card', 'mobile_money', 'bank'],
              'callback_url': PayChanguConfig.callbackUrl,
              'return_url': PayChanguConfig.returnUrl,
              'customization': {
                'title': 'Vero 360 — Stay',
                'description':
                    '${widget.propertyName} · $_staySummaryLine · Ref $bookingNo',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status != 'success') {
        throw Exception(data['message']?.toString() ?? 'Payment init failed');
      }
      final checkoutUrl = data['data']?['checkout_url'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('No checkout URL from payment provider');
      }

      final hostUid = hostForAlerts?.trim() ?? '';
      final AccommodationEscrowParams? escrow = hostUid.isNotEmpty
          ? AccommodationEscrowParams(
              hostMerchantUid: hostUid,
              hostDisplayName:
                  (widget.hostDisplayName ?? widget.propertyName).trim(),
              bookingRef: bookingNo,
              propertyName: widget.propertyName,
            )
          : null;

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => InAppPaymentPage(
            checkoutUrl: checkoutUrl,
            txRef: txRef,
            totalAmount: _totalMwk.toDouble(),
            rootContext: context,
            deliveryType: DeliveryType.pickup,
            accommodationEscrow: escrow,
            onSuccessNavigate: (bookingCtx) {
              unawaited(() async {
                try {
                  await NotificationService.instance
                      .notifyAccommodationBookingForGuestAndHost(
                    propertyName: widget.propertyName,
                    bookingRef: bookingNo,
                    hostMerchantUid: hostForAlerts,
                    guestDisplayLine: _nameController.text.trim(),
                    guestEmail: _emailController.text.trim(),
                    checkInLabel: DateFormat.yMMMd().format(_checkIn),
                    nights: _nights,
                  );
                } catch (_) {}
              }());
              final cb = widget.afterSuccessfulPayment;
              if (cb != null) {
                cb(bookingCtx, widget.accommodationId);
              } else if (bookingCtx.mounted) {
                Navigator.of(bookingCtx).pop();
              }
            },
          ),
        ),
      );
    } on SocketException catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Network error. Check your connection.',
          isSuccess: false,
          errorMessage: e.message,
        );
      }
    } on TimeoutException {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Connection timeout. Try again.',
          isSuccess: false,
          errorMessage: '',
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          e.message,
          isSuccess: false,
          errorMessage: '',
        );
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          e.toString().replaceAll(RegExp(r'^Exception:\s*'), ''),
          isSuccess: false,
          errorMessage: '',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDeco(String label, IconData icon, {String? hint}) {
    final r = BorderRadius.circular(16);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _brandOrange.withValues(alpha: 0.9), size: 22),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    final pages = _heroPages;

    if (!_authReady) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _brandNavy,
          foregroundColor: Colors.white,
          title: const Text('Book stay'),
        ),
        body: const Center(child: CircularProgressIndicator(color: _brandOrange)),
      );
    }

    return Scaffold(
      backgroundColor: _surface,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 288,
              pinned: true,
              stretch: true,
              backgroundColor: _brandNavy,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                _isLoggedIn ? 'Book your stay' : 'Sign in to book',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                if (!_isLoggedIn)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Members only',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView(
                      controller: _heroController,
                      physics: const BouncingScrollPhysics(
                        parent: PageScrollPhysics(),
                      ),
                      onPageChanged: (i) {
                        setState(() {
                          _heroIndex = i;
                          if (i > 0) _showSwipeHint = false;
                        });
                      },
                      children: pages,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 120,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.propertyName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                              shadows: [
                                Shadow(
                                  blurRadius: 12,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                          if (widget.location.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.place_rounded,
                                    size: 16, color: Colors.white70),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_isMultiRoomType) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '${widget.roomsAvailable < 1 ? 1 : widget.roomsAvailable} room${(widget.roomsAvailable < 1 ? 1 : widget.roomsAvailable) == 1 ? '' : 's'} available',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (pages.length > 1)
                      Positioned(
                        bottom: 88,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(pages.length, (i) {
                            final on = i == _heroIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              width: on ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: on
                                    ? _brandOrange
                                    : Colors.white.withValues(alpha: 0.45),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 4,
                                    color: Colors.black26,
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    if (_showSwipeHint && pages.length > 1)
                      Positioned(
                        top: 56,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: _showSwipeHint ? 1 : 0,
                            duration: const Duration(milliseconds: 280),
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.swipe_rounded,
                                      size: 18,
                                      color: Colors.white.withValues(alpha: 0.95),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Swipe for more photos',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!_isLoggedIn)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _SignInRequiredCard(onSignIn: _goToSignIn),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _AccommodationOwnerBanner(
                    ownerName: _ownerName.isNotEmpty
                        ? _ownerName
                        : (widget.hostDisplayName ?? ''),
                    ownerEmail: _ownerEmail,
                    ownerPhone: _ownerPhone,
                    ownerPhotoUrl: _ownerPhotoUrl,
                    onViewProfile: _showOwnerProfileSheet,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _SectionCard(
                    icon: Icons.calendar_month_rounded,
                    title: 'Dates',
                    child: Row(
                      children: [
                        Expanded(
                          child: _DateTile(
                            label: 'Check-in',
                            value: dateFmt.format(_checkIn),
                            onTap: _submitting ? null : _pickCheckIn,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateTile(
                            label: 'Check-out',
                            value: dateFmt.format(_checkOut),
                            onTap: _submitting ? null : _pickCheckOut,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: _SectionCard(
                    icon: Icons.payments_rounded,
                    title: 'Total Amount',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isMultiRoomType) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Text(
                              '${widget.roomsAvailable < 1 ? 1 : widget.roomsAvailable} room${(widget.roomsAvailable < 1 ? 1 : widget.roomsAvailable) == 1 ? '' : 's'} available now',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          'MWK ${NumberFormat('#,##0').format(widget.pricePerNight.round())}${_effectivePricePeriod.uiSuffix}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Colors.green.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _staySummaryLine,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Divider(height: 22, color: Colors.grey.shade200),
                        Text(
                          'MWK ${NumberFormat('#,##0').format(_totalMwk.round())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: _brandNavy,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'secure your stay using secure payment on the next step.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: _SectionCard(
                    icon: Icons.person_rounded,
                    title: 'Your details',
                    subtitle:
                        'Prefilled from your account and saved profile. Edit anything before you pay.',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDeco(
                            'Full name',
                            Icons.badge_outlined,
                            hint: 'Enter your full name',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 2) {
                              return 'Enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: _fieldDeco(
                            'Email',
                            Icons.alternate_email_rounded,
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return 'Enter your email';
                            if (!s.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _fieldDeco(
                            'Phone',
                            Icons.phone_iphone_rounded,
                            hint: 'Enter your phone number',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 6) {
                              return 'Enter a phone number';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Continue to payment',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignInRequiredCard extends StatelessWidget {
  final VoidCallback onSignIn;

  const _SignInRequiredCard({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
            color: const Color(0xFFFF8A00).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.lock_person_rounded,
                    color: Color(0xFFFF8A00), size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Account required',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF16284C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Only signed-in guests can book a stay and pay securely. Your name, email, and phone will be filled from your account and profile after you sign in.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 20, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Swipe the photos above to see the property. Sign in below to choose dates and pay.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in to continue'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccommodationOwnerBanner extends StatelessWidget {
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String ownerPhotoUrl;
  final VoidCallback onViewProfile;

  const _AccommodationOwnerBanner({
    required this.ownerName,
    required this.ownerEmail,
    required this.ownerPhone,
    required this.ownerPhotoUrl,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final display =
        ownerName.trim().isNotEmpty ? ownerName.trim() : 'Accommodation owner';
    final emailLine = ownerEmail.trim();
    final phoneLine = ownerPhone.trim();
    final missingPhone = phoneLine.isEmpty;
    final hasPhoto = ownerPhotoUrl.startsWith('http');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF16284C),
            const Color(0xFF16284C).withValues(alpha: 0.88),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16284C).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: hasPhoto
                ? ClipOval(
                    child: Image.network(
                      ownerPhotoUrl,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                      ),
                    ),
                  )
                : const Icon(Icons.person_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Accommodation owner',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (emailLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    emailLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  missingPhone ? 'No phone' : phoneLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: missingPhone
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        missingPhone ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onViewProfile,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.person_search_rounded, size: 16),
                  label: const Text(
                    'View profile',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
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

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFFFF8A00), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF16284C),
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DateTile({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF16284C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
