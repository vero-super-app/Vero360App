// lib/Pages/details_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/utils/profile_open_helper.dart';
import 'package:vero360_app/features/Marketplace/presentation/pages/merchant_reviews_page.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:saver_gallery/saver_gallery.dart';

import 'package:vero360_app/Home/MessagePageBackendApi.dart';
import 'package:vero360_app/GeneralModels/chat_product_context.dart';
import 'package:vero360_app/GeneralPages/checkout_page.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_handler.dart';
import 'package:vero360_app/features/Auth/AuthServices/auth_storage.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace.model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/marketplace_time.dart';
import 'package:vero360_app/features/Cart/CartService/cart_services.dart';
import 'package:vero360_app/GernalServices/backend_chat_service.dart';
import 'package:vero360_app/GernalServices/backend_messaging_socket.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceModel/merchant_review_model.dart';
import 'package:vero360_app/features/Marketplace/MarkeplaceService/merchant_seller_loader.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/widgets/resilient_cached_network_image.dart';

import '../../../../GeneralPages/video_player_page.dart';

class DetailsPage extends StatefulWidget {
  static const routeName = '/details';

  final MarketplaceDetailModel item;
  final CartService cartService;

  const DetailsPage({
    required this.item,
    required this.cartService,
    super.key,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _SellerInfo {
  String? businessName,
      openingHours,
      status,
      description,
      logoUrl,
      serviceProviderId;
  double? rating;
  int reviewCount;
  int? backendMerchantId;
  List<MerchantReview> recentReviews;
  _SellerInfo({
    this.businessName,
    this.openingHours,
    this.status,
    this.description,
    this.rating,
    this.reviewCount = 0,
    this.logoUrl,
    this.serviceProviderId,
    this.backendMerchantId,
    this.recentReviews = const [],
  });
}

class _Media {
  final String url;
  final bool isVideo;
  _Media._(this.url, this.isVideo);
  factory _Media.image(String u) => _Media._(u, false);
  factory _Media.video(String u) => _Media._(u, true);
}

Widget _buildMarketplaceImage(String src, {BoxFit fit = BoxFit.cover}) {
  final s = src.trim();
  if (s.isEmpty) {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(
        Icons.broken_image_outlined,
        color: Colors.grey,
      ),
    );
  }

  // HTTP/HTTPS URL (disk-cached, full resolution)
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return ResilientCachedNetworkImage(url: s, fit: fit);
  }

  // Try base64 (with or without data: prefix)
  try {
    final base64Part = s.contains(',') ? s.split(',').last : s;
    final bytes = base64Decode(base64Part);
    return Image.memory(
      bytes,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.grey,
        ),
      ),
    );
  } catch (_) {
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return ResilientCachedNetworkImage(url: s, fit: fit);
    }
    return Image.network(
      s,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(
          Icons.broken_image_outlined,
          color: Colors.grey,
        ),
      ),
    );
  }
}

class _DetailsPageState extends State<DetailsPage> {
  // ── Brand (UI only)
  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandSoft = Color(0xFFFFE8CC);
  static const Color _bg = Color(0xFFF7F8FA);
  static const Color _ink = Color(0xFF101010);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFECEEF2);

  Future<_SellerInfo>? _sellerFuture;
  _SellerInfo? _seller;
  final TextEditingController _commentController = TextEditingController();
  final FToast _fToast = FToast();

  late final PageController _pc;
  int _page = 0;
  List<_Media> _media = const [];
  Timer? _autoTimer;
  static const _autoInterval = Duration(seconds: 4);
  bool _openingChat = false;

  /// Instant shop-hours for OPEN/CLOSED (independent of full seller load).
  String? _openingHours;
  List<int> _openingDays = const [];
  Timer? _shopStatusTicker;

  @override
  void initState() {
    super.initState();
    unawaited(BackendChatService.warmForMarketplaceChat().catchError((_) {}));
    unawaited(BackendMessagingSocket.connect().catchError((_) {}));
    _pc = PageController();
    _seedOpeningHoursFast();
    _sellerFuture = _loadSeller().then((s) {
      if (mounted) {
        setState(() {
          _seller = s;
          final h = (s.openingHours ?? '').trim();
          if (h.isNotEmpty) _openingHours = h;
        });
      }
      return s;
    });
    _prefetchSellerChat();
    _fToast.init(context);
    _shopStatusTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    final it = widget.item;
    final images = it.gallery.where((u) => u.toString().trim().isNotEmpty).toList();
    final videos = it.videos.where((u) => u.toString().trim().isNotEmpty).toList();
    final mainImg = it.image.toString().trim();
    _media = [
      if (mainImg.isNotEmpty) _Media.image(mainImg),
      ...images.map((u) => _Media.image(u.toString().trim())),
      ...videos.map((u) => _Media.video(u.toString().trim())),
    ];
    if (_media.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAutoplay();
      });
    }
  }

  /// Share current product
  void _shareProduct() {
    final item = widget.item;
    final merchantName = item.merchantName ?? item.sellerBusinessName ?? 'A merchant';
    final productUrl = 'https://vero360.app/marketplace/${item.id}';
    final priceStr = NumberFormat('#,###', 'en').format(item.price.truncate());
    Share.share(
      '$merchantName is selling this on Vero360 - Check out ${item.name} - MWK $priceStr\n$productUrl',
    );
  }

  /// Copy product link to clipboard (for pasting in other apps)
  void _copyProductLink() {
    final item = widget.item;
    final productUrl = 'https://vero360.app/marketplace/${item.id}';
    Clipboard.setData(ClipboardData(text: productUrl));
    _toast('Product link copied', Icons.link, _brandOrange);
  }

  @override
  void dispose() {
    _shopStatusTicker?.cancel();
    _autoTimer?.cancel();
    _pc.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // autoplay
  void _startAutoplay() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_autoInterval, (_) {
      if (!mounted || _media.length <= 1) return;
      final next = (_page + 1) % _media.length;
      _pc.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut);
    });
  }

  // seller/data
  void _seedOpeningHoursFast() {
    final i = widget.item;
    final mid = (i.merchantId ?? '').trim();
    final sid = (i.sellerUserId ?? '').trim();
    final fromItem = (i.sellerOpeningHours ?? '').trim();
    final fromCache = MerchantSellerLoader.peekOpeningHours(mid) ??
        MerchantSellerLoader.peekOpeningHours(sid);
    final seed = fromItem.isNotEmpty ? fromItem : (fromCache ?? '');
    if (seed.isNotEmpty) {
      _openingHours = seed;
      MerchantSellerLoader.cacheOpeningHours(mid, seed);
      MerchantSellerLoader.cacheOpeningHours(sid, seed);
    }
    final days = MerchantSellerLoader.peekOpeningDays(mid) ??
        MerchantSellerLoader.peekOpeningDays(sid);
    if (days != null && days.isNotEmpty) {
      _openingDays = days;
    }
    unawaited(_prefetchOpeningHoursOnly());
  }

  Future<void> _prefetchOpeningHoursOnly() async {
    final i = widget.item;
    final mid = (i.merchantId ?? '').trim();
    final sid = (i.sellerUserId ?? '').trim();

    // Disk first (very fast).
    final diskHours = await MerchantSellerLoader.peekOpeningHoursPersisted(mid) ??
        await MerchantSellerLoader.peekOpeningHoursPersisted(sid);
    final diskDays = await MerchantSellerLoader.peekOpeningDaysPersisted(mid) ??
        await MerchantSellerLoader.peekOpeningDaysPersisted(sid);
    if (!mounted) return;
    var dirty = false;
    if (diskHours != null &&
        diskHours.isNotEmpty &&
        _openingHours != diskHours) {
      _openingHours = diskHours;
      dirty = true;
    }
    if (diskDays != null &&
        diskDays.isNotEmpty &&
        !_sameDays(_openingDays, diskDays)) {
      _openingDays = diskDays;
      dirty = true;
    }
    if (dirty) setState(() {});

    // Always refresh from server so OPEN/CLOSED matches latest merchant edit.
    final schedule = await MerchantSellerLoader.prefetchShopSchedule(
      mid.isNotEmpty ? mid : sid,
      extraIds: [sid, mid, i.serviceProviderId],
    );
    if (!mounted) return;
    final hours = (schedule.hours ?? '').trim();
    final days = schedule.days;
    dirty = false;
    if (hours.isNotEmpty && _openingHours != hours) {
      _openingHours = hours;
      dirty = true;
    }
    if (days.isNotEmpty && !_sameDays(_openingDays, days)) {
      _openingDays = days;
      dirty = true;
    }
    // Force rebuild even when equal so chip re-evaluates open-now.
    if (dirty || hours.isNotEmpty || days.isNotEmpty) {
      setState(() {});
    }
  }

  bool _sameDays(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String? get _resolvedOpeningHours {
    final live = (_openingHours ?? '').trim();
    if (live.isNotEmpty) return live;
    final fromSeller = (_seller?.openingHours ?? '').trim();
    if (fromSeller.isNotEmpty) return fromSeller;
    final fromItem = (widget.item.sellerOpeningHours ?? '').trim();
    if (fromItem.isNotEmpty) return fromItem;
    return MerchantSellerLoader.peekOpeningHours(widget.item.merchantId) ??
        MerchantSellerLoader.peekOpeningHours(widget.item.sellerUserId);
  }

  List<int> get _resolvedOpeningDays {
    if (_openingDays.isNotEmpty) return _openingDays;
    return MerchantSellerLoader.peekOpeningDays(widget.item.merchantId) ??
        MerchantSellerLoader.peekOpeningDays(widget.item.sellerUserId) ??
        const [];
  }

  Future<_SellerInfo> _loadSeller() async {
    final i = widget.item;
    final seller = await MerchantSellerLoader.load(
      merchantId: i.merchantId,
      sellerUserId: i.sellerUserId,
      serviceProviderId: i.serviceProviderId,
      sellerBusinessName: i.sellerBusinessName,
      sellerOpeningHours: i.sellerOpeningHours ?? _openingHours,
      sellerStatus: i.sellerStatus,
      sellerBusinessDescription: i.sellerBusinessDescription,
      sellerRating: i.sellerRating,
      sellerLogoUrl: i.sellerLogoUrl,
      backendUserIdHint: i.merchantBackendId,
    );
    final info = _SellerInfo(
      businessName: seller.businessName,
      openingHours: seller.openingHours,
      status: seller.status,
      description: seller.description,
      rating: seller.rating,
      reviewCount: seller.reviewCount,
      logoUrl: seller.logoUrl,
      serviceProviderId: seller.serviceProviderId,
      backendMerchantId: seller.backendMerchantId,
      recentReviews: seller.recentReviews,
    );
    return info;
  }

  void _prefetchSellerChat() {
    final item = widget.item;
    final immediate = item.merchantBackendId;
    if (immediate != null && immediate > 0) {
      unawaited(BackendChatService.prefetchDirectChat(immediate).catchError((_) {}));
      return;
    }
    unawaited(
      (_sellerFuture ?? _loadSeller()).then((seller) {
        final backendId = seller.backendMerchantId;
        if (backendId != null && backendId > 0) {
          return BackendChatService.prefetchDirectChat(backendId);
        }
      }).catchError((_) {}),
    );
  }

  Future<String?> _readAuthToken() async => AuthHandler.getTokenForApi();

  Future<bool> _requireLogin() async {
    final t = await _readAuthToken();
    final ok = t != null;
    if (!ok) {
      ToastHelper.showCustomToast(
        context,
        'Please log in to chat with merchant.',
        isSuccess: false,
        errorMessage: '',
      );
    }
    return ok;
  }

  Future<String?> getMyUserId() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('jwt_token') ?? sp.getString('token');
    if (token == null || token.isEmpty) return null;
    final claims = JwtDecoder.decode(token);
    final id = (claims['sub'] ?? claims['id'])?.toString();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  Future<void> _goToCheckout(MarketplaceDetailModel item) async {
    if (item.isOutOfStock) {
      ToastHelper.showCustomToast(
        context,
        'This item is out of stock',
        isSuccess: false,
        errorMessage: '',
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final _ = prefs.getInt('userId'); // kept as-is
    // ignore: use_build_context_synchronously
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutPage(item: item)),
    );
  }

  void _toast(String msg, IconData icon, Color color) {
    _fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ]),
      ),
      gravity: ToastGravity.CENTER,
      toastDuration: const Duration(seconds: 2),
    );
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

  bool _isShopOpenFromHours(
    String? openingHours, [
    List<int> openingDays = const [],
  ]) {
    final s = (openingHours ?? '').trim();
    if (s.isEmpty) return false;
    if (openingDays.isNotEmpty &&
        !openingDays.contains(DateTime.now().weekday)) {
      return false;
    }
    final parts = s.replaceAll('–', '-').replaceAll('—', '-').split('-');
    if (parts.length != 2) return false;
    final open = _parseShopTime(parts[0]);
    final close = _parseShopTime(parts[1]);
    if (open == null || close == null) return false;
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

  Widget _shopStatusChip(String? openingHours, [List<int>? openingDays]) {
    final open = _isShopOpenFromHours(
      openingHours,
      openingDays ?? _resolvedOpeningDays,
    );
    final fg = open ? Colors.green.shade700 : Colors.red.shade700;
    final bg = open ? Colors.green.shade50 : Colors.red.shade50;
    return Chip(
      label: Text(
        open ? 'OPEN' : 'CLOSED',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.2,
        ),
      ),
      backgroundColor: bg,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  String _fmtRating(double? r) {
    if (r == null) return '—';
    final whole = r.truncateToDouble();
    return r == whole ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  String _formatTimeAgo(DateTime time) =>
      MarketplaceTime.formatTimeAgo(time, verbose: true);

  Widget _ratingStars(double? rating, {bool showScore = true}) {
    final rr = ((rating ?? 0).clamp(0, 5)).toDouble();
    final filled = rr.floor();
    final hasHalf = (rr - filled) >= 0.5 && filled < 5;
    final empty = 5 - filled - (hasHalf ? 1 : 0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (int i = 0; i < filled; i++)
        const Icon(Icons.star, size: 16, color: Colors.amber),
      if (hasHalf)
        const Icon(Icons.star_half, size: 16, color: Colors.amber),
      for (int i = 0; i < empty; i++)
        const Icon(Icons.star_border, size: 16, color: Colors.amber),
      if (showScore && rr > 0) ...[
        const SizedBox(width: 6),
        Text(_fmtRating(rr),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ]);
  }

  void _openMerchantReviews({
    required String merchantId,
    required String merchantName,
    String? logoUrl,
    double? rating,
    String? serviceProviderId,
    String? sellerUserId,
    int? merchantBackendId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MerchantReviewsPage(
          merchantId: merchantId,
          merchantName: merchantName,
          logoUrl: logoUrl,
          rating: rating,
          serviceProviderId: serviceProviderId,
          sellerUserId: sellerUserId,
          merchantBackendId: merchantBackendId,
        ),
      ),
    );
  }

  Widget _buildMerchantCard({
    required MarketplaceDetailModel item,
    required String merchantDisplayName,
    required String merchantId,
    required bool hasMerchant,
    String? businessName,
    String? openingHours,
    List<int> openingDays = const [],
    double? rating,
    int reviewCount = 0,
    List<MerchantReview> recentReviews = const [],
    String? businessDesc,
    String? logo,
    int? merchantBackendId,
  }) {
    const ink = Color(0xFF101010);
    const muted = Color(0xFF6B7280);
    const border = Color(0xFFECEEF2);
    final days = openingDays.isNotEmpty ? openingDays : _resolvedOpeningDays;
    final shopOpen = _isShopOpenFromHours(openingHours, days);
    final statusLabel = shopOpen ? 'OPEN' : 'CLOSED';
    final statusColor =
        shopOpen ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _merchantAvatar(logo ?? item.sellerLogoUrl, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchantDisplayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ratingStars(rating, showScore: reviewCount > 0),
                          Text(
                            reviewCount > 0
                                ? '$reviewCount review${reviewCount == 1 ? '' : 's'}'
                                : 'No reviews yet',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _shopStatusChip(openingHours, days),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _merchantDetailRow(
                    icon: Icons.badge_outlined,
                    label: 'Business name',
                    value: businessName ??
                        item.sellerBusinessName ??
                        item.merchantName,
                  ),
                  const SizedBox(height: 8),
                  _merchantDetailRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Status',
                    value: statusLabel,
                    valueColor: statusColor,
                    valueBold: true,
                  ),
                  if ((openingHours ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _merchantDetailRow(
                      icon: Icons.schedule_rounded,
                      label: 'Hours',
                      value: openingHours!.trim(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Business description',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (businessDesc ?? '').trim().isNotEmpty ? businessDesc!.trim() : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            if (recentReviews.isNotEmpty) ...[
              const Text(
                'Recent reviews',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              ...recentReviews.map((review) => _recentReviewTile(review)),
              const SizedBox(height: 14),
            ],
            Material(
              color: const Color(0xFFFFF8F0),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: hasMerchant && merchantId.trim().isNotEmpty
                    ? () => _openMerchantReviews(
                          merchantId: merchantId,
                          merchantName: merchantDisplayName,
                          logoUrl: logo ?? item.sellerLogoUrl,
                          rating: rating,
                          serviceProviderId: item.serviceProviderId,
                          sellerUserId: item.sellerUserId,
                          merchantBackendId: merchantBackendId,
                        )
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _brandOrange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _brandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.rate_review_outlined,
                          color: _brandOrange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reviews & Ratings',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'See what customers are saying',
                              style: TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade500,
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

  Widget _recentReviewTile(MerchantReview review) {
    final comment = review.comment.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEEF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.authorName.trim().isEmpty
                      ? 'Customer'
                      : review.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF101010),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: Colors.amber,
                  );
                }),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4B5563),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _merchantDetailRow({
    required IconData icon,
    required String label,
    required String? value,
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            (value ?? '').trim().isEmpty ? '—' : value!.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: valueBold ? FontWeight.w900 : FontWeight.w600,
              color: valueColor ?? const Color(0xFF101010),
            ),
          ),
        ),
      ],
    );
  }

  Widget _merchantAvatar(String? raw, {double size = 36}) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFFFFF4E5),
        child: Icon(
          Icons.storefront_outlined,
          color: _brandOrange,
          size: size * 0.45,
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFF0F2F5),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: _buildMarketplaceImage(s, fit: BoxFit.cover),
        ),
      ),
    );
  }

  void _openVideo(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerPage(url: url)),
    );
  }

  /// Open fullscreen image viewer with watermark (merchant name + Vero360App) and download.
  void _openImageViewer(String imageUrl, {String? merchantName}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          imageUrl: imageUrl,
          merchantName: merchantName ?? widget.item.sellerBusinessName ?? widget.item.merchantName ?? 'Merchant',
        ),
      ),
    );
  }

  Future<void> _openChat(MarketplaceDetailModel item) async {
    if (_openingChat) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;

    setState(() => _openingChat = true);

    try {
      unawaited(BackendChatService.warmForMarketplaceChat().catchError((_) {}));
      unawaited(BackendMessagingSocket.connect().catchError((_) {}));

      final ownerId = item.merchantBackendId;
      final myId = BackendChatService.peekUserId();
      if (myId != null &&
          BackendChatService.isOwnMarketplaceListingSync(
            myBackendId: myId,
            ownerId: ownerId,
            sellerUserId: item.sellerUserId,
            merchantId: item.merchantId,
          )) {
        throw Exception(
          'This is your own listing — you cannot chat with yourself😂😂.',
        );
      }

      String peerId = '';
      int? peerUserId =
          (ownerId != null && ownerId > 0) ? ownerId : null;
      if (peerUserId != null) {
        final cached =
            BackendChatService.findCachedDirectChatWithPeer(peerUserId);
        if (cached != null) {
          peerId = cached.id;
        }
      }

      // Start resolve immediately; share the same Future with the chat page.
      Future<MerchantChatResult>? pendingChat;
      if (peerId.isEmpty) {
        pendingChat = BackendChatService.startMerchantChat(
          sqlItemId: item.id > 0 ? item.id : null,
          ownerId: ownerId,
          sellerUserId: item.sellerUserId,
          serviceProviderId: item.serviceProviderId,
          merchantId: item.merchantId,
          firestoreItemDocId: item.firestoreDocId,
        );

        // Brief race: if server answers quickly, open with real chat id.
        try {
          final quick = await pendingChat.timeout(
            const Duration(milliseconds: 550),
          );
          peerId = quick.chat.id;
          peerUserId = quick.sellerId;
          pendingChat = null;
        } on TimeoutException {
          // Continue into chat UI; page awaits the same in-flight future.
        } catch (e) {
          // Hard failure before navigation — surface on details page.
          rethrow;
        }
      } else {
        // Warm messages for this chat while we push the route.
        unawaited(BackendChatService.getMessages(peerId).catchError((_) =>
            <BackendChatMessage>[]));
      }

      final sellerName =
          item.sellerBusinessName ?? item.merchantName ?? 'Seller';
      final sellerAvatar = item.sellerLogoUrl ?? '';
      final productContext = ChatProductContext(
        productId: item.id.toString(),
        name: item.name,
        image: item.image,
        price: item.price,
        description: item.description,
        merchantId: (item.merchantId ?? item.serviceProviderId ?? '')
                .trim()
                .isEmpty
            ? null
            : (item.merchantId ?? item.serviceProviderId),
      );

      if (!mounted) return;
      setState(() => _openingChat = false);

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => MessagePageBackendApi(
            peerId: peerId,
            peerName: sellerName,
            peerAvatarUrl: sellerAvatar,
            productContext: productContext,
            peerMerchantId: item.merchantId ?? item.serviceProviderId,
            peerUserId: peerUserId,
            sendProductEnquiry: true,
            resolveSqlItemId: item.id > 0 ? item.id : null,
            resolveOwnerId: ownerId,
            resolveSellerUserId: item.sellerUserId,
            resolveServiceProviderId: item.serviceProviderId,
            resolveMerchantId: item.merchantId,
            resolveFirestoreItemDocId: item.firestoreDocId,
            pendingMerchantChat: pendingChat,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[_openChat] Exception: $e');
      if (mounted) {
        final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        final message = raw.contains('own listing') ||
                raw.contains('cannot chat with yourself') ||
                raw.contains('cannot chat with ur self')
            ? raw
            : raw.contains('could not find this seller') ||
                    raw.contains('not linked on the server')
                ? raw
                : raw.contains('Failed to create chat') ||
                        raw.contains('User ') && raw.contains('not found')
                    ? 'Seller chat is unavailable — this seller\'s account is not linked on the server yet. Ask them to open the merchant dashboard once while logged in.'
                    : raw;
        _toast(message, Icons.error, Colors.red);
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  /// Navigate to a page that shows all products from this merchant.
  /// You need to implement `MerchantProductsPage` + fetching by merchantId.
  void _openMerchantProducts(
      {required String merchantId,
      required String merchantName}) {
    openMerchantOrDriverProfile(
      context,
      profileId: merchantId,
      displayName: merchantName,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Item Details',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: _ink,
          letterSpacing: -0.3,
        ),
      ),
      centerTitle: false,
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.link_rounded),
          onPressed: _copyProductLink,
          tooltip: 'Copy link',
        ),
        IconButton(
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: _shareProduct,
          tooltip: 'Share product',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildHeroGallery() {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: PageView.builder(
              controller: _pc,
              physics: _media.length > 1
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: _media.isEmpty ? 1 : _media.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                if (_media.length > 1) _startAutoplay();
              },
              itemBuilder: (_, i) {
                if (_media.isEmpty) {
                  return ColoredBox(
                    color: const Color(0xFFF0F2F5),
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                  );
                }
                final m = _media[i];
                if (!m.isVideo) {
                  return InkWell(
                    onTap: () => _openImageViewer(
                      m.url,
                      merchantName: widget.item.merchantName ??
                          widget.item.sellerBusinessName,
                    ),
                    child: _buildMarketplaceImage(m.url, fit: BoxFit.cover),
                  );
                }
                return InkWell(
                  onTap: () => _openVideo(m.url),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 40,
                            color: _brandOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_media.length > 1) ...[
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_page + 1} / ${_media.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_media.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? _brandOrange
                          : Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard({
    required MarketplaceDetailModel item,
    required String merchantDisplayName,
    String? openingHours,
    List<int> openingDays = const [],
  }) {
    final price =
        'MWK ${NumberFormat('#,###', 'en').format(item.price.truncate())}';
    final category = (item.category ?? '').trim();
    final days = openingDays.isNotEmpty ? openingDays : _resolvedOpeningDays;
    final shopOpen = _isShopOpenFromHours(openingHours, days);
    final statusFg = shopOpen ? Colors.green.shade700 : Colors.red.shade700;
    final statusBg = shopOpen ? Colors.green.shade50 : Colors.red.shade50;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (category.isNotEmpty)
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _brandSoft.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _brandOrange,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              if (category.isNotEmpty) const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  shopOpen ? 'OPEN' : 'CLOSED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: statusFg,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9A2E), Color(0xFFFF8A00)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _brandOrange.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (item.location.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.location.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'About this item',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.description,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: _ink,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (merchantDisplayName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.createdAt != null
                        ? 'Posted by $merchantDisplayName • ${_formatTimeAgo(item.createdAt!)}'
                        : 'Posted by $merchantDisplayName',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatButton(MarketplaceDetailModel item) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandOrange,
          side: BorderSide(color: _brandOrange.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _openingChat ? null : () => _openChat(item),
        icon: _openingChat
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _brandOrange,
                ),
              )
            : const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(
          _openingChat ? 'Opening chat…' : 'Chat with seller',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildMerchantProductsButton({
    required String merchantId,
    required String merchantDisplayName,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openMerchantProducts(
            merchantId: merchantId,
            merchantName: merchantDisplayName,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brandSoft.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: _brandOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'More from $merchantDisplayName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Browse all products from this seller',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(MarketplaceDetailModel item) {
    final price =
        'MWK ${NumberFormat('#,###', 'en').format(item.price.truncate())}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _goToCheckout(item),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                  label: const Text(
                    'Checkout',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _ink,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final s = _seller;
    final businessName = s?.businessName ?? item.sellerBusinessName;
    final openingHours = _resolvedOpeningHours;
    final openingDays = _resolvedOpeningDays;
    final rating = s?.rating ?? item.sellerRating;
    final reviewCount = s?.reviewCount ?? 0;
    final recentReviews = s?.recentReviews ?? const <MerchantReview>[];
    final businessDesc = s?.description ?? item.sellerBusinessDescription;
    final logo = s?.logoUrl ?? item.sellerLogoUrl;

    final hasMerchant =
        (item.merchantId != null && item.merchantId!.isNotEmpty) ||
            (item.serviceProviderId != null &&
                item.serviceProviderId!.isNotEmpty);

    final merchantId = item.merchantId ?? item.serviceProviderId ?? '';
    final merchantDisplayName = businessName ??
        item.sellerBusinessName ??
        item.merchantName ??
        'Merchant';

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomBar(item),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildHeroGallery(),
          const SizedBox(height: 16),
          _buildProductCard(
            item: item,
            merchantDisplayName: merchantDisplayName,
            openingHours: openingHours,
            openingDays: openingDays,
          ),
          const SizedBox(height: 12),
          _buildChatButton(item),
          const SizedBox(height: 24),
          _sectionLabel('Seller'),
          _buildMerchantCard(
            item: item,
            merchantDisplayName: merchantDisplayName,
            merchantId: merchantId,
            hasMerchant: hasMerchant,
            businessName: businessName,
            openingHours: openingHours,
            openingDays: openingDays,
            rating: rating,
            reviewCount: reviewCount,
            recentReviews: recentReviews,
            businessDesc: businessDesc,
            logo: logo,
            merchantBackendId: s?.backendMerchantId,
          ),
          if (hasMerchant && merchantId.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildMerchantProductsButton(
              merchantId: merchantId,
              merchantDisplayName: merchantDisplayName,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Fullscreen image viewer with watermark (merchant name + Vero360App) and download.
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.merchantName,
  });
  final String imageUrl;
  final String merchantName;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  static const Color _brandOrange = Color(0xFFFF8A00);
  bool _saving = false;

  Future<void> _downloadImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final uri = Uri.tryParse(widget.imageUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            'Cannot download this image',
            isSuccess: false,
            errorMessage: '',
          );
        }
        return;
      }
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        if (mounted) {
          ToastHelper.showCustomToast(
            context,
            'Failed to load image',
            isSuccess: false,
            errorMessage: '',
          );
        }
        return;
      }
      // Decode image, draw watermark on it, then save (watermark only on saved file)
      Uint8List bytesToSave = res.bodyBytes;
      try {
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final w = image.width.toDouble();
        final h = image.height.toDouble();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final src = Rect.fromLTWH(0, 0, w, h);
        canvas.drawImageRect(image, src, src, Paint());
        image.dispose();
        // Watermark: app logo + merchant name + Vero360App
        const double fontSize = 32;
        const double fontSize2 = 24;
        const double logoHeight = 58;
        const double leftPad = 24;
        final maxW = w - 48;
        final bottomY = h - 24 - fontSize - 6 - fontSize2;

        // 1) App logo (assets/logo_mark.png), expanded a bit
        try {
          final logoBytes = await rootBundle.load('assets/logo_mark.png');
          final logoCodec = await ui.instantiateImageCodec(
            logoBytes.buffer.asUint8List(logoBytes.offsetInBytes, logoBytes.lengthInBytes),
          );
          final logoFrame = await logoCodec.getNextFrame();
          final logoImage = logoFrame.image;
          final lw = logoImage.width.toDouble();
          final lh = logoImage.height.toDouble();
          if (lw > 0 && lh > 0) {
            final scale = logoHeight / lh;
            final scaledW = lw * scale;
            final logoRect = Rect.fromLTWH(leftPad, bottomY - logoHeight - 4, scaledW, logoHeight);
            canvas.drawImageRect(
              logoImage,
              Rect.fromLTWH(0, 0, lw, lh),
              logoRect,
              Paint()..filterQuality = ui.FilterQuality.medium,
            );
            logoImage.dispose();
          }
        } catch (_) {}

        // 2) Merchant name + Vero360App text
        final tp1 = TextPainter(
          text: TextSpan(
            text: widget.merchantName,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4, offset: const Offset(1, 1)),
                Shadow(color: Colors.black54, blurRadius: 2, offset: const Offset(0, 0)),
              ],
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: maxW);
        final tp2 = TextPainter(
          text: const TextSpan(
            text: 'Vero360App',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize2,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 1)),
                Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 0)),
              ],
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: maxW);
        tp1.paint(canvas, Offset(leftPad, bottomY));
        tp2.paint(canvas, Offset(leftPad, bottomY + fontSize + 6));

        final picture = recorder.endRecording();
        final outImage = await picture.toImage(w.round(), h.round());
        final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
        outImage.dispose();
        if (byteData != null) {
          bytesToSave = byteData.buffer.asUint8List();
        }
      } catch (_) {
        // If watermarking fails, save original bytes
      }
      final fileName = 'vero360_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await SaverGallery.saveImage(
        bytesToSave,
        quality: 100,
        extension: 'png',
        fileName: fileName,
        androidRelativePath: 'Pictures/Vero360',
        skipIfExists: false,
      );
      if (mounted) {
        if (result.isSuccess) {
          ToastHelper.showCustomToast(
            context,
            'Image saved to gallery',
            isSuccess: true,
            errorMessage: '',
          );
        } else {
          ToastHelper.showCustomToast(
            context,
            result.errorMessage ?? 'Save failed',
            isSuccess: false,
            errorMessage: '',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showCustomToast(
          context,
          'Download failed',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: _buildMarketplaceImage(
                widget.imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Top bar: close
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          // Download button
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _saving ? null : _downloadImage,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_saving ? 'Saving…' : 'Download'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}